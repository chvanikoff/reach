defmodule Reach.Smell.Checks.TrivialDelegate do
  @moduledoc "Detects pass-through API layers that only forward to another function."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:trivial_forwarder]

  defp scan_ast(ast, file) do
    aliases = aliases(ast)

    context = %{
      aliases: aliases,
      imports: imports(ast, aliases),
      local_functions: function_clause_counts(ast)
    }

    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        findings = prepend_findings(finding_for_node(node, file, context), findings)
        {node, findings}
      end)

    Enum.reverse(findings)
  end

  defp finding_for_node({:defp, meta, [head, body]}, file, context) do
    with false <- impl_before?(file, meta[:line]),
         {:ok, name, params} <- function_head(head),
         false <- multi_clause?(context.local_functions, name, params),
         {:ok, call} <- single_call_body(body, context),
         true <- forwarding_call?(name, params, call) do
      Finding.new(
        kind: :trivial_forwarder,
        message:
          "defp #{name}/#{length(params)} only forwards to #{call_label(call)} with the same arguments; call the target directly unless this helper is an intentional boundary",
        location: location(file, meta),
        evidence: %{target: call_label(call), function: name, arity: length(params)}
      )
    else
      _ -> nil
    end
  end

  defp finding_for_node(_node, _file, _context), do: nil

  defp prepend_findings(nil, findings), do: findings

  defp prepend_findings(finding, findings), do: [finding | findings]

  defp function_clause_counts(ast) do
    {_ast, counts} =
      Macro.prewalk(ast, %{}, fn
        {def_kind, _meta, [head | _rest]} = node, counts when def_kind in [:def, :defp] ->
          counts =
            case function_head(head) do
              {:ok, name, params} -> Map.update(counts, {name, length(params)}, 1, &(&1 + 1))
              :error -> counts
            end

          {node, counts}

        node, counts ->
          {node, counts}
      end)

    counts
  end

  defp multi_clause?(clause_counts, name, params) do
    Map.get(clause_counts, {name, length(params)}, 0) > 1
  end

  defp function_head({:when, _meta, [head | _guards]}), do: function_head(head)

  defp function_head({name, _meta, params}) when is_atom(name) and is_list(params),
    do: {:ok, name, params}

  defp function_head({name, _meta, nil}) when is_atom(name), do: {:ok, name, []}
  defp function_head(_head), do: :error

  defp single_call_body([do: body], context), do: single_call(body, context)

  defp single_call_body([{{:__block__, _meta, [:do]}, body}], context),
    do: single_call(body, context)

  defp single_call_body(_body, _context), do: :error

  defp single_call({:__block__, _meta, [body]}, context), do: single_call(body, context)

  defp single_call({{:., _meta, [module_ast, call_name]}, _call_meta, args}, context)
       when is_atom(call_name) and is_list(args) do
    case module_names(module_ast, context.aliases, %{}) do
      [module] -> {:ok, %{module: module, name: call_name, args: args}}
      _modules -> :error
    end
  end

  defp single_call({call_name, _meta, args}, context) when is_atom(call_name) and is_list(args) do
    case imported_module_for_call(context, call_name, length(args)) do
      nil -> {:ok, %{module: nil, name: call_name, args: args}}
      module -> {:ok, %{module: module, name: call_name, args: args}}
    end
  end

  defp single_call({call_name, _meta, nil}, context) when is_atom(call_name) do
    case imported_module_for_call(context, call_name, 0) do
      nil -> {:ok, %{module: nil, name: call_name, args: []}}
      module -> {:ok, %{module: module, name: call_name, args: []}}
    end
  end

  defp single_call(_body, _context), do: :error

  defp forwarding_call?(name, params, %{module: module, name: name, args: args})
       when module != nil do
    bare_variables?(params) and same_variables?(params, args)
  end

  defp forwarding_call?(_name, _params, _call), do: false

  defp bare_variables?(params), do: Enum.all?(params, &bare_variable?/1)

  defp bare_variable?({:\\, _meta, [{name, _var_meta, context}, _default]})
       when is_atom(name) and is_atom(context),
       do: true

  defp bare_variable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp bare_variable?(_param), do: false

  defp same_variables?([], []), do: true

  defp same_variables?([param | params], [arg | args]) do
    variable_name(param) == variable_name(arg) and same_variables?(params, args)
  end

  defp same_variables?(_params, _args), do: false

  defp variable_name({:\\, _meta, [{name, _var_meta, context}, _default]})
       when is_atom(name) and is_atom(context),
       do: name

  defp variable_name({name, _meta, context}) when is_atom(name) and is_atom(context), do: name
  defp variable_name(_node), do: nil

  defp option_value(opts, key) when is_list(opts) do
    Enum.find_value(opts, fn
      {{:__block__, _meta, [^key]}, value} -> value
      {^key, value} -> value
      _entry -> nil
    end)
  end

  defp option_value(_opts, _key), do: nil

  defp aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _meta, [module_ast]} = node, aliases ->
          {node, add_alias(aliases, module_ast, nil)}

        {:alias, _meta, [module_ast, opts]} = node, aliases ->
          {node, add_alias(aliases, module_ast, option_value(opts, :as))}

        node, aliases ->
          {node, aliases}
      end)

    aliases
  end

  defp add_alias(aliases, module_ast, as_ast) do
    with [module] <- module_names(module_ast, aliases, %{}),
         alias_name <- literal_atom(as_ast) || module |> String.split(".") |> List.last() do
      Map.put(aliases, alias_name, module)
    else
      _ -> aliases
    end
  end

  defp imports(ast, aliases) do
    {_ast, imports} =
      Macro.prewalk(ast, [], fn
        {:import, _meta, [module_ast]} = node, imports ->
          {node, import_entry(module_ast, [], aliases, imports)}

        {:import, _meta, [module_ast, opts]} = node, imports ->
          {node, import_entry(module_ast, opts, aliases, imports)}

        node, imports ->
          {node, imports}
      end)

    imports
  end

  defp import_entry(module_ast, opts, aliases, imports) do
    case module_names(module_ast, aliases, %{}) do
      [module] ->
        [
          %{module: module, only: option_value(opts, :only), except: option_value(opts, :except)}
          | imports
        ]

      _modules ->
        imports
    end
  end

  defp imported_module_for_call(context, name, arity) do
    if Map.has_key?(context.local_functions, {name, arity}) do
      nil
    else
      context.imports
      |> Enum.filter(&import_matches?(&1, name, arity))
      |> Enum.map(& &1.module)
      |> Enum.uniq()
      |> case do
        [module] -> module
        _modules -> nil
      end
    end
  end

  defp import_matches?(%{only: only, except: except}, name, arity) do
    import_option_allows?(only, name, arity, true) and
      import_option_allows?(except, name, arity, false)
  end

  defp import_option_allows?(nil, _name, _arity, default), do: default

  defp import_option_allows?(entries, name, arity, allowed_when_present) when is_list(entries) do
    present? = Enum.any?(entries, &(&1 == {name, arity}))
    if allowed_when_present, do: present?, else: not present?
  end

  defp import_option_allows?(_entries, _name, _arity, default), do: default

  @attribute_lookup_window 12

  defp impl_before?(file, line), do: previous_attribute?(file, line, "@impl")

  defp previous_attribute?(file, line, attribute) when is_binary(file) and is_integer(line) do
    if line > 1 and File.regular?(file) do
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.take(line - 1)
      |> Enum.reverse()
      |> Enum.take(@attribute_lookup_window)
      |> Enum.any?(&(String.trim_leading(&1) |> String.starts_with?(attribute)))
    else
      false
    end
  end

  defp previous_attribute?(_file, _line, _attribute), do: false

  defp literal_atom({:__block__, _meta, [atom]}) when is_atom(atom), do: atom
  defp literal_atom(atom) when is_atom(atom), do: atom
  defp literal_atom(_ast), do: nil

  defp module_names(nil, _aliases, _dynamic_targets), do: []

  defp module_names({:__aliases__, _meta, [alias_name]}, aliases, _dynamic_targets) do
    alias_key = Atom.to_string(alias_name)
    [Map.get(aliases, alias_key, alias_key)]
  end

  defp module_names({:__aliases__, _meta, parts}, _aliases, _dynamic_targets) do
    if Enum.all?(parts, &is_atom/1), do: [Enum.join(parts, ".")], else: []
  end

  defp module_names({:__block__, _meta, [atom]}, aliases, dynamic_targets) when is_atom(atom),
    do: module_names(atom, aliases, dynamic_targets)

  defp module_names({:__MODULE__, _meta, _args}, _aliases, _dynamic_targets), do: ["__MODULE__"]

  defp module_names({name, _meta, context}, _aliases, dynamic_targets)
       when is_atom(name) and is_atom(context) do
    Map.get(dynamic_targets, name, [])
  end

  defp module_names(atom, aliases, _dynamic_targets) when is_atom(atom) do
    name = Atom.to_string(atom)
    [Map.get(aliases, name, name)]
  end

  defp module_names(_ast, _aliases, _dynamic_targets), do: []

  defp call_label(%{module: nil, name: name}), do: Atom.to_string(name)
  defp call_label(%{module: module, name: name}), do: "#{module}.#{name}"

  defp location(file, meta), do: "#{file}:#{meta[:line] || 0}"
end
