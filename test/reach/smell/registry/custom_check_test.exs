defmodule Reach.Smell.CustomCheckTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Smell.Finding

  defmodule LocalSmell do
    @behaviour Reach.Smell.Check

    alias Reach.Smell.Finding

    @impl true
    def run(_project) do
      [
        Finding.new(
          kind: :local_rule,
          message: "local smell ran",
          location: "lib/example.ex:1"
        )
      ]
    end
  end

  defmodule InvalidSmell do
  end

  defmodule LocalPlugin do
    def smell_checks, do: [LocalSmell]
  end

  defmodule InvalidPlugin do
    def smell_checks, do: [InvalidSmell]
  end

  test "runs configured custom smell checks" do
    project = %{nodes: %{}}
    config = Reach.Config.normalize(smells: [custom_checks: [LocalSmell]])

    assert [%Finding{kind: :local_rule, message: "local smell ran"}] =
             Smells.run(project, config)
  end

  test "raises when a configured custom smell check does not implement the behaviour" do
    project = %{nodes: %{}}
    config = Reach.Config.normalize(smells: [custom_checks: [InvalidSmell]])

    assert_raise Mix.Error, ~r/must implement Reach.Smell.Check/, fn ->
      Smells.run(project, config)
    end
  end

  test "runs configured plugin smell checks" do
    project = %{nodes: %{}, plugins: [LocalPlugin]}

    assert [%Finding{kind: :local_rule, message: "local smell ran"}] =
             Smells.run(project, Reach.Config.normalize([]))
  end

  test "raises when a configured plugin smell check does not implement the behaviour" do
    project = %{nodes: %{}, plugins: [InvalidPlugin]}

    assert_raise Mix.Error, ~r/must implement Reach.Smell.Check/, fn ->
      Smells.run(project, Reach.Config.normalize([]))
    end
  end
end
