defmodule Reach.Smell.PatternRunner do
  @moduledoc false

  alias ExAST.Patcher
  alias Reach.Smell.Finding
  alias Reach.Smell.Source

  def run(project, checks) do
    check_configs = Enum.map(checks, &{&1, &1.__reach_pattern_check__()})

    project
    |> source_files()
    |> Enum.flat_map(&scan_file(&1, check_configs))
  end

  defp source_files(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_, %{type: :module_def, source_span: %{file: file}}} when is_binary(file) -> [file]
      _ -> []
    end)
    |> Enum.uniq()
  end

  defp scan_file(file, check_configs) do
    if File.regular?(file) do
      active_configs = Enum.reject(check_configs, &same_source_file?(&1, file))
      zipper = Source.cached_zipper(file)

      find_pattern_smells(zipper, file, active_configs) ++
        find_query_smells(zipper, file, active_configs)
    else
      []
    end
  rescue
    _ -> []
  end

  defp same_source_file?({_module, %{source: source}}, file) do
    Path.expand(source) == Path.expand(file)
  end

  defp find_pattern_smells(zipper, file, check_configs) do
    {named, meta} = pattern_maps(check_configs)

    if map_size(named) == 0 do
      []
    else
      zipper
      |> Patcher.find_many(named)
      |> Enum.map(fn match ->
        {kind, message} = Map.fetch!(meta, match.pattern)
        line = (match.range && match.range.start[:line]) || 0
        Finding.new(kind: kind, message: message, location: "#{file}:#{line}")
      end)
    end
  end

  defp pattern_maps(check_configs) do
    check_configs
    |> Stream.with_index()
    |> Enum.reduce({%{}, %{}}, fn {{_module, %{patterns: patterns}}, module_idx}, {named, meta} ->
      patterns
      |> Stream.with_index()
      |> Enum.reduce({named, meta}, fn {{pattern, kind, message}, pattern_idx}, {named, meta} ->
        name = :"p#{module_idx}_#{pattern_idx}"
        {Map.put(named, name, pattern), Map.put(meta, name, {kind, message})}
      end)
    end)
  end

  defp find_query_smells(zipper, file, check_configs) do
    Enum.flat_map(check_configs, fn {module, %{queries: queries}} ->
      Enum.flat_map(queries, &query_smells(zipper, file, module, &1))
    end)
  end

  defp query_smells(zipper, file, module, {fun_name, kind, message}) do
    zipper
    |> Patcher.find_all(apply(module, fun_name, []))
    |> Enum.map(fn match ->
      line = (match.range && match.range.start[:line]) || 0
      Finding.new(kind: kind, message: message, location: "#{file}:#{line}")
    end)
  end
end
