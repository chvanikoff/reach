defmodule Reach.Plugins.Phoenix.Smells.DisconnectedMountRepo do
  @moduledoc "Detects direct Repo work in LiveView mount/3 without a connected?/1 guard."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @async_fns [:assign_async, :start_async, :stream_async]

  @repo_fns [
    :all,
    :one,
    :one!,
    :get,
    :get!,
    :get_by,
    :get_by!,
    :exists?,
    :aggregate,
    :preload,
    :reload,
    :reload!,
    :insert,
    :insert!,
    :update,
    :update!,
    :delete,
    :delete!,
    :insert_or_update,
    :insert_or_update!,
    :insert_all,
    :update_all,
    :delete_all,
    :transaction
  ]

  @impl true
  def kinds, do: [:phoenix_disconnected_mount_repo]

  @impl true
  def run(project) do
    Reach.Plugins.Phoenix.Smells.Helpers.mount_findings(project, &findings_for_mount/1)
  end

  defp findings_for_mount(function) do
    nodes = IR.all_nodes(function)

    if guarded_or_async?(nodes) do
      []
    else
      nodes
      |> Enum.filter(&repo_call?/1)
      |> Enum.map(&finding/1)
    end
  end

  defp guarded_or_async?(nodes) do
    Enum.any?(nodes, &(connected_call?(&1) or async_call?(&1)))
  end

  defp connected_call?(%{type: :call, meta: %{function: :connected?}}), do: true
  defp connected_call?(_node), do: false

  defp async_call?(%{type: :call, meta: %{function: function}}) when function in @async_fns,
    do: true

  defp async_call?(_node), do: false

  defp repo_call?(%{type: :call, meta: %{module: module, function: function}})
       when function in @repo_fns do
    repo_module?(module)
  end

  defp repo_call?(_node), do: false

  defp repo_module?(module) when is_atom(module) and module != nil do
    module
    |> Module.split()
    |> List.last()
    |> Kernel.==("Repo")
  rescue
    ArgumentError -> false
  end

  defp repo_module?(_module), do: false

  defp finding(call) do
    Finding.new(
      kind: :phoenix_disconnected_mount_repo,
      message:
        "Repo work in LiveView mount/3 runs during disconnected render and connected mount; guard it with connected?/1 or move it to assign_async/start_async",
      location: Helpers.location(call)
    )
  end
end
