defmodule Reach.Inspect.Data.NodeSummary do
  @moduledoc "Struct for a data flow node summary."

  @derive JSON.Encoder
  defstruct [:id, :kind, :name, :file, :line]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
