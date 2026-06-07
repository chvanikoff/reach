defmodule Reach.Map.Hotspot do
  @moduledoc "Struct for complexity × callers hotspot metrics."
  @derive JSON.Encoder
  defstruct [
    :module,
    :function,
    :display_function,
    :file,
    :line,
    :branches,
    :callers,
    :score,
    :clauses
  ]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
