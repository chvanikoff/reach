defmodule Reach.CLI.Render.ReportTest do
  use ExUnit.Case, async: false

  alias Reach.CLI.Render.Report
  alias Reach.Visualize.Chunks

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "reach_report_render_test_#{:erlang.unique_integer([:positive])}"
           )

  setup do
    File.mkdir_p!(Path.join(@tmp_dir, "lib"))
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "render_html writes index, manifest, and per-module chunks" do
    path = Path.join(@tmp_dir, "lib/render_fixture.ex")

    File.write!(path, """
    defmodule RenderFixture do
      def go(x), do: x + 1
    end
    """)

    project = Reach.Project.from_sources([path])
    chunked = Chunks.build(project, project: "fixture")
    out = Path.join(@tmp_dir, "report")

    Report.render_html(chunked, out, open: false)

    index = File.read!(Path.join(out, "index.html"))
    assert index =~ ~s(<script src="manifest.js"></script>)
    assert index =~ "Reach — fixture"
    refute index =~ "window.graphData"

    # The JS bundles must be genuinely embedded (elk alone is >1MB) — a
    # missing assets build must raise in render_html, never silently
    # produce a blank report.
    assert byte_size(index) > 1_000_000

    manifest_js = File.read!(Path.join(out, "manifest.js"))
    assert String.starts_with?(manifest_js, "window.__reachManifest = ")

    manifest =
      manifest_js
      |> String.trim_leading("window.__reachManifest = ")
      |> String.trim_trailing(";\n")
      |> JSON.decode!()

    assert Enum.any?(manifest["modules"], &(&1["id"] == "RenderFixture"))

    chunk_js = File.read!(Path.join([out, "chunks", "RenderFixture.js"]))

    assert [_, id_json, payload_json] =
             Regex.run(~r/^window\.__reachChunk\((".*?"), (.*)\);\n$/s, chunk_js)

    assert JSON.decode!(id_json) == "RenderFixture"

    assert %{"functions" => [_ | _], "source" => %{"lines_html" => [_ | _]}} =
             JSON.decode!(payload_json)
  end

  test "render_html removes stale chunks left over from a previous run" do
    path = Path.join(@tmp_dir, "lib/render_fixture.ex")

    File.write!(path, """
    defmodule RenderFixture do
      def go(x), do: x + 1
    end
    """)

    project = Reach.Project.from_sources([path])
    chunked = Chunks.build(project, project: "fixture")
    out = Path.join(@tmp_dir, "report")

    Report.render_html(chunked, out, open: false)

    stale_chunk = Path.join([out, "chunks", "StaleModule.js"])
    File.write!(stale_chunk, "window.__reachChunk(\"StaleModule\", {});\n")
    assert File.exists?(stale_chunk)

    # Re-render (e.g. after StaleModule was renamed/removed from the source
    # project) must not leave the old chunk file behind.
    Report.render_html(chunked, out, open: false)

    refute File.exists?(stale_chunk)
    assert File.exists?(Path.join([out, "chunks", "RenderFixture.js"]))
  end
end
