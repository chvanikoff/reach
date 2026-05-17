defmodule Reach.Plugins.Ecto.Smells.UnpinnedQueryValue do
  @moduledoc "Detects unpinned local variables in Ecto query comparisons."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:ecto_unpinned_query_value]

  defp scan_ast(ast, file) do
    find_unpinned_values(ast, file)
  end

  defp find_unpinned_values(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn
        {:from, _meta, args} = node, findings ->
          {node, findings_for_from(args, file) ++ findings}

        node, findings ->
          {node, findings}
      end)

    Enum.reverse(findings)
  end

  defp findings_for_from(args, file) do
    bindings = query_bindings(args)

    args
    |> Enum.flat_map(&keyword_entries/1)
    |> Keyword.get_values(:where)
    |> Enum.flat_map(&comparison_findings(&1, bindings, file))
  end

  defp query_bindings(args) do
    args
    |> Enum.flat_map(fn
      {:in, _meta, [{name, _binding_meta, context}, _source]}
      when is_atom(name) and is_atom(context) ->
        [name]

      _arg ->
        []
    end)
    |> MapSet.new()
  end

  defp keyword_entries(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      {key, value} when is_atom(key) -> [{key, value}]
      {{:__block__, _meta, [key]}, value} when is_atom(key) -> [{key, value}]
      _entry -> []
    end)
  end

  defp keyword_entries(_entry), do: []

  defp comparison_findings(ast, bindings, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn
        {:==, meta, [left, right]} = node, findings ->
          finding = comparison_finding(left, right, bindings, file, meta)
          {node, maybe_add(finding, findings)}

        node, findings ->
          {node, findings}
      end)

    findings
  end

  defp comparison_finding(left, right, bindings, file, meta) do
    cond do
      field_access?(left, bindings) and unpinned_local_value?(right, bindings) ->
        finding(file, meta)

      field_access?(right, bindings) and unpinned_local_value?(left, bindings) ->
        finding(file, meta)

      true ->
        nil
    end
  end

  defp field_access?(
         {{:., _dot_meta, [{binding, _meta, context}, _field]}, _call_meta, []},
         bindings
       )
       when is_atom(binding) and is_atom(context) do
    MapSet.member?(bindings, binding)
  end

  defp field_access?(_ast, _bindings), do: false

  defp unpinned_local_value?({:^, _meta, [_value]}, _bindings), do: false

  defp unpinned_local_value?({name, _meta, context}, bindings)
       when is_atom(name) and is_atom(context) do
    not MapSet.member?(bindings, name) and name not in [nil, :_, :__MODULE__]
  end

  defp unpinned_local_value?(_ast, _bindings), do: false

  defp maybe_add(nil, findings), do: findings
  defp maybe_add(finding, findings), do: [finding | findings]

  defp finding(file, meta) do
    Finding.new(
      kind: :ecto_unpinned_query_value,
      message:
        "Ecto query compares a field with an unpinned local variable; use ^variable to inject values",
      location: "#{file}:#{meta[:line] || 0}"
    )
  end
end
