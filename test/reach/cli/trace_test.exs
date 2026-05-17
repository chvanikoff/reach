defmodule Reach.CLI.TraceTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Reach.CLI.Commands.Trace

  test "reach.trace runs variable tracing directly" do
    project = fixture_project()

    output =
      capture_io(fn ->
        Trace.run(variable: "graph", in: "run/1", format: "oneline", project: project)
      end)

    assert output =~ "graph"
  end

  defp fixture_project do
    source = """
    defmodule TraceFixture do
      def run(graph) do
        value = graph
        value
      end
    end
    """

    dir = Path.join(System.tmp_dir!(), "reach-trace-fixture-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Reach.Project.from_sources([path])
  end
end
