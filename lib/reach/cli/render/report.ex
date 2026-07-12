defmodule Reach.CLI.Render.Report do
  @moduledoc false

  alias Reach.CLI.Requirements

  @priv_dir Application.app_dir(:reach, "priv")

  @template_path Path.join(@priv_dir, "template.html.eex")
  @js_bundle_path Path.join([@priv_dir, "static", "js", "reach.js"])
  @elk_bundle_path Path.join([@priv_dir, "static", "js", "elk.bundled.js"])
  @vue_flow_css_path Path.join([@priv_dir, "static", "css", "vue-flow.css"])

  for path <- [
        @template_path,
        @js_bundle_path,
        @elk_bundle_path,
        @vue_flow_css_path
      ] do
    @external_resource path
  end

  @template File.read!(@template_path)
  @js_bundle if File.exists?(@js_bundle_path), do: File.read!(@js_bundle_path), else: ""
  @elk_bundle if File.exists?(@elk_bundle_path), do: File.read!(@elk_bundle_path), else: ""
  @vue_flow_css if File.exists?(@vue_flow_css_path), do: File.read!(@vue_flow_css_path), else: ""

  def render_html(%{manifest: manifest, chunks: chunks}, output_dir, opts) do
    Requirements.json!("HTML/JSON output")

    chunks_dir = Path.join(output_dir, "chunks")
    File.mkdir_p!(chunks_dir)

    File.write!(
      Path.join(output_dir, "manifest.js"),
      ["window.__reachManifest = ", JSON.encode!(manifest), ";\n"]
    )

    for {chunk_id, data} <- chunks do
      File.write!(
        Path.join(chunks_dir, "#{chunk_id}.js"),
        ["window.__reachChunk(", JSON.encode!(chunk_id), ", ", JSON.encode!(data), ");\n"]
      )
    end

    html =
      EEx.eval_string(@template,
        project: manifest.project,
        elk_bundle: @elk_bundle,
        js_bundle: @js_bundle,
        vue_flow_css: @vue_flow_css,
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

  defp open_browser(path) do
    abs = Path.expand(path)

    case :os.type() do
      {:unix, :darwin} -> System.cmd("open", [abs], stderr_to_stdout: true)
      {:unix, _} -> System.cmd("xdg-open", [abs], stderr_to_stdout: true)
      {:win32, _} -> System.cmd("cmd", ["/c", "start", "", abs], stderr_to_stdout: true)
    end
  end
end
