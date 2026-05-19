defmodule Reach.Smell.Checks.ConversionIdioms do
  @moduledoc "Detects unnecessary conversion idioms such as one-shot tuple access and identity float coercion."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @loop_calls [
    :map,
    :each,
    :filter,
    :flat_map,
    :reject,
    :reduce,
    :reduce_while,
    :all?,
    :any?,
    :find
  ]

  @impl true
  def kinds, do: [:list_to_tuple_for_access, :identity_float_coercion]

  defp scan_ast(ast, file) do
    list_to_tuple_findings(ast, file) ++ identity_float_findings(ast, file)
  end

  defp list_to_tuple_findings(ast, file) do
    ast
    |> function_bodies()
    |> Enum.flat_map(&list_to_tuple_findings_in_scope(&1, file))
  end

  defp function_bodies(ast) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {def_kind, _meta, [_head, block]} = node, bodies when def_kind in [:def, :defp] ->
          {node, add_function_body(block, bodies)}

        {def_kind, _meta, [{:when, _, [_head | _guards]}, block]} = node, bodies
        when def_kind in [:def, :defp] ->
          {node, add_function_body(block, bodies)}

        node, bodies ->
          {node, bodies}
      end)

    bodies
  end

  defp add_function_body([do: body], bodies), do: [body | bodies]
  defp add_function_body([{{:__block__, _meta, [:do]}, body}], bodies), do: [body | bodies]
  defp add_function_body(_block, bodies), do: bodies

  defp list_to_tuple_findings_in_scope(ast, file) do
    bindings = top_level_tuple_bindings(ast)

    if map_size(bindings) == 0 do
      []
    else
      readers = tuple_readers(ast, bindings)

      bindings
      |> Enum.flat_map(fn {var, _binding_meta} ->
        var_readers = Map.get(readers, var, [])

        cond do
          var_readers == [] -> []
          Enum.any?(var_readers, & &1.in_loop?) -> []
          true -> [list_to_tuple_finding(file, var, hd(var_readers).meta)]
        end
      end)
    end
  end

  defp top_level_tuple_bindings({:__block__, _meta, statements}) do
    statements
    |> Enum.reduce(%{}, fn
      {:=, meta, [{var, _, context}, rhs]}, bindings when is_atom(var) and is_atom(context) ->
        if list_to_tuple_call?(rhs), do: Map.put(bindings, var, meta), else: bindings

      _statement, bindings ->
        bindings
    end)
  end

  defp top_level_tuple_bindings({:=, meta, [{var, _, context}, rhs]})
       when is_atom(var) and is_atom(context) do
    if list_to_tuple_call?(rhs), do: %{var => meta}, else: %{}
  end

  defp top_level_tuple_bindings(_ast), do: %{}

  defp tuple_readers(ast, bindings) do
    {_ast, {_loop_depth, readers}} =
      Macro.traverse(
        ast,
        {0, %{}},
        fn node, {loop_depth, readers} ->
          readers = maybe_record_tuple_reader(node, bindings, loop_depth, readers)
          {node, {enter_loop(node, loop_depth), readers}}
        end,
        fn node, {loop_depth, readers} ->
          {node, {exit_loop(node, loop_depth), readers}}
        end
      )

    readers
  end

  defp maybe_record_tuple_reader(node, bindings, loop_depth, readers) do
    case elem_reader_var(node) do
      {:ok, var, meta} when is_map_key(bindings, var) ->
        Map.update(readers, var, [%{meta: meta, in_loop?: loop_depth > 0}], fn existing ->
          [%{meta: meta, in_loop?: loop_depth > 0} | existing]
        end)

      _ ->
        readers
    end
  end

  defp elem_reader_var({:elem, meta, [{var, _, context}, _index]})
       when is_atom(var) and is_atom(context),
       do: {:ok, var, meta}

  defp elem_reader_var(
         {{:., meta, [{:__aliases__, _, [:Kernel]}, :elem]}, _, [{var, _, context}, _index]}
       )
       when is_atom(var) and is_atom(context),
       do: {:ok, var, meta}

  defp elem_reader_var(_node), do: :error

  defp list_to_tuple_call?({{:., _, [{:__aliases__, _, [:List]}, :to_tuple]}, _, [_]}), do: true
  defp list_to_tuple_call?({:to_tuple, _, [_]}), do: false
  defp list_to_tuple_call?(_node), do: false

  defp enter_loop({:fn, _, _}, depth), do: depth + 1
  defp enter_loop({:for, _, _}, depth), do: depth + 1

  defp enter_loop({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}, depth)
       when fun in @loop_calls,
       do: depth + 1

  defp enter_loop(_node, depth), do: depth

  defp exit_loop({:fn, _, _}, depth), do: depth - 1
  defp exit_loop({:for, _, _}, depth), do: depth - 1

  defp exit_loop({{:., _, [{:__aliases__, _, [:Enum]}, fun]}, _, _}, depth)
       when fun in @loop_calls,
       do: depth - 1

  defp exit_loop(_node, depth), do: depth

  defp list_to_tuple_finding(file, var, meta) do
    Finding.new(
      kind: :list_to_tuple_for_access,
      message:
        "List.to_tuple/1 followed by elem/2 copies the list for one-shot indexed access; prefer pattern matching or Enum.at/2 unless repeated random access is needed",
      location: "#{file}:#{meta[:line] || 0}",
      evidence: %{variable: var}
    )
  end

  defp identity_float_findings(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn
        {op, meta, [expr, value]} = node, findings when op in [:*, :/, :+, :-] ->
          if identity_right?(op, literal_value(value)) and not bare_var?(expr) do
            {node, [identity_float_finding(file, meta, op) | findings]}
          else
            {node, findings}
          end

        {op, meta, [value, expr]} = node, findings when op in [:*, :+] ->
          if identity_left?(op, literal_value(value)) and not bare_var?(expr) do
            {node, [identity_float_finding(file, meta, op) | findings]}
          else
            {node, findings}
          end

        node, findings ->
          {node, findings}
      end)

    Enum.reverse(findings)
  end

  defp identity_right?(:*, value), do: value == 1.0
  defp identity_right?(:/, value), do: value == 1.0
  defp identity_right?(:+, value), do: value == 0.0
  defp identity_right?(:-, value), do: value == 0.0

  defp identity_left?(:*, value), do: value == 1.0
  defp identity_left?(:+, value), do: value == 0.0

  defp literal_value({:__block__, _meta, [value]}) when is_float(value), do: value
  defp literal_value(value) when is_float(value), do: value
  defp literal_value(_value), do: :unknown

  defp bare_var?({var, _, context}) when is_atom(var) and is_atom(context), do: true
  defp bare_var?(_expr), do: false

  defp identity_float_finding(file, meta, op) do
    Finding.new(
      kind: :identity_float_coercion,
      message:
        "identity float arithmetic with #{op} is unnecessary; remove the neutral float operand or use :erlang.float/1 for explicit coercion",
      location: "#{file}:#{meta[:line] || 0}"
    )
  end
end
