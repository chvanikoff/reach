defmodule Reach.CLI.Commands.Report do
  @moduledoc """
  Analyze code with Reach and generate an interactive dependency graph.

      mix reach
      mix reach lib/my_app/server.ex
      mix reach --dead-code
      mix reach --format dot

  ## Options

    * `--format` — output format: `html` (default), `dot`, `json`
    * `--output` — output directory (default: `reach_report`)
    * `--open` / `--no-open` — open browser after generating (default: true)
    * `--dead-code` — highlight dead code

  """

  alias Reach.CLI.Render.Report, as: ReportRender

  def run(opts, files \\ []) do
    Reach.CLI.Project.compile()

    format = opts[:format] || "html"
    output_dir = opts[:output] || "reach_report"

    graph = build_graph(files)

    case format do
      "html" ->
        chunked =
          Reach.Visualize.Chunks.build(graph, build_viz_opts(opts) ++ [project: project_name()])

        ReportRender.render_html(chunked, output_dir, opts)

      "json" ->
        graph_data = Reach.Visualize.to_graph_json(graph, build_viz_opts(opts))
        ReportRender.render_json(graph_data, output_dir)

      "dot" ->
        ReportRender.render_dot(graph, output_dir)

      other ->
        Mix.raise("Unknown format: #{other}. Use html, dot, or json.")
    end
  end

  defp project_name do
    case Mix.Project.config()[:app] do
      nil -> File.cwd!() |> Path.basename()
      app -> to_string(app)
    end
  end

  defp build_graph([]) do
    Mix.shell().info("Analyzing project...")
    Reach.Project.from_mix_project()
  end

  defp build_graph(files) do
    Mix.shell().info("Analyzing #{length(files)} file(s)...")
    Reach.Project.from_sources(files)
  end

  defp build_viz_opts(opts) do
    if opts[:dead_code], do: [dead_code: true], else: []
  end
end
