defmodule Reach.Plugins.Ecto.Smells.RepoAllThenEnum do
  @moduledoc "Detects loading all rows before filtering or aggregating in Elixir."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @filter_fns [:filter, :reject, :find]
  @count_fns [:count]

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call} = call} -> finding_for_call(call)
      _entry -> []
    end)
  end

  defp finding_for_call(%{meta: %{module: Enum, function: fun}, children: [source | _]} = call)
       when fun in @filter_fns do
    if repo_all_call?(source) do
      finding(
        call,
        :ecto_filter_after_repo_all,
        "Repo.all followed by Enum.#{fun}/2 loads all rows before filtering; push the predicate into the query"
      )
    else
      []
    end
  end

  defp finding_for_call(%{meta: %{module: Enum, function: fun}, children: [source | _]} = call)
       when fun in @count_fns do
    if repo_all_call?(source) do
      finding(
        call,
        :ecto_count_after_repo_all,
        "Repo.all followed by Enum.count/1 loads all rows before counting; use Repo.aggregate/3 or Repo.exists?/1"
      )
    else
      []
    end
  end

  defp finding_for_call(%{meta: %{module: nil, function: fun}, children: [source]} = call)
       when fun in [:length] do
    if repo_all_call?(source) do
      finding(
        call,
        :ecto_count_after_repo_all,
        "Repo.all followed by length/1 loads all rows before counting; use Repo.aggregate/3 or Repo.exists?/1"
      )
    else
      []
    end
  end

  defp finding_for_call(_call), do: []

  defp repo_all_call?(%{type: :call, meta: %{module: Repo, function: :all}}), do: true
  defp repo_all_call?(_node), do: false

  defp finding(call, kind, message) do
    [Finding.new(kind: kind, message: message, location: Helpers.location(call))]
  end
end
