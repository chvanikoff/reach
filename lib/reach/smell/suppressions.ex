defmodule Reach.Smell.Suppressions do
  @moduledoc "Filters smell findings using config ignores and shared source-level suppressions."

  alias Reach.Check.Architecture
  alias Reach.Suppressions

  def filter(findings, project, config) do
    findings
    |> Suppressions.filter(&tokens/1)
    |> Enum.reject(fn finding ->
      suppressed_by_config?(finding, config) or suppressed_by_module?(finding, project, config)
    end)
  end

  defp tokens(finding), do: [Atom.to_string(finding.kind), "smells", "all"]

  def suppressed_by_config?(finding, config) do
    case Suppressions.location(finding) do
      {file, _line} when is_binary(file) ->
        finding
        |> ignore_configs(config)
        |> Enum.any?(fn ignore ->
          ignore
          |> Keyword.get(:paths, [])
          |> List.wrap()
          |> Enum.any?(&Architecture.glob_match?(file, to_string(&1)))
        end)

      _ ->
        false
    end
  end

  def suppressed_by_module?(finding, project, config) do
    ignores = ignore_configs(finding, config)

    case finding_module(finding, project) do
      nil ->
        false

      module ->
        Enum.any?(ignores, fn ignore ->
          ignore
          |> Keyword.get(:modules, [])
          |> List.wrap()
          |> Enum.any?(&Architecture.module_matches_any?(module, [&1]))
        end)
    end
  end

  defp ignore_configs(finding, config) do
    smells = config.smells
    global_ignore = Map.get(smells, :ignore, [])
    per_check_ignore = per_check_ignore(smells, finding.kind)

    [global_ignore, per_check_ignore]
    |> Enum.filter(&Keyword.keyword?/1)
  end

  defp per_check_ignore(smells, kind) do
    smells
    |> Map.get(kind)
    |> case do
      value when is_map(value) -> Map.get(value, :ignore, [])
      _ -> []
    end
  end

  defp finding_module(finding, project) do
    module_from_finding(finding) || module_from_location(finding, project)
  end

  defp module_from_finding(%{modules: [module | _]}) when is_atom(module), do: module
  defp module_from_finding(_finding), do: nil

  defp module_from_location(finding, project) do
    case Suppressions.location(finding) do
      {file, line} when is_binary(file) and is_integer(line) ->
        project.nodes
        |> Enum.map(fn {_id, node} -> node end)
        |> Enum.filter(&module_in_file?(&1, file))
        |> Enum.find_value(&module_at_line(&1, line))

      _ ->
        nil
    end
  end

  defp module_in_file?(node, file) do
    (node.type == :module_def and node.source_span) && node.source_span.file == file
  end

  defp module_at_line(node, line) do
    span = node.source_span

    if line >= span.start_line and (is_nil(span.end_line) or line <= span.end_line) do
      node.meta[:name]
    end
  end
end
