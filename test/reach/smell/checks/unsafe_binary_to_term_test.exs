defmodule Reach.Smell.Checks.UnsafeBinaryToTermTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags binary_to_term without safe option" do
    project =
      project_from_string(
        "defmodule M do\n  def parse(input), do: :erlang.binary_to_term(input)\nend"
      )

    assert [%Finding{kind: :unsafe_binary_to_term}] = Smells.run(project)
  end

  test "allows binary_to_term with safe option" do
    project =
      project_from_string(
        "defmodule M do\n  def parse(input), do: :erlang.binary_to_term(input, [:safe])\nend"
      )

    assert [] = Smells.run(project)
  end

  defp project_from_string(source) do
    graph = Reach.string_to_graph!(source)

    %Project{
      modules: %{},
      graph: Reach.to_graph(graph),
      nodes: Map.new(Reach.nodes(graph), &{&1.id, &1}),
      call_graph: graph.call_graph,
      plugins: []
    }
  end
end
