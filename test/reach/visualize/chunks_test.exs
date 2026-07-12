defmodule Reach.Visualize.ChunksTest do
  use ExUnit.Case, async: false

  alias Reach.Visualize.Chunks

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "reach_chunks_test_#{:erlang.unique_integer([:positive])}"
           )

  setup_all do
    File.mkdir_p!(Path.join(@tmp_dir, "lib"))

    a =
      write_file("lib/chunk_a.ex", """
      defmodule ChunkA do
        def run(x) do
          y = ChunkB.transform(x)
          y + 1
        end
      end
      """)

    b =
      write_file("lib/chunk_b.ex", """
      defmodule ChunkB do
        def transform(v) do
          w = v * 2
          Enum.max([w, 0])
        end
      end
      """)

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)

    project = Reach.Project.from_sources([a, b])
    {:ok, output: Chunks.build(project, project: "fixture")}
  end

  defp write_file(rel, content) do
    path = Path.join(@tmp_dir, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp chunk(output, id) do
    {^id, data} = Enum.find(output.chunks, fn {chunk_id, _} -> chunk_id == id end)
    data
  end

  test "manifest lists modules with functions and chunk paths", %{output: output} do
    manifest = output.manifest

    assert manifest.project == "fixture"
    assert is_binary(manifest.generated_at)

    ids = Enum.map(manifest.modules, & &1.id)
    assert "ChunkA" in ids
    assert "ChunkB" in ids

    mod_a = Enum.find(manifest.modules, &(&1.id == "ChunkA"))
    assert mod_a.chunk == "chunks/ChunkA.js"
    assert [%{name: "run", arity: 1}] = mod_a.functions

    assert manifest.counts.modules == 2
    assert manifest.counts.functions == 2
  end

  test "manifest call graph has module-level internal edges with counts", %{output: output} do
    edges = output.manifest.call_graph.edges

    assert %{source: "ChunkA", target: "ChunkB", count: 1} in edges
    refute Enum.any?(edges, &(&1.target == "Enum"))
    refute Enum.any?(edges, &(&1.source == &1.target))
  end

  test "each chunk carries highlighted source aligned with the file", %{output: output} do
    chunk_a = chunk(output, "ChunkA")

    raw = @tmp_dir |> Path.join("lib/chunk_a.ex") |> File.read!() |> String.split("\n")
    assert length(chunk_a.source.lines_html) == length(raw)
    assert chunk_a.source.file =~ "chunk_a.ex"
  end

  test "chunk functions carry line-range CFG nodes", %{output: output} do
    chunk_a = chunk(output, "ChunkA")

    [func] = chunk_a.functions
    assert func.name == "run"
    assert func.nodes != []
    assert Enum.all?(func.nodes, &(is_integer(&1.start_line) and is_integer(&1.end_line)))
    refute Enum.any?(func.nodes, &Map.has_key?(&1, :source_html))
  end

  test "chunk calls include internal and external functions and edges", %{output: output} do
    chunk_b = chunk(output, "ChunkB")

    assert Enum.any?(
             chunk_b.calls.edges,
             &(&1.source == "ChunkA.run/1" and &1.target == "ChunkB.transform/1")
           )

    assert Enum.any?(chunk_b.calls.functions, &(&1.id == "Enum.max/1" and &1.external))

    assert Enum.any?(
             chunk_b.calls.functions,
             &(&1.id == "ChunkB.transform/1" and not &1.external)
           )
  end

  test "data flow is partitioned across chunks by owning module", %{output: output} do
    all_edges = Enum.flat_map(output.chunks, fn {_, c} -> c.data_flow.edges end)
    assert all_edges != []

    for {_, c} <- output.chunks do
      fn_ids = MapSet.new(c.data_flow.functions, & &1.id)

      for edge <- c.data_flow.edges do
        assert MapSet.member?(fn_ids, edge.source)
        assert MapSet.member?(fn_ids, edge.target)
      end
    end
  end
end
