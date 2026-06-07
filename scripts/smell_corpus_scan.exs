defmodule Reach.Scripts.SmellCorpusScan do
  @moduledoc false

  @default_globs ["lib/**/*.ex", "apps/*/lib/**/*.ex"]
  @default_plugins [
    Reach.Plugins.Ecto,
    Reach.Plugins.Phoenix,
    Reach.Plugins.Oban,
    Reach.Plugins.ExUnit
  ]

  def main(argv) do
    {opts, positional, invalid} =
      OptionParser.parse(argv,
        strict: [
          repos_file: :string,
          repo: :keep,
          output: :string,
          limit: :integer,
          glob: :keep,
          plugins: :keep,
          include_tests: :boolean,
          kinds: :string,
          quiet_zero: :boolean,
          progress_every: :integer,
          fail_fast: :boolean,
          help: :boolean
        ],
        aliases: [r: :repo, o: :output, l: :limit, g: :glob, p: :plugins, h: :help]
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
    quiet_zero = Keyword.get(opts, :quiet_zero, false)
    progress_every = Keyword.get(opts, :progress_every, 50)
    fail_fast = Keyword.get(opts, :fail_fast, false)

    {rows, stopped?} =
      scan_repos(
        repos,
        globs,
        plugins,
        opts[:limit],
        kinds,
        quiet_zero,
        progress_every,
        fail_fast
      )

    File.mkdir_p!(Path.dirname(Path.expand(output)))
    File.write!(output, JSON.encode!(rows))

    print_summary(rows, output)
    if stopped?, do: System.halt(2)
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
    case Keyword.get_values(opts, :plugins) do
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

  defp scan_repos(repos, globs, plugins, limit, kinds, quiet_zero, progress_every, fail_fast) do
    started_at = System.monotonic_time(:second)
    total = length(repos)

    repos
    |> Enum.with_index(1)
    |> Enum.reduce_while({[], false}, fn {repo, index}, {rows, _stopped?} ->
      row = scan_repo(repo, globs, plugins, limit, kinds)
      print_progress(row, index, total, started_at, progress_every)
      print_repo(row, quiet_zero)

      rows = [row | rows]

      if fail_fast and row[:error] do
        {:halt, {Enum.reverse(rows), true}}
      else
        {:cont, {rows, false}}
      end
    end)
    |> then(fn {rows, stopped?} -> {Enum.reverse(rows), stopped?} end)
  end

  defp scan_repo(repo, globs, plugins, limit, kinds) do
    paths = source_paths(repo, globs, limit)

    try do
      {load_us, project} =
        :timer.tc(fn -> Reach.Project.from_sources(paths, plugins: plugins) end)

      checks =
        project
        |> Reach.Smell.Registry.checks(Reach.Config.normalize([]))
        |> filter_checks_by_kind(kinds)

      {pattern_checks, semantic_checks} = Enum.split_with(checks, &pattern_check?/1)

      {pattern_us, pattern_findings} =
        :timer.tc(fn -> Reach.Smell.SourceRunner.run(project, pattern_checks) end)

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
        error_result(repo, paths, Exception.format(:error, exception, __STACKTRACE__))
    catch
      :exit, reason ->
        error_result(repo, paths, Exception.format_exit(reason))
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

  defp error_result(repo, paths, error) do
    %{
      repo: repo,
      files: length(paths),
      error: error,
      count: 0,
      findings: []
    }
  end

  defp filter_checks_by_kind(checks, nil), do: checks

  defp filter_checks_by_kind(checks, kinds) do
    Enum.filter(checks, fn check ->
      check
      |> check_kinds()
      |> Enum.any?(&MapSet.member?(kinds, &1))
    end)
  end

  defp check_kinds(check) do
    cond do
      pattern_check?(check) -> pattern_check_kinds(check)
      function_exported?(check, :kinds, 0) -> check.kinds()
      true -> []
    end
  end

  defp pattern_check_kinds(check) do
    metadata = check.__reach_pattern_check__()

    pattern_kinds = Enum.map(metadata.patterns, &smell_metadata_kind/1)
    query_kinds = Enum.map(metadata.queries, &smell_metadata_kind/1)

    pattern_kinds ++ query_kinds
  end

  defp smell_metadata_kind({_matcher, kind, _message}), do: kind
  defp smell_metadata_kind({_matcher, kind, _message, _prefilter}), do: kind

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

  defp print_repo(row, quiet_zero) do
    if not quiet_zero or row.count > 0 or row[:error] do
      timings =
        if row[:error] do
          "error"
        else
          "load=#{row.load_ms}ms pattern=#{row.pattern_ms}ms semantic=#{row.semantic_ms}ms"
        end

      IO.puts("#{row.repo}: files=#{row.files} findings=#{row.count} #{timings}")
      if row[:kinds], do: IO.puts("  #{inspect(row.kinds)}")
    end
  end

  defp print_progress(_row, _index, _total, _started_at, progress_every)
       when not is_integer(progress_every) or progress_every <= 0,
       do: :ok

  defp print_progress(row, index, total, started_at, progress_every) do
    if index == 1 or rem(index, progress_every) == 0 or row[:error] do
      elapsed = System.monotonic_time(:second) - started_at

      IO.puts(
        "progress=#{index}/#{total} elapsed_s=#{elapsed} findings=#{row.count} current=#{row.repo}"
      )
    end
  end

  defp print_summary(rows, output) do
    counts = kind_counts(rows)
    errors = Enum.count(rows, & &1[:error])
    findings = Enum.reduce(rows, 0, &(&1.count + &2))
    files = Enum.reduce(rows, 0, &(&1.files + &2))

    IO.puts("\nSummary")
    IO.puts("repos=#{length(rows)} files=#{files} findings=#{findings} errors=#{errors}")

    if counts != %{} do
      counts
      |> Enum.sort_by(fn {_kind, count} -> -count end)
      |> Enum.each(fn {kind, count} -> IO.puts("  #{kind}: #{count}") end)
    end

    IO.puts("Wrote #{Path.expand(output)}")
  end

  defp kind_counts(rows) do
    Enum.reduce(rows, %{}, fn row, counts ->
      Enum.reduce(row[:kinds] || %{}, counts, fn {kind, count}, counts ->
        Map.update(counts, kind, count, &(&1 + count))
      end)
    end)
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
      --plugins, -p MODULE   Plugin module. May be repeated. Defaults to Ecto, Phoenix, Oban, ExUnit.
      --kinds a,b,c          Only run checks that emit selected smell kinds, and only include those findings.
      --quiet-zero           Do not print per-repo lines for repositories with zero findings.
      --progress-every N     Print progress every N repositories. Defaults to 50. Use 0 to disable.
      --fail-fast            Stop at the first repository error and exit non-zero after writing partial output.
      --help, -h             Show this help.
    """)
  end
end

Reach.Scripts.SmellCorpusScan.main(System.argv())
