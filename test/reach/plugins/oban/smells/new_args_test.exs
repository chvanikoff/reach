defmodule Reach.Plugins.Oban.Smells.NewArgsTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Oban
  alias Reach.Project

  test "flags struct values when enqueuing Oban jobs" do
    project =
      project_from_string(
        "defmodule M do\n  def enqueue(user), do: MyWorker.new(%{user: %User{id: user.id}})\nend"
      )

    kinds = project |> Smells.run() |> Enum.map(& &1.kind)

    assert :oban_struct_args in kinds
  end

  test "flags local new with struct args inside Oban workers" do
    project =
      project_from_string(~S'''
      defmodule MyWorker do
        use Oban.Worker

        def enqueue(user), do: new(%{user: %User{id: user.id}})
      end
      ''')

    assert [%{kind: :oban_struct_args}] = Smells.run(project)
  end

  test "allows struct args for unrelated new constructors" do
    project =
      project_from_string(
        "defmodule M do\n  def build(user), do: Thing.new(%{user: %User{id: user.id}})\nend"
      )

    assert [] = Smells.run(project)
  end

  test "allows primitive args" do
    project =
      project_from_string(
        "defmodule M do\n  def enqueue(user), do: MyWorker.new(%{user_id: user.id})\nend"
      )

    assert [] = Smells.run(project)
  end

  defp project_from_string(source) do
    graph = Reach.string_to_graph!(source, plugins: [Oban])

    %Project{
      modules: %{},
      graph: Reach.to_graph(graph),
      nodes: Map.new(Reach.nodes(graph), &{&1.id, &1}),
      call_graph: graph.call_graph,
      plugins: [Oban]
    }
  end
end
