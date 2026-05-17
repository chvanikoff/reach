defmodule Reach.Plugins.Ecto.Smells.RepoCallInLoop do
  @moduledoc "Detects Repo calls inside enumerable loops that can cause N+1 queries."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @enum_loop_fns [:map, :each, :flat_map, :filter, :reduce, :reject]
  @repo_modules [Repo, Ecto.Repo]

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{module: Enum, function: fun}} = call}
      when fun in @enum_loop_fns ->
        findings_for_enum_call(call)

      _entry ->
        []
    end)
  end

  defp findings_for_enum_call(call) do
    call.children
    |> Enum.filter(&(&1.type == :fn))
    |> Enum.flat_map(&repo_calls/1)
    |> Enum.map(fn repo_call ->
      Finding.new(
        kind: :ecto_repo_call_in_loop,
        message: "Repo call inside Enum callback may cause N+1 queries; batch or preload instead",
        location: Helpers.location(repo_call)
      )
    end)
  end

  defp repo_calls(fn_node) do
    fn_node
    |> IR.all_nodes()
    |> Enum.filter(&repo_call?/1)
  end

  defp repo_call?(%{type: :call, meta: %{module: module}}) when module in @repo_modules, do: true
  defp repo_call?(_node), do: false
end
