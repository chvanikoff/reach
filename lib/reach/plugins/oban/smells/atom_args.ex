defmodule Reach.Plugins.Oban.Smells.AtomArgs do
  @moduledoc "Detects Oban perform/1 callbacks that pattern match atom keys in job args."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :function_def, meta: %{name: :perform, arity: 1}} = function} ->
        function_findings(function)

      _entry ->
        []
    end)
  end

  defp function_findings(function) do
    function
    |> IR.all_nodes()
    |> Enum.filter(&oban_args_with_atom_keys?/1)
    |> Enum.map(fn node ->
      Finding.new(
        kind: :oban_atom_args,
        message:
          "Oban job args are JSON-decoded with string keys; pattern match string keys instead of atom keys",
        location: Helpers.location(node)
      )
    end)
  end

  defp oban_args_with_atom_keys?(%{type: :struct, meta: %{name: Oban.Job}, children: fields}) do
    Enum.any?(fields, &args_field_with_atom_keys?/1)
  end

  defp oban_args_with_atom_keys?(_node), do: false

  defp args_field_with_atom_keys?(%{type: :map_field, children: [key, value]}) do
    literal_value(key) == :args and map_has_atom_key?(value)
  end

  defp args_field_with_atom_keys?(_node), do: false

  defp map_has_atom_key?(%{type: :map, children: fields}) do
    Enum.any?(fields, fn
      %{type: :map_field, children: [key, _value]} -> is_atom(literal_value(key))
      _node -> false
    end)
  end

  defp map_has_atom_key?(_node), do: false

  defp literal_value(%{type: :literal, meta: %{value: value}}), do: value
  defp literal_value(_node), do: nil
end
