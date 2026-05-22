defmodule Reach.Smell.ASTRunner do
  @moduledoc false

  alias Reach.Smell.Finding
  alias Reach.Smell.PatternConfig
  alias Reach.Smell.Source

  def run(project, checks) do
    checks
    |> Enum.flat_map(&check_entries/1)
    |> run_entries(project)
  end

  defp check_entries(check) do
    if function_exported?(check, :__reach_ast_smells__, 0) do
      Enum.map(check.__reach_ast_smells__(), &{check, &1})
    else
      []
    end
  end

  defp run_entries([], _project), do: []

  defp run_entries(entries, project) do
    project
    |> Source.module_files()
    |> Enum.flat_map(&scan_file(&1, entries))
  end

  defp scan_file(file, entries) do
    if File.regular?(file) do
      source = File.read!(file)
      active_entries = Enum.filter(entries, &entry_matches_source?(source, &1))

      if active_entries == [] do
        []
      else
        file
        |> Source.cached_ast()
        |> scan_ast(file, active_entries)
      end
    else
      []
    end
  rescue
    _error in [ArgumentError, File.Error, MatchError] -> []
  end

  defp entry_matches_source?(source, {_check, {_callback, _kind, _message, prefilter}}) do
    PatternConfig.source_matches?(source, prefilter)
  end

  defp scan_ast(ast, file, entries) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        {node, node_findings(node, file, entries) ++ findings}
      end)

    Enum.reverse(findings)
  end

  defp node_findings(node, file, entries) do
    Enum.flat_map(entries, fn {check, {callback, kind, message, _prefilter}} ->
      check.__reach_ast_smell_match__(callback, node)
      |> finding_result(file, kind, message)
    end)
  end

  defp finding_result(nil, _file, _kind, _message), do: []
  defp finding_result(false, _file, _kind, _message), do: []
  defp finding_result(:error, _file, _kind, _message), do: []
  defp finding_result(:ok, file, kind, message), do: [finding(file, [], kind, message)]
  defp finding_result({:ok, meta}, file, kind, message), do: [finding(file, meta, kind, message)]

  defp finding_result({:ok, meta, message}, file, kind, _message),
    do: [finding(file, meta, kind, message)]

  defp finding_result({:ok, meta, kind, message}, file, _kind, _message),
    do: [finding(file, meta, kind, message)]

  defp finding_result(_other, _file, _kind, _message), do: []

  defp finding(file, meta, kind, message) do
    Finding.new(kind: kind, message: message, location: "#{file}:#{meta[:line] || 0}")
  end
end
