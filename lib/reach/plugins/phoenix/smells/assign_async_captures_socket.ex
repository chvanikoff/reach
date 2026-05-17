defmodule Reach.Plugins.Phoenix.Smells.AssignAsyncCapturesSocket do
  @moduledoc "Detects LiveView async callbacks that capture the socket."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @async_fns [:assign_async, :start_async, :stream_async]

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{function: fun}} = call} when fun in @async_fns ->
        findings_for_call(call)

      _entry ->
        []
    end)
  end

  defp findings_for_call(%{children: [%{type: :var, meta: %{name: socket_name}} | args]} = call) do
    if Enum.any?(args, &fn_captures_var?(&1, socket_name)) do
      [
        Finding.new(
          kind: :phoenix_assign_async_captures_socket,
          message:
            "LiveView async callback captures socket; extract needed assigns before the closure to avoid copying socket state",
          location: Helpers.location(call)
        )
      ]
    else
      []
    end
  end

  defp findings_for_call(_call), do: []

  defp fn_captures_var?(%{type: :fn} = fn_node, socket_name) do
    fn_node
    |> IR.all_nodes()
    |> Enum.any?(&var_reference?(&1, socket_name))
  end

  defp fn_captures_var?(_node, _socket_name), do: false

  defp var_reference?(%{type: :var, meta: %{name: name} = meta}, name) do
    Map.get(meta, :binding_role) != :definition
  end

  defp var_reference?(_node, _socket_name), do: false
end
