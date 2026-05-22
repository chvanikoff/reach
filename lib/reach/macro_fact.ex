defmodule Reach.MacroFact do
  @moduledoc "Source-level facts for macro and DSL declarations."

  defstruct [
    :kind,
    :source,
    :owner_module,
    :target,
    :generated?,
    :framework,
    :name,
    :arity,
    :call_module,
    :nesting,
    :data,
    :confidence
  ]

  @type location :: %{
          optional(:file) => String.t(),
          optional(:line) => non_neg_integer(),
          optional(:column) => non_neg_integer() | nil
        }

  @type t :: %__MODULE__{
          kind: atom(),
          source: location() | nil,
          owner_module: module() | nil,
          target: term(),
          generated?: boolean(),
          framework: atom() | nil,
          name: atom() | nil,
          arity: non_neg_integer() | nil,
          call_module: module() | nil,
          nesting: [atom()],
          data: map(),
          confidence: atom() | nil
        }

  @definition_forms [:def, :defp, :defmacro, :defmacrop]
  @module_forms [:defmodule, :defprotocol, :defimpl]
  @control_forms [:=, :->, :fn, :case, :cond, :if, :unless, :with, :for, :receive, :try]

  @doc "Collects source-level macro/DSL declaration facts from quoted Elixir AST."
  @spec collect_ast(Macro.t(), keyword()) :: [t()]
  def collect_ast(ast, opts \\ []) do
    file = Keyword.get(opts, :file)

    ast
    |> Reach.AST.modules_in_file()
    |> Enum.flat_map(&collect_module(&1, file))
  end

  @doc "Parses and collects macro/DSL facts from an Elixir source string."
  @spec collect_source(String.t(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def collect_source(source, opts \\ []) do
    file = Keyword.get(opts, :file, "nofile")

    case Code.string_to_quoted(source,
           columns: true,
           token_metadata: true,
           emit_warnings: false,
           file: file
         ) do
      {:ok, ast} -> {:ok, collect_ast(ast, Keyword.put(opts, :file, file))}
      {:error, _reason} = error -> error
    end
  end

  @doc "Reads and collects macro/DSL facts from a source file."
  @spec collect_file(Path.t()) :: {:ok, [t()]} | {:error, term()}
  def collect_file(path) do
    with {:ok, source} <- File.read(path) do
      collect_source(source, file: path)
    end
  end

  defp collect_module({:defmodule, _meta, [module_ast, body]}, file) do
    module = module_name(module_ast)

    body
    |> module_body()
    |> statements()
    |> Enum.flat_map(&collect_declaration(&1, module, [], file))
  end

  defp module_body(body) when is_list(body) do
    Keyword.get(body, :do) ||
      Enum.find_value(body, fn
        {{:__block__, _meta, [:do]}, value} -> value
        _entry -> nil
      end)
  end

  defp statements({:__block__, _meta, statements}) when is_list(statements), do: statements
  defp statements(nil), do: []
  defp statements(statement), do: [statement]

  defp collect_declaration({form, _meta, _args}, _module, _nesting, _file)
       when form in @definition_forms or form in @module_forms,
       do: []

  defp collect_declaration({form, _meta, _args}, _module, _nesting, _file)
       when form in @control_forms,
       do: []

  defp collect_declaration(node, module, nesting, file) do
    case declaration_call(node) do
      nil ->
        []

      declaration ->
        fact = new(declaration, module, nesting, file)

        child_facts =
          node
          |> declaration_body_statements()
          |> Enum.flat_map(&collect_declaration(&1, module, [declaration.name | nesting], file))

        [fact | child_facts]
    end
  end

  defp declaration_call({:use, meta, args}) when is_list(args) do
    {call_module, rest} = use_module_and_args(args)

    %{
      name: :use,
      arity: length(args),
      call_module: call_module,
      meta: meta,
      target: call_module,
      data: %{args: Macro.to_string(rest)}
    }
  end

  defp declaration_call({name, meta, args}) when is_atom(name) and is_list(args) do
    %{
      name: name,
      arity: call_arity(args),
      call_module: nil,
      meta: meta,
      target: {nil, name, call_arity(args)},
      data: %{}
    }
  end

  defp declaration_call({{:., meta, [module_ast, name]}, _call_meta, args})
       when is_atom(name) and is_list(args) do
    call_module = module_name(module_ast)
    arity = call_arity(args)

    %{
      name: name,
      arity: arity,
      call_module: call_module,
      meta: meta,
      target: {call_module, name, arity},
      data: %{}
    }
  end

  defp declaration_call(_node), do: nil

  defp use_module_and_args([module_ast | args]), do: {module_name(module_ast), args}
  defp use_module_and_args([]), do: {nil, []}

  defp call_arity(args), do: args |> Enum.reject(&keyword_block?/1) |> length()

  defp keyword_block?(block) when is_list(block) do
    Keyword.keyword?(block) and Enum.any?(block, fn {key, _value} -> block_key?(key) end)
  end

  defp keyword_block?(_block), do: false

  defp declaration_body_statements({_name, _meta, args}) when is_list(args) do
    args
    |> Enum.flat_map(&body_from_arg/1)
    |> Enum.flat_map(&statements/1)
  end

  defp declaration_body_statements({{:., _meta, _parts}, _call_meta, args}) when is_list(args) do
    args
    |> Enum.flat_map(&body_from_arg/1)
    |> Enum.flat_map(&statements/1)
  end

  defp declaration_body_statements(_node), do: []

  defp body_from_arg(block) when is_list(block) do
    block
    |> Enum.filter(fn
      {key, _value} -> block_key?(key)
      _entry -> false
    end)
    |> Enum.map(fn {_key, value} -> value end)
  end

  defp body_from_arg(_arg), do: []

  defp block_key?(:do), do: true
  defp block_key?(:else), do: true
  defp block_key?({:__block__, _meta, [key]}) when key in [:do, :else], do: true
  defp block_key?(_key), do: false

  defp new(declaration, module, nesting, file) do
    %__MODULE__{
      kind: :macro_dsl_declaration,
      source: location(declaration.meta, file),
      owner_module: module,
      target: declaration.target,
      generated?: false,
      framework: nil,
      name: declaration.name,
      arity: declaration.arity,
      call_module: declaration.call_module,
      nesting: Enum.reverse(nesting),
      data: declaration.data,
      confidence: :low
    }
  end

  defp module_name({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
  end

  defp module_name({:__block__, _meta, [value]}), do: module_name(value)
  defp module_name(atom) when is_atom(atom), do: atom
  defp module_name(_ast), do: nil

  defp location(meta, nil), do: location(meta, nil, false)
  defp location(meta, file), do: location(meta, file, true)

  defp location(meta, file, include_file?) do
    base = %{line: meta[:line] || 0, column: meta[:column]}
    if include_file?, do: Map.put(base, :file, file), else: base
  end
end
