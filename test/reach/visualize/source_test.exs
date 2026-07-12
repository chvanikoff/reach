defmodule Reach.Visualize.SourceTest do
  use ExUnit.Case, async: true

  alias Reach.Visualize.Source

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "reach_source_test_#{:erlang.unique_integer([:positive])}"
           )

  setup do
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  defp write_file(name, content) do
    path = Path.join(@tmp_dir, name)
    File.write!(path, content)
    path
  end

  describe "highlight_file_lines/1" do
    test "returns one HTML line per source line, including multi-line tokens" do
      path =
        write_file("sample.ex", """
        defmodule Sample do
          @doc \"\"\"
          multi-line
          doc
          \"\"\"
          def add(a, b) do
            a + b
          end
        end
        """)

      lines = Source.highlight_file_lines(path)
      raw_lines = path |> File.read!() |> String.split("\n")

      assert length(lines) == length(raw_lines)
      refute Enum.any?(lines, &String.contains?(&1, "\n"))
    end

    test "wraps tokens in highlight spans" do
      path = write_file("hl.ex", "defmodule HL do\nend\n")
      [first | _] = Source.highlight_file_lines(path)

      assert first =~ "<span"
      assert first =~ "defmodule"
    end

    test "line content matches source line positions" do
      path = write_file("pos.ex", "defmodule Pos do\n  def go(x), do: x\nend\n")
      lines = Source.highlight_file_lines(path)

      assert Enum.at(lines, 1) =~ "go"
      refute Enum.at(lines, 0) =~ "go"
    end

    test "returns nil for missing files" do
      assert Source.highlight_file_lines(Path.join(@tmp_dir, "missing.ex")) == nil
    end

    test "returns nil for non-source files and nil paths" do
      path = write_file("notes.txt", "hello")
      assert Source.highlight_file_lines(path) == nil
      assert Source.highlight_file_lines(nil) == nil
    end
  end

  describe "escape_html/1" do
    test "escapes markup characters" do
      assert Source.escape_html(~s(a < b && "c")) == "a &lt; b &amp;&amp; \"c\""
    end
  end
end
