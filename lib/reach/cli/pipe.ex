defmodule Reach.CLI.Pipe do
  @moduledoc false

  def safely(fun) when is_function(fun, 0) do
    previous_level = Logger.level()
    Logger.configure(level: :emergency)

    try do
      fun.()
    rescue
      error in [
        ErlangError,
        FunctionClauseError,
        RuntimeError,
        ArgumentError,
        MatchError,
        CaseClauseError,
        WithClauseError,
        KeyError,
        BadMapError,
        UndefinedFunctionError,
        Protocol.UndefinedError
      ] ->
        if broken_pipe?(error), do: :ok, else: reraise(error, __STACKTRACE__)
    catch
      :exit, reason ->
        if broken_pipe_reason?(reason), do: :ok, else: exit(reason)
    after
      Logger.configure(level: previous_level)
    end
  end

  defp broken_pipe?(%ErlangError{original: reason}), do: broken_pipe_reason?(reason)
  defp broken_pipe?(_error), do: false

  defp broken_pipe_reason?(:epipe), do: true
  defp broken_pipe_reason?(:terminated), do: true
  defp broken_pipe_reason?({:terminated, _details}), do: true
  defp broken_pipe_reason?({:epipe, _details}), do: true
  defp broken_pipe_reason?(_reason), do: false
end
