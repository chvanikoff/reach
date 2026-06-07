defmodule Reach.CLI.JSON do
  @moduledoc false

  def encode!(data, _opts \\ []) do
    data
    |> to_data()
    |> JSON.encode!()
  end

  def to_data(%Reach.IR.Node{} = node) do
    %{type: Atom.to_string(node.type), id: node.id}
    |> maybe_put(:name, node.meta[:name])
    |> maybe_put(:module, node.meta[:module])
    |> maybe_put(:function, node.meta[:function])
    |> maybe_put(:location, node_location(node))
  end

  def to_data(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> to_data()
  end

  def to_data(%{} = map) do
    Map.new(map, fn {key, value} -> {json_key(key), to_data(value)} end)
  end

  def to_data(list) when is_list(list), do: Enum.map(list, &to_data/1)

  def to_data({module, function, arity})
      when is_atom(module) and is_atom(function) and is_number(arity) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  def to_data(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> to_data()
  def to_data(atom) when is_atom(atom) and not is_nil(atom), do: Atom.to_string(atom)
  def to_data(nil), do: nil
  def to_data(other), do: other

  defp node_location(%{source_span: %{file: file, start_line: line}}), do: "#{file}:#{line}"
  defp node_location(_node), do: "unknown"

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, to_data(value))

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end
