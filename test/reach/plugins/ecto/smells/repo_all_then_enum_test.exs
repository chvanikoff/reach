defmodule Reach.Plugins.Ecto.Smells.RepoAllThenEnumTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Ecto
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags Repo.all followed by Enum.filter" do
    project =
      project_from_string(
        "defmodule M do\n  def active, do: Repo.all(User) |> Enum.filter(& &1.active)\nend"
      )

    assert [%Finding{kind: :ecto_filter_after_repo_all}] = Smells.run(project)
  end

  test "flags Repo.all followed by length" do
    project =
      project_from_string("defmodule M do\n  def count, do: Repo.all(User) |> length()\nend")

    assert [%Finding{kind: :ecto_count_after_repo_all}] = Smells.run(project)
  end

  test "allows filtering query results that were already materialized elsewhere" do
    project =
      project_from_string(
        "defmodule M do\n  def active(users), do: Enum.filter(users, & &1.active)\nend"
      )

    assert [] = Smells.run(project)
  end

  defp project_from_string(source) do
    graph = Reach.string_to_graph!(source, plugins: [Ecto])

    %Project{
      modules: %{},
      graph: Reach.to_graph(graph),
      nodes: Map.new(Reach.nodes(graph), &{&1.id, &1}),
      call_graph: graph.call_graph,
      plugins: [Ecto]
    }
  end
end
