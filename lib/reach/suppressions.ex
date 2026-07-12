defmodule Reach.Suppressions do
  @moduledoc """
  Parses and applies source-level suppression comments shared by all check surfaces.

  Two directives are recognized, each starting its own line (leading whitespace
  allowed):

      # reach:disable-next-line <tokens>
      # reach:disable-for-this-file <tokens>

  Tokens are space- or comma-separated strings. A directive with no tokens is
  equivalent to `all`. Unknown tokens are ignored without creating atoms.
  """

  @next_line_prefix "# reach:disable-next-line"
  @this_file_prefix "# reach:disable-for-this-file"

  @doc """
  Rejects findings covered by a suppression directive.

  `tokens_fun` receives each finding and returns the string tokens that may
  suppress it — typically `[kind, check_group, "all"]`.
  """
  def filter(findings, tokens_fun) do
    suppressions = parse_files(finding_files(findings))
    Enum.reject(findings, &suppressed?(&1, suppressions, tokens_fun))
  end

  @doc "Returns true when the finding's file:line is covered by a matching directive."
  def suppressed?(finding, suppressions, tokens_fun) do
    with {file, line} when is_binary(file) and is_integer(line) <- location(finding),
         %{file: file_tokens, lines: lines} <- Map.get(suppressions, file) do
      active = MapSet.union(file_tokens, Map.get(lines, line, MapSet.new()))
      not MapSet.disjoint?(active, MapSet.new(tokens_fun.(finding)))
    else
      _ -> false
    end
  end

  @doc "Parses suppression directives for each file, once per file."
  def parse_files(files) do
    Map.new(files, &{&1, parse_file(&1)})
  end

  @doc "Extracts `{file, line}` from any supported finding shape."
  def location(%{location: %{file: file, line: line}}), do: {file, line}
  def location(%{location: %{file: file, start_line: line}}), do: {file, line}

  def location(%{location: location}) when is_binary(location) do
    case String.split(location, ":", parts: 3) do
      [file, line] -> {file, parse_line_number(line)}
      [file, line, _column] -> {file, parse_line_number(line)}
      _ -> {nil, nil}
    end
  end

  def location(%{file: file, line: line}), do: {file, line}
  def location(_finding), do: {nil, nil}

  defp finding_files(findings) do
    findings
    |> Enum.flat_map(fn finding ->
      case location(finding) do
        {file, _line} when is_binary(file) -> [file]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp parse_file(file) do
    if File.regular?(file) do
      file
      |> File.stream!(:line, [])
      |> Stream.with_index(1)
      |> Enum.reduce(%{file: MapSet.new(), lines: %{}}, &parse_line/2)
    else
      %{file: MapSet.new(), lines: %{}}
    end
  end

  defp parse_line({line, number}, acc) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, @this_file_prefix) ->
        %{acc | file: MapSet.union(acc.file, tokens(trimmed, @this_file_prefix))}

      String.starts_with?(trimmed, @next_line_prefix) ->
        tokens = tokens(trimmed, @next_line_prefix)
        %{acc | lines: Map.update(acc.lines, number + 1, tokens, &MapSet.union(&1, tokens))}

      true ->
        acc
    end
  end

  defp tokens(line, prefix) do
    line
    |> String.trim()
    |> String.replace_prefix(prefix, "")
    |> String.split([",", " ", "\t"], trim: true)
    |> case do
      [] -> MapSet.new(["all"])
      tokens -> MapSet.new(tokens)
    end
  end

  defp parse_line_number(line) do
    case Integer.parse(line) do
      {line, _rest} -> line
      :error -> nil
    end
  end
end
