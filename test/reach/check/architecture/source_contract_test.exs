defmodule Reach.Check.Architecture.SourceContractTest do
  use ExUnit.Case, async: true

  @lib_files Path.wildcard("lib/**/*.ex")
  @domain_files Enum.reject(@lib_files, &String.starts_with?(&1, "lib/reach/cli/"))
  @removed_tasks %{
    "lib/mix/tasks/reach.modules.ex" => "reach.map --modules",
    "lib/mix/tasks/reach.coupling.ex" => "reach.map --coupling",
    "lib/mix/tasks/reach.hotspots.ex" => "reach.map --hotspots",
    "lib/mix/tasks/reach.depth.ex" => "reach.map --depth",
    "lib/mix/tasks/reach.effects.ex" => "reach.map --effects",
    "lib/mix/tasks/reach.boundaries.ex" => "reach.map --boundaries",
    "lib/mix/tasks/reach.xref.ex" => "reach.map --data",
    "lib/mix/tasks/reach.deps.ex" => "reach.inspect TARGET --deps",
    "lib/mix/tasks/reach.impact.ex" => "reach.inspect TARGET --impact",
    "lib/mix/tasks/reach.slice.ex" => "reach.trace TARGET",
    "lib/mix/tasks/reach.flow.ex" => "reach.trace",
    "lib/mix/tasks/reach.dead_code.ex" => "reach.check --dead-code",
    "lib/mix/tasks/reach.smell.ex" => "reach.check --smells",
    "lib/mix/tasks/reach.graph.ex" => "reach.inspect TARGET --graph",
    "lib/mix/tasks/reach.concurrency.ex" => "reach.otp --concurrency"
  }

  test "forbidden CLI analysis and task runner modules are not reintroduced" do
    refute Enum.any?(@lib_files, &String.starts_with?(&1, "lib/reach/cli/analyses/"))
    refute File.exists?("lib/reach/cli/task_runner.ex")

    refute source_contains?(@lib_files, [
             "defmodule Reach.CLI.Analyses",
             "defmodule Reach.CLI.TaskRunner"
           ])
  end

  test "Reach Mix tasks are not called internally" do
    forbidden = [
      ~r/Mix\.Task\.run\(["']reach(?:\.|["'])/,
      ~r/Mix\.Tasks\.Reach\.[A-Za-z0-9_.]+\.run\(/,
      ~r/TaskRunner\.run\(/
    ]

    refute source_matches?(@lib_files, forbidden)
  end

  test "compile task invocation stays centralized in Reach.CLI.Project" do
    offenders =
      @lib_files
      |> Enum.reject(&(&1 == "lib/reach/cli/project.ex"))
      |> matching_files([~r/Mix\.Task\.run\(["']compile["']/])

    assert offenders == []
  end

  test "removed Mix tasks stay hard-deprecated and do not delegate" do
    for {file, guidance} <- @removed_tasks do
      source = File.read!(file)

      assert source =~ guidance
      assert source =~ "Mix.raise" or source =~ "Deprecation.warn"
      refute source =~ "Deprecation.delegated"
      refute source =~ "Mix.Task.run"
      refute source =~ ".run(args)"
      refute source =~ ".run(argv)"
    end
  end

  test "domain modules use named limits instead of magic Enum.take literals" do
    allowed_files = [
      "lib/reach/cli/render/check.ex"
    ]

    offenders =
      @domain_files
      |> Enum.reject(&(&1 in allowed_files))
      |> matching_files([~r/Enum\.take\(\s*\d+\s*\)/])

    assert offenders == []
  end

  defp source_contains?(files, needles) do
    Enum.any?(files, fn file ->
      source = File.read!(file)
      Enum.any?(needles, &String.contains?(source, &1))
    end)
  end

  defp source_matches?(files, patterns), do: matching_files(files, patterns) != []

  defp matching_files(files, patterns) do
    Enum.filter(files, fn file ->
      source = File.read!(file)
      Enum.any?(patterns, &Regex.match?(&1, source))
    end)
  end
end
