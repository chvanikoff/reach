defmodule Reach.MacroFactScan do
  @moduledoc false

  def run(["--" | argv]), do: run(argv)

  def run(argv) do
    {opts, args, invalid} =
      OptionParser.parse(argv,
        strict: [
          framework: :string,
          kind: :string,
          limit: :integer,
          format: :string,
          plugin: :keep
        ],
        aliases: [f: :framework, k: :kind, n: :limit, p: :plugin]
      )

    if invalid != [], do: usage("invalid option(s): #{inspect(invalid)}")

    framework = atom_filter(opts[:framework])
    kind = atom_filter(opts[:kind])
    limit = Keyword.get(opts, :limit, 20)
    format = Keyword.get(opts, :format, "text")

    unless format in ["text", "json"], do: usage("unknown format #{inspect(format)}")

    plugins = plugins(opts)

    case args do
      [] -> usage("expected at least one repository or source directory")
      paths -> scan(paths, plugins, framework, kind, limit, format)
    end
  end

  defp plugins(opts) do
    case Keyword.get_values(opts, :plugin) do
      [] -> Reach.Plugin.detect()
      names -> Enum.map(names, &module!/1)
    end
  end

  defp module!(name) do
    module = Module.concat([name])

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("Could not load plugin module #{name}")
    end
  end

  defp scan(paths, plugins, framework, kind, limit, format) do
    paths
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "{lib,test}/**/*.{ex,exs}")))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(&scan_file(&1, plugins))
    |> filter_framework(framework)
    |> filter_kind(kind)
    |> print_results(limit, format)
  end

  defp scan_file(path, plugins) do
    case Reach.MacroFact.collect_file(path, plugins: plugins) do
      {:ok, facts} -> facts
      {:error, _reason} -> []
    end
  end

  defp filter_framework(facts, nil), do: facts
  defp filter_framework(facts, framework), do: Reach.MacroFact.by_framework(facts, framework)

  defp filter_kind(facts, nil), do: facts
  defp filter_kind(facts, kind), do: Reach.MacroFact.by_kind(facts, kind)

  defp print_results(facts, _limit, "json") do
    facts
    |> Enum.map(&json_fact/1)
    |> Jason.encode!(pretty: true)
    |> IO.puts()
  end

  defp print_results(facts, limit, "text") do
    IO.puts("Macro fact scan")
    IO.puts("total=#{length(facts)}")

    facts
    |> Enum.frequencies_by(& &1.framework)
    |> Enum.sort_by(fn {framework, count} -> {-count, framework || :zz_none} end)
    |> Enum.each(fn {framework, count} ->
      IO.puts("framework=#{framework || :none} count=#{count}")
    end)

    IO.puts("\n## Kinds")

    facts
    |> Enum.frequencies_by(& &1.kind)
    |> Enum.sort_by(fn {kind, count} -> {-count, kind} end)
    |> Enum.each(fn {kind, count} -> IO.puts("#{kind}=#{count}") end)

    IO.puts("\n## Examples")

    facts
    |> Enum.take(limit)
    |> Enum.each(fn fact ->
      source = fact.source || %{}
      file = source[:file] || "nofile"
      line = source[:line] || 0
      owner = fact.owner_module || "unknown"
      target = inspect(fact.target)

      IO.puts("- #{fact.kind} #{file}:#{line} owner=#{inspect(owner)} target=#{target}")
    end)
  end

  defp json_fact(fact) do
    fact
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  defp json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> json_value()
  defp json_value(value) when is_list(value), do: Enum.map(value, &json_value/1)

  defp json_value(value) when is_map(value) do
    Map.new(value, fn {key, value} -> {to_string(key), json_value(value)} end)
  end

  defp json_value(value), do: value

  defp atom_filter(nil), do: nil

  defp atom_filter(value) do
    value
    |> String.trim()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp usage(message) do
    Mix.raise("""
    #{message}

    Usage:
      mix run scripts/macro_fact_scan.exs PATH [PATH...]
      mix run scripts/macro_fact_scan.exs -- --framework phoenix PATH [PATH...]
      mix run scripts/macro_fact_scan.exs -- --kind phoenix_route --format json PATH [PATH...]

    Options:
      --framework, -f NAME  Only include facts refined for a framework, e.g. phoenix, ecto, ash.
      --plugin, -p MODULE   Plugin module. May be repeated. Defaults to auto-detected plugins.
      --kind, -k KIND       Only include one macro fact kind.
      --limit, -n N         Number of text examples. Defaults to 20.
      --format FORMAT       text or json. Defaults to text.
    """)
  end
end

Reach.MacroFactScan.run(System.argv())
