defmodule Reach.Smell.PatternRunner do
  @moduledoc false

  alias ExAST.Patcher
  alias Reach.Smell.Finding
  alias Reach.Smell.Source

  def run(project, checks) do
    check_configs =
      Enum.map(checks, fn check ->
        {check, normalize_config(check, check.__reach_pattern_check__())}
      end)

    project
    |> source_files()
    |> Enum.flat_map(&scan_file(&1, check_configs))
  end

  defp normalize_config(module, %{patterns: patterns, queries: queries} = config) do
    %{
      config
      | patterns: Enum.map(patterns, &normalize_pattern(&1)),
        queries: Enum.map(queries, &normalize_query(module, &1))
    }
  end

  defp normalize_pattern({pattern, kind, message}),
    do: {pattern, kind, message, inferred_prefilter(pattern, :auto)}

  defp normalize_pattern({pattern, kind, message, prefilter}),
    do: {pattern, kind, message, inferred_prefilter(pattern, prefilter)}

  defp normalize_query(module, {fun_name, kind, message}),
    do: normalize_query(module, {fun_name, kind, message, :auto})

  defp normalize_query(module, {fun_name, kind, message, prefilter}) do
    selector = apply(module, fun_name, [])
    {fun_name, kind, message, inferred_prefilter(selector, prefilter)}
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

  defp source_matches?(_source, []), do: true
  defp source_matches?(nil, _prefilter), do: true

  defp source_matches?(source, {:all, prefilter}) when is_list(prefilter) do
    Enum.all?(prefilter, &String.contains?(source, &1))
  end

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

  defp add_pattern(
         {{pattern, kind, message, prefilter}, pattern_idx},
         module_idx,
         source,
         {named, meta}
       ) do
    if source_matches?(source, prefilter) do
      name = :"p#{module_idx}_#{pattern_idx}"
      {Map.put(named, name, pattern), Map.put(meta, name, {kind, message})}
    else
      {named, meta}
    end
  end

  defp find_query_smells(zipper, source, file, check_configs) do
    Enum.flat_map(check_configs, fn {module, %{queries: queries}} ->
      queries
      |> Enum.filter(fn {_fun_name, _kind, _message, prefilter} ->
        source_matches?(source, prefilter)
      end)
      |> Enum.flat_map(&query_smells(zipper, file, module, &1))
    end)
  end

  defp query_smells(zipper, file, module, {fun_name, kind, message, _prefilter}) do
    zipper
    |> Patcher.find_all(apply(module, fun_name, []))
    |> Enum.map(fn match ->
      line = (match.range && match.range.start[:line]) || 0
      Finding.new(kind: kind, message: message, location: "#{file}:#{line}")
    end)
  end

  defp inferred_prefilter(_term, false), do: []
  defp inferred_prefilter(_term, nil), do: []
  defp inferred_prefilter(_term, prefilter) when is_binary(prefilter), do: [prefilter]
  defp inferred_prefilter(_term, prefilter) when is_list(prefilter), do: prefilter

  defp inferred_prefilter(term, :auto) do
    case term |> remote_call_tokens() |> Enum.uniq() do
      [] -> structural_prefilter(term)
      tokens -> tokens
    end
  end

  defp structural_prefilter(term) do
    case term |> structural_tokens() |> Enum.uniq() do
      [] -> []
      tokens -> {:all, tokens}
    end
  end

  defp remote_call_tokens(term), do: remote_call_tokens(term, [])

  defp remote_call_tokens({{:., _, [{:__aliases__, _, aliases}, function]}, _, args}, tokens)
       when is_atom(function) do
    token = Enum.map_join(aliases, ".", &Atom.to_string/1) <> "." <> Atom.to_string(function)
    Enum.reduce(args, [token | tokens], &remote_call_tokens/2)
  end

  defp remote_call_tokens({:__aliases__, _, _aliases}, tokens), do: tokens

  defp remote_call_tokens(tuple, tokens) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(tokens, &remote_call_tokens/2)
  end

  defp remote_call_tokens(list, tokens) when is_list(list),
    do: Enum.reduce(list, tokens, &remote_call_tokens/2)

  defp remote_call_tokens(map, tokens) when is_map(map) do
    map
    |> Map.from_struct()
    |> Map.values()
    |> Enum.reduce(tokens, &remote_call_tokens/2)
  end

  defp remote_call_tokens(_term, tokens), do: tokens

  defp structural_tokens(term), do: structural_tokens(term, [])

  defp structural_tokens(%ExAST.Selector{steps: steps}, tokens),
    do: structural_tokens(steps, tokens)

  defp structural_tokens(%ExAST.Selector.Predicate{}, tokens), do: tokens

  defp structural_tokens({name, _meta, args}, tokens) when is_atom(name) and is_list(args) do
    args
    |> Enum.reduce(tokens, &structural_tokens/2)
    |> structural_token(name)
  end

  defp structural_tokens(tuple, tokens) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(tokens, &structural_tokens/2)
  end

  defp structural_tokens(list, tokens) when is_list(list),
    do: Enum.reduce(list, tokens, &structural_tokens/2)

  defp structural_tokens(map, tokens) when is_map(map), do: tokens

  defp structural_tokens(atom, tokens) when is_atom(atom), do: structural_token(tokens, atom)
  defp structural_tokens(_term, tokens), do: tokens

  defp structural_token(tokens, name) when name in [:case, :cond, :if, :unless, :fn, :defp],
    do: [Atom.to_string(name) | tokens]

  defp structural_token(tokens, value) when value in [true, false],
    do: [Atom.to_string(value) | tokens]

  defp structural_token(tokens, _name), do: tokens
end
