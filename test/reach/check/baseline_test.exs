defmodule Reach.Check.BaselineTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Baseline
  alias Reach.Check.Finding
  alias Reach.Check.Violation
  alias Reach.Smell

  test "writes and filters known findings" do
    path = baseline_path()
    known = finding("known")
    new = finding("new")

    Baseline.write(path, :smells, [known])

    assert {[^new], [^known]} = Baseline.filter([known, new], path)
  after
    cleanup_baseline()
  end

  test "rewrites only the selected source" do
    path = baseline_path()
    arch = %Finding{finding("arch") | source: :arch}
    old_smell = %Finding{finding("old-smell") | source: :smells}
    new_smell = %Finding{finding("new-smell") | source: :smells}

    Baseline.write(path, :arch, [arch])
    Baseline.write(path, :smells, [old_smell])
    Baseline.write(path, :smells, [new_smell])

    baseline = Baseline.read(path)

    assert Enum.map(baseline.findings, & &1.fingerprint) |> Enum.sort() ==
             Enum.map([arch, new_smell], & &1.fingerprint) |> Enum.sort()
  after
    cleanup_baseline()
  end

  test "converts architecture violations to fingerprints" do
    violation =
      Violation.new(
        type: :forbidden_call,
        file: "lib/foo.ex",
        line: 12,
        caller_module: Foo,
        call: "Bar.baz/1",
        rule: "test"
      )

    finding = Finding.from_arch_violation(violation)

    assert finding.source == :arch
    assert finding.kind == :forbidden_call
    assert finding.file == "lib/foo.ex"
    assert finding.line == 12
    assert finding.fingerprint =~ "sha256:"
  end

  test "converts smell findings to stable fingerprints" do
    left =
      Smell.Finding.new(
        kind: :suboptimal,
        message: "use match?/2",
        location: "lib/foo.ex:10"
      )

    right =
      Smell.Finding.new(
        kind: :suboptimal,
        message: "use match?/2",
        location: "lib/foo.ex:99"
      )

    assert Finding.from_smell(left).fingerprint == Finding.from_smell(right).fingerprint
  end

  defp finding(id) do
    %Finding{
      source: :smells,
      kind: :suboptimal,
      fingerprint: "sha256:" <> id,
      message: id,
      file: "lib/#{id}.ex",
      line: 1
    }
  end

  defp baseline_path do
    path = Path.join(System.tmp_dir!(), "reach-baseline-test-#{System.unique_integer()}.json")
    Process.put(:baseline_path, path)
    path
  end

  defp cleanup_baseline do
    if path = Process.get(:baseline_path), do: File.rm(path)
  end
end
