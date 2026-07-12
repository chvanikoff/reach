defmodule Reach.CLI.Render.Report do
  @moduledoc false

  alias Reach.CLI.Requirements

  @template_path Path.join(Application.app_dir(:reach, "priv"), "template.html.eex")
  @external_resource @template_path
  @template File.read!(@template_path)

  # The JS/CSS bundles are read at render time rather than baked in at compile
  # time: `priv/static` is a build artifact (`mix assets.build`), so embedding
  # it during compilation silently produces blank reports whenever the module
  # compiles before the assets exist.

  def render_html(%{manifest: manifest, chunks: chunks}, output_dir, opts) do
    Requirements.json!("HTML/JSON output")

    chunks_dir = Path.join(output_dir, "chunks")
    # Clear out chunks from a previous run — modules can be renamed, merged,
    # or removed between runs, and a stale chunk file left behind would keep
    # being served alongside the current manifest.
    File.rm_rf!(chunks_dir)
    File.mkdir_p!(chunks_dir)

    File.write!(
      Path.join(output_dir, "manifest.js"),
      ["window.__reachManifest = ", JSON.encode!(manifest), ";\n"]
    )

    Enum.each(chunks, fn {chunk_id, data} ->
      File.write!(
        Path.join(chunks_dir, "#{chunk_id}.js"),
        ["window.__reachChunk(", JSON.encode!(chunk_id), ", ", JSON.encode!(data), ");\n"]
      )
    end)

    html =
      EEx.eval_string(@template,
        project: manifest.project,
        elk_bundle: static_asset!(["js", "elk.bundled.js"]),
        js_bundle: static_asset!(["js", "reach.js"]),
        vue_flow_css: static_asset!(["css", "vue-flow.css"]),
        makeup_css: Reach.Visualize.makeup_stylesheet()
      )

    path = Path.join(output_dir, "index.html")
    File.write!(path, html)

    Mix.shell().info("Reach report directory: #{output_dir} (entry: #{path})")

    if Keyword.get(opts, :open, true), do: open_browser(path)
  end

  def render_dot(graph, output_dir) do
    File.mkdir_p!(output_dir)
    path = Path.join(output_dir, "reach.dot")

    {:ok, dot} = Reach.to_dot(graph)
    File.write!(path, dot)

    Mix.shell().info("DOT file: #{path}")
  end

  def render_json(graph_data, output_dir) do
    Requirements.json!("HTML/JSON output")

    File.mkdir_p!(output_dir)
    path = Path.join(output_dir, "reach.json")

    File.write!(path, JSON.encode!(graph_data))

    Mix.shell().info("JSON file: #{path}")
  end

  defp static_asset!(relative_parts) do
    path = Path.join([Application.app_dir(:reach, "priv"), "static" | relative_parts])

    case File.read(path) do
      {:ok, content} when byte_size(content) > 0 ->
        content

      _missing_or_empty ->
        Mix.raise("""
        Reach frontend asset missing or empty: #{path}

        The HTML report needs Reach's built frontend assets. From the Reach
        project directory, run:

            (cd assets && npm install) && mix assets.build

        Hex releases of Reach ship these assets prebuilt; this only affects
        path/git checkouts that have not built them yet.
        """)
    end
  end

  defp open_browser(path) do
    abs = Path.expand(path)

    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [abs], stderr_to_stdout: true)
      {:unix, _} -> System.cmd("xdg-open", [abs], stderr_to_stdout: true)
      {:win32, _} -> System.cmd("cmd", ["/c", "start", "", abs], stderr_to_stdout: true)
    end
  end
end
