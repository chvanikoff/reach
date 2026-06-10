defmodule Reach.Smell.SourceRunner do
  @moduledoc false

  alias Reach.Smell.{ASTRunner, PatternRunner, Source}

  def run(project, checks) do
    files = Source.module_files(project)
    PatternRunner.run(project, checks, files) ++ ASTRunner.run(project, checks, files)
  end
end
