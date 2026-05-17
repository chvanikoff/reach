defmodule Reach.Plugins.Oban.Smells.NewArgs do
  @moduledoc "Detects non-portable Oban job args at enqueue time."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{function: :new}, children: [%{type: :map} = args]} = call} ->
        findings_for_args(call, args)

      _entry ->
        []
    end)
  end

  defp findings_for_args(call, args) do
    []
    |> maybe_add_atom_key_finding(call, has_atom_key?(args))
    |> maybe_add_struct_finding(call, has_struct_value?(args))
  end

  defp maybe_add_atom_key_finding(findings, call, true) do
    [
      Finding.new(
        kind: :oban_atom_keys_in_new_args,
        message:
          "Oban job args are JSON-encoded with string keys; use string keys when enqueuing jobs",
        location: Helpers.location(call)
      )
      | findings
    ]
  end

  defp maybe_add_atom_key_finding(findings, _call, false), do: findings

  defp maybe_add_struct_finding(findings, call, true) do
    [
      Finding.new(
        kind: :oban_struct_args,
        message: "Oban job args should contain JSON primitives; store IDs instead of structs",
        location: Helpers.location(call)
      )
      | findings
    ]
  end

  defp maybe_add_struct_finding(findings, _call, false), do: findings

  defp has_atom_key?(%{type: :map, children: fields}) do
    Enum.any?(fields, fn
      %{type: :map_field, children: [%{type: :literal, meta: %{value: key}}, _value]} ->
        is_atom(key)

      _field ->
        false
    end)
  end

  defp has_struct_value?(%{type: :map, children: fields}) do
    Enum.any?(fields, fn
      %{type: :map_field, children: [_key, value]} -> contains_struct?(value)
      _field -> false
    end)
  end

  defp contains_struct?(%{type: :struct}), do: true

  defp contains_struct?(%{children: children}) when is_list(children),
    do: Enum.any?(children, &contains_struct?/1)

  defp contains_struct?(_node), do: false
end
