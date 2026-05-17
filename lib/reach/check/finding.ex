defmodule Reach.Check.Finding do
  @moduledoc false

  @derive Jason.Encoder
  @enforce_keys [:source, :kind, :fingerprint, :message]
  defstruct [:source, :kind, :fingerprint, :message, :file, :line]

  alias Reach.Smell.Finding, as: SmellFinding

  def from_arch_violation(violation) do
    data = Map.from_struct(violation)
    file = Map.get(data, :file)
    line = Map.get(data, :line)
    kind = Map.get(data, :type, :architecture)
    message = arch_message(data)

    %__MODULE__{
      source: :arch,
      kind: kind,
      file: file,
      line: line,
      message: message,
      fingerprint: fingerprint(:arch, kind, file, line, message)
    }
  end

  def from_smell(%SmellFinding{} = finding) do
    {file, line} = location_parts(finding.location)

    %__MODULE__{
      source: :smells,
      kind: finding.kind,
      file: file,
      line: line,
      message: finding.message,
      fingerprint: fingerprint(:smells, finding.kind, nil, nil, finding.message)
    }
  end

  defp location_parts(%{file: file, line: line}), do: {file, line}
  defp location_parts(%{file: file, start_line: line}), do: {file, line}

  defp location_parts(location) when is_binary(location) do
    case Regex.run(~r/^(.*):(\d+)$/, location) do
      [_match, file, line] -> {file, String.to_integer(line)}
      _ -> {location, nil}
    end
  end

  defp location_parts(_location), do: {nil, nil}

  defp arch_message(data) do
    data
    |> Map.drop([:__struct__])
    |> Jason.encode!()
  end

  defp fingerprint(source, kind, file, line, message) do
    input = [to_string(source), to_string(kind), to_string(file), to_string(line), message]

    ["sha256:", Base.encode16(:crypto.hash(:sha256, Enum.join(input, "\0")), case: :lower)]
    |> IO.iodata_to_binary()
  end
end
