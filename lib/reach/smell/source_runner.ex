defmodule Reach.Smell.SourceRunner do
  @moduledoc false

  alias Reach.Smell.ASTRunner
  alias Reach.Smell.PatternRunner

  def run(project, checks) do
    PatternRunner.run(project, checks) ++ ASTRunner.run(project, checks)
  end
end
