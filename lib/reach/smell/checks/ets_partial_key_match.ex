defmodule Reach.Smell.Checks.ETSPartialKeyMatch do
  @moduledoc "Detects ETS wildcard matches over versioned tuple keys that may return arbitrary rows."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:ets_partial_key_match]

  defp scan_ast(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        case partial_key_match(node) do
          nil -> {node, findings}
          meta -> {node, [finding(file, meta) | findings]}
        end
      end)

    Enum.reverse(findings)
  end

  defp partial_key_match({{:., meta, [module, function]}, _call_meta, [_table, pattern | _args]})
       when function in [:match_object, :match, :select, :match_delete] do
    if literal_atom(module) == :ets and versioned_tuple_key_wildcard?(pattern), do: meta
  end

  defp partial_key_match(_node), do: nil

  defp versioned_tuple_key_wildcard?(pattern) do
    case tuple_items(pattern) do
      [key | _rest] ->
        key_parts = tuple_items(key)
        length(key_parts) > 1 and wildcard_tuple_key?(key_parts)

      _other ->
        false
    end
  end

  defp tuple_items({:{}, _meta, items}) when is_list(items), do: items
  defp tuple_items({:__block__, _meta, [items]}) when is_list(items), do: items
  defp tuple_items({:__block__, _meta, [{left, right}]}), do: [left, right]
  defp tuple_items({left, right}), do: [left, right]
  defp tuple_items(_pattern), do: []

  defp wildcard_tuple_key?(key_parts) do
    Enum.any?(Enum.drop(key_parts, 1), &wildcard?/1)
  end

  defp wildcard?({:_, _meta, context}), do: is_atom(context)
  defp wildcard?(part), do: literal_atom(part) == :_

  defp literal_atom({:__block__, _meta, [atom]}) when is_atom(atom), do: atom
  defp literal_atom(atom) when is_atom(atom), do: atom
  defp literal_atom(_value), do: nil

  defp finding(file, meta) do
    Finding.new(
      kind: :ets_partial_key_match,
      message:
        "ETS match uses a wildcard inside a tuple key; if multiple versions can exist, lookup may return an arbitrary row",
      location: %{file: file, line: meta[:line] || 0, column: meta[:column]}
    )
  end
end
