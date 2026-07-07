defmodule Reach.Smell.Checks.KeywordGetIntegerKey do
  @moduledoc "Detects Keyword.get/2 calls with integer literal keys."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.{Finding, Source}

  @message "Keyword.get/2 requires atom keys; an integer key always raises FunctionClauseError"

  @impl true
  def run(project) do
    project
    |> Source.module_files()
    |> Enum.flat_map(&file_findings/1)
  end

  defp file_findings(file) do
    if File.regular?(file) do
      ast = Source.cached_ast(file)
      piped_positions = piped_get_positions(ast)

      {_ast, findings} =
        Macro.prewalk(ast, [], fn node, findings ->
          {node, node_findings(node, file, piped_positions) ++ findings}
        end)

      Enum.reverse(findings)
    else
      []
    end
  rescue
    _error in [ArgumentError, File.Error, MatchError] -> []
  end

  defp node_findings(
         {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [_list, key]},
         file,
         piped
       ) do
    if not MapSet.member?(piped, position(meta)) and integer_literal?(key) do
      [finding(file, meta)]
    else
      []
    end
  end

  defp node_findings({{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, [key]}, file, _piped) do
    if integer_literal?(key), do: [finding(file, meta)], else: []
  end

  defp node_findings(_node, _file, _piped), do: []

  defp piped_get_positions(ast) do
    {_ast, positions} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:|>, _, [_lhs, {{:., _, [{:__aliases__, _, [:Keyword]}, :get]}, meta, _args}]} = node,
        positions ->
          {node, MapSet.put(positions, position(meta))}

        node, positions ->
          {node, positions}
      end)

    positions
  end

  defp integer_literal?({:__block__, _meta, [value]}), do: integer_literal?(value)
  defp integer_literal?({:-, _meta, [value]}), do: is_integer(unwrap_literal(value))
  defp integer_literal?(value), do: is_integer(value)

  defp unwrap_literal({:__block__, _meta, [value]}), do: value
  defp unwrap_literal(value), do: value

  defp position(meta), do: {Keyword.get(meta, :line), Keyword.get(meta, :column)}

  defp finding(file, meta) do
    Finding.new(kind: :bug_risk, message: @message, location: "#{file}:#{meta[:line] || 0}")
  end
end
