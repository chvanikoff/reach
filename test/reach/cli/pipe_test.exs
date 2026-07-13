defmodule Reach.CLI.PipeTest do
  use ExUnit.Case, async: false

  alias Reach.CLI.Pipe

  test "reraises non-pipe exceptions" do
    assert_raise FunctionClauseError, fn ->
      Pipe.safely(fn -> raise FunctionClauseError end)
    end
  end

  test "restores runtime and configured Logger levels independently" do
    previous_runtime_level = Logger.level()
    previous_configured_level = Application.fetch_env(:logger, :level)

    on_exit(fn ->
      Logger.configure(level: previous_runtime_level)

      case previous_configured_level do
        {:ok, level} -> Application.put_env(:logger, :level, level)
        :error -> Application.delete_env(:logger, :level)
      end
    end)

    Logger.configure(level: :debug)
    Application.put_env(:logger, :level, :warning)

    assert :ok = Pipe.safely(fn -> :ok end)
    assert Logger.level() == :debug
    assert Application.fetch_env(:logger, :level) == {:ok, :warning}
  end
end
