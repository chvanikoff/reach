defmodule Reach.Check.Architecture.SuppressionsTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Architecture
  alias Reach.Project

  @config [
    forbidden_calls: [{"Fixture.Suppressions.Command", ["Fixture.Suppressions.Config.read"]}]
  ]

  test "control: a forbidden call produces a violation" do
    result = Architecture.run(project_for(command_source(nil)), @config)

    assert result.status == "failed"
    assert Enum.any?(result.violations, &(&1.type == :forbidden_call))
  end

  test "disable-next-line with the violation type suppresses it" do
    project = project_for(command_source("# reach:disable-next-line forbidden_call"))
    result = Architecture.run(project, @config)

    assert result.status == "ok"
    assert result.violations == []
  end

  test "the arch group token suppresses violations" do
    project = project_for(command_source("# reach:disable-next-line arch"))
    result = Architecture.run(project, @config)

    assert result.violations == []
  end

  defp command_source(comment) do
    comment_line = if comment, do: "    #{comment}\n", else: ""

    """
    defmodule Fixture.Suppressions.Config do
      def read, do: :ok
    end

    defmodule Fixture.Suppressions.Command do
      def run do
    #{comment_line}    Fixture.Suppressions.Config.read()
      end
    end
    """
  end

  defp project_for(source) do
    dir = Path.join(System.tmp_dir!(), "reach-arch-suppressions-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    Project.from_sources([path])
  end
end
