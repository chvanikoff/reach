defmodule Reach.Inspect.Data.VariableSummary do
  @moduledoc "Struct for a variable flow summary."

  @derive JSON.Encoder
  defstruct [:name, :role, :file, :line]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
