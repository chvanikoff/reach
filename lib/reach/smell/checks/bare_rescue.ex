defmodule Reach.Smell.Checks.BareRescue do
  @moduledoc "Detects rescue clauses that catch every exception type."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:bare_rescue]

  defp scan_ast(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        {node, findings ++ findings_for_rescue(node, file)}
      end)

    findings
  end

  defp findings_for_rescue({{:__block__, _meta, [:rescue]}, clauses}, file)
       when is_list(clauses) do
    clauses
    |> Enum.flat_map(fn
      {:->, meta, [[pattern], _body]} -> finding_for_pattern(pattern, meta, file)
      _clause -> []
    end)
  end

  defp findings_for_rescue(_node, _file), do: []

  defp finding_for_pattern(pattern, meta, file) do
    if bare_pattern?(pattern) do
      [
        Finding.new(
          kind: :bare_rescue,
          message:
            "bare rescue catches every exception type; rescue specific exception modules or use `exception in [...]`",
          location: %{file: file, line: meta[:line] || 0, column: meta[:column]}
        )
      ]
    else
      []
    end
  end

  defp bare_pattern?({:_, _meta, context}), do: is_atom(context)

  defp bare_pattern?({name, _meta, context})
       when is_atom(name) and is_atom(context) and name not in [:__aliases__, :in],
       do: true

  defp bare_pattern?(_pattern), do: false
end
