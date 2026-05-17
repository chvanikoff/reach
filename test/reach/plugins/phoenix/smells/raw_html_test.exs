defmodule Reach.Plugins.Phoenix.Smells.RawHTMLTest do
  use ExUnit.Case, async: true

  alias Reach.Plugins.Phoenix
  alias Reach.Plugins.Phoenix.Smells.RawHTML
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags raw/1 with dynamic content" do
    project =
      project_from_file(~S'''
      defmodule MyAppWeb.CommentHTML do
        def body(assigns) do
          raw(assigns.comment.body)
        end
      end
      ''')

    assert [%Finding{kind: :phoenix_raw_html}] = RawHTML.run(project)
  end

  test "allows raw/1 with literal content" do
    project =
      project_from_file(~S'''
      defmodule MyAppWeb.IconHTML do
        def icon do
          raw("<svg></svg>")
        end
      end
      ''')

    assert [] = RawHTML.run(project)
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-phoenix-raw-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path], plugins: [Phoenix])
  end
end
