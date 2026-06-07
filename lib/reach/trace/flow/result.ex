defmodule Reach.Trace.Flow.Result do
  @moduledoc "Struct for flow trace results."

  @derive JSON.Encoder
  defstruct [:type, :from, :to, :paths, :variable, :definitions, :uses]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
