defmodule Reach.Evidence.CloneAnalysis.ExDNATest do
  use ExUnit.Case, async: true

  alias Reach.Evidence.CloneAnalysis.ExDNA
  alias Reach.IR.Node
  alias Reach.Project

  test "ignores non-Elixir source files in the project graph" do
    dir = Path.join(System.tmp_dir!(), "reach-ex-dna-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    elixir_path = Path.join(dir, "sample.ex")
    javascript_path = Path.join(dir, "app.js")

    File.write!(elixir_path, "defmodule Sample do\n  def ok, do: :ok\nend\n")
    File.write!(javascript_path, "const theme = prefersLight ? 'light' : 'dark';\n")

    project =
      [elixir_path]
      |> Project.from_sources()
      |> add_javascript_module_node(javascript_path)

    assert [] = ExDNA.analyze(project, %Reach.Config.CloneAnalysis{min_mass: 3})
  end

  defp add_javascript_module_node(project, file) do
    node = %Node{
      id: 999_999,
      type: :module_def,
      meta: %{name: :JavascriptApp},
      source_span: %{file: file, start_line: 1, start_col: 1, end_line: 1, end_col: 50}
    }

    %{project | nodes: Map.put(project.nodes, node.id, node)}
  end
end
