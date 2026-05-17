defmodule Reach.Scripts.SmellCorpusScan do
  @moduledoc false

  @default_globs ["lib/**/*.ex", "apps/*/lib/**/*.ex"]
  @default_plugins [Reach.Plugins.Ecto, Reach.Plugins.Phoenix, Reach.Plugins.Oban]

  def main(argv) do
    {opts, positional, invalid} =
      OptionParser.parse(argv,
        strict: [
          repos_file: :string,
          repo: :keep,
          output: :string,
          limit: :integer,
          glob: :keep,
          plugin: :keep,
          include_tests: :boolean,
          kinds: :string,
          help: :boolean
        ],
        aliases: [r: :repo, o: :output, l: :limit, g: :glob, p: :plugin, h: :help]
      )

    if Keyword.get(opts, :help, false) or invalid != [] do
      print_usage(invalid)
      if invalid == [], do: System.halt(0), else: System.halt(2)
    end

    repos = repos(opts, positional)
    output = opts[:output] || Path.join(File.cwd!(), "smell-corpus-results.json")
    globs = globs(opts)
    plugins = plugins(opts)
    kinds = kinds(opts)

    rows = Enum.map(repos, &scan_repo(&1, globs, plugins, opts[:limit], kinds))

    File.mkdir_p!(Path.dirname(Path.expand(output)))
    File.write!(output, Jason.encode!(rows, pretty: true))

    print_summary(rows, output)
  end

  defp repos(opts, positional) do
    cli_repos = Keyword.get_values(opts, :repo) ++ positional

    file_repos =
      case opts[:repos_file] do
        nil ->
          []

        path ->
          path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "#")))
      end

    (cli_repos ++ file_repos)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  defp globs(opts) do
    base = Keyword.get_values(opts, :glob)
    base = if base == [], do: @default_globs, else: base

    if Keyword.get(opts, :include_tests, false) do
      base ++ ["test/**/*.exs", "apps/*/test/**/*.exs"]
    else
      base
    end
  end

  defp plugins(opts) do
    case Keyword.get_values(opts, :plugin) do
      [] -> @default_plugins
      names -> Enum.map(names, &module!/1)
    end
  end

  defp kinds(opts) do
    case opts[:kinds] do
      nil ->
        nil

      value ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
        |> MapSet.new()
    end
  end

  defp scan_repo(repo, globs, plugins, limit, kinds) do
    paths = source_paths(repo, globs, limit)
    IO.puts("Scanning #{repo} (#{length(paths)} files)")

    try do
      {load_us, project} =
        :timer.tc(fn -> Reach.Project.from_sources(paths, plugins: plugins) end)

      checks = Reach.Smell.Registry.checks(project, Reach.Config.normalize([]))
      {pattern_checks, semantic_checks} = Enum.split_with(checks, &pattern_check?/1)

      {pattern_us, pattern_findings} =
        :timer.tc(fn -> Reach.Smell.PatternRunner.run(project, pattern_checks) end)

      {semantic_us, semantic_findings} =
        :timer.tc(fn -> Enum.flat_map(semantic_checks, &run_check(&1, project)) end)

      findings = filter_kinds(pattern_findings ++ semantic_findings, kinds)

      %{
        repo: repo,
        files: length(paths),
        load_ms: div(load_us, 1000),
        pattern_ms: div(pattern_us, 1000),
        semantic_ms: div(semantic_us, 1000),
        count: length(findings),
        kinds: Enum.frequencies_by(findings, & &1.kind),
        findings: Enum.map(findings, &finding_json/1)
      }
    rescue
      exception ->
        %{
          repo: repo,
          files: length(paths),
          error: Exception.format(:error, exception, __STACKTRACE__),
          count: 0,
          findings: []
        }
    end
  end

  defp source_paths(repo, globs, limit) do
    globs
    |> Enum.flat_map(&Path.wildcard(Path.join(repo, &1)))
    |> Enum.reject(&String.contains?(&1, "/deps/"))
    |> Enum.reject(&String.contains?(&1, "/_build/"))
    |> Enum.uniq()
    |> maybe_limit(limit)
  end

  defp maybe_limit(paths, nil), do: paths
  defp maybe_limit(paths, limit), do: Enum.take(paths, limit)

  defp pattern_check?(check) do
    Code.ensure_loaded?(check) and function_exported?(check, :__reach_pattern_check__, 0)
  end

  defp run_check(check, project) do
    config = Reach.Config.normalize([])

    if function_exported?(check, :run, 2),
      do: check.run(project, config),
      else: check.run(project)
  end

  defp filter_kinds(findings, nil), do: findings
  defp filter_kinds(findings, kinds), do: Enum.filter(findings, &MapSet.member?(kinds, &1.kind))

  defp finding_json(finding) do
    %{
      kind: finding.kind,
      location: finding.location,
      message: finding.message,
      evidence: finding.evidence
    }
  end

  defp module!(name) do
    module = Module.concat([name])

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("Could not load plugin module #{name}")
    end
  end

  defp print_summary(rows, output) do
    Enum.each(rows, fn row ->
      timings =
        if row[:error] do
          "error"
        else
          "load=#{row.load_ms}ms pattern=#{row.pattern_ms}ms semantic=#{row.semantic_ms}ms"
        end

      IO.puts("#{row.repo}: files=#{row.files} findings=#{row.count} #{timings}")
      if row[:kinds], do: IO.puts("  #{inspect(row.kinds)}")
    end)

    IO.puts("Wrote #{Path.expand(output)}")
  end

  defp print_usage(invalid) do
    if invalid != [], do: IO.puts(:stderr, "Invalid options: #{inspect(invalid)}")

    IO.puts("""
    Usage:
      mix run scripts/smell_corpus_scan.exs --repo PATH [--repo PATH ...]
      mix run scripts/smell_corpus_scan.exs --repos-file repos.txt

    Options:
      --repo, -r PATH        Repository directory to scan. May be repeated.
      --repos-file PATH      Newline-separated repository directories. Blank lines and # comments ignored.
      --output, -o PATH      JSON output path. Defaults to ./smell-corpus-results.json.
      --limit, -l N          Maximum source files per repository.
      --glob, -g GLOB        Source glob relative to each repo. May be repeated.
      --include-tests        Include test/**/*.exs and apps/*/test/**/*.exs.
      --plugin, -p MODULE    Plugin module. May be repeated. Defaults to Ecto, Phoenix, Oban.
      --kinds a,b,c          Only include selected smell kinds in the output.
      --help, -h             Show this help.
    """)
  end
end

Reach.Scripts.SmellCorpusScan.main(System.argv())
