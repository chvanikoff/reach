defmodule Reach.Check.Architecture.SourceContractTest do
  use ExUnit.Case, async: true

  @lib_files Path.wildcard("lib/**/*.ex")
  @domain_files Enum.reject(@lib_files, &String.starts_with?(&1, "lib/reach/cli/"))
  @removed_task_files ~w(
    lib/mix/tasks/reach.modules.ex
    lib/mix/tasks/reach.coupling.ex
    lib/mix/tasks/reach.hotspots.ex
    lib/mix/tasks/reach.depth.ex
    lib/mix/tasks/reach.effects.ex
    lib/mix/tasks/reach.boundaries.ex
    lib/mix/tasks/reach.xref.ex
    lib/mix/tasks/reach.deps.ex
    lib/mix/tasks/reach.impact.ex
    lib/mix/tasks/reach.slice.ex
    lib/mix/tasks/reach.flow.ex
    lib/mix/tasks/reach.dead_code.ex
    lib/mix/tasks/reach.smell.ex
    lib/mix/tasks/reach.graph.ex
    lib/mix/tasks/reach.concurrency.ex
  )

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

  test "removed Mix tasks are not shipped" do
    refute File.exists?("lib/reach/cli/deprecation.ex")

    for file <- @removed_task_files do
      refute File.exists?(file)
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
