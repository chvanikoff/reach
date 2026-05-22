defmodule Reach.CLI.PipeTest do
  use ExUnit.Case, async: false

  alias Reach.CLI.Pipe

  test "reraises non-pipe exceptions" do
    assert_raise FunctionClauseError, fn ->
      Pipe.safely(fn -> raise FunctionClauseError end)
    end
  end
end
