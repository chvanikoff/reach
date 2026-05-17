defmodule Reach.Smell.Checks.UnsafeBinaryToTerm do
  @moduledoc "Detects unsafe binary_to_term calls without the :safe option."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{module: :erlang, function: :binary_to_term}} = call} ->
        finding_for_call(call)

      _entry ->
        []
    end)
  end

  defp finding_for_call(%{children: [_input, opts]}) do
    if safe_option?(opts), do: [], else: unsafe_finding(opts)
  end

  defp finding_for_call(call), do: unsafe_finding(call)

  defp safe_option?(%{type: :list, children: children}) do
    Enum.any?(children, &match?(%{type: :literal, meta: %{value: :safe}}, &1))
  end

  defp safe_option?(_opts), do: false

  defp unsafe_finding(call) do
    [
      Finding.new(
        kind: :unsafe_binary_to_term,
        message:
          ":erlang.binary_to_term without [:safe] can deserialize dangerous terms; pass [:safe] for untrusted input",
        location: Helpers.location(call)
      )
    ]
  end
end
