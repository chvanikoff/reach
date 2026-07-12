# Report Speed & Chunked Output — Design

**Date:** 2026-07-12
**Status:** Approved
**Branch:** feature/speed

## Problem

On a large codebase (GymNation's jarl: 1,307 files, ~208k lines), `mix reach` is
unusably slow and its output unusably large. Measured:

| Stage | Time |
|---|---|
| Analysis (`Reach.Project.from_sources`) | 19s |
| Visualization (`Reach.Visualize.to_graph_json`) | **94s** |
| JSON encode + write | 2s |
| Report JSON size | **58.5 MB** (control_flow 32.8, data_flow 14.8, call_graph 10.9) |

Root causes, verified by measurement and eprof profiling:

1. **Quadratic membership check.** `Visualize.data_flow_data/2` builds
   `involved_ids` as a flat **list** of data-edge endpoints, then
   `build_data_flow_nodes` evaluates `n.id in involved_ids` for all ~517k
   project nodes. ~50s of the 94s. (Measured at 200 files: 1.3s as list,
   ~0s as MapSet.)
2. **Per-block syntax highlighting.** `Visualize.ControlFlow` calls Makeup for
   every CFG block of every function (9,557 functions), serially. Dominates the
   remaining viz time and produces 22 MB of duplicated pre-rendered
   `source_html` in the JSON.
3. **Whole-project single-canvas frontend.** `ReachGraph.vue#buildControlFlow`
   puts every expression node of every function (~100k nodes for jarl) into one
   ELK layout and one Vue Flow canvas. This is why "no browser can open it" —
   it is independent of file size and never finishes.
4. **Everything inlined.** `index.html` embeds the entire project JSON plus JS
   bundles in one file.

## Decisions (from brainstorming with Roman)

- Report usage: project overview **and** per-function drill-down, both matter.
- Output shape: a **directory** of files is fine; single-file not required.
- Speed target: ~25–30s total on jarl is acceptable now; **incremental caching
  is the long-term direction** — the design must align with it, not implement it.
- Highlighting: **server-side Makeup, once per file**; blocks reference line
  ranges. No new JS dependencies.
- Future (out of scope, but enabled): auth-protected in-app route serving the
  report (SwaggerUI-style), via a small Plug serving the report directory.

## Section 1: Pipeline speed fixes

Target: `to_graph_json` 94s → ~3–5s on jarl.

**1a. MapSet for involved ids.** In `data_flow_data`, convert `involved_ids`
to a `MapSet` before `build_data_flow_nodes` filters `all_nodes` against it.

**1b. Highlight once per file.** Remove per-block Makeup calls
(`highlight_line`, `highlight_lines` per block). Add a per-file pass that
highlights the entire file into an array of per-line HTML strings (one entry
per source line, index = line − 1). It reuses the existing process-dict file
cache; the JavaScript `meta[:source]` injection path keeps working because it
feeds that same cache. CFG blocks emit only `{start_line, end_line}` — no
`source_html`. Consequences:
- Dedent moves client-side (compute min indent of the displayed range in JS).
- The blank-block filter (`source_blank?`) switches from inspecting rendered
  HTML to inspecting the raw source lines for the block's range.

**1c. Parallelize the viz build.** The per-module `Enum.map` in
`Visualize.ControlFlow.build/2` becomes `Task.async_stream` with
`max_concurrency: System.schedulers_online()`. Process-dict source caches are
per-worker; modules are ~1:1 with files, so duplicate file work is negligible.

**Optional stretch (only if cheap once we're in there):** parallelize the
serial per-module `add_call_edges_with_externals` rebuild inside
`Reach.Project.merge_project/2` the same way (analysis 19s → ~10–12s).
Analysis is otherwise untouched this round.

## Section 2: Report format — chunked directory

```
reach_report/
  index.html          # app shell; JS/CSS bundles inlined as today; NO data
  manifest.js         # window.__reachManifest = {...}
  chunks/
    MyApp.Billing.js  # window.__reachChunk("MyApp.Billing", {...})
    ...               # one per module
```

**manifest.js** (~1–2 MB for jarl) — everything the browser needs up front:
- `modules`: `[{id, name, file, chunk, functions: [{id, name, arity}]}]`
  (drives sidebar + search).
- `call_graph`: **module-level** aggregated, deduped edges.
- `meta`: project name, generation timestamp, node/edge counts.

**chunks/<module>.js** — loaded on demand:
- `source`: `{file, lines_html: [...]}` — the file highlighted once.
- `functions`: per-function CFG — blocks as `{id, type, label, start_line,
  end_line}` + edges (schema otherwise as today).
- `calls`: function-level call edges touching this module (for the ego graph).
- `data_flow`: module-scoped data-flow nodes/edges.

Chunk loading works over `file://` by injecting `<script src>` tags
(JSONP-style `window.__reachChunk` callback), with a promise-per-chunk cache.
Module ids are sanitized for filesystem safety; the manifest's `chunk` field is
the source of truth for the filename.

`--format json` (single `reach.json`, existing schema) and `--format dot` are
**unchanged** — they are machine-consumed and become fast via fix 1a.

**Alignment with future work:** one chunk per module is the natural unit for
incremental regeneration (skip chunks whose source content hash is unchanged)
and is directly servable by a future `Reach.Plug`.

## Section 3: Frontend rendering — never render the whole project

- **Landing (Call Graph tab):** module-level graph from the manifest. Above
  ~150 modules, collapse into namespace groups (`Jarl.Billing.*` → one node)
  that expand on click, so ELK never lays out more than a few hundred nodes.
  Grouping is computed client-side from module names in the manifest.
- **Module selected** → load its chunk → function-level call graph for that
  module plus direct external callers/callees (ego graph, not global).
- **Function selected** → Control Flow tab renders that function only, building
  code nodes from line ranges against the chunk's `lines_html` (client-side
  dedent). Data Flow tab is scoped the same way; with no selection it shows a
  "select a module" hint.
- **Sidebar:** modules collapsed by default, expand on click; search box
  filters modules/functions from the manifest. No more 9,557 buttons in the
  DOM.
- Minimap, controls, node styling, and tab structure stay as they are.

## Section 4: CLI & compatibility

- `mix reach` flags and defaults unchanged; `--output` still names the
  directory; `--open` opens `index.html`.
- Behavioral change: `index.html` is no longer self-contained — it requires its
  sibling `manifest.js` and `chunks/`. Console output mentions the report
  directory.

## Section 5: Testing

- Adapt existing `Visualize`/render tests to the new block schema (line ranges,
  no `source_html`).
- New unit tests: per-file highlighter (output array aligns 1:1 with source
  lines); manifest/chunk writer (valid JS wrappers, one chunk per module,
  proper escaping). Namespace grouping is client-side; it is covered by
  `mix js.check` linting and manual verification.
- Integration test: generate a report for `examples/`, assert directory
  structure (index + manifest + expected chunks) and parseable payloads.
- Manual verification: full run on jarl — target ~25s compute, report opens
  and is navigable in Chrome. `mix ci` green.

## Section 6: Out of scope (deliberately enabled)

- **Incremental cache:** per-file content-hash keyed reuse of parse/SDG results
  and chunk re-emission.
- **`Reach.Plug`:** mount the report directory in a host app behind the host's
  auth (the SwaggerUI-style in-prod idea).
- Further analysis-phase optimization beyond the optional merge_project
  stretch.
