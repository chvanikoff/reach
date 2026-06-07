defmodule Reach.Map.DepthMetric do
  @moduledoc "Struct for control nesting depth metrics of a function."
  @derive JSON.Encoder
  defstruct [:module, :function, :depth, :clauses, :file, :line, :branch_count]
  def new(attrs), do: struct!(__MODULE__, attrs)
end
