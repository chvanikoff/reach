defmodule Reach.Check.DeadCode.Finding do
  @moduledoc "Struct for a dead code finding."

  @derive JSON.Encoder
  defstruct [:file, :line, :kind, :description]

  def new(attrs), do: struct!(__MODULE__, attrs)
end
