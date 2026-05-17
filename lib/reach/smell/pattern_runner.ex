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
      source = lazy_source(file, active_configs)
      zipper = Source.cached_zipper(file)

      find_pattern_smells(zipper, source, file, active_configs) ++
        find_query_smells(zipper, source, file, active_configs)
    else
      []
    end
  rescue
    _ -> []
  end

  defp same_source_file?({_module, %{source: source}}, file) do
    Path.expand(source) == Path.expand(file)
  end

  defp lazy_source(file, check_configs) do
    if Enum.any?(check_configs, fn {_module, %{patterns: patterns, queries: queries}} ->
         Enum.any?(patterns, &prefiltered?/1) or Enum.any?(queries, &prefiltered?/1)
       end) do
      File.read!(file)
    end
  end

  defp prefiltered?({_name_or_pattern, _kind, _message, prefilter}), do: prefilter != []
  defp prefiltered?(_entry), do: false

  defp source_matches?(_source, []), do: true
  defp source_matches?(nil, _prefilter), do: true

  defp source_matches?(source, prefilter) when is_list(prefilter) do
    Enum.any?(prefilter, &String.contains?(source, &1))
  end

  defp source_matches?(source, prefilter) when is_binary(prefilter),
    do: String.contains?(source, prefilter)

  defp find_pattern_smells(zipper, source, file, check_configs) do
    {named, meta} = pattern_maps(check_configs, source)

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

  defp pattern_maps(check_configs, source) do
    check_configs
    |> Stream.with_index()
    |> Enum.reduce({%{}, %{}}, fn {{_module, %{patterns: patterns}}, module_idx}, acc ->
      add_patterns(patterns, module_idx, source, acc)
    end)
  end

  defp add_patterns(patterns, module_idx, source, acc) do
    patterns
    |> Stream.with_index()
    |> Enum.reduce(acc, fn pattern_entry, acc ->
      add_pattern(pattern_entry, module_idx, source, acc)
    end)
  end

  defp add_pattern(pattern_entry, module_idx, source, {named, meta}) do
    {{pattern, kind, message, prefilter}, pattern_idx} = normalize_pattern_entry(pattern_entry)

    if source_matches?(source, prefilter) do
      name = :"p#{module_idx}_#{pattern_idx}"
      {Map.put(named, name, pattern), Map.put(meta, name, {kind, message})}
    else
      {named, meta}
    end
  end

  defp normalize_pattern_entry({{pattern, kind, message}, pattern_idx}),
    do: {{pattern, kind, message, []}, pattern_idx}

  defp normalize_pattern_entry({{pattern, kind, message, prefilter}, pattern_idx}),
    do: {{pattern, kind, message, prefilter}, pattern_idx}

  defp find_query_smells(zipper, source, file, check_configs) do
    Enum.flat_map(check_configs, fn {module, %{queries: queries}} ->
      queries
      |> Enum.map(&normalize_query_entry/1)
      |> Enum.filter(fn {_fun_name, _kind, _message, prefilter} ->
        source_matches?(source, prefilter)
      end)
      |> Enum.flat_map(&query_smells(zipper, file, module, &1))
    end)
  end

  defp normalize_query_entry({fun_name, kind, message}), do: {fun_name, kind, message, []}

  defp normalize_query_entry({fun_name, kind, message, prefilter}),
    do: {fun_name, kind, message, prefilter}

  defp query_smells(zipper, file, module, {fun_name, kind, message, _prefilter}) do
    zipper
    |> Patcher.find_all(apply(module, fun_name, []))
    |> Enum.map(fn match ->
      line = (match.range && match.range.start[:line]) || 0
      Finding.new(kind: kind, message: message, location: "#{file}:#{line}")
    end)
  end
end
