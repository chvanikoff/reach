defmodule Reach.Inspect.Data.EdgeSummary do
  @moduledoc "Struct for a cross-function data flow edge summary."

  @derive JSON.Encoder
  defstruct [:from, :to, :label]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
