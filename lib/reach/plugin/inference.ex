defmodule Reach.Plugin.Inference do
  @moduledoc false

  @dependency_plugins %{
    ash: [Reach.Plugins.Ash],
    ecto: [Reach.Plugins.Ecto],
    ecto_sql: [Reach.Plugins.Ecto],
    ex_unit: [Reach.Plugins.ExUnit],
    gen_stage: [Reach.Plugins.GenStage],
    jason: [Reach.Plugins.Jason],
    jido: [Reach.Plugins.Jido],
    oban: [Reach.Plugins.Oban],
    opentelemetry: [Reach.Plugins.OpenTelemetry],
    opentelemetry_api: [Reach.Plugins.OpenTelemetry],
    phoenix: [Reach.Plugins.Phoenix],
    phoenix_html: [Reach.Plugins.Phoenix],
    phoenix_live_view: [Reach.Plugins.Phoenix, Reach.Plugins.LiveView],
    poison: [Reach.Plugins.Poison],
    quickbeam: [Reach.Plugins.QuickBEAM],
    quick_beam: [Reach.Plugins.QuickBEAM]
  }

  @source_markers [
    {Reach.Plugins.Phoenix,
     ["Phoenix.Router", "Phoenix.LiveView", "Phoenix.LiveComponent", "Phoenix.Component"]},
    {Reach.Plugins.LiveView, ["Phoenix.LiveView", "Phoenix.LiveComponent", "~H", "sigil_H"]},
    {Reach.Plugins.Ecto, ["Ecto", "Ecto.Schema", "Ecto.Query", "Ecto.Migration"]},
    {Reach.Plugins.Oban, ["Oban", "Oban.Worker"]},
    {Reach.Plugins.Ash, ["Ash", "Ash.Resource", "Ash.Domain"]},
    {Reach.Plugins.Jason, ["Jason."]},
    {Reach.Plugins.Poison, ["Poison."]},
    {Reach.Plugins.ExUnit, ["ExUnit.Case"]},
    {Reach.Plugins.GenStage, ["GenStage"]},
    {Reach.Plugins.OpenTelemetry, ["OpenTelemetry"]},
    {Reach.Plugins.QuickBEAM, ["QuickBEAM"]}
  ]

  def infer(paths) do
    paths = paths |> List.wrap() |> Enum.reject(&is_nil/1)
    files = source_files(paths)

    (infer_from_mix_files(paths) ++ infer_from_sources(files))
    |> Enum.uniq()
  end

  def infer_from_mix_file(path) do
    with {:ok, source} <- File.read(path),
         {:ok, ast} <- Code.string_to_quoted(source, emit_warnings: false) do
      ast
      |> dependency_names()
      |> Enum.flat_map(&Map.get(@dependency_plugins, &1, []))
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
        {dep, _meta, _args} = node, names
        when is_atom(dep) and is_map_key(@dependency_plugins, dep) ->
          {node, [dep | names]}

        {:{}, _meta, [dep | _rest]} = node, names
        when is_atom(dep) and is_map_key(@dependency_plugins, dep) ->
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
      [dep, _version] when is_atom(dep) and is_map_key(@dependency_plugins, dep) -> [dep]
      _entry -> []
    end)
  end

  defp source_plugins(file) do
    case File.read(file) do
      {:ok, source} ->
        for {plugin, markers} <- @source_markers,
            Enum.any?(markers, &String.contains?(source, &1)),
            do: plugin

      {:error, _reason} ->
        []
    end
  end
end
