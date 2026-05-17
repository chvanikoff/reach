defmodule Reach.Smell.Checks.UnsafeAtomTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags String.to_atom on dynamic input" do
    project =
      project_from_string(~S'''
      defmodule MyApp.Parser do
        def parse(input), do: String.to_atom(input)
      end
      ''')

    assert [%Finding{kind: :unsafe_atom_creation}] = Smells.run(project)
  end

  test "allows String.to_atom on literal input" do
    project =
      project_from_string(~S'''
      defmodule MyApp.Parser do
        def parse, do: String.to_atom("ok")
      end
      ''')

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
