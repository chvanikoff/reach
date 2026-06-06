defmodule Reach.Plugin.Inference do
  @moduledoc false

  def infer(paths) do
    paths = paths |> List.wrap() |> Enum.reject(&is_nil/1)
    files = source_files(paths)

    (infer_from_mix_files(paths) ++ infer_from_sources(files))
    |> Enum.uniq()
  end

  def infer_from_mix_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source, emit_warnings: false) do
      deps = dependency_names(ast)

      Reach.Plugin.built_in_plugins()
      |> Enum.filter(&dependency_match?(&1, deps))
      |> Enum.uniq()
    else
      _error -> []
    end
  end

  def infer_from_sources(files) do
    files
    |> Enum.flat_map(&source_plugins/1)
    |> Enum.uniq()
  end

  defp infer_from_mix_files(paths) do
    paths
    |> Enum.flat_map(&nearest_mix_files/1)
    |> Enum.uniq()
    |> Enum.flat_map(&infer_from_mix_file/1)
  end

  defp nearest_mix_files(path) do
    path
    |> root_candidate()
    |> ancestor_dirs()
    |> Enum.find_value([], fn dir ->
      mix = Path.join(dir, "mix.exs")
      if File.regular?(mix), do: [mix]
    end)
  end

  defp root_candidate(path) do
    expanded = Path.expand(path)

    if File.dir?(expanded), do: expanded, else: Path.dirname(expanded)
  end

  defp ancestor_dirs(dir) do
    dir
    |> Path.expand()
    |> Stream.iterate(&Path.dirname/1)
    |> Enum.reduce_while([], fn current, acc ->
      next = Path.dirname(current)
      acc = [current | acc]

      if next == current, do: {:halt, Enum.reverse(acc)}, else: {:cont, acc}
    end)
  end

  defp source_files(paths) do
    paths
    |> Enum.flat_map(&source_files_for_path/1)
    |> Enum.uniq()
  end

  defp source_files_for_path(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        Path.wildcard(Path.join(path, "**/*.{ex,exs,erl,hrl,gleam,heex,js,jsx,ts,tsx}"))

      true ->
        Path.wildcard(path)
    end
  end

  defp dependency_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {:{}, _meta, [dep | _rest]} = node, names when is_atom(dep) ->
          {node, [dep | names]}

        {dep, _meta, _args} = node, names when is_atom(dep) ->
          {node, [dep | names]}

        tuple, names when is_tuple(tuple) ->
          {tuple, dependency_names_from_tuple(tuple) ++ names}

        node, names ->
          {node, names}
      end)

    Enum.uniq(names)
  end

  defp dependency_names_from_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.chunk_every(2)
    |> Enum.flat_map(fn
      [dep, _version] when is_atom(dep) -> [dep]
      _entry -> []
    end)
  end

  defp dependency_match?(plugin, deps) do
    hints(plugin)
    |> Map.get(:deps, [])
    |> Enum.any?(&(&1 in deps))
  end

  defp source_match?(plugin, source) do
    hints(plugin)
    |> Map.get(:source, [])
    |> Enum.any?(&String.contains?(source, &1))
  end

  defp hints(plugin) do
    if Code.ensure_loaded?(plugin) and function_exported?(plugin, :inference_hints, 0) do
      plugin.inference_hints()
    else
      %{}
    end
  end

  defp source_plugins(file) do
    case File.read(file) do
      {:ok, source} ->
        Reach.Plugin.built_in_plugins()
        |> Enum.filter(&source_match?(&1, source))

      {:error, _reason} ->
        []
    end
  end
end
