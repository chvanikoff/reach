defmodule Reach.Map.ModuleCoupling do
  @moduledoc "Struct for per-module coupling detail."
  @derive JSON.Encoder
  defstruct [:name, :file, :afferent, :efferent, :instability]
  def new(attrs), do: struct!(__MODULE__, attrs)
end
