defmodule Reach.Smell.SourceRunnerTest do
  use ExUnit.Case, async: true

  alias Reach.IR.Node
  alias Reach.Project
  alias Reach.Smell.SourceRunner

  defmodule PatternCheck do
    use Reach.Smell.Check.Source

    smell(
      ~p[Enum.reverse(_) |> Enum.reverse()],
      :redundant_reverse,
      "redundant reverse"
    )
  end

  defmodule ASTCheck do
    use Reach.Smell.Check.Source

    smell(:module_attribute, :module_attribute, "module attribute", mode: :ast, prefilter: [])

    def module_attribute({:@, meta, _children}), do: {:ok, meta}
    def module_attribute(_node), do: false
  end

  test "source runners skip non-Elixir module files" do
    dir = Path.join(System.tmp_dir!(), "reach-source-runner-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    js_path = Path.join(dir, "theme.js")
    ex_path = Path.join(dir, "sample.ex")

    File.write!(js_path, ~S[document.documentElement.dataset.theme = dark ? "dark" : "light";])

    File.write!(ex_path, """
    defmodule Sample do
      @moduledoc false
      def run(items), do: items |> Enum.reverse() |> Enum.reverse()
    end
    """)

    project = project_with_sources(js_path, ex_path)

    assert findings = SourceRunner.run(project, [PatternCheck, ASTCheck])
    assert Enum.any?(findings, &(&1.kind == :redundant_reverse))
    assert Enum.any?(findings, &(&1.kind == :module_attribute))

    refute Enum.any?(findings, fn finding ->
             finding.location |> to_string() |> String.contains?(js_path)
           end)
  end

  defp project_with_sources(js_path, ex_path) do
    %Project{
      modules: %{},
      graph: Graph.new(type: :directed),
      call_graph: Graph.new(type: :directed),
      nodes: %{
        "js-module" => module_node("js-module", JSModule, js_path, 1),
        "ex-module" => module_node("ex-module", Sample, ex_path, 1)
      }
    }
  end

  defp module_node(id, module, file, line) do
    %Node{
      id: id,
      type: :module_def,
      meta: %{name: module},
      source_span: %{file: file, start_line: line, end_line: line},
      children: []
    }
  end
end
