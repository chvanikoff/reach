# Per-occurrence skip annotations across all check surfaces

**Date:** 2026-07-12
**Status:** Approved
**Branch:** feature/skips

## Problem

Reach's `# reach:disable-next-line` / `# reach:disable-for-this-file` comments only
apply to smell findings (`mix reach.check --smells`). Every other finding-producing
surface — dead code, OTP, architecture — has no per-occurrence escape hatch: a false
positive can only be silenced by not running the check.

Motivating example: `mix reach.check --dead-code` flags
`Gettext.put_locale(GNWeb.Gettext, locale)` as "result unused". The call is executed
for its side effect (a process-dictionary write), but the effects model classifies it
`:pure` via spec/inferred-type inference, so the dead-code analysis treats the
discarded result as dead code. The user can neither annotate the line nor configure
an ignore — only stop running `--dead-code`.

## Goals

1. One consistent suppression-comment syntax honored by every per-line
   finding-producing check surface: smells, dead code, OTP, architecture.
2. Fix the root cause of the motivating false positive: classify
   `Gettext.put_locale/1,2` (and `Gettext.get_locale/0,1`) as process-dictionary
   effects, not pure calls.

## Non-goals

- `--changed` and `--candidates` output (reports/rankings, not pass-fail findings).
- HTML report surfaces.
- Config-level path/module ignores for non-smell checks (smells keep theirs; other
  surfaces can gain them later if needed).
- Suppressing findings that have no `file:line` location (project-level arch
  violations such as `layer_cycle`, OTP module reports with `"unknown"` locations).

## Design

### 1. Shared core: `Reach.Suppressions`

New module `lib/reach/suppressions.ex`. The comment-parsing half of
`Reach.Smell.Suppressions` moves here:

- Directives: `# reach:disable-next-line <tokens>` and
  `# reach:disable-for-this-file <tokens>`.
- Tokens are space/comma-separated; unknown tokens are ignored without creating
  atoms.
- A directive must start its own line (leading whitespace allowed); trailing
  same-line directives are not recognized (unchanged from today).
- **Behavior change (deliberate):** a bare directive with no tokens is treated as
  `all`. Today a bare directive silently suppresses nothing, which is almost
  certainly user error; Credo's equivalent bare directive disables all checks, and
  matching that intuition is safer than a no-op.
- Location extraction (`location/1`) moves here too. It currently handles
  `%{location: %{file:, line:}}`, `%{location: %{file:, start_line:}}`, and
  `%{location: "file:line[:col]"}`; it gains one new clause for top-level
  `%{file:, line:}` structs (dead-code findings, arch violations).

Public API:

```elixir
@spec filter(findings :: [finding], tokens_fun :: (finding -> [String.t()])) :: [finding]
```

`filter/2` rejects any finding whose `file:line` is covered by a directive carrying
at least one of `tokens_fun.(finding)`. Files are parsed once per run and only when
they contain findings (same strategy as today). A `# reach:disable-next-line`
directive on line N suppresses findings located on line N+1; multi-line expressions
are matched by their start line.

### 2. Token model

Every finding is suppressible by three tiers of token:

| Tier | Examples | Meaning |
|---|---|---|
| Kind | `bare_rescue`, `dead_reply`, `forbidden_call` | this specific finding kind |
| Check group | `smells`, `dead_code`, `otp`, `arch` | anything from that surface |
| Global | `all` | anything Reach reports |

### 3. Per-surface wiring

**Smells** — `Reach.Smell.Suppressions` remains the smells entry point and keeps the
smell-specific config ignores (`smells[:ignore]`, per-check `ignore`), but delegates
comment matching to `Reach.Suppressions`. Tokens: finding kind + `smells` + `all`.
Behavior is identical to today; the existing suppression test suite must pass
unchanged (except the bare-directive change above).

**Dead code** — filtered inside `Reach.Check.DeadCode.run/2`, so library callers
benefit as well as the CLI. Tokens: `dead_code` + `all` only. Node-type kinds
(`call`, `match`, `binary_op`) are deliberately not exposed as tokens — too generic
to be meaningful suppression names.

```elixir
# reach:disable-next-line dead_code
Gettext.put_locale(GNWeb.Gettext, locale)
```

**OTP** — filtered where `Reach.OTP.Analysis` assembles its result, for each
location-bearing, finding-like sub-report: dead replies, hidden coupling, missing
handlers, cross-process. Tokens: sub-report kind (`dead_reply`, `hidden_coupling`,
`missing_handler`, `cross_process`) + `otp` + `all`. Inventory sub-reports
(behaviours, state machines, supervision) are not findings and are not filtered.
Entries whose location is `"unknown"` pass through unfiltered.

**Architecture** — violations filtered in the `--arch` pipeline **before** baseline
filtering and gate evaluation (the same ordering smells document today), so a
suppressed violation does not fail the gate. Tokens: violation type
(`forbidden_module`, `forbidden_file`, `forbidden_call`, `public_api_boundary`,
`internal_boundary`, `effect_policy`, …) + `arch` + `all`. Violations without a
`file`/`line` (e.g. `layer_cycle`, `missing_layer` config issues) are not
comment-suppressible.

All filtering happens before rendering, so `--format json` output is filtered
consistently with text output.

### 4. Gettext purity fix (`lib/reach/effects.ex`)

1. `process_dict_write?(Gettext, :put_locale)` and
   `process_dict_read?(Gettext, :get_locale)` — function-name matches cover both
   arities of each. `classify_state` runs before spec-based inference, so this wins
   over the current `:pure` misclassification.
2. Add `Gettext` to `@impure_modules` so spec/inferred-type classification never
   marks other Gettext functions `:pure` — translation lookups read the locale from
   the process dictionary, so `:unknown` is the honest classification.
3. Audit `Logger.metadata/1` (also a process-dictionary write); add it the same way
   if currently misclassified, otherwise leave untouched.

Result: the motivating warning disappears with no annotation; the annotation remains
as the escape hatch for future false positives.

## Documentation

- `guides/configuration.md`: move the suppression-comment section out of the
  smells-only area; document the directive syntax, the token table, the ordering
  (suppressions apply before baseline filtering and strict/gate evaluation), and the
  bare-directive-means-`all` rule.
- `mix reach.check` and `mix reach.otp` moduledocs: mention suppression comments.
- CHANGELOG entry under Unreleased.

## Testing

- Unit tests for `Reach.Suppressions` (moved and extended from
  `test/reach/smell/suppressions_test.exs`): directive parsing, tokenization,
  bare-directive-as-`all`, next-line vs whole-file scope, location extraction for
  all four finding shapes.
- Integration tests per newly wired surface (dead code, OTP, arch): suppressed
  finding, wrong-token not suppressed, group token, `all` token; arch also covers
  gate ordering (suppressed violation does not raise).
- Smells suppression regression suite passes unchanged (bar the bare-directive
  case).
- Effects tests: `Gettext.put_locale` classified `:write`, `Gettext.get_locale`
  classified `:read`.
- Dead-code regression fixture: a discarded `Gettext.put_locale/2` call is not
  reported.

## Compatibility

- Existing `# reach:disable-next-line <kind>` smell comments keep working unchanged.
- The only behavior change for existing users is the bare directive (no-op → `all`).
- New tokens (`dead_code`, `otp`, `arch`, OTP kinds, arch violation types) are
  additive; unknown tokens remain inert.
