defmodule Reach.Map.UnknownCall do
  @moduledoc "Struct for a call with unresolved effect classification."
  @derive JSON.Encoder
  defstruct [:module, :function, :count]
  def new(attrs), do: struct!(__MODULE__, attrs)
end
