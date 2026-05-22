defmodule Reach.Plugins.Phoenix.Smells.PubSubSubscribeWithoutConnected do
  @moduledoc "Detects LiveView mount/3 subscriptions that are not guarded by connected?/1."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def kinds, do: [:phoenix_pubsub_subscribe_without_connected]

  @impl true
  def run(project) do
    Reach.Plugins.Phoenix.Smells.Helpers.mount_findings(project, &findings_for_mount/1)
  end

  defp findings_for_mount(function) do
    nodes = IR.all_nodes(function)

    if Enum.any?(nodes, &connected_call?/1) do
      []
    else
      nodes
      |> Enum.filter(&pubsub_subscribe?/1)
      |> Enum.map(fn call ->
        Finding.new(
          kind: :phoenix_pubsub_subscribe_without_connected,
          message:
            "PubSub subscription in LiveView mount/3 should be guarded by connected?/1 to avoid duplicate subscriptions",
          location: Helpers.location(call)
        )
      end)
    end
  end

  defp connected_call?(%{type: :call, meta: %{function: :connected?}}), do: true
  defp connected_call?(_node), do: false

  defp pubsub_subscribe?(%{type: :call, meta: %{module: Phoenix.PubSub, function: :subscribe}}),
    do: true

  defp pubsub_subscribe?(%{type: :call, meta: %{function: :subscribe, module: module}})
       when is_atom(module) and module != nil do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> Kernel.==("PubSub")
  end

  defp pubsub_subscribe?(_node), do: false
end
