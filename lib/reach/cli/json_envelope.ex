defmodule Reach.CLI.JSONEnvelope do
  @moduledoc false

  @enforce_keys [:command, :data]
  defstruct [:command, :data, tool: nil]
end

defimpl JSON.Encoder, for: Reach.CLI.JSONEnvelope do
  def encode(%{command: command, tool: tool, data: data}, encoder) do
    data
    |> Reach.CLI.JSON.to_data()
    |> Map.merge(%{command: command})
    |> maybe_put_tool(tool)
    |> JSON.Encoder.Map.encode(encoder)
  end

  defp maybe_put_tool(data, nil), do: data
  defp maybe_put_tool(data, tool), do: Map.put(data, :tool, tool)
end
