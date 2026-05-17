defmodule Reach.Plugins.Ecto.Smells.ImplicitCrossJoin do
  @moduledoc "Detects Ecto queries that use multiple from generators instead of explicit joins."

  use Reach.Smell.ASTCheck

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:ecto_implicit_cross_join]

  defp scan_ast(ast, file) do
    find_implicit_cross_joins(ast, file)
  end

  defp find_implicit_cross_joins(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn
        {:from, meta, args} = node, findings ->
          finding = if implicit_cross_join?(args), do: [finding(file, meta)], else: []
          {node, finding ++ findings}

        node, findings ->
          {node, findings}
      end)

    Enum.reverse(findings)
  end

  defp implicit_cross_join?(args) do
    generators = Enum.count(args, &match?({:in, _, [_binding, _source]}, &1))
    keywords = Enum.flat_map(args, &keyword_entries/1)

    generators > 1 and not Keyword.has_key?(keywords, :join)
  end

  defp keyword_entries(entries) when is_list(entries) do
    Enum.filter(entries, &match?({key, _value} when is_atom(key), &1))
  end

  defp keyword_entries(_entry), do: []

  defp finding(file, meta) do
    line = meta[:line] || 0

    Finding.new(
      kind: :ecto_implicit_cross_join,
      message:
        "Ecto query uses multiple from generators; use explicit join/on to avoid accidental cross joins",
      location: "#{file}:#{line}"
    )
  end
end
