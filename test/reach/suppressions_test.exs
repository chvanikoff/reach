defmodule Reach.SuppressionsTest do
  use ExUnit.Case, async: true

  alias Reach.Suppressions

  defp tokens_fun(finding), do: [finding.kind, "group", "all"]

  test "disable-next-line with a kind token suppresses only the following line" do
    path =
      fixture("""
      line one
      # reach:disable-next-line some_kind
      line three
      line four
      """)

    findings = [
      %{kind: "some_kind", file: path, line: 3},
      %{kind: "some_kind", file: path, line: 4}
    ]

    assert Suppressions.filter(findings, &tokens_fun/1) == [
             %{kind: "some_kind", file: path, line: 4}
           ]
  end

  test "disable-for-this-file suppresses findings anywhere in the file" do
    path =
      fixture("""
      # reach:disable-for-this-file some_kind
      line two
      line three
      """)

    findings = [
      %{kind: "some_kind", file: path, line: 2},
      %{kind: "some_kind", file: path, line: 3}
    ]

    assert Suppressions.filter(findings, &tokens_fun/1) == []
  end

  test "group and all tokens suppress; unrelated tokens do not" do
    path =
      fixture("""
      # reach:disable-next-line group
      line two
      # reach:disable-next-line all
      line four
      # reach:disable-next-line other_kind
      line six
      """)

    findings = [
      %{kind: "some_kind", file: path, line: 2},
      %{kind: "some_kind", file: path, line: 4},
      %{kind: "some_kind", file: path, line: 6}
    ]

    assert Suppressions.filter(findings, &tokens_fun/1) == [
             %{kind: "some_kind", file: path, line: 6}
           ]
  end

  test "a bare directive with no tokens suppresses everything in scope" do
    path =
      fixture("""
      # reach:disable-next-line
      line two
      """)

    findings = [%{kind: "some_kind", file: path, line: 2}]

    assert Suppressions.filter(findings, &tokens_fun/1) == []
  end

  test "comma-separated tokens all apply" do
    path =
      fixture("""
      # reach:disable-next-line first_kind, second_kind
      line two
      """)

    findings = [%{kind: "second_kind", file: path, line: 2}]

    assert Suppressions.filter(findings, &tokens_fun/1) == []
  end

  test "indented directives are recognized" do
    path =
      fixture("""
      line one
        # reach:disable-next-line some_kind
        line three
      """)

    findings = [%{kind: "some_kind", file: path, line: 3}]

    assert Suppressions.filter(findings, &tokens_fun/1) == []
  end

  test "location/1 handles every supported finding shape" do
    assert Suppressions.location(%{location: %{file: "a.ex", line: 3}}) == {"a.ex", 3}
    assert Suppressions.location(%{location: %{file: "a.ex", start_line: 4}}) == {"a.ex", 4}
    assert Suppressions.location(%{location: "a.ex:5"}) == {"a.ex", 5}
    assert Suppressions.location(%{location: "a.ex:6:2"}) == {"a.ex", 6}
    assert Suppressions.location(%{file: "a.ex", line: 7}) == {"a.ex", 7}
    assert Suppressions.location(%{location: "unknown"}) == {nil, nil}
    assert Suppressions.location(%{message: "no location"}) == {nil, nil}
  end

  test "findings without a resolvable location are kept" do
    findings = [%{kind: "some_kind", location: "unknown"}, %{kind: "some_kind"}]

    assert Suppressions.filter(findings, &tokens_fun/1) == findings
  end

  test "findings in unreadable files are kept" do
    findings = [%{kind: "some_kind", file: "/nonexistent/reach/sample.ex", line: 1}]

    assert Suppressions.filter(findings, &tokens_fun/1) == findings
  end

  test "disable-for-this-file suppresses a finding with a binary file but no line" do
    path =
      fixture("""
      # reach:disable-for-this-file some_kind
      line two
      line three
      """)

    findings = [%{kind: "some_kind", file: path, line: nil}]

    assert Suppressions.filter(findings, &tokens_fun/1) == []
  end

  test "disable-next-line elsewhere in the file does not suppress a finding with no line" do
    path =
      fixture("""
      line one
      # reach:disable-next-line some_kind
      line three
      """)

    findings = [%{kind: "some_kind", file: path, line: nil}]

    assert Suppressions.filter(findings, &tokens_fun/1) == findings
  end

  defp fixture(source) do
    dir = Path.join(System.tmp_dir!(), "reach-suppressions-core-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    path
  end
end
