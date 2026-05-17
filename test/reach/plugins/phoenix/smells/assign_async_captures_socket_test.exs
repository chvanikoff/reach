defmodule Reach.Plugins.Phoenix.Smells.AssignAsyncCapturesSocketTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Phoenix
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags async callbacks that capture socket" do
    project =
      project_from_string(
        ~S'''
        defmodule MyAppWeb.PageLive do
          def mount(_params, _session, socket) do
            assign_async(socket, :org, fn ->
              {:ok, %{org: fetch_org(socket.assigns.org_id)}}
            end)
          end
        end
        ''',
        plugins: [Phoenix]
      )

    assert [%Finding{kind: :phoenix_assign_async_captures_socket}] = Smells.run(project)
  end

  test "allows extracted values in async callbacks" do
    project =
      project_from_string(
        ~S'''
        defmodule MyAppWeb.PageLive do
          def mount(_params, _session, socket) do
            org_id = socket.assigns.org_id

            assign_async(socket, :org, fn ->
              {:ok, %{org: fetch_org(org_id)}}
            end)
          end
        end
        ''',
        plugins: [Phoenix]
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
