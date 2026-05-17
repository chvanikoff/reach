defmodule Reach.CLI.CanonicalTasksTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Reach.CLI.Commands.Inspect
  alias Reach.CLI.Commands.Map

  test "canonical commands call analyses directly and keep canonical json envelope" do
    project = fixture_project()

    output =
      capture_io(fn ->
        warning =
          capture_io(:stderr, fn ->
            Inspect.run([deps: true, format: "json", project: project], ["run/1"])
          end)

        assert warning == ""
      end)

    data = decode_json(output)
    assert data["command"] == "reach.inspect"
    assert data["tool"] == "reach.inspect"
  end

  test "reach.map delegates to selected project summaries" do
    project = fixture_project()

    output =
      capture_io(fn -> Map.run(hotspots: true, top: 1, format: "oneline", project: project) end)

    assert is_binary(output)
  end

  test "reach.map preserves legacy overview command options" do
    project = fixture_project()

    assert capture_io(fn -> Map.run(coupling: true, orphans: true, top: 2, project: project) end) =~
             "Coupling"

    assert capture_io(fn -> Map.run(boundaries: true, min: 3, top: 2, project: project) end) =~
             "Effect Boundaries"

    depth = capture_io(fn -> Map.run(depth: true, top: 1, format: "json", project: project) end)

    assert {:ok, %{"sections" => %{"depth" => depth_rows}}} = Jason.decode(depth)
    assert is_list(depth_rows)

    data = capture_io(fn -> Map.run(data: true, top: 1, format: "json", project: project) end)

    assert {:ok, %{"sections" => %{"data" => %{"cross_function_edges" => edges}}}} =
             Jason.decode(data)

    assert is_list(edges)
  end

  defp fixture_project do
    source = """
    defmodule Demo.Helper do
      def clean(value), do: String.trim(value)
    end

    defmodule Demo.Main do
      def run(value), do: Demo.Helper.clean(value)
      def noisy(value), do: IO.inspect(value)
    end
    """

    dir = Path.join(System.tmp_dir!(), "reach-canonical-fixture-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Reach.Project.from_sources([path])
  end

  defp decode_json(output) do
    json =
      output
      |> String.split("\n")
      |> Enum.drop_while(&(not String.starts_with?(&1, "{")))
      |> Enum.join("\n")

    assert {:ok, data} = Jason.decode(json)
    data
  end
end
