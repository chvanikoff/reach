defmodule Reach.CLI.Commands.Check.DeadCode do
  @moduledoc false

  alias Reach.Check.DeadCode, as: DeadCodeCheck
  alias Reach.CLI.Plugins
  alias Reach.CLI.Project
  alias Reach.CLI.Render.Check.DeadCode, as: DeadCodeRender

  def run(opts, positional, command \\ "reach.check") do
    format = opts[:format] || "text"

    Project.compile(format == "json" or opts[:multi_check?] == true)

    files = DeadCodeCheck.collect_files(opts[:path] || List.first(positional))

    unless format == "json" or opts[:multi_check?],
      do: Mix.shell().info("Analyzing #{length(files)} file(s)...")

    findings = DeadCodeCheck.run(files, Plugins.project_opts(opts))
    DeadCodeRender.render(findings, format, command)
  end
end
