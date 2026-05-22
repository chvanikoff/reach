defmodule Reach.CLI.Text do
  @moduledoc false

  alias Reach.CLI.Format

  def section(title, lines) when is_list(lines) do
    IO.puts(Format.header(title))
    Enum.each(lines, &IO.puts/1)
  end

  def subsection(title), do: Format.section(title)

  def line(text), do: ["  ", text]
  def empty(text \\ "none"), do: line(Format.empty(text))
  def summary(text), do: line(text)
  def blank, do: ""
end
