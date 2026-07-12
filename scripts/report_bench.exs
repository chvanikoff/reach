# Benchmarks the report pipeline. Usage:
#   mix run scripts/report_bench.exs [source_glob ...]
# Defaults to this project's lib/**/*.ex.

globs =
  case System.argv() do
    [] -> ["lib/**/*.ex"]
    args -> args
  end

paths = globs |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq() |> Enum.sort()
IO.puts("Files: #{length(paths)}")

{t_project, project} = :timer.tc(fn -> Reach.Project.from_sources(paths) end)

IO.puts(
  "from_sources:  #{Float.round(t_project / 1_000_000, 1)}s (#{map_size(project.nodes)} nodes)"
)

{t_chunks, output} = :timer.tc(fn -> Reach.Visualize.Chunks.build(project, project: "bench") end)

IO.puts(
  "Chunks.build:  #{Float.round(t_chunks / 1_000_000, 1)}s (#{length(output.chunks)} chunks)"
)

manifest_bytes = byte_size(JSON.encode!(output.manifest))
chunk_bytes = output.chunks |> Enum.map(fn {_, c} -> byte_size(JSON.encode!(c)) end) |> Enum.sum()

IO.puts("manifest:      #{Float.round(manifest_bytes / 1_048_576, 2)} MB")
IO.puts("chunks total:  #{Float.round(chunk_bytes / 1_048_576, 2)} MB")

largest =
  output.chunks
  |> Enum.map(fn {id, c} -> {id, byte_size(JSON.encode!(c))} end)
  |> Enum.max_by(&elem(&1, 1))

IO.puts("largest chunk: #{elem(largest, 0)} #{Float.round(elem(largest, 1) / 1_048_576, 2)} MB")
