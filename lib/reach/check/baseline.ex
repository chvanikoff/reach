defmodule Reach.Check.Baseline do
  @moduledoc false

  alias Reach.Check.Finding

  @derive JSON.Encoder
  defstruct version: 1, tool: "reach", findings: []

  def path(opts, config) do
    opts[:baseline] || config.checks.baseline
  end

  def write_path(opts), do: opts[:write_baseline]

  def filter(findings, nil), do: {findings, []}

  def filter(findings, path) do
    baseline = read(path)
    known = MapSet.new(Enum.map(baseline.findings, & &1.fingerprint))
    Enum.split_with(findings, &(!MapSet.member?(known, &1.fingerprint)))
  end

  def write(path, source, findings) do
    existing = read(path)
    source = to_string(source)

    retained =
      Enum.reject(existing.findings, fn finding ->
        to_string(finding.source) == source
      end)

    baseline = %__MODULE__{existing | findings: Enum.sort_by(retained ++ findings, &sort_key/1)}
    File.write!(path, JSON.encode!(baseline) <> "\n")
  end

  def read(nil), do: %__MODULE__{}

  def read(path) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> JSON.decode!()
      |> from_map()
    else
      %__MODULE__{}
    end
  end

  defp from_map(data) do
    findings = field(data, :findings, [])

    %__MODULE__{
      version: field(data, :version, 1),
      tool: field(data, :tool, "reach"),
      findings: Enum.map(findings, &finding_from_map/1)
    }
  end

  defp finding_from_map(data) do
    %Finding{
      source: field(data, :source),
      kind: field(data, :kind),
      fingerprint: field!(data, :fingerprint),
      message: field(data, :message),
      file: field(data, :file),
      line: field(data, :line)
    }
  end

  defp field(map, key, default \\ nil),
    do: Map.get(map, key) || Map.get(map, to_string(key), default)

  defp field!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(map, to_string(key))
    end
  end

  defp sort_key(finding) do
    {to_string(finding.source), to_string(finding.file), finding.line || 0,
     to_string(finding.kind)}
  end
end
