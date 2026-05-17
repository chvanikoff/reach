defmodule Reach.Plugins.ObanSmellTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Oban
  alias Reach.Plugins.Oban.Smells.AtomArgs
  alias Reach.Project
  alias Reach.Smell.Finding

  test "plugin contributes Oban smell checks" do
    assert AtomArgs in Reach.Plugin.smell_checks([Oban])
  end

  test "flags atom keys in Oban job args" do
    project =
      project_from_string(
        ~S'''
        defmodule MyApp.Worker do
          def perform(%Oban.Job{args: %{user_id: id}}) do
            {:ok, id}
          end
        end
        ''',
        plugins: [Oban]
      )

    assert [%Finding{kind: :oban_atom_args}] = Smells.run(project)
  end

  test "allows string keys in Oban job args" do
    project =
      project_from_string(
        ~S'''
        defmodule MyApp.Worker do
          def perform(%Oban.Job{args: %{"user_id" => id}}) do
            {:ok, id}
          end
        end
        ''',
        plugins: [Oban]
      )

    assert [] = Smells.run(project)
  end

  defp project_from_string(source, opts) do
    graph = Reach.string_to_graph!(source, opts)

    %Project{
      modules: %{},
      graph: Reach.to_graph(graph),
      nodes: Map.new(Reach.nodes(graph), &{&1.id, &1}),
      call_graph: graph.call_graph,
      plugins: Keyword.fetch!(opts, :plugins)
    }
  end
end
