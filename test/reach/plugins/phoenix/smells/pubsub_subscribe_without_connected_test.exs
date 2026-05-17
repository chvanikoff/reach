defmodule Reach.Plugins.Phoenix.Smells.PubSubSubscribeWithoutConnectedTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Phoenix
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags PubSub subscriptions in mount without connected? guard" do
    project =
      project_from_string(
        ~S'''
        defmodule MyAppWeb.PageLive do
          def mount(_params, _session, socket) do
            Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
            {:ok, socket}
          end
        end
        ''',
        plugins: [Phoenix]
      )

    assert [%Finding{kind: :phoenix_pubsub_subscribe_without_connected}] = Smells.run(project)
  end

  test "allows PubSub subscriptions when mount checks connected?" do
    project =
      project_from_string(
        ~S'''
        defmodule MyAppWeb.PageLive do
          def mount(_params, _session, socket) do
            if connected?(socket) do
              Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
            end

            {:ok, socket}
          end
        end
        ''',
        plugins: [Phoenix]
      )

    assert [] = Smells.run(project)
  end

  test "ignores PubSub subscriptions outside mount" do
    project =
      project_from_string(
        ~S'''
        defmodule MyAppWeb.PageLive do
          def handle_event("subscribe", _params, socket) do
            Phoenix.PubSub.subscribe(MyApp.PubSub, "topic")
            {:noreply, socket}
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
