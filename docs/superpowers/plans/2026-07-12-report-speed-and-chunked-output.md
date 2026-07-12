# Report Speed & Chunked Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mix reach` fast on large codebases (~25s instead of ~115s on a 1,300-file project) and replace the single 58MB HTML report with a chunked directory (`index.html` + `manifest.js` + per-module `chunks/*.js`) that any browser can open.

**Architecture:** Three pipeline fixes (MapSet membership, once-per-file Makeup highlighting, parallel per-module viz build) plus a new `Reach.Visualize.Chunks` builder that emits a manifest + per-module data chunks. The Vue frontend stops rendering the whole project: module-level call graph landing (namespace-grouped), per-module ego graphs, per-function control flow, module-scoped data flow — all lazy-loaded via `<script src>` injection (works over `file://`).

**Tech Stack:** Elixir ~> 1.19 (std-lib `JSON`), Makeup (optional dep), Vue 3 + Vue Flow + elkjs, volt (esbuild wrapper) for assets.

**Spec:** `docs/superpowers/specs/2026-07-12-report-speed-and-chunked-output-design.md`

## Global Constraints

- Layering (AGENTS.md): data building lives in `Reach.Visualize.*`; file writing/rendering in `Reach.CLI.Render.*`; orchestration in `Reach.CLI.Commands.*`. Never call Reach Mix tasks internally.
- No framework-specific names in generic visualization modules; plugin callbacks only.
- No magic numbers in domain code — named constants/options (e.g. the 150-module grouping threshold is a named export `GROUP_THRESHOLD` in JS).
- `--format json` and `--format dot` keep their single-file outputs. The only intended `json` schema change: control-flow block nodes carry `start_line`/`end_line`/`source_text` instead of `source_html`.
- Block quality invariants (AGENTS.md) must keep holding; invariant 6 is reworded by this plan (Task 3), not dropped.
- Test inventory: no existing test *name* may disappear (AGENTS.md). We modify test bodies/private helpers only, and add new tests.
- Makeup is an optional dependency at runtime: every new Makeup call must be guarded by `Code.ensure_loaded?/1` and listed in `no_warn_undefined` in `mix.exs`.
- All commands run from the repo root. Elixir tests: `mix test <path>`. JS lint: `mix js.check`.

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `lib/reach/visualize.ex` | modify | MapSet fix; public `call_graph/1` (view + raw edges) and `data_flow/2` |
| `lib/reach/visualize/source.ex` | modify | new `highlight_file_lines/1` (once-per-file highlighting) |
| `lib/reach/visualize/control_flow.ex` | modify | blocks as line ranges (no `source_html`), `source_text` fallback, parallel `build/2`, public `build_module/1` + `build_top_level/2` |
| `lib/reach/visualize/chunks.ex` | create | manifest + per-module chunk payloads |
| `lib/reach/cli/render/report.ex` | modify | write `index.html` + `manifest.js` + `chunks/*.js` |
| `lib/reach/cli/commands/report.ex` | modify | orchestrate html→Chunks, json/dot→existing |
| `priv/template.html.eex` | modify | drop inline data; `<script src="manifest.js">`; new CSS |
| `mix.exs` | modify | `no_warn_undefined` additions; vendor-copy step in `assets.build` |
| `assets/js/types.ts` | replace | manifest/chunk TypeScript interfaces (currently unused by imports — safe) |
| `assets/js/chunks.ts` | create | script-injection chunk loader |
| `assets/js/source.ts` | create | line slicing, HTML dedent, text extraction, escaping |
| `assets/js/grouping.ts` | create | namespace grouping for module landing graph |
| `assets/js/app.ts` | modify | boot from `window.__reachManifest` |
| `assets/js/components/ReachGraph.vue` | rewrite | lazy per-selection rendering |
| `assets/js/components/CodeNode.vue` | modify | render pre-sliced `lines` array |
| `test/reach/visualize/source_test.exs` | create | `highlight_file_lines/1` |
| `test/reach/visualize/chunks_test.exs` | create | manifest/chunk building |
| `test/reach/cli/render/report_test.exs` | create | directory writer integration |
| `test/reach/visualize_test.exs` | modify | line-range block schema assertions |
| `test/reach/program_facts/visualize_fuzz_test.exs` | modify | replace `source_html` assertion |
| `test/reach/visualize/control_flow/block_quality_test.exs` | modify | R5 empty-block check via line ranges |
| `AGENTS.md`, `CHANGELOG.md` | modify | invariant 6 rewording; changelog entries |
| `scripts/report_bench.exs` | create | reproducible pipeline benchmark |

Pre-existing facts you'll rely on (verified):
- `Reach.Visualize.ControlFlow.build_function/2` is already public (used by `Reach.CLI.BoxartGraph.render_cfg/2`, which reads `start_line`/`end_line` itself and never touches `source_html`).
- Makeup API: `lexer.lex(source)` → tokens; `Makeup.Lexer.split_into_lines(tokens)` → per-line token lists (splits multi-line tokens correctly); `Makeup.Formatters.HTML.HTMLFormatter.format_inner_as_binary(tokens, [])` → inner HTML.
- `assets/js/types.ts` is imported nowhere (`grep -rn "@reach/types" assets/js` is empty) — full replacement is safe.
- Vendor files exist after `cd assets && npm install`: `assets/node_modules/elkjs/lib/elk.bundled.js`, `assets/node_modules/@vue-flow/{core/dist/style.css,core/dist/theme-default.css,minimap/dist/style.css,controls/dist/style.css}`.
- `Reach.Project.t` has `modules: %{module() => %Reach.SystemDependence{nodes: %{id => node}}}` — the source for node→module ownership.

---

### Task 1: MapSet fix for data-flow membership

The quadratic hot spot: `Reach.Visualize.data_flow_data/2` builds `involved_ids` as a flat list and `build_data_flow_nodes/4` evaluates `n.id in involved_ids` for every project node (~50s on jarl).

**Files:**
- Modify: `lib/reach/visualize.ex` (functions `data_flow_data/2` ~line 195 and `build_data_flow_nodes/4` ~line 254)

**Interfaces:**
- Consumes: nothing new.
- Produces: identical `data_flow` output, `involved_ids` is a `MapSet.t()`.

- [ ] **Step 1: Make the change**

In `data_flow_data/2`, replace:

```elixir
    involved_ids =
      data_edges
      |> Enum.flat_map(&[&1.v1, &1.v2])
```

with:

```elixir
    involved_ids =
      data_edges
      |> Enum.flat_map(&[&1.v1, &1.v2])
      |> MapSet.new()
```

`build_data_flow_nodes/4` needs no code change — `n.id in involved_ids` compiles to `Enum.member?/2`, which is O(1) on a MapSet. Just verify the comprehension still reads:

```elixir
    for n <- all_nodes,
        n.id in involved_ids,
```

- [ ] **Step 2: Run the visualize tests**

Run: `mix test test/reach/visualize_test.exs test/reach/program_facts/visualize_fuzz_test.exs`
Expected: PASS (output is order-identical; only membership speed changes)

- [ ] **Step 3: Commit**

```bash
git add lib/reach/visualize.ex
git commit -m "perf: use MapSet for data-flow node membership"
```

---

### Task 2: `Source.highlight_file_lines/1` — highlight each file once

**Files:**
- Modify: `lib/reach/visualize/source.ex`
- Modify: `mix.exs` (`no_warn_undefined`)
- Test: `test/reach/visualize/source_test.exs` (create)

**Interfaces:**
- Consumes: existing private `cached_file_lines/1`, `lang_for_file/1` in the same module.
- Produces: `Reach.Visualize.Source.highlight_file_lines(file :: String.t() | nil) :: [String.t()] | nil` — one inner-HTML string per source line, index 0 = line 1; `nil` when the file has no readable source lines (unreadable path, non-source extension, or `nil`). Falls back to HTML-escaped plain lines when Makeup/lexer is unavailable. Also public `escape_html/1`.

- [ ] **Step 1: Write the failing tests**

Create `test/reach/visualize/source_test.exs`:

```elixir
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/visualize/source_test.exs`
Expected: FAIL with `function Reach.Visualize.Source.highlight_file_lines/1 is undefined`

- [ ] **Step 3: Implement**

Add to `lib/reach/visualize/source.ex` (public section, near `highlight_source/2`):

```elixir
  @doc """
  Highlights an entire source file once, returning one inner-HTML string per
  line (index 0 = line 1, aligned 1:1 with the file's lines).

  Returns `nil` when the file has no readable source lines. Falls back to
  HTML-escaped plain lines when Makeup (or a suitable lexer) is unavailable.
  """
  def highlight_file_lines(file) do
    case cached_file_lines(file) do
      nil -> nil
      lines -> highlight_lines_list(lines, lang_for_file(file))
    end
  end

  @doc false
  def escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp highlight_lines_list(lines, lang) do
    case lexer_for(lang) do
      nil ->
        Enum.map(lines, &escape_html/1)

      lexer ->
        lines
        |> Enum.join("\n")
        |> lexer.lex()
        |> Makeup.Lexer.split_into_lines()
        |> Enum.map(&Makeup.Formatters.HTML.HTMLFormatter.format_inner_as_binary(&1, []))
    end
  end

  defp lexer_for(:javascript) do
    if Code.ensure_loaded?(Makeup.Lexers.JsLexer), do: Makeup.Lexers.JsLexer
  end

  defp lexer_for(_lang) do
    if Code.ensure_loaded?(Makeup.Lexers.ElixirLexer), do: Makeup.Lexers.ElixirLexer
  end
```

Note: `cached_file_lines/1` handles `nil`/non-source/unreadable paths already (returns `nil`), and for JavaScript functions the injected process-dict cache (`inject_js_source_cache`) feeds the same `cached_file_lines/1`, so embedded JS sources highlight transparently — as long as `highlight_file_lines/1` is called in the same process that built the functions (Task 6 guarantees this).

`lang_for_file/1` expects a binary; guard the `nil` case — `cached_file_lines(nil)` already returns `nil` before `lang_for_file` is reached, so no change needed there.

In `mix.exs`, extend `no_warn_undefined`:

```elixir
        no_warn_undefined: [
          {Makeup, :highlight_inner_html, 2},
          {Makeup, :stylesheet, 0},
          {Makeup.Lexer, :split_into_lines, 1},
          {Makeup.Formatters.HTML.HTMLFormatter, :format_inner_as_binary, 2},
          {Makeup.Lexers.ElixirLexer, :lex, 1},
          {Makeup.Lexers.JsLexer, :lex, 1}
        ]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/visualize/source_test.exs`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/reach/visualize/source.ex mix.exs test/reach/visualize/source_test.exs
git commit -m "feat: highlight whole source files once into per-line HTML"
```

---

### Task 3: Control-flow blocks carry line ranges, not rendered HTML

Blocks stop embedding `source_html`; they carry `{start_line, end_line}` plus an optional `source_text` plain-text fallback (fallback single blocks, exit "end" when the file line is blank/unavailable). Display rule (client-side and for blank checks): `entry`/`exit`/`branch` nodes show only `start_line`; other types show `start_line..end_line`.

**Files:**
- Modify: `lib/reach/visualize/control_flow.ex`
- Modify: `lib/reach/visualize.ex` (`build_data_flow_nodes/4` drops `source_html: nil`)
- Modify: `test/reach/visualize_test.exs`, `test/reach/program_facts/visualize_fuzz_test.exs`, `test/reach/visualize/control_flow/block_quality_test.exs`
- Modify: `AGENTS.md` (invariant 6 + module description + test path)

**Interfaces:**
- Consumes: `Source.read_line/2`, `Source.cached_file_lines/1` (both already public).
- Produces: viz node maps shaped `%{id, type, label, start_line, end_line, source_text, parent_id}` (`source_text: nil | String.t()`). `make_node/6` becomes `make_node(id, type, label, start_line, end_line, opts \\ [])` with `opts[:source_text]`.

- [ ] **Step 1: Write the failing test**

Add to `test/reach/visualize_test.exs` inside `describe "to_graph_json/2"`:

```elixir
    test "control flow blocks reference line ranges instead of embedded HTML" do
      graph =
        Reach.string_to_graph!("""
        defmodule Ranges do
          def f(x) do
            y = x + 1
            y * 2
          end
        end
        """)

      %{control_flow: [mod | _]} = Reach.Visualize.to_graph_json(graph)
      [func | _] = mod.functions

      assert func.nodes != []

      for node <- func.nodes do
        assert is_integer(node.start_line)
        assert is_integer(node.end_line)
        assert node.end_line >= node.start_line
        refute Map.has_key?(node, :source_html)
      end
    end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/reach/visualize_test.exs`
Expected: FAIL — nodes still have `source_html` and no `source_text` key.

- [ ] **Step 3: Rework `control_flow.ex`**

All changes in `lib/reach/visualize/control_flow.ex`:

3a. New constructor (replaces the old 6-arg `make_node`):

```elixir
  defp make_node(id, type, label, start_line, end_line, opts \\ []) do
    %{
      id: id,
      type: type,
      label: label,
      start_line: start_line,
      end_line: end_line,
      source_text: opts[:source_text],
      parent_id: nil
    }
  end
```

3b. Entry nodes (two call sites: `build_multi_clause_blocks/8` and `build_from_cfg/4`) — drop the `highlight_line` argument:

```elixir
    entry =
      make_node(
        func_id,
        :entry,
        "#{name}/#{arity}",
        func_start,
        func_start
      )
```

(in `build_from_cfg/4` the label is `"#{func.meta[:name]}/#{func.meta[:arity]}"` as today.)

3c. Exit node — replace `build_exit_node/5`, `exit_source_html/2`, and `fallback_html/2` with:

```elixir
  defp build_exit_node(cfg, block_for_vertex, file, func_id, exit_line) do
    exit_id = "#{func_id}_exit"
    source_text = if blank_line?(file, exit_line), do: "end"

    exit_node = make_node(exit_id, :exit, "end", exit_line, exit_line, source_text: source_text)
    exit_edges = build_exit_edges(find_exit_predecessors(cfg, block_for_vertex), exit_id)

    {exit_node, exit_edges}
  end

  defp blank_line?(file, line) do
    case Source.read_line(file, line) do
      nil -> true
      text -> String.trim(text) == ""
    end
  end
```

3d. Block nodes — in `blocks_to_viz_nodes/6`, remove the `source` computation and the `source_blank?`-based filter:

```elixir
      node = Map.get(node_map, first_v)
      type = block_type(block, branch_vertices, node_map)
      label = block_label(type, node, block, node_map, cfg)
      block_id = "b_" <> Enum.map_join(block, "_", &to_string/1)

      make_node(block_id, type, label, start_l, end_l)
    end)
    |> Enum.reject(&(&1.type not in [:entry, :exit] and blank_block_range?(file, &1)))
```

with the new blank check (mirrors the old rendered-HTML blankness: `branch` looked at one line, others at the range; unreadable file meant blank):

```elixir
  defp blank_block_range?(file, %{type: :branch, start_line: start_l}),
    do: blank_line?(file, start_l)

  defp blank_block_range?(file, %{start_line: start_l, end_line: end_l}) do
    case Source.cached_file_lines(file) do
      nil ->
        true

      lines ->
        lines
        |> Enum.slice((start_l - 1)..max(start_l - 1, end_l - 1))
        |> Enum.all?(&(String.trim(&1) == ""))
    end
  end
```

Delete the now-unused `source_blank?/1`.

3e. Fallback single block — replace `fallback_single_block/3`:

```elixir
  defp fallback_single_block(func, source, start_line) do
    node =
      make_node(
        to_string(func.id),
        :entry,
        "#{func.meta[:name]}/#{func.meta[:arity]}",
        start_line,
        start_line,
        source_text: source
      )

    {[node], []}
  end
```

3f. Clean up imports: `import Reach.Visualize.Source` stays (still used for `span_field`, `min_line_in_subtree`, `func_end_line`, `extract_func_source`, `ensure_def_cache`), but the module no longer calls `highlight_line/2`, `highlight_lines/3`, or `Source.highlight_source/2` — remove any leftover references. Keep those functions in `Source` (they remain public API).

3g. In `lib/reach/visualize.ex`, `build_data_flow_nodes/4`: delete the `source_html: nil` key from the emitted map (keep `id`, `label`, `module`, `start_line`).

- [ ] **Step 4: Adapt the fuzz test**

In `test/reach/program_facts/visualize_fuzz_test.exs`, replace the body of `assert_visual_node!/1`'s non-entry/exit branch:

```elixir
  defp assert_visual_node!(node) do
    assert is_binary(node["label"])
    assert node["label"] != ""

    if node["type"] not in ["entry", "exit"] do
      if node["source_text"] do
        assert node["source_text"] != ""
      else
        assert is_integer(node["start_line"])
        assert is_integer(node["end_line"])
        assert node["end_line"] >= node["start_line"]
      end
    end
  end
```

- [ ] **Step 5: Adapt the block quality test (R5)**

In `test/reach/visualize/control_flow/block_quality_test.exs`:

Change the pipeline call from `|> check_source_html(name, nodes)` to `|> check_block_content(name, nodes, source_lines)` and replace the `check_source_html/3` implementation:

```elixir
  # R5: No empty blocks — every non-entry/exit block resolves to non-blank
  # source lines (or carries a source_text fallback)
  defp check_block_content(violations, name, nodes, source_lines) do
    empty =
      Enum.filter(nodes, fn n ->
        n["type"] not in ["entry", "exit"] and blank_block?(n, source_lines)
      end)

    for b <- empty do
      {:empty_block, name, "#{b["id"]} [#{b["type"]}] label=#{inspect(b["label"])}"}
    end ++ violations
  end

  defp blank_block?(n, source_lines) do
    cond do
      is_binary(n["source_text"]) and String.trim(n["source_text"]) != "" ->
        false

      source_lines == nil ->
        n["source_text"] in [nil, ""]

      true ->
        start_l = n["start_line"]
        end_l = if n["type"] == "branch", do: start_l, else: n["end_line"]

        start_l == nil or end_l == nil or
          source_lines
          |> Enum.slice((start_l - 1)..max(start_l - 1, end_l - 1))
          |> Enum.all?(&(String.trim(&1) == ""))
    end
  end
```

(the test computes `source_lines` in `audit_function/4` already — pass it through.)

- [ ] **Step 6: Run the affected suites**

Run: `mix test test/reach/visualize_test.exs test/reach/program_facts/visualize_fuzz_test.exs test/reach/visualize/control_flow/block_quality_test.exs test/reach/cli`
Expected: PASS. (The block-quality test only audits repos present under `/tmp` — it passes trivially if they're absent; clone per AGENTS.md if you want the full audit.)

- [ ] **Step 7: Update AGENTS.md**

- Invariant 6 under "Block Content": replace

  > 6. No empty blocks — every block has `source_html`. Clauses with no compiler source spans show the pattern label as fallback.

  with

  > 6. No empty blocks — every block's line range (`start_line..end_line`; `branch`/`entry`/`exit` display `start_line` only) resolves to non-blank source, or the block carries a `source_text` fallback. Clauses with no compiler source spans show the pattern label as fallback.

- Key modules list: change `Reach.Visualize.Source — source extraction, highlighting, line helpers` to `Reach.Visualize.Source — source extraction, once-per-file highlighting, line helpers`.
- "Testing Changes" section: fix the stale path `test/reach/visualize/block_quality_test.exs` → `test/reach/visualize/control_flow/block_quality_test.exs`.

- [ ] **Step 8: Run the full test suite and commit**

Run: `mix test`
Expected: PASS

```bash
git add lib/reach/visualize/control_flow.ex lib/reach/visualize.ex test/reach/visualize_test.exs test/reach/program_facts/visualize_fuzz_test.exs test/reach/visualize/control_flow/block_quality_test.exs AGENTS.md
git commit -m "feat: emit control-flow blocks as line ranges without rendered HTML"
```

---

### Task 4: Parallelize the viz build; extract per-module builders

**Files:**
- Modify: `lib/reach/visualize/control_flow.ex` (`build/2` and new `build_module/1`, `build_top_level/2`)

**Interfaces:**
- Consumes: existing `build_function/2`, `find_top_level_functions/2`.
- Produces:
  - `build_module(mod_def_node) :: %{module: String.t(), file: String.t() | nil, functions: [map()]}` (public)
  - `build_top_level(all_nodes, modules) :: map() | nil` (public; same shape with `module: nil`)
  - `build/2` output unchanged in shape and order.

- [ ] **Step 1: Refactor `build/2`**

Replace the existing `build/2` in `lib/reach/visualize/control_flow.ex`:

```elixir
  def build(all_nodes, _graph) do
    modules =
      all_nodes
      |> Enum.filter(&(&1.type == :module_def))
      |> Task.async_stream(&build_module/1,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, module_map} -> module_map end)

    case build_top_level(all_nodes, modules) do
      nil -> modules
      top -> [top | modules]
    end
  end

  @doc "Builds the visualization map for a single module definition node."
  def build_module(mod) do
    file = span_field(mod, :file)

    func_nodes =
      IR.all_nodes(mod)
      |> Enum.filter(&(&1.type == :function_def))
      |> Enum.sort_by(&(span_field(&1, :start_line) || 0))

    %{
      module: inspect(mod.meta[:name]),
      file: file,
      functions: Enum.map(func_nodes, &build_function(&1, file))
    }
  end

  @doc "Builds the top-level (module-less) function group, or nil if none exist."
  def build_top_level(all_nodes, modules) do
    case find_top_level_functions(all_nodes, modules) do
      [] ->
        nil

      top_funcs ->
        file = Enum.find_value(top_funcs, &span_field(&1, :file))

        %{
          module: nil,
          file: file,
          functions: Enum.map(top_funcs, &build_function(&1, file))
        }
    end
  end
```

`Task.async_stream` defaults to `ordered: true`, so module order is preserved. Each worker process gets its own process-dictionary source caches — correct by construction (JS `meta[:source]` injection happens inside `build_function/2` within the worker).

- [ ] **Step 2: Run the visualization suites**

Run: `mix test test/reach/visualize_test.exs test/reach/program_facts/visualize_fuzz_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add lib/reach/visualize/control_flow.ex
git commit -m "perf: parallelize per-module visualization build"
```

---

### Task 5: Expose call-graph and data-flow builders for reuse

**Files:**
- Modify: `lib/reach/visualize.ex`
- Test: `test/reach/visualize_test.exs` (add one test)

**Interfaces:**
- Consumes: existing private helpers.
- Produces (all on `Reach.Visualize`):
  - `call_graph(graph) :: %{view: %{modules: [map()], edges: [map()]}, raw_edges: [{{module(), atom(), non_neg_integer()}, {module(), atom(), non_neg_integer()}}], internal_modules: MapSet.t(module())}`
  - `data_flow(graph, opts \\ []) :: %{functions: [map()], edges: [map()], taint_paths: [map()]}` (the former `data_flow_data/2`, made public)
  - `safe_module_name/1` and `call_id/3` public (`@doc false`).

- [ ] **Step 1: Write the failing test**

Add to `test/reach/visualize_test.exs`:

```elixir
  describe "call_graph/1" do
    test "returns view plus raw MFA edges and internal module set" do
      graph =
        Reach.string_to_graph!("""
        defmodule RawCg do
          def caller, do: RawCg.callee()
          def callee, do: Enum.count([1])
        end
        """)

      %{view: view, raw_edges: raw_edges, internal_modules: internal} =
        Reach.Visualize.call_graph(graph)

      assert is_list(view.modules)
      assert is_list(view.edges)
      assert MapSet.member?(internal, RawCg)
      assert Enum.any?(raw_edges, fn {_src, {tm, tf, ta}} -> {tm, tf, ta} == {Enum, :count, 1} end)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/reach/visualize_test.exs`
Expected: FAIL with `function Reach.Visualize.call_graph/1 is undefined or private`

- [ ] **Step 3: Refactor `visualize.ex`**

- Rename `call_graph_data/1` to `call_graph/1`, make it public, and extend its return. The body keeps everything up to and including `clean_edges`/`internal_funcs`, then:

```elixir
    internal_modules = MapSet.new(internal_funcs, fn {mod, _f, _a} -> mod end)

    modules = ...            # existing modules construction, unchanged
    edges = ...              # existing edges construction, unchanged

    %{
      view: %{modules: modules, edges: edges},
      raw_edges: clean_edges,
      internal_modules: internal_modules
    }
```

- Rename `data_flow_data/2` to `data_flow/2`, make it public with `opts \\ []` default, body unchanged (including Task 1's MapSet).
- Make `safe_module_name/1` and `call_id/3` public with `@doc false` (they are pure formatters needed by `Chunks`).
- Update `to_graph_json/2`:

```elixir
  def to_graph_json(graph, opts \\ []) do
    %Reach.Visualize.Graph.JSON{
      control_flow: ControlFlow.build(Reach.nodes(graph), graph),
      call_graph: call_graph(graph).view,
      data_flow: data_flow(graph, opts)
    }
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/visualize_test.exs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/reach/visualize.ex test/reach/visualize_test.exs
git commit -m "refactor: expose call_graph/1 and data_flow/2 with raw edge data"
```

---

### Task 6: `Reach.Visualize.Chunks` — manifest + per-module chunks

**Files:**
- Create: `lib/reach/visualize/chunks.ex`
- Test: `test/reach/visualize/chunks_test.exs` (create)

**Interfaces:**
- Consumes: `ControlFlow.build_module/1`, `ControlFlow.build_top_level/2`, `Source.highlight_file_lines/1`, `Visualize.call_graph/1`, `Visualize.data_flow/2`, `Visualize.safe_module_name/1`, `Visualize.call_id/3`.
- Produces: `Chunks.build(project, opts) :: %{manifest: map(), chunks: [{chunk_id :: String.t(), chunk :: map()}]}`. Options: `:project` (name string), `:generated_at` (ISO8601 string, defaults to now), plus pass-through viz opts (`:taint`).
  - manifest: `%{project, generated_at, modules: [%{id, name, file, chunk, functions: [%{id, name, arity}]}], call_graph: %{edges: [%{source, target, count}]}, counts: %{modules, functions}}`
  - chunk: `%{module, source: %{file, lines_html}, functions: [ControlFlow function maps], calls: %{functions: [%{id, name, module, external}], edges: [%{id, source, target, color}]}, data_flow: %{functions, edges}}`

- [ ] **Step 1: Write the failing tests**

Create `test/reach/visualize/chunks_test.exs`:

```elixir
defmodule Reach.Visualize.ChunksTest do
  use ExUnit.Case, async: false

  alias Reach.Visualize.Chunks

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "reach_chunks_test_#{:erlang.unique_integer([:positive])}"
           )

  setup_all do
    File.mkdir_p!(Path.join(@tmp_dir, "lib"))

    a =
      write_file("lib/chunk_a.ex", """
      defmodule ChunkA do
        def run(x) do
          y = ChunkB.transform(x)
          y + 1
        end
      end
      """)

    b =
      write_file("lib/chunk_b.ex", """
      defmodule ChunkB do
        def transform(v) do
          w = v * 2
          Enum.max([w, 0])
        end
      end
      """)

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)

    project = Reach.Project.from_sources([a, b])
    {:ok, output: Chunks.build(project, project: "fixture")}
  end

  defp write_file(rel, content) do
    path = Path.join(@tmp_dir, rel)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
    path
  end

  defp chunk(output, id) do
    {^id, data} = Enum.find(output.chunks, fn {chunk_id, _} -> chunk_id == id end)
    data
  end

  test "manifest lists modules with functions and chunk paths", %{output: output} do
    manifest = output.manifest

    assert manifest.project == "fixture"
    assert is_binary(manifest.generated_at)

    ids = Enum.map(manifest.modules, & &1.id)
    assert "ChunkA" in ids
    assert "ChunkB" in ids

    mod_a = Enum.find(manifest.modules, &(&1.id == "ChunkA"))
    assert mod_a.chunk == "chunks/ChunkA.js"
    assert [%{name: "run", arity: 1}] = mod_a.functions

    assert manifest.counts.modules == 2
    assert manifest.counts.functions == 2
  end

  test "manifest call graph has module-level internal edges with counts", %{output: output} do
    edges = output.manifest.call_graph.edges

    assert %{source: "ChunkA", target: "ChunkB", count: 1} in edges
    refute Enum.any?(edges, &(&1.target == "Enum"))
    refute Enum.any?(edges, &(&1.source == &1.target))
  end

  test "each chunk carries highlighted source aligned with the file", %{output: output} do
    chunk_a = chunk(output, "ChunkA")

    raw = @tmp_dir |> Path.join("lib/chunk_a.ex") |> File.read!() |> String.split("\n")
    assert length(chunk_a.source.lines_html) == length(raw)
    assert chunk_a.source.file =~ "chunk_a.ex"
  end

  test "chunk functions carry line-range CFG nodes", %{output: output} do
    chunk_a = chunk(output, "ChunkA")

    [func] = chunk_a.functions
    assert func.name == "run"
    assert func.nodes != []
    assert Enum.all?(func.nodes, &(is_integer(&1.start_line) and is_integer(&1.end_line)))
    refute Enum.any?(func.nodes, &Map.has_key?(&1, :source_html))
  end

  test "chunk calls include internal and external functions and edges", %{output: output} do
    chunk_b = chunk(output, "ChunkB")

    assert Enum.any?(
             chunk_b.calls.edges,
             &(&1.source == "ChunkA.run/1" and &1.target == "ChunkB.transform/1")
           )

    assert Enum.any?(chunk_b.calls.functions, &(&1.id == "Enum.max/1" and &1.external))
    assert Enum.any?(chunk_b.calls.functions, &(&1.id == "ChunkB.transform/1" and not &1.external))
  end

  test "data flow is partitioned across chunks by owning module", %{output: output} do
    all_edges = Enum.flat_map(output.chunks, fn {_, c} -> c.data_flow.edges end)
    assert all_edges != []

    for {_, c} <- output.chunks do
      fn_ids = MapSet.new(c.data_flow.functions, & &1.id)

      for edge <- c.data_flow.edges do
        assert MapSet.member?(fn_ids, edge.source)
        assert MapSet.member?(fn_ids, edge.target)
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/reach/visualize/chunks_test.exs`
Expected: FAIL with `module Reach.Visualize.Chunks is not available`

- [ ] **Step 3: Implement**

Create `lib/reach/visualize/chunks.ex`:

```elixir
defmodule Reach.Visualize.Chunks do
  @moduledoc """
  Builds the chunked HTML report payload: a manifest with the module tree and
  a module-level call graph, plus one lazily-loaded data chunk per module.

  One chunk per module is the deliberate unit of future incremental caching
  and of a future `Reach.Plug` serving the report directory.
  """

  alias Reach.Visualize
  alias Reach.Visualize.{ControlFlow, Source}

  @top_level_id "_top_level"

  @type output :: %{manifest: map(), chunks: [{String.t(), map()}]}

  @spec build(Reach.Project.t(), keyword()) :: output()
  def build(%Reach.Project{} = project, opts \\ []) do
    all_nodes = Reach.nodes(project)

    module_entries = build_module_entries(all_nodes)
    %{raw_edges: raw_edges, internal_modules: internal} = Visualize.call_graph(project)
    data_flow = Visualize.data_flow(project, opts)

    node_owner = node_owner_map(project)
    df_by_chunk = partition_data_flow(data_flow, node_owner)

    chunks =
      Enum.map(module_entries, fn {mod_atom, module_map, lines_html} ->
        id = chunk_id(mod_atom)

        {id,
         %{
           module: id,
           source: %{file: module_map.file, lines_html: lines_html},
           functions: module_map.functions,
           calls: calls_for(raw_edges, mod_atom, internal),
           data_flow: Map.get(df_by_chunk, id, %{functions: [], edges: []})
         }}
      end)

    manifest = %{
      project: to_string(Keyword.get(opts, :project, "project")),
      generated_at:
        Keyword.get_lazy(opts, :generated_at, fn ->
          DateTime.utc_now() |> DateTime.to_iso8601()
        end),
      modules: manifest_modules(module_entries),
      call_graph: %{edges: module_level_edges(raw_edges, internal)},
      counts: %{
        modules: length(module_entries),
        functions:
          module_entries |> Enum.map(fn {_, map, _} -> length(map.functions) end) |> Enum.sum()
      }
    }

    %{manifest: manifest, chunks: chunks}
  end

  # --- Module entries (parallel CFG build + once-per-file highlighting) ---

  defp build_module_entries(all_nodes) do
    entries =
      all_nodes
      |> Enum.filter(&(&1.type == :module_def))
      |> Task.async_stream(
        fn mod ->
          module_map = ControlFlow.build_module(mod)
          # Highlight in the same process: build_function/2 may have injected
          # embedded (JS) sources into this process's file-line cache.
          {mod.meta[:name], module_map, Source.highlight_file_lines(module_map.file)}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, entry} -> entry end)

    module_maps = Enum.map(entries, fn {_mod, map, _lines} -> map end)

    case ControlFlow.build_top_level(all_nodes, module_maps) do
      nil -> entries
      top -> entries ++ [{nil, top, Source.highlight_file_lines(top.file)}]
    end
  end

  defp manifest_modules(entries) do
    Enum.map(entries, fn {mod_atom, module_map, _lines} ->
      id = chunk_id(mod_atom)

      %{
        id: id,
        name: module_map.module || "(top-level)",
        file: module_map.file,
        chunk: "chunks/#{id}.js",
        functions:
          Enum.map(module_map.functions, &%{id: &1.id, name: &1.name, arity: &1.arity})
      }
    end)
  end

  defp chunk_id(nil), do: @top_level_id

  defp chunk_id(mod_atom) do
    mod_atom
    |> Visualize.safe_module_name()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end

  # --- Call graph slices ---

  defp module_level_edges(raw_edges, internal) do
    raw_edges
    |> Enum.filter(fn {{sm, _, _}, {tm, _, _}} ->
      sm != tm and sm in internal and tm in internal
    end)
    |> Enum.frequencies_by(fn {{sm, _, _}, {tm, _, _}} -> {sm, tm} end)
    |> Enum.map(fn {{sm, tm}, count} ->
      %{
        source: Visualize.safe_module_name(sm),
        target: Visualize.safe_module_name(tm),
        count: count
      }
    end)
  end

  defp calls_for(raw_edges, mod_atom, internal) do
    edges =
      Enum.filter(raw_edges, fn {{sm, _, _}, {tm, _, _}} ->
        sm == mod_atom or tm == mod_atom
      end)

    functions =
      edges
      |> Enum.flat_map(fn {src, tgt} -> [src, tgt] end)
      |> Enum.uniq()
      |> Enum.map(fn {m, f, a} ->
        %{
          id: Visualize.call_id(m, f, a),
          name: "#{f}/#{a}",
          module: Visualize.safe_module_name(m),
          external: m not in internal
        }
      end)

    edge_maps =
      edges
      |> Enum.map(fn {{sm, sf, sa}, {tm, tf, ta}} ->
        source = Visualize.call_id(sm, sf, sa)
        target = Visualize.call_id(tm, tf, ta)

        %{
          id: "call_#{source}_#{target}",
          source: source,
          target: target,
          color: call_edge_color(sm, tm, mod_atom)
        }
      end)
      |> Enum.uniq_by(& &1.id)

    %{functions: functions, edges: edge_maps}
  end

  defp call_edge_color(sm, tm, mod_atom) do
    cond do
      sm == :"<javascript>" or tm == :"<javascript>" -> "#f97316"
      tm == mod_atom -> "#7c3aed"
      true -> "#94a3b8"
    end
  end

  # --- Data flow partitioning ---

  defp node_owner_map(%Reach.Project{modules: modules}) do
    for {mod, sdg} <- modules, {id, _node} <- sdg.nodes, into: %{}, do: {id, mod}
  end

  defp partition_data_flow(%{functions: functions, edges: edges}, node_owner) do
    fn_by_id = Map.new(functions, &{&1.id, &1})
    owner = fn id -> id |> owner_module(node_owner) |> chunk_id() end

    base =
      Enum.reduce(functions, %{}, fn f, acc ->
        Map.update(acc, owner.(f.id), %{functions: [f], edges: []}, fn cur ->
          %{cur | functions: [f | cur.functions]}
        end)
      end)

    edges
    |> Enum.group_by(&owner.(&1.source))
    |> Enum.reduce(base, fn {cid, chunk_edges}, acc ->
      endpoint_fns =
        chunk_edges
        |> Enum.flat_map(&[&1.source, &1.target])
        |> Enum.uniq()
        |> Enum.map(&Map.get(fn_by_id, &1))
        |> Enum.reject(&is_nil/1)

      Map.update(acc, cid, %{functions: endpoint_fns, edges: chunk_edges}, fn cur ->
        %{
          functions: Enum.uniq_by(cur.functions ++ endpoint_fns, & &1.id),
          edges: chunk_edges
        }
      end)
    end)
    |> Map.new(fn {cid, %{functions: fns, edges: es}} ->
      {cid,
       %{
         functions: fns |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.start_line),
         edges: es
       }}
    end)
  end

  defp owner_module(id_string, node_owner) do
    case Integer.parse(id_string) do
      {int, ""} -> Map.get(node_owner, int)
      _ -> nil
    end
  end
end
```

Note the data-flow edges are filtered at the source (`Visualize.data_flow/2` already restricts edges to nodes present in its `functions` list), so every edge endpoint has a function entry; the partitioner pulls both endpoint entries into the owning chunk, satisfying the containment test.

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/reach/visualize/chunks_test.exs`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/reach/visualize/chunks.ex test/reach/visualize/chunks_test.exs
git commit -m "feat: build chunked report payload (manifest + per-module chunks)"
```

---

### Task 7: Directory writer, template, and command orchestration

**Files:**
- Modify: `lib/reach/cli/render/report.ex`
- Modify: `lib/reach/cli/commands/report.ex`
- Modify: `priv/template.html.eex`
- Modify: `CHANGELOG.md`
- Test: `test/reach/cli/render/report_test.exs` (create)

**Interfaces:**
- Consumes: `Chunks.build/2` output.
- Produces:
  - `Reach.CLI.Render.Report.render_html(%{manifest: map, chunks: list}, output_dir, opts)` — writes `index.html`, `manifest.js`, `chunks/*.js`.
  - `render_json(graph_data, output_dir)` and `render_dot(graph, output_dir)` — unchanged behavior, now public entry points (the old `render/5` head dispatch is removed).

- [ ] **Step 1: Write the failing integration test**

Create `test/reach/cli/render/report_test.exs`:

```elixir
defmodule Reach.CLI.Render.ReportTest do
  use ExUnit.Case, async: false

  alias Reach.CLI.Render.Report
  alias Reach.Visualize.Chunks

  @tmp_dir Path.join(
             System.tmp_dir!(),
             "reach_report_render_test_#{:erlang.unique_integer([:positive])}"
           )

  setup do
    File.mkdir_p!(Path.join(@tmp_dir, "lib"))
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    :ok
  end

  test "render_html writes index, manifest, and per-module chunks" do
    path = Path.join(@tmp_dir, "lib/render_fixture.ex")

    File.write!(path, """
    defmodule RenderFixture do
      def go(x), do: x + 1
    end
    """)

    project = Reach.Project.from_sources([path])
    chunked = Chunks.build(project, project: "fixture")
    out = Path.join(@tmp_dir, "report")

    Report.render_html(chunked, out, open: false)

    index = File.read!(Path.join(out, "index.html"))
    assert index =~ ~s(<script src="manifest.js"></script>)
    assert index =~ "Reach — fixture"
    refute index =~ "window.graphData"

    manifest_js = File.read!(Path.join(out, "manifest.js"))
    assert String.starts_with?(manifest_js, "window.__reachManifest = ")

    manifest =
      manifest_js
      |> String.trim_leading("window.__reachManifest = ")
      |> String.trim_trailing(";\n")
      |> JSON.decode!()

    assert Enum.any?(manifest["modules"], &(&1["id"] == "RenderFixture"))

    chunk_js = File.read!(Path.join([out, "chunks", "RenderFixture.js"]))

    assert [_, id_json, payload_json] =
             Regex.run(~r/^window\.__reachChunk\((".*?"), (.*)\);\n$/s, chunk_js)

    assert JSON.decode!(id_json) == "RenderFixture"
    assert %{"functions" => [_ | _], "source" => %{"lines_html" => [_ | _]}} = JSON.decode!(payload_json)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/reach/cli/render/report_test.exs`
Expected: FAIL with `function Reach.CLI.Render.Report.render_html/3 is undefined`

- [ ] **Step 3: Rewrite the template**

Replace the `<title>` line and the body scripts in `priv/template.html.eex`. Title:

```html
<title>Reach — <%= project %></title>
```

Body (replace the three `<script>` lines):

```html
<body>
<div id="app"></div>
<script src="manifest.js"></script>
<script><%= elk_bundle %></script>
<script><%= js_bundle %></script>
</body>
```

Add to the `<style>` block (after the `.reach-flow` rule):

```css
.reach-flow-wrap { flex: 1; position: relative; }
.reach-flow { width: 100%; height: 100%; }
.hint-overlay { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: #64748b; font-size: 14px; pointer-events: none; }
.sidebar-search { padding: 8px 12px; border-bottom: 1px solid #f1f5f9; }
.sidebar-search input { width: 100%; box-sizing: border-box; padding: 4px 8px; border: 1px solid #e2e8f0; border-radius: 4px; font-size: 12px; }
.sidebar-module-name { display: block; width: 100%; text-align: left; border: none; cursor: pointer; }
.breadcrumb { margin-left: auto; color: #94a3b8; font-size: 12px; display: flex; gap: 8px; align-items: center; }
.breadcrumb button { background: none; border: none; color: #60a5fa; cursor: pointer; font-size: 12px; }
```

(the existing `.sidebar-module-name` div styles remain and now apply to a `<button>`.)

- [ ] **Step 4: Rewrite `Render.Report`**

Replace `render/5` heads and `render_html/3` in `lib/reach/cli/render/report.ex` (keep the module attributes, `@external_resource` block, and `open_browser/1` exactly as they are):

```elixir
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
```

(the old `render_html(graph_data, output_dir, opts)` with `graph_json:`/`file:`/`module:` assigns is deleted; the template no longer has those assigns.)

- [ ] **Step 5: Update `Commands.Report`**

Replace `run/2` and `build_viz_opts/1` in `lib/reach/cli/commands/report.ex`:

```elixir
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
```

(`build_graph/1` and `build_viz_opts/1` stay as they are.)

- [ ] **Step 6: Run tests**

Run: `mix test test/reach/cli/render/report_test.exs test/reach/cli`
Expected: PASS

- [ ] **Step 7: Update CHANGELOG**

Under `## Unreleased` in `CHANGELOG.md` add:

```markdown
### Changed

- **Report performance** — fixed a quadratic data-flow membership check, moved syntax highlighting to a single pass per source file, and parallelized the per-module visualization build. On a ~1,300-file project the visualization build drops from ~94s to seconds.
- **Chunked HTML report** — `mix reach` now writes a report directory (`index.html`, `manifest.js`, and one lazily-loaded `chunks/<Module>.js` per module) instead of a single self-contained HTML file. The browser renders the selected module/function instead of the entire project, so reports open instantly on large codebases. `--format json` and `--format dot` still produce single files; control-flow block nodes in JSON now carry `start_line`/`end_line`/`source_text` instead of pre-rendered `source_html`.
```

- [ ] **Step 8: Full suite and commit**

Run: `mix test`
Expected: PASS

```bash
git add lib/reach/cli/render/report.ex lib/reach/cli/commands/report.ex priv/template.html.eex test/reach/cli/render/report_test.exs CHANGELOG.md
git commit -m "feat: write chunked report directory (manifest + per-module chunks)"
```

---

### Task 8: Frontend foundation — types, chunk loader, source utils, boot

**Files:**
- Replace: `assets/js/types.ts`
- Create: `assets/js/chunks.ts`
- Create: `assets/js/source.ts`
- Modify: `assets/js/app.ts`

**Interfaces:**
- Consumes: `window.__reachManifest` (set by `manifest.js`), `window.__reachChunk` callback convention from Task 7.
- Produces:
  - `loadChunk(id: string, chunkPath: string): Promise<Chunk>`
  - `sliceLines(linesHtml, startLine, endLine): string[]`, `dedentHtmlLines(lines): string[]`, `lineText(html): string`, `escapeHtml(text): string`
  - TS interfaces `Manifest`, `ManifestModule`, `Chunk`, `ChunkFunction`, `CfNode`, `CfEdge`, `CallFunction`, `CallEdge`, `DataFlowFunction`, `DataFlowEdge`, `ModuleEdge`.

- [ ] **Step 1: Replace `assets/js/types.ts`** (current content is imported nowhere)

```ts
export interface ManifestFunction {
  id: string
  name: string
  arity: number
}

export interface ManifestModule {
  id: string
  name: string
  file: string | null
  chunk: string
  functions: ManifestFunction[]
}

export interface ModuleEdge {
  source: string
  target: string
  count: number
}

export interface Manifest {
  project: string
  generated_at: string
  modules: ManifestModule[]
  call_graph: { edges: ModuleEdge[] }
  counts: { modules: number; functions: number }
}

export interface CfNode {
  id: string
  type: string
  label: string | null
  start_line: number
  end_line: number
  source_text: string | null
  parent_id: string | null
}

export interface CfEdge {
  id: string
  source: string
  target: string
  label: string
  edge_type: string
  color: string
}

export interface ChunkFunction {
  id: string
  name: string
  arity: number
  nodes: CfNode[]
  edges: CfEdge[]
}

export interface CallFunction {
  id: string
  name: string
  module: string
  external: boolean
}

export interface CallEdge {
  id: string
  source: string
  target: string
  color: string
}

export interface DataFlowFunction {
  id: string
  label: string
  start_line: number | null
}

export interface DataFlowEdge {
  id: string
  source: string
  target: string
  label: string
  color: string
}

export interface Chunk {
  module: string
  source: { file: string | null; lines_html: string[] | null }
  functions: ChunkFunction[]
  calls: { functions: CallFunction[]; edges: CallEdge[] }
  data_flow: { functions: DataFlowFunction[]; edges: DataFlowEdge[] }
}
```

- [ ] **Step 2: Create `assets/js/chunks.ts`**

```ts
import type { Chunk } from "@reach/types"

const cache = new Map<string, Promise<Chunk>>()
const resolvers = new Map<string, (chunk: Chunk) => void>()

declare global {
  interface Window {
    __reachChunk: (id: string, data: Chunk) => void
  }
}

window.__reachChunk = (id: string, data: Chunk) => {
  resolvers.get(id)?.(data)
  resolvers.delete(id)
}

export function loadChunk(id: string, chunkPath: string): Promise<Chunk> {
  const cached = cache.get(id)
  if (cached) return cached

  const promise = new Promise<Chunk>((resolve, reject) => {
    resolvers.set(id, resolve)
    const script = document.createElement("script")
    script.src = chunkPath
    script.onerror = () => {
      resolvers.delete(id)
      cache.delete(id)
      reject(new Error(`failed to load chunk: ${chunkPath}`))
    }
    document.head.appendChild(script)
  })

  cache.set(id, promise)
  return promise
}
```

- [ ] **Step 3: Create `assets/js/source.ts`**

```ts
export function sliceLines(linesHtml: string[], startLine: number, endLine: number): string[] {
  const start = Math.max(startLine - 1, 0)
  const end = Math.max(endLine, start + 1)
  return linesHtml.slice(start, end)
}

export function lineText(html: string): string {
  const el = document.createElement("div")
  el.innerHTML = html
  return el.textContent ?? ""
}

export function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

export function dedentHtmlLines(lines: string[]): string[] {
  const texts = lines.map(lineText)
  const indents = texts
    .filter((t) => t.trim() !== "")
    .map((t) => t.length - t.trimStart().length)
  const min = indents.length ? Math.min(...indents) : 0
  if (min === 0) return lines
  return lines.map((line) => stripLeadingChars(line, min))
}

function stripLeadingChars(html: string, count: number): string {
  const el = document.createElement("div")
  el.innerHTML = html
  let remaining = count

  const strip = (node: Node): boolean => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent ?? ""
      const leading = text.length - text.trimStart().length
      const take = Math.min(remaining, leading)
      node.textContent = text.slice(take)
      remaining -= take
      return remaining <= 0 || text.trim() !== ""
    }
    for (const child of Array.from(node.childNodes)) {
      if (strip(child)) return true
    }
    return false
  }

  strip(el)
  return el.innerHTML
}
```

- [ ] **Step 4: Update `assets/js/app.ts`**

```ts
import ReachGraph from "@reach/components/ReachGraph.vue"
import { createApp } from "vue"

createApp(ReachGraph, {
  manifest: (window as Record<string, unknown>).__reachManifest,
}).mount("#app")
```

- [ ] **Step 5: Lint**

Run: `mix js.check`
Expected: PASS (oxfmt + oxlint clean). If oxfmt complains, run `cd assets && npx --yes oxfmt js/` and re-check.

- [ ] **Step 6: Commit**

```bash
git add assets/js/types.ts assets/js/chunks.ts assets/js/source.ts assets/js/app.ts
git commit -m "feat: frontend chunk loader, source utilities, manifest boot"
```

---

### Task 9: Frontend rendering — grouping, ReachGraph rework, CodeNode

**Files:**
- Create: `assets/js/grouping.ts`
- Rewrite: `assets/js/components/ReachGraph.vue`
- Modify: `assets/js/components/CodeNode.vue`

**Interfaces:**
- Consumes: Task 8's `loadChunk`, `sliceLines`, `dedentHtmlLines`, `lineText`, `escapeHtml`; manifest/chunk shapes from Tasks 6–7.
- Produces: `buildModuleGraph(modules, edges, expanded): { nodes, edges }` with named `GROUP_THRESHOLD = 150`; `CodeNode` renders `data.lines: string[]` (pre-sliced/dedented HTML lines).

- [ ] **Step 1: Create `assets/js/grouping.ts`**

```ts
export interface GroupableModule {
  id: string
  name: string
}

export interface ModuleEdge {
  source: string
  target: string
  count: number
}

export interface ModuleGraphNode {
  id: string
  label: string
  kind: "module" | "group"
  size: number
}

export interface ModuleGraph {
  nodes: ModuleGraphNode[]
  edges: ModuleEdge[]
}

// Above this many modules the landing call graph collapses dotted
// namespaces (e.g. "MyApp.Billing.*") into expandable group nodes.
export const GROUP_THRESHOLD = 150

export function buildModuleGraph(
  modules: GroupableModule[],
  edges: ModuleEdge[],
  expanded: Set<string>
): ModuleGraph {
  if (modules.length <= GROUP_THRESHOLD) {
    return { nodes: modules.map(moduleNode), edges: aggregate(edges, identityAssignment(modules)) }
  }

  const byPrefix = new Map<string, GroupableModule[]>()
  for (const m of modules) {
    const prefix = groupPrefix(m.name)
    const list = byPrefix.get(prefix) ?? []
    list.push(m)
    byPrefix.set(prefix, list)
  }

  const assignment = new Map<string, string>()
  const nodes: ModuleGraphNode[] = []

  for (const [prefix, members] of byPrefix) {
    if (members.length === 1 || expanded.has(prefix)) {
      for (const m of members) {
        assignment.set(m.id, m.id)
        nodes.push(moduleNode(m))
      }
    } else {
      for (const m of members) assignment.set(m.id, prefix)
      nodes.push({ id: prefix, label: prefix, kind: "group", size: members.length })
    }
  }

  return { nodes, edges: aggregate(edges, assignment) }
}

function identityAssignment(modules: GroupableModule[]): Map<string, string> {
  return new Map(modules.map((m) => [m.id, m.id]))
}

function aggregate(edges: ModuleEdge[], assignment: Map<string, string>): ModuleEdge[] {
  const merged = new Map<string, ModuleEdge>()
  for (const e of edges) {
    const source = assignment.get(e.source)
    const target = assignment.get(e.target)
    if (!source || !target || source === target) continue
    const key = `${source}->${target}`
    const existing = merged.get(key)
    if (existing) existing.count += e.count
    else merged.set(key, { source, target, count: e.count })
  }
  return [...merged.values()]
}

function moduleNode(m: GroupableModule): ModuleGraphNode {
  return { id: m.id, label: m.name, kind: "module", size: 1 }
}

function groupPrefix(name: string): string {
  const parts = name.split(".")
  return parts.length <= 2 ? name : `${parts.slice(0, 2).join(".")}.*`
}
```

- [ ] **Step 2: Rewrite `assets/js/components/ReachGraph.vue`**

```vue
<script setup>
import { ref, computed, nextTick, onMounted, watch } from "vue"
import { VueFlow, useVueFlow } from "@vue-flow/core"
import { MiniMap } from "@vue-flow/minimap"
import { Controls } from "@vue-flow/controls"
import CodeNode from "@reach/components/CodeNode.vue"
import CompactNode from "@reach/components/CompactNode.vue"
import { computeLayout } from "@reach/layout"
import { loadChunk } from "@reach/chunks"
import { buildModuleGraph } from "@reach/grouping"
import { dedentHtmlLines, escapeHtml, lineText, sliceLines } from "@reach/source"

const props = defineProps({
  manifest: { type: Object, required: true },
})

const nodeTypes = { code: CodeNode, compact: CompactNode }
const mode = ref("call_graph")
const nodes = ref([])
const edges = ref([])
const hint = ref("")
const search = ref("")
const selectedModuleId = ref(null)
const selectedFunctionId = ref(null)
const expandedGroups = ref(new Set())
const expandedModules = ref(new Set())
const { fitView } = useVueFlow()

const moduleById = computed(() => new Map(props.manifest.modules.map((m) => [m.id, m])))
const selectedModule = computed(() =>
  selectedModuleId.value ? moduleById.value.get(selectedModuleId.value) : null
)

// ── Layout ──

async function applyLayout(rawNodes, rawEdges, layoutOverrides = {}) {
  const nodeSizes = new Map()
  for (const n of rawNodes) nodeSizes.set(n.id, estimateSize(n.data))

  const nodeIdSet = new Set(rawNodes.map((n) => n.id))
  const validEdges = rawEdges.filter((e) => nodeIdSet.has(e.source) && nodeIdSet.has(e.target))

  const positions = await computeLayout(
    rawNodes.map((n) => n.id),
    nodeSizes,
    validEdges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
    layoutOverrides
  )

  for (const n of rawNodes) {
    const pos = positions.get(n.id)
    if (pos) n.position = pos
  }

  nodes.value = rawNodes
  edges.value = validEdges
  await nextTick()
  fitView({ padding: 0.1 })
}

function estimateSize(data) {
  if (data.nodeType === "compact" || data.nodeType === "call" || data.nodeType === "external") {
    const len = (data.label ?? "").length
    return { width: Math.max(100, len * 7.5 + 24), height: 32 }
  }

  const lines = data.lines || []
  const labelLen = (data.label ?? "").length
  const maxCodeLen = Math.max(labelLen, 0, ...lines.map((l) => lineText(l).length))
  return {
    width: Math.min(700, Math.max(180, maxCodeLen * 7.5 + 70)),
    height: Math.max(36, lines.length * 18 + (data.label ? 26 : 8)),
  }
}

// ── Call Graph: module landing + per-module ego graph ──

async function buildCallGraph() {
  hint.value = ""
  if (selectedModule.value) return buildModuleEgoGraph(selectedModule.value)

  const graph = buildModuleGraph(
    props.manifest.modules,
    props.manifest.call_graph.edges,
    expandedGroups.value
  )

  const rawNodes = graph.nodes.map((n) => ({
    id: n.id,
    type: "compact",
    position: { x: 0, y: 0 },
    data: {
      label: n.kind === "group" ? `${n.label} (${n.size})` : n.label,
      nodeType: "compact",
      kind: n.kind,
    },
  }))

  const rawEdges = graph.edges.map((e) => ({
    id: `mod_${e.source}_${e.target}`,
    source: e.source,
    target: e.target,
    type: "default",
    style: { stroke: "#94a3b8", strokeWidth: Math.min(1 + Math.log2(1 + e.count) * 0.5, 4) },
  }))

  await applyLayout(rawNodes, rawEdges, {
    "elk.direction": "RIGHT",
    "elk.aspectRatio": "1.5",
  })
}

async function buildModuleEgoGraph(mod) {
  const chunk = await loadChunk(mod.id, mod.chunk)

  const rawNodes = chunk.calls.functions.map((f) => ({
    id: f.id,
    type: "compact",
    position: { x: 0, y: 0 },
    data: {
      label: f.module === mod.id ? f.name : f.id,
      nodeType: f.external ? "external" : "call",
      callFunction: f,
    },
  }))

  const rawEdges = chunk.calls.edges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: "default",
    style: { stroke: e.color, strokeWidth: 1.5 },
  }))

  await applyLayout(rawNodes, rawEdges, {
    "elk.direction": "RIGHT",
    "elk.aspectRatio": "1.5",
    "elk.edgeRouting": "SPLINES",
  })
}

// ── Control Flow: one function at a time ──

async function buildControlFlow() {
  if (!selectedModule.value || !selectedFunctionId.value) {
    nodes.value = []
    edges.value = []
    hint.value = "Select a function from the sidebar"
    return
  }

  hint.value = ""
  const chunk = await loadChunk(selectedModule.value.id, selectedModule.value.chunk)
  const func = chunk.functions.find((f) => f.id === selectedFunctionId.value)
  if (!func) return

  const rawNodes = func.nodes.map((n) => makeCfNode(n, chunk, func))
  const rawEdges = (func.edges || []).map((edge) => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    type: edgeStyle(edge.edge_type),
    style: edgeVisualStyle(edge),
    label: edge.label,
    labelStyle: {
      fill: edge.color,
      fontSize: 11,
      fontFamily: "ui-monospace, SFMono-Regular, monospace",
    },
    animated: edge.edge_type === "data",
  }))

  await applyLayout(rawNodes, rawEdges)
}

function makeCfNode(node, chunk, func) {
  let label = node.label
  if (!label && node.type === "entry") label = `${func.name}/${func.arity}`

  return {
    id: node.id,
    type: "code",
    position: { x: 0, y: 0 },
    data: {
      label,
      nodeType: visNodeType(node.type),
      funcId: func.id,
      lines: nodeLines(node, chunk),
      startLine: node.start_line,
    },
  }
}

function nodeLines(node, chunk) {
  if (node.source_text) return node.source_text.split("\n").map(escapeHtml)

  const linesHtml = chunk.source?.lines_html
  if (!linesHtml) return []

  const singleLine = node.type === "entry" || node.type === "exit" || node.type === "branch"
  const endLine = singleLine ? node.start_line : node.end_line
  return dedentHtmlLines(sliceLines(linesHtml, node.start_line, endLine))
}

function visNodeType(type) {
  switch (type) {
    case "entry": return "function"
    case "exit": return "exit"
    case "branch": return "match"
    case "dispatch": return "clause"
    case "clause": return "clause"
    default: return "expression"
  }
}

function edgeStyle(edgeType) {
  switch (edgeType) {
    case "branch": return "smoothstep"
    case "converge": return "smoothstep"
    case "data": return "smoothstep"
    default: return "default"
  }
}

function edgeVisualStyle(edge) {
  const width = edge.edge_type === "sequential" ? 1 : 2
  return { stroke: edge.color, strokeWidth: width }
}

// ── Data Flow: module-scoped ──

async function buildDataFlow() {
  if (!selectedModule.value) {
    nodes.value = []
    edges.value = []
    hint.value = "Select a module to see its data flow"
    return
  }

  hint.value = ""
  const chunk = await loadChunk(selectedModule.value.id, selectedModule.value.chunk)

  const rawNodes = chunk.data_flow.functions.map((f) => ({
    id: f.id,
    type: "code",
    position: { x: 0, y: 0 },
    data: { label: f.label, nodeType: "data", lines: [], startLine: f.start_line ?? 1 },
  }))

  const rawEdges = chunk.data_flow.edges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: "smoothstep",
    style: { stroke: e.color, strokeWidth: 2 },
    label: e.label,
    labelStyle: { fill: "#16a34a", fontSize: 11 },
  }))

  await applyLayout(rawNodes, rawEdges)
}

// ── Rebuild / selection ──

async function rebuild() {
  try {
    switch (mode.value) {
      case "call_graph":
        await buildCallGraph()
        break
      case "control_flow":
        await buildControlFlow()
        break
      case "data_flow":
        await buildDataFlow()
        break
    }
  } catch (e) {
    console.error("rebuild error:", e)
  }
}

watch([mode, selectedModuleId, selectedFunctionId], rebuild)
onMounted(rebuild)

function selectModule(id) {
  const next = new Set(expandedModules.value)
  next.add(id)
  expandedModules.value = next

  if (selectedModuleId.value === id) return
  selectedModuleId.value = id
  selectedFunctionId.value = null
}

function selectFunction(moduleId, funcId) {
  selectedModuleId.value = moduleId
  selectedFunctionId.value = funcId
  if (mode.value !== "control_flow") mode.value = "control_flow"
}

function clearSelection() {
  selectedModuleId.value = null
  selectedFunctionId.value = null
}

async function onNodeClick({ node }) {
  if (mode.value !== "call_graph") return

  if (!selectedModuleId.value) {
    if (node.data.kind === "group") {
      const next = new Set(expandedGroups.value)
      if (next.has(node.id)) next.delete(node.id)
      else next.add(node.id)
      expandedGroups.value = next
      await rebuild()
    } else if (moduleById.value.has(node.id)) {
      selectModule(node.id)
    }
    return
  }

  const fn = node.data.callFunction
  if (fn && !fn.external) {
    const mod = moduleById.value.get(fn.module)
    const target = mod?.functions.find((f) => `${f.name}/${f.arity}` === fn.name)
    if (mod && target) selectFunction(mod.id, target.id)
  }
}

// ── Sidebar ──

const filteredModules = computed(() => {
  const q = search.value.trim().toLowerCase()

  if (!q) {
    return props.manifest.modules.map((m) => ({
      ...m,
      functions: expandedModules.value.has(m.id) ? m.functions : [],
    }))
  }

  return props.manifest.modules
    .map((m) => {
      const nameHit = m.name.toLowerCase().includes(q)
      const funcs = m.functions.filter((f) =>
        `${f.name}/${f.arity}`.toLowerCase().includes(q)
      )
      if (!nameHit && funcs.length === 0) return null
      return { ...m, functions: nameHit && funcs.length === 0 ? m.functions : funcs }
    })
    .filter(Boolean)
})
</script>

<template>
  <div class="reach-container">
    <div class="tab-bar">
      <div class="tab-bar-tabs">
        <button class="tab" :class="{ active: mode === 'call_graph' }" @click="mode = 'call_graph'">
          Call Graph
        </button>
        <button class="tab" :class="{ active: mode === 'control_flow' }" @click="mode = 'control_flow'">
          Control Flow
        </button>
        <button class="tab" :class="{ active: mode === 'data_flow' }" @click="mode = 'data_flow'">
          Data Flow
        </button>
      </div>
      <div class="breadcrumb">
        <span>{{ manifest.project }}</span>
        <template v-if="selectedModule">
          <span>·</span>
          <span>{{ selectedModule.name }}</span>
          <button @click="clearSelection">back to overview</button>
        </template>
      </div>
    </div>

    <div class="main-area">
      <div class="sidebar">
        <div class="sidebar-title">Modules</div>
        <div class="sidebar-search">
          <input v-model="search" placeholder="Filter modules and functions…" />
        </div>
        <div v-for="mod in filteredModules" :key="mod.id" class="sidebar-module">
          <button class="sidebar-module-name" @click="selectModule(mod.id)">
            {{ mod.name }}
          </button>
          <button
            v-for="func in mod.functions"
            :key="func.id"
            class="sidebar-func"
            :class="{ active: selectedFunctionId === func.id }"
            @click="selectFunction(mod.id, func.id)"
          >
            {{ func.name }}/{{ func.arity }}
          </button>
        </div>
      </div>

      <div class="reach-flow-wrap">
        <VueFlow
          :nodes="nodes"
          :edges="edges"
          :node-types="nodeTypes"
          :default-edge-options="{ type: 'smoothstep' }"
          :min-zoom="0.1"
          :max-zoom="3"
          :nodes-draggable="false"
          class="reach-flow"
          @node-click="onNodeClick"
        >
          <MiniMap pannable zoomable />
          <Controls />
        </VueFlow>
        <div v-if="hint" class="hint-overlay">{{ hint }}</div>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 3: Modify `assets/js/components/CodeNode.vue`**

Replace the `lines` computation in the script block (keep everything else, including `TYPE_COLORS`):

```js
const colors = TYPE_COLORS[props.data.nodeType] ?? TYPE_COLORS.expression
const lines = props.data.lines || []
const showLabel = props.data.label && props.data.nodeType !== "expression"
```

(the template already iterates `lines` with `v-html` — unchanged.)

- [ ] **Step 4: Lint and build**

Run: `mix js.check`
Expected: PASS

Run: `mix assets.build`
Expected: `Building "assets/js/app.ts"... reach.js ~275 KB ... Built in <n>ms` (requires `cd assets && npm install` once beforehand)

- [ ] **Step 5: Commit**

```bash
git add assets/js/grouping.ts assets/js/components/ReachGraph.vue assets/js/components/CodeNode.vue
git commit -m "feat: lazy per-selection report rendering with namespace grouping"
```

---

### Task 10: Vendor asset copy, end-to-end verification, benchmark

**Files:**
- Modify: `mix.exs` (extend `assets.build` alias)
- Create: `scripts/report_bench.exs`

**Interfaces:**
- Consumes: everything above.
- Produces: complete `priv/static` (reach.js + elk.bundled.js + vue-flow.css) so `Render.Report` embeds real bundles; a reproducible benchmark script.

- [ ] **Step 1: Add the vendor copy step to `mix.exs`**

In `aliases/0`:

```elixir
      "assets.build": [
        "volt.build --name reach",
        &copy_vendor_assets/1
      ]
```

And the private function in `Reach.MixProject`:

```elixir
  defp copy_vendor_assets(_args) do
    File.mkdir_p!("priv/static/css")

    File.cp!(
      "assets/node_modules/elkjs/lib/elk.bundled.js",
      "priv/static/js/elk.bundled.js"
    )

    vendor_css =
      [
        "assets/node_modules/@vue-flow/core/dist/style.css",
        "assets/node_modules/@vue-flow/core/dist/theme-default.css",
        "assets/node_modules/@vue-flow/minimap/dist/style.css",
        "assets/node_modules/@vue-flow/controls/dist/style.css"
      ]
      |> Enum.map_join("\n", &File.read!/1)

    File.write!("priv/static/css/vue-flow.css", vendor_css)
  end
```

- [ ] **Step 2: Build assets and force re-embed**

Run:

```bash
cd assets && npm install && cd ..
mix assets.build
mix compile --force
```

Expected: `priv/static/js/elk.bundled.js` and `priv/static/css/vue-flow.css` exist; compile succeeds. (`Render.Report` reads the bundles at compile time via module attributes with `@external_resource`; `--force` guarantees the fresh bundles are embedded.)

- [ ] **Step 3: Create `scripts/report_bench.exs`**

```elixir
# Benchmarks the report pipeline. Usage:
#   mix run scripts/report_bench.exs [source_glob ...]
# Defaults to this project's lib/**/*.ex.

globs =
  case System.argv() do
    [] -> ["lib/**/*.ex"]
    args -> args
  end

paths = globs |> Enum.flat_map(&Path.wildcard/1) |> Enum.uniq() |> Enum.sort()
IO.puts("Files: #{length(paths)}")

{t_project, project} = :timer.tc(fn -> Reach.Project.from_sources(paths) end)
IO.puts("from_sources:  #{Float.round(t_project / 1_000_000, 1)}s (#{map_size(project.nodes)} nodes)")

{t_chunks, output} = :timer.tc(fn -> Reach.Visualize.Chunks.build(project, project: "bench") end)
IO.puts("Chunks.build:  #{Float.round(t_chunks / 1_000_000, 1)}s (#{length(output.chunks)} chunks)")

manifest_bytes = byte_size(JSON.encode!(output.manifest))
chunk_bytes = output.chunks |> Enum.map(fn {_, c} -> byte_size(JSON.encode!(c)) end) |> Enum.sum()

IO.puts("manifest:      #{Float.round(manifest_bytes / 1_048_576, 2)} MB")
IO.puts("chunks total:  #{Float.round(chunk_bytes / 1_048_576, 2)} MB")

largest =
  output.chunks
  |> Enum.map(fn {id, c} -> {id, byte_size(JSON.encode!(c))} end)
  |> Enum.max_by(&elem(&1, 1))

IO.puts("largest chunk: #{elem(largest, 0)} #{Float.round(elem(largest, 1) / 1_048_576, 2)} MB")
```

- [ ] **Step 4: Self-run smoke test**

Run:

```bash
mix run scripts/report_bench.exs
mix reach --no-open --output /tmp/reach_report_self
ls /tmp/reach_report_self /tmp/reach_report_self/chunks | head -20
```

Expected: bench prints timings; report directory contains `index.html`, `manifest.js`, and `chunks/*.js` (one per Reach module). Open `/tmp/reach_report_self/index.html` in a browser: module call graph renders; clicking a module loads its ego graph; sidebar function click renders its control flow with highlighted, dedented source; data-flow tab shows module-scoped graph.

- [ ] **Step 5: Full CI**

Run: `mix ci`
Expected: PASS (compile with warnings-as-errors, format, js.check, credo --strict, ex_dna, reach.check, dialyzer, tests). Fix anything it flags — common suspects: format (`mix format`), unused imports in `control_flow.ex`, dialyzer specs on the new modules.

- [ ] **Step 6: Commit**

```bash
git add mix.exs scripts/report_bench.exs
git commit -m "feat: vendor asset copy step and report pipeline benchmark"
```

- [ ] **Step 7: Verify on jarl (manual, with Roman)**

From `~/GymNation/app/jarl` with reach as a path dependency (or via the bench script from the reach repo):

```bash
mix run scripts/report_bench.exs "$HOME/GymNation/app/jarl/lib/**/*.ex"
```

Expected: `from_sources` ~19s, `Chunks.build` a few seconds, manifest ~1–2 MB, largest chunk well under 1 MB. Then generate and open a real report against jarl sources and confirm the browser stays responsive. Record the numbers in the PR description.

---

### Task 11 (OPTIONAL stretch): Parallelize `merge_project` cross-module rebuild

Only do this if Tasks 1–10 landed cleanly and the analysis phase (~19s on jarl) is still the dominant cost. Skip freely.

**Files:**
- Modify: `lib/reach/project.ex` (`merge_project/2`)

- [ ] **Step 1: Parallelize the per-module rebuild**

In `merge_project/2`, replace the serial `Map.new(module_sdgs, fn {mod, sdg} -> ... end)` block with:

```elixir
    module_sdgs =
      module_sdgs
      |> Task.async_stream(
        fn {mod, sdg} ->
          all_nodes = Map.values(sdg.nodes)
          func_defs = Reach.CallGraph.collect_function_defs(all_nodes, mod)

          graph =
            Reach.SystemDependence.add_call_edges_with_externals(
              sdg.graph,
              all_nodes,
              func_defs,
              external_sdgs: external_sdgs,
              summaries: summaries
            )

          {mod, %{sdg | graph: graph}}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity,
        ordered: false
      )
      |> Map.new(fn {:ok, result} -> result end)
```

- [ ] **Step 2: Verify**

Run: `mix test test/reach/project`
Expected: PASS

Run: `mix run scripts/report_bench.exs "$HOME/GymNation/app/jarl/lib/**/*.ex"`
Expected: `from_sources` drops measurably (~19s → ~10–13s).

- [ ] **Step 3: Commit**

```bash
git add lib/reach/project.ex
git commit -m "perf: parallelize cross-module call edge rebuild"
```
