defmodule Reach.CLI.Options do
  @moduledoc false

  def parse(args, switches, aliases \\ []) do
    {opts, positional, invalid} = OptionParser.parse(args, strict: switches, aliases: aliases)

    if invalid != [] do
      Mix.raise("Unknown option(s): #{format_invalid_options(invalid)}")
    end

    {opts, positional}
  end

  def run(args, switches, aliases, fun) when is_function(fun, 2) do
    {opts, positional} = parse(args, switches, aliases)
    fun.(opts, positional)
  end

  defp format_invalid_options(invalid) do
    Enum.map_join(invalid, ", ", &format_invalid_option/1)
  end

  defp format_invalid_option({option, nil}), do: option
  defp format_invalid_option({option, value}), do: "#{option}=#{value}"
end
