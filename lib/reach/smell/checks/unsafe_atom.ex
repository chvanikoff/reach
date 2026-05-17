defmodule Reach.Smell.Checks.UnsafeAtom do
  @moduledoc "Detects dynamic atom creation from non-literal input."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{module: String, function: :to_atom}, children: [arg]} = call} ->
        if trusted_parser_module?(call), do: [], else: finding_for_arg(call, arg)

      _entry ->
        []
    end)
  end

  defp trusted_parser_module?(%{source_span: %{file: file}}) when is_binary(file) do
    file in [
      "lib/reach/frontend/gleam.ex",
      "lib/reach/plugins/quickbeam/javascript_frontend.ex",
      "lib/reach/plugins/quickbeam.ex"
    ]
  end

  defp trusted_parser_module?(_call), do: false

  defp finding_for_arg(_call, %{type: :literal, meta: %{value: value}}) when is_binary(value),
    do: []

  defp finding_for_arg(call, _arg) do
    [
      Finding.new(
        kind: :unsafe_atom_creation,
        message:
          "String.to_atom/1 on dynamic input can exhaust the atom table; use explicit mapping or String.to_existing_atom/1",
        location: Helpers.location(call)
      )
    ]
  end
end
