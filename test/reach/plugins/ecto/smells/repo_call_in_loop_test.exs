defmodule Reach.Plugins.Ecto.Smells.RepoCallInLoopTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Ecto
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags Repo calls inside Enum callbacks" do
    project =
      project_from_string(
        ~S'''
        defmodule MyApp.Orders do
          def load_orders(users) do
            Enum.map(users, fn user -> Repo.get(Order, user.order_id) end)
          end
        end
        ''',
        plugins: [Ecto]
      )

    assert [%Finding{kind: :ecto_repo_call_in_loop}] = Smells.run(project)
  end

  test "allows Repo calls outside Enum callbacks" do
    project =
      project_from_string(
        ~S'''
        defmodule MyApp.Orders do
          def load_order(user) do
            Repo.get(Order, user.order_id)
          end
        end
        ''',
        plugins: [Ecto]
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
