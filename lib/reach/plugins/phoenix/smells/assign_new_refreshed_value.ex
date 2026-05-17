defmodule Reach.Plugins.Phoenix.Smells.AssignNewRefreshedValue do
  @moduledoc "Detects assign_new/3 for assigns that usually need refreshing inside LiveView mount/3."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @assign_new_modules [nil, Phoenix.Component, Phoenix.LiveView]
  @refreshed_keys MapSet.new([
                    :current_scope,
                    :current_user,
                    :locale,
                    :organization,
                    :tenant,
                    :timezone
                  ])

  @impl true
  def kinds, do: [:phoenix_assign_new_refreshed_value]

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :function_def, meta: %{name: :mount, arity: 3}} = function} ->
        function
        |> IR.all_nodes()
        |> Enum.filter(&assign_new_refreshed_value?/1)
        |> Enum.map(&finding/1)

      _entry ->
        []
    end)
  end

  defp assign_new_refreshed_value?(%{
         type: :call,
         meta: %{function: :assign_new, module: module},
         children: [_socket, %{type: :literal, meta: %{value: key}} | _]
       })
       when module in @assign_new_modules do
    MapSet.member?(@refreshed_keys, key)
  end

  defp assign_new_refreshed_value?(_node), do: false

  defp finding(call) do
    Finding.new(
      kind: :phoenix_assign_new_refreshed_value,
      message:
        "assign_new/3 in mount/3 skips when the assign already exists; use assign/3 for values refreshed every mount",
      location: Helpers.location(call)
    )
  end
end
