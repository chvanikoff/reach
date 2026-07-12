# Per-Occurrence Skip Annotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `# reach:disable-next-line` / `# reach:disable-for-this-file` comments work for every per-line finding surface (smells, dead code, OTP, architecture), and fix the `Gettext.put_locale` purity misclassification that motivated the feature.

**Architecture:** Extract the comment-parsing half of `Reach.Smell.Suppressions` into a new shared `Reach.Suppressions` module with a `filter(findings, tokens_fun)` API. Each check pipeline calls it with its own token list (finding kind + check-group token + `all`). The Gettext fix adds two process-dictionary predicate clauses in `Reach.Effects` plus an `@impure_modules` entry.

**Tech Stack:** Elixir (1.18+/OTP 27), ExUnit. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-07-12-per-occurrence-skips-design.md`

## Global Constraints

- Elixir 1.18+ / OTP 27; no new dependencies.
- Suppression tokens are compared as **strings** — never call `String.to_atom` on user comment tokens (existing test asserts no atom creation).
- Directives must start their own line (leading whitespace allowed); trailing same-line directives are not recognized.
- A bare directive with no tokens means `all` (deliberate behavior change from silent no-op).
- Suppression filtering happens at the library layer (check modules), not the CLI layer, so JSON/text/API output is filtered consistently.
- Run `mix format` on touched files before every commit.
- Tests use `async: true` and unique temp dirs via `System.unique_integer()`, cleaned up with `on_exit` (existing convention).

---

### Task 1: `Reach.Suppressions` shared core

**Files:**
- Create: `lib/reach/suppressions.ex`
- Test: `test/reach/suppressions_test.exs` (new)

**Interfaces:**
- Consumes: nothing (self-contained; reads source files from disk).
- Produces (used by Tasks 2–5):
  - `Reach.Suppressions.filter(findings :: [finding], tokens_fun :: (finding -> [String.t()])) :: [finding]` — rejects findings whose `file:line` is covered by a directive carrying at least one token from `tokens_fun.(finding)`.
  - `Reach.Suppressions.location(finding) :: {String.t() | nil, integer() | nil}` — extracts `{file, line}` from any supported finding shape: `%{location: %{file:, line:}}`, `%{location: %{file:, start_line:}}`, `%{location: "file:line[:col]"}`, top-level `%{file:, line:}`, else `{nil, nil}`.

- [ ] **Step 1: Write the failing tests**

Create `test/reach/suppressions_test.exs`:

```elixir
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

  defp fixture(source) do
    dir = Path.join(System.tmp_dir!(), "reach-suppressions-core-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    path
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/suppressions_test.exs`
Expected: FAIL — `module Reach.Suppressions is not available` (or UndefinedFunctionError).

- [ ] **Step 3: Write the implementation**

Create `lib/reach/suppressions.ex`:

```elixir
defmodule Reach.Suppressions do
  @moduledoc """
  Parses and applies source-level suppression comments shared by all check surfaces.

  Two directives are recognized, each starting its own line (leading whitespace
  allowed):

      # reach:disable-next-line <tokens>
      # reach:disable-for-this-file <tokens>

  Tokens are space- or comma-separated strings. A directive with no tokens is
  equivalent to `all`. Unknown tokens are ignored without creating atoms.
  """

  @next_line_prefix "# reach:disable-next-line"
  @this_file_prefix "# reach:disable-for-this-file"

  @doc """
  Rejects findings covered by a suppression directive.

  `tokens_fun` receives each finding and returns the string tokens that may
  suppress it — typically `[kind, check_group, "all"]`.
  """
  def filter(findings, tokens_fun) do
    suppressions = parse_files(finding_files(findings))
    Enum.reject(findings, &suppressed?(&1, suppressions, tokens_fun))
  end

  @doc "Returns true when the finding's file:line is covered by a matching directive."
  def suppressed?(finding, suppressions, tokens_fun) do
    with {file, line} when is_binary(file) and is_integer(line) <- location(finding),
         %{file: file_tokens, lines: lines} <- Map.get(suppressions, file) do
      active = MapSet.union(file_tokens, Map.get(lines, line, MapSet.new()))
      not MapSet.disjoint?(active, MapSet.new(tokens_fun.(finding)))
    else
      _ -> false
    end
  end

  @doc "Parses suppression directives for each file, once per file."
  def parse_files(files) do
    Map.new(files, &{&1, parse_file(&1)})
  end

  @doc "Extracts `{file, line}` from any supported finding shape."
  def location(%{location: %{file: file, line: line}}), do: {file, line}
  def location(%{location: %{file: file, start_line: line}}), do: {file, line}

  def location(%{location: location}) when is_binary(location) do
    case String.split(location, ":", parts: 3) do
      [file, line] -> {file, parse_line_number(line)}
      [file, line, _column] -> {file, parse_line_number(line)}
      _ -> {nil, nil}
    end
  end

  def location(%{file: file, line: line}), do: {file, line}
  def location(_finding), do: {nil, nil}

  defp finding_files(findings) do
    findings
    |> Enum.flat_map(fn finding ->
      case location(finding) do
        {file, _line} when is_binary(file) -> [file]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp parse_file(file) do
    if File.regular?(file) do
      file
      |> File.stream!(:line, [])
      |> Stream.with_index(1)
      |> Enum.reduce(%{file: MapSet.new(), lines: %{}}, &parse_line/2)
    else
      %{file: MapSet.new(), lines: %{}}
    end
  end

  defp parse_line({line, number}, acc) do
    trimmed = String.trim_leading(line)

    cond do
      String.starts_with?(trimmed, @this_file_prefix) ->
        %{acc | file: MapSet.union(acc.file, tokens(trimmed, @this_file_prefix))}

      String.starts_with?(trimmed, @next_line_prefix) ->
        tokens = tokens(trimmed, @next_line_prefix)
        %{acc | lines: Map.update(acc.lines, number + 1, tokens, &MapSet.union(&1, tokens))}

      true ->
        acc
    end
  end

  defp tokens(line, prefix) do
    line
    |> String.trim()
    |> String.replace_prefix(prefix, "")
    |> String.split([",", " ", "\t"], trim: true)
    |> case do
      [] -> MapSet.new(["all"])
      tokens -> MapSet.new(tokens)
    end
  end

  defp parse_line_number(line) do
    case Integer.parse(line) do
      {line, _rest} -> line
      :error -> nil
    end
  end
end
```

Note: the `location/1` clause order matters — `%{location: ...}` clauses must come before the top-level `%{file:, line:}` clause so structs carrying both shapes prefer `location`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/suppressions_test.exs`
Expected: PASS (9 tests).

- [ ] **Step 5: Format and commit**

```bash
mix format lib/reach/suppressions.ex test/reach/suppressions_test.exs
git add lib/reach/suppressions.ex test/reach/suppressions_test.exs
git commit -m "feat: add shared source-level suppressions core"
```

---

### Task 2: Delegate smell suppressions to the shared core

**Files:**
- Modify: `lib/reach/smell/suppressions.ex`
- Test: `test/reach/smell/suppressions_test.exs`

**Interfaces:**
- Consumes: `Reach.Suppressions.filter/2`, `Reach.Suppressions.location/1` (Task 1).
- Produces: `Reach.Smell.Suppressions.filter(findings, project, config)` — signature unchanged; still called from `Reach.Check.Smells.run/2` (`lib/reach/check/smells.ex:19`, no change needed there).

- [ ] **Step 1: Write the failing test**

Add to `test/reach/smell/suppressions_test.exs` (before the private `fixture/2` helper):

```elixir
  test "bare disable-next-line comment suppresses the next line's findings" do
    path =
      fixture("bare_directive", """
      defmodule Generated.BareDirective do
        # reach:disable-next-line
        def run(items), do: items |> Enum.reverse() |> Enum.reverse()
      end
      """)

    project = Project.from_sources([path])

    refute Enum.any?(Smells.run(project, []), &(&1.kind == :redundant_traversal))
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/reach/smell/suppressions_test.exs`
Expected: the new test FAILS (bare directive is currently a no-op); the 6 existing tests PASS.

- [ ] **Step 3: Rewrite `Reach.Smell.Suppressions` to delegate**

Replace the entire contents of `lib/reach/smell/suppressions.ex` with:

```elixir
defmodule Reach.Smell.Suppressions do
  @moduledoc "Filters smell findings using config ignores and shared source-level suppressions."

  alias Reach.Check.Architecture
  alias Reach.Suppressions

  def filter(findings, project, config) do
    findings
    |> Suppressions.filter(&tokens/1)
    |> Enum.reject(fn finding ->
      suppressed_by_config?(finding, config) or suppressed_by_module?(finding, project, config)
    end)
  end

  defp tokens(finding), do: [Atom.to_string(finding.kind), "smells", "all"]

  def suppressed_by_config?(finding, config) do
    case Suppressions.location(finding) do
      {file, _line} when is_binary(file) ->
        finding
        |> ignore_configs(config)
        |> Enum.any?(fn ignore ->
          ignore
          |> Keyword.get(:paths, [])
          |> List.wrap()
          |> Enum.any?(&Architecture.glob_match?(file, to_string(&1)))
        end)

      _ ->
        false
    end
  end

  def suppressed_by_module?(finding, project, config) do
    ignores = ignore_configs(finding, config)

    case finding_module(finding, project) do
      nil ->
        false

      module ->
        Enum.any?(ignores, fn ignore ->
          ignore
          |> Keyword.get(:modules, [])
          |> List.wrap()
          |> Enum.any?(&Architecture.module_matches_any?(module, [&1]))
        end)
    end
  end

  defp ignore_configs(finding, config) do
    smells = config.smells
    global_ignore = Map.get(smells, :ignore, [])
    per_check_ignore = per_check_ignore(smells, finding.kind)

    [global_ignore, per_check_ignore]
    |> Enum.filter(&Keyword.keyword?/1)
  end

  defp per_check_ignore(smells, kind) do
    smells
    |> Map.get(kind)
    |> case do
      value when is_map(value) -> Map.get(value, :ignore, [])
      _ -> []
    end
  end

  defp finding_module(finding, project) do
    module_from_finding(finding) || module_from_location(finding, project)
  end

  defp module_from_finding(%{modules: [module | _]}) when is_atom(module), do: module
  defp module_from_finding(_finding), do: nil

  defp module_from_location(finding, project) do
    case Suppressions.location(finding) do
      {file, line} when is_binary(file) and is_integer(line) ->
        project.nodes
        |> Enum.map(fn {_id, node} -> node end)
        |> Enum.filter(&module_in_file?(&1, file))
        |> Enum.find_value(&module_at_line(&1, line))

      _ ->
        nil
    end
  end

  defp module_in_file?(node, file) do
    (node.type == :module_def and node.source_span) && node.source_span.file == file
  end

  defp module_at_line(node, line) do
    span = node.source_span

    if line >= span.start_line and (is_nil(span.end_line) or line <= span.end_line) do
      node.meta[:name]
    end
  end
end
```

What moved out (now lives in `Reach.Suppressions`): `@all_tokens`, both prefixes, `suppressed_by_source?/2`, `source_suppressions/1`, `parse_file/1`, `parse_line/2`, `tokens/2`, `token_allowed?/2`, `kind_token/1`, `location/1`, `parse_line_number/1`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/smell/suppressions_test.exs`
Expected: PASS (7 tests, including the 6 pre-existing ones unchanged).

- [ ] **Step 5: Run the wider smell suite for regressions**

Run: `mix test test/reach/smell/`
Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
mix format lib/reach/smell/suppressions.ex test/reach/smell/suppressions_test.exs
git add lib/reach/smell/suppressions.ex test/reach/smell/suppressions_test.exs
git commit -m "refactor: delegate smell suppressions to shared core"
```

---

### Task 3: Wire suppressions into the dead-code check

**Files:**
- Modify: `lib/reach/check/dead_code.ex` (the `run/2` pipeline, currently ending at line 37 with `Enum.uniq_by/2`)
- Test: `test/reach/check/dead_code/dead_code_test.exs`

**Interfaces:**
- Consumes: `Reach.Suppressions.filter/2` (Task 1).
- Produces: `Reach.Check.DeadCode.run/2` — same signature, now returns suppression-filtered findings. Accepted tokens: `dead_code`, `all` (node-type kinds like `call`/`match` are deliberately not tokens).

- [ ] **Step 1: Write the failing tests**

Add to `test/reach/check/dead_code/dead_code_test.exs` (before the private `temp_source/1` helper):

```elixir
  test "disable-next-line dead_code suppresses a finding" do
    path =
      temp_source(~S'''
      defmodule Repro.Suppressed do
        def run(value) do
          # reach:disable-next-line dead_code
          String.trim(value)
          value
        end
      end
      ''')

    refute Enum.any?(
             DeadCode.run([path]),
             &String.contains?(&1.description, "String.trim result unused")
           )
  end

  test "disable-for-this-file dead_code suppresses the whole file" do
    path =
      temp_source(~S'''
      # reach:disable-for-this-file dead_code
      defmodule Repro.SuppressedFile do
        def run(value) do
          String.trim(value)
          value
        end
      end
      ''')

    refute Enum.any?(
             DeadCode.run([path]),
             &String.contains?(&1.description, "String.trim result unused")
           )
  end

  test "unrelated suppression tokens keep dead code findings" do
    path =
      temp_source(~S'''
      defmodule Repro.WrongToken do
        def run(value) do
          # reach:disable-next-line smells
          String.trim(value)
          value
        end
      end
      ''')

    assert Enum.any?(
             DeadCode.run([path]),
             &String.contains?(&1.description, "String.trim result unused")
           )
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/check/dead_code/dead_code_test.exs`
Expected: the two suppression tests FAIL (findings still reported); "unrelated tokens" and the 2 pre-existing tests PASS.

- [ ] **Step 3: Add the filter to `DeadCode.run/2`**

In `lib/reach/check/dead_code.ex`, change the end of the `run/2` pipeline from:

```elixir
    |> Enum.sort_by(&{&1.file, &1.line})
    |> Enum.uniq_by(&{&1.file, &1.line})
  end
```

to:

```elixir
    |> Enum.sort_by(&{&1.file, &1.line})
    |> Enum.uniq_by(&{&1.file, &1.line})
    |> Reach.Suppressions.filter(fn _finding -> ["dead_code", "all"] end)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/check/dead_code/dead_code_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 5: Format and commit**

```bash
mix format lib/reach/check/dead_code.ex test/reach/check/dead_code/dead_code_test.exs
git add lib/reach/check/dead_code.ex test/reach/check/dead_code/dead_code_test.exs
git commit -m "feat: honor suppression comments in dead code check"
```

---

### Task 4: Wire suppressions into OTP analysis findings

**Files:**
- Modify: `lib/reach/otp/analysis.ex` (the `run/2` result assembly at lines 24–32)
- Test: `test/reach/otp/suppressions_test.exs` (new)

**Interfaces:**
- Consumes: `Reach.Suppressions.filter/2` (Task 1).
- Produces: `Reach.OTP.Analysis.run/2` — same signature; the finding-like sub-reports (`dead_replies`, `missing_handlers`, `cross_process`, `hidden_coupling`) are suppression-filtered. Kind tokens: `dead_reply`, `missing_handler`, `cross_process`, `hidden_coupling`; group tokens: `otp`, `all`. Inventory sub-reports (`behaviours`, `state_machines`, `supervision`) are not filtered.

- [ ] **Step 1: Write the failing tests**

Create `test/reach/otp/suppressions_test.exs`:

```elixir
defmodule Reach.OTP.SuppressionsTest do
  use ExUnit.Case, async: true

  alias Reach.OTP.Analysis
  alias Reach.Project

  test "control: discarded replies and ets coupling are reported without comments" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Control do
        def kick(pid, value) do
          GenServer.call(pid, :refresh)
          :ets.insert(:reach_fixture_table, {:latest, value})
          :ok
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.dead_replies != []
    assert result.hidden_coupling.ets != %{}
  end

  test "disable-next-line dead_reply suppresses a dead reply finding" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Suppressed do
        def kick(pid) do
          # reach:disable-next-line dead_reply
          GenServer.call(pid, :refresh)
          :ok
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.dead_replies == []
  end

  test "otp group token suppresses hidden coupling entries" do
    project =
      project_for(~S'''
      defmodule OtpFixture.Ets do
        def track(value) do
          # reach:disable-next-line otp
          :ets.insert(:reach_fixture_table, {:latest, value})
          value
        end
      end
      ''')

    result = Analysis.run(project, nil)

    assert result.hidden_coupling.ets == %{}
  end

  defp project_for(source) do
    dir = Path.join(System.tmp_dir!(), "reach-otp-suppressions-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    Project.from_sources([path])
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/otp/suppressions_test.exs`
Expected: the control test PASSES; the two suppression tests FAIL (findings still present).

If the control test fails instead, stop and inspect what `Analysis.run/2` returned for the fixture (`dbg` the result) — the fixture must genuinely produce a `dead_replies` entry and an `ets` group before the suppression tests mean anything. Adjust the fixture, not the assertions.

- [ ] **Step 3: Filter the finding-like sub-reports in `Analysis.run/2`**

In `lib/reach/otp/analysis.ex`, change the `Result.new` call in `run/2` from:

```elixir
    Result.new(
      behaviours: behaviours,
      state_machines: state_machines,
      hidden_coupling: hidden_coupling,
      missing_handlers: missing_handlers,
      supervision: supervision,
      dead_replies: dead_replies,
      cross_process: cross_process
    )
```

to:

```elixir
    Result.new(
      behaviours: behaviours,
      state_machines: state_machines,
      hidden_coupling: filter_hidden_coupling(hidden_coupling),
      missing_handlers: filter_findings(missing_handlers, "missing_handler"),
      supervision: supervision,
      dead_replies: filter_findings(dead_replies, "dead_reply"),
      cross_process: filter_findings(cross_process, "cross_process")
    )
```

and add these private helpers (after `run/2`):

```elixir
  defp filter_findings(entries, kind) do
    Reach.Suppressions.filter(entries, fn _entry -> [kind, "otp", "all"] end)
  end

  defp filter_hidden_coupling(%{ets: ets, process_dict: process_dict}) do
    %{ets: filter_grouped(ets), process_dict: filter_grouped(process_dict)}
  end

  defp filter_grouped(groups) do
    groups
    |> Enum.map(fn {key, ops} -> {key, filter_findings(ops, "hidden_coupling")} end)
    |> Enum.reject(fn {_key, ops} -> ops == [] end)
    |> Map.new()
  end
```

(`hidden_coupling` is `%{ets: %{table => [op]}, process_dict: %{key => [op]}}` — grouped maps, so each ops list is filtered and empty groups dropped.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/otp/suppressions_test.exs test/reach/otp/`
Expected: PASS (new suite plus existing `otp_test.exs` / `concurrency_test.exs` regressions).

- [ ] **Step 5: Format and commit**

```bash
mix format lib/reach/otp/analysis.ex test/reach/otp/suppressions_test.exs
git add lib/reach/otp/analysis.ex test/reach/otp/suppressions_test.exs
git commit -m "feat: honor suppression comments in OTP analysis findings"
```

---

### Task 5: Wire suppressions into architecture violations

**Files:**
- Modify: `lib/reach/check/architecture.ex` (`run/2` at lines 18–26)
- Test: `test/reach/check/architecture/suppressions_test.exs` (new)

**Interfaces:**
- Consumes: `Reach.Suppressions.filter/2` (Task 1); `Reach.Check.Violation` struct (`:type`, `:file`, `:line` fields).
- Produces: `Reach.Check.Architecture.run/2` — same signature; returned `Result.violations` is suppression-filtered and `Result.status` reflects the filtered list, so the CLI gate (`Reach.CLI.Commands.Check.run_arch/1`) and baseline filtering operate on post-suppression violations with no CLI change. Kind tokens: violation type atoms as strings (`forbidden_call`, `forbidden_dependency`, `forbidden_module`, …); group tokens: `arch`, `all`. Violations without `file`/`line` (e.g. `layer_cycle`, config errors) are never comment-suppressed.

- [ ] **Step 1: Write the failing tests**

Create `test/reach/check/architecture/suppressions_test.exs`:

```elixir
defmodule Reach.Check.Architecture.SuppressionsTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Architecture
  alias Reach.Project

  @config [
    forbidden_calls: [{"Fixture.Suppressions.Command", ["Fixture.Suppressions.Config.read"]}]
  ]

  test "control: a forbidden call produces a violation" do
    result = Architecture.run(project_for(command_source(nil)), @config)

    assert result.status == "failed"
    assert Enum.any?(result.violations, &(&1.type == :forbidden_call))
  end

  test "disable-next-line with the violation type suppresses it" do
    project = project_for(command_source("# reach:disable-next-line forbidden_call"))
    result = Architecture.run(project, @config)

    assert result.status == "ok"
    assert result.violations == []
  end

  test "the arch group token suppresses violations" do
    project = project_for(command_source("# reach:disable-next-line arch"))
    result = Architecture.run(project, @config)

    assert result.violations == []
  end

  defp command_source(comment) do
    comment_line = if comment, do: "    #{comment}\n", else: ""

    """
    defmodule Fixture.Suppressions.Config do
      def read, do: :ok
    end

    defmodule Fixture.Suppressions.Command do
      def run do
    #{comment_line}    Fixture.Suppressions.Config.read()
      end
    end
    """
  end

  defp project_for(source) do
    dir = Path.join(System.tmp_dir!(), "reach-arch-suppressions-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)
    Project.from_sources([path])
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/check/architecture/suppressions_test.exs`
Expected: the control test PASSES; the two suppression tests FAIL (`status == "failed"`).

If the control test fails, the fixture or config shape is wrong — compare against the working pattern in `test/reach/check/architecture/policy_test.exs:123` (`forbidden_calls: [{"Fixture.CLI.Command", ["Fixture.Config.read"]}]`) before touching the implementation.

- [ ] **Step 3: Filter violations in `Architecture.run/2`**

In `lib/reach/check/architecture.ex`, change `run/2` from:

```elixir
  def run(project, config) do
    violations =
      case Config.from_terms(config) do
        {:ok, normalized} -> violations(project, normalized)
        {:error, errors} -> Enum.map(errors, &Config.Error.to_violation/1)
      end

    %Result{status: if(violations == [], do: "ok", else: "failed"), violations: violations}
  end
```

to:

```elixir
  def run(project, config) do
    violations =
      case Config.from_terms(config) do
        {:ok, normalized} -> violations(project, normalized)
        {:error, errors} -> Enum.map(errors, &Config.Error.to_violation/1)
      end

    violations = Reach.Suppressions.filter(violations, &violation_tokens/1)

    %Result{status: if(violations == [], do: "ok", else: "failed"), violations: violations}
  end

  defp violation_tokens(%Violation{type: type}) when is_atom(type) and not is_nil(type),
    do: [Atom.to_string(type), "arch", "all"]

  defp violation_tokens(_violation), do: ["arch", "all"]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/check/architecture/`
Expected: PASS (new suite plus all existing architecture tests — the CLI gate tests in `policy_test.exs` must be unaffected because their fixtures contain no suppression comments).

- [ ] **Step 5: Format and commit**

```bash
mix format lib/reach/check/architecture.ex test/reach/check/architecture/suppressions_test.exs
git add lib/reach/check/architecture.ex test/reach/check/architecture/suppressions_test.exs
git commit -m "feat: honor suppression comments in architecture violations"
```

---

### Task 6: Classify Gettext locale functions as process-dictionary effects

**Files:**
- Modify: `lib/reach/effects.ex` (`@impure_modules` at lines 580–613; `process_dict_write?/2` and `process_dict_read?/2` at lines 983–989)
- Test: `test/reach/effects/effects_test.exs`, `test/reach/check/dead_code/dead_code_test.exs`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Reach.Effects.classify/2` returns `:write` for `Gettext.put_locale` (any arity) and `:read` for `Gettext.get_locale` (any arity). `Gettext` joins `@impure_modules`, so spec/inferred-type inference can never classify its other functions `:pure`.

- [ ] **Step 1: Write the failing tests**

Add to the `describe "classify"` block in `test/reach/effects/effects_test.exs`:

```elixir
    test "Gettext locale functions are process-dictionary effects" do
      assert Effects.classify(node_for("Gettext.put_locale(backend, locale)")) == :write
      assert Effects.classify(node_for("Gettext.put_locale(locale)")) == :write
      assert Effects.classify(node_for("Gettext.get_locale(backend)")) == :read
      assert Effects.classify(node_for("Gettext.get_locale()")) == :read
    end

    test "Logger.metadata stays effectful" do
      assert Effects.classify(node_for("Logger.metadata(request_id: id)")) == :io
    end
```

(The Logger test documents the spec's audit result: `Logger.metadata/1` is already classified `:io` via `io_function?(Logger, _)` at `lib/reach/effects.ex:925` — effectful, so no change needed.)

Add to `test/reach/check/dead_code/dead_code_test.exs`:

```elixir
  test "does not flag discarded Gettext.put_locale calls" do
    path =
      temp_source(~S'''
      defmodule Repro.Locale do
        def set(locale) do
          Gettext.put_locale(GNWeb.Gettext, locale)
          :ok
        end
      end
      ''')

    refute Enum.any?(
             DeadCode.run([path]),
             &String.contains?(&1.description, "put_locale")
           )
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/effects/effects_test.exs test/reach/check/dead_code/dead_code_test.exs`
Expected: the Gettext classify test and the dead-code regression test FAIL; the Logger test PASSES (already `:io`).

- [ ] **Step 3: Add the classifications**

In `lib/reach/effects.ex`:

1. In `@impure_modules`, add `Gettext` after `GenServer,`:

```elixir
    Registry,
    GenServer,
    Gettext,
    Supervisor
```

2. Change the process-dictionary predicates from:

```elixir
  defp process_dict_write?(Process, :put), do: true
  defp process_dict_write?(Process, :delete), do: true
  defp process_dict_write?(_, _), do: false

  defp process_dict_read?(Process, :get), do: true
  defp process_dict_read?(Process, :get_keys), do: true
  defp process_dict_read?(_, _), do: false
```

to:

```elixir
  defp process_dict_write?(Process, :put), do: true
  defp process_dict_write?(Process, :delete), do: true
  defp process_dict_write?(Gettext, :put_locale), do: true
  defp process_dict_write?(_, _), do: false

  defp process_dict_read?(Process, :get), do: true
  defp process_dict_read?(Process, :get_keys), do: true
  defp process_dict_read?(Gettext, :get_locale), do: true
  defp process_dict_read?(_, _), do: false
```

(`classify_state` runs before `classify_from_spec` in `do_classify_call/3`, so these win over the spec/inferred-type `:pure` misclassification.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/effects/ test/reach/check/dead_code/`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format lib/reach/effects.ex test/reach/effects/effects_test.exs test/reach/check/dead_code/dead_code_test.exs
git add lib/reach/effects.ex test/reach/effects/effects_test.exs test/reach/check/dead_code/dead_code_test.exs
git commit -m "fix: classify Gettext locale functions as process-dictionary effects"
```

---

### Task 7: Documentation, CHANGELOG, and full-suite verification

**Files:**
- Modify: `guides/configuration.md` (lines 481–489, the smells-scoped comment docs)
- Modify: `lib/mix/tasks/reach.check.ex` (moduledoc)
- Modify: `lib/mix/tasks/reach.otp.ex` (moduledoc)
- Modify: `CHANGELOG.md` (`## Unreleased` section)

**Interfaces:**
- Consumes: the behavior shipped in Tasks 1–6.
- Produces: user-facing docs; no code.

- [ ] **Step 1: Generalize the suppression docs in `guides/configuration.md`**

Replace this block (currently at the end of the `### smells[:ignore]` section, lines 481–489):

```markdown
For local, source-level exceptions, use Credo-style comments:

```elixir
# reach:disable-for-this-file fixed_shape_map
# reach:disable-next-line bare_rescue
def run, do: rescue_fallback()
```

Use `smells` or `all` instead of a specific kind to suppress every smell finding at that scope. Unknown comment tokens are ignored without creating atoms.
```

with:

```markdown
For local, source-level exceptions, see the source-level suppression comments section below — smell kinds work as tokens there.

### Source-level suppression comments

For per-occurrence exceptions in any check surface, use Credo-style comments on their own line:

```elixir
# reach:disable-for-this-file fixed_shape_map
# reach:disable-next-line bare_rescue
def run, do: rescue_fallback()

# reach:disable-next-line dead_code
Gettext.put_locale(MyAppWeb.Gettext, locale)
```

Comments are honored by `mix reach.check --smells`, `mix reach.check --dead-code`, `mix reach.check --arch`, and the finding-like `mix reach.otp` reports (dead replies, hidden coupling, missing handlers, cross-process coupling). Each finding accepts three tiers of token:

| Tier | Examples | Meaning |
|---|---|---|
| Finding kind | `bare_rescue`, `dead_reply`, `forbidden_call` | one specific finding kind |
| Check group | `smells`, `dead_code`, `otp`, `arch` | any finding from that surface |
| Global | `all` | any Reach finding |

Tokens are space- or comma-separated. A directive with no tokens is equivalent to `all`. Unknown tokens are ignored without creating atoms. Suppressions are applied before baseline filtering and strict/gate failure checks, so a suppressed architecture violation no longer fails `--arch`. Findings without a source location (project-level violations such as `layer_cycle`, OTP reports with unknown locations) cannot be comment-suppressed.
```

- [ ] **Step 2: Mention suppressions in the task moduledocs**

In `lib/mix/tasks/reach.check.ex`, add to the end of the moduledoc (after the `## Options` list):

```markdown
  Findings can be suppressed per occurrence with `# reach:disable-next-line <token>`
  and `# reach:disable-for-this-file <token>` comments; see the configuration guide.
```

In `lib/mix/tasks/reach.otp.ex`, add the same two lines to the end of its moduledoc (after the `## Options` list).

- [ ] **Step 3: Add the CHANGELOG entry**

In `CHANGELOG.md`, replace:

```markdown
## Unreleased
```

with:

```markdown
## Unreleased

### Changed

- **Per-occurrence suppressions everywhere** — `# reach:disable-next-line` and `# reach:disable-for-this-file` comments are now honored by `mix reach.check --dead-code`, `mix reach.check --arch`, and `mix reach.otp` findings in addition to smells, with check-group tokens (`smells`, `dead_code`, `otp`, `arch`) and `all`. A bare directive with no tokens now suppresses all checks for its scope (previously a silent no-op).

### Fixed

- **Gettext locale effects** — `Gettext.put_locale/1,2` and `Gettext.get_locale/0,1` are now classified as process-dictionary effects, so `mix reach.check --dead-code` no longer flags discarded `put_locale` calls as dead code.
```

- [ ] **Step 4: Run the full test suite**

Run: `mix test`
Expected: PASS, no failures anywhere (this is the whole-project regression gate for the feature).

- [ ] **Step 5: Format and commit**

```bash
mix format lib/mix/tasks/reach.check.ex lib/mix/tasks/reach.otp.ex
git add guides/configuration.md lib/mix/tasks/reach.check.ex lib/mix/tasks/reach.otp.ex CHANGELOG.md
git commit -m "docs: document per-occurrence suppression comments across checks"
```
