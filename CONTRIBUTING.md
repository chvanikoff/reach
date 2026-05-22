# Contributing to Reach

Thanks for helping improve Reach. This project analyzes Elixir/Erlang code, so changes should preserve a high signal-to-noise ratio and be validated against both focused tests and real-world code.

## Getting started

```bash
mix deps.get
MIX_ENV=test mix test
```

Before opening a substantial change, run the full local check suite:

```bash
MIX_ENV=test mix ci
```

This runs formatting, Credo, clone detection, Reach's own architecture/smell checks, Dialyzer, and the test suite.

## CLI shape

Reach 2.x has five canonical Mix tasks:

| Command | Purpose |
|---|---|
| `mix reach.map` | Project map: modules, coupling, effects, hotspots, depth, data/xref |
| `mix reach.inspect TARGET` | Target-local deps, impact, graph, context, why, data, candidates |
| `mix reach.trace` | Data flow, taint paths, backward/forward slices |
| `mix reach.check` | CI/release checks: architecture, changed-code risk, dead code, smells, candidates |
| `mix reach.otp` | OTP/process analysis: behaviours, supervision, concurrency, coupling |

Removed commands should stay as hard-deprecated shims with migration guidance. Do not add new command tunnels or make Mix tasks call other Reach Mix tasks internally.

## Architecture expectations

Keep responsibilities separated:

- `Mix.Tasks.Reach.*` parses CLI args and invokes the canonical command layer.
- `Reach.CLI.Commands.*` orchestrates command modes.
- `Reach.CLI.Render.*`, `Reach.CLI.Format`, and `Reach.CLI.Text` render output.
- `Reach.Smell.*` owns smell rules and findings.
- `Reach.Check.*` owns CI/release-oriented policy checks.
- `Reach.Evidence.*` owns reusable observed facts.
- `Reach.Plugin` and `Reach.Plugins.*` own framework/library-specific semantics.

Framework-specific policy should live behind plugins. Generic smell, evidence, trace, map, and visualization code should not hardcode Ecto/Phoenix/Oban/Ash/Jido/etc. semantics.

## Adding or tuning a smell

A good smell starts conservative. Prefer a small high-confidence rule over a broad noisy one.

New or broader smell rules need a false-positive scan before they are merged. If you want to contribute a rule but are not ready to run the corpus workflow, please open an issue instead. Include the pattern you want Reach to catch, why it matters, and a few real examples if you have them. That gives maintainers enough context to turn the idea into a validated rule later.

1. Add the smell under the right layer:
   - generic structural smells: `lib/reach/smell/checks/`
   - plugin-specific smells: `lib/reach/plugins/<plugin>/smells/`
2. Add focused tests in `test/reach/smell/checks/` or the matching plugin test directory.
3. Include at least one negative test for a legitimate nearby pattern.
4. Run the targeted tests:

   ```bash
   MIX_ENV=test mix test test/reach/smell/checks/<smell>_test.exs
   ```

5. Dogfood locally:

   ```bash
   MIX_ENV=test mix reach.check --arch --smells --strict
   ```

6. Run corpus validation before broadening the heuristic. Review every finding for the new rule in the scan output, tune away false positives, and add regression tests for both the intended hit and any allowed nearby pattern.

### Corpus workflow

Use `scripts/smell_corpus_scan.exs` for real-world signal checks. The script supports individual smell runs via `--kinds`.

For broad validation we use a local **Hex playground**: a directory of unpacked Hex packages, usually checked out next to Reach as `../hex-playground`. Reach expects package sources under `../hex-playground/sources/<package-version>/`.

Create it with the companion corpus repository:

```bash
cd ..
git clone https://github.com/elixir-vibe/hex-playground.git
cd hex-playground
mix deps.get
mix run scripts/fetch.exs
```

If the fetch script name changes, check the playground README and use whichever command populates `sources/` with unpacked Hex packages. You can also point scans at any directory with the same shape by writing its package directories to a repos file.

Create a repo list from a local Hex playground checkout:

```bash
find ../hex-playground/sources -mindepth 1 -maxdepth 1 -type d | sort > /tmp/hex-playground-all-repos.txt
```

Run a single smell:

```bash
MIX_ENV=test mix run scripts/smell_corpus_scan.exs \
  --repos-file /tmp/hex-playground-all-repos.txt \
  --kinds false_success_error \
  --quiet-zero \
  --progress-every 500 \
  --output /tmp/reach-false-success-hex.json
```

Run a small group of related smells:

```bash
MIX_ENV=test mix run scripts/smell_corpus_scan.exs \
  --repos-file /tmp/hex-playground-all-repos.txt \
  --kinds false_success_error,ets_partial_key_match,ex_unit_async_global_state \
  --include-tests \
  --quiet-zero \
  --progress-every 500 \
  --output /tmp/reach-new-smells-hex.json
```

Useful options:

- `--kinds a,b,c` — run only checks that can emit those kinds, and only write those findings.
- `--include-tests` — include `test/**/*.exs` and `apps/*/test/**/*.exs`; important for ExUnit smells.
- `--quiet-zero` — suppress per-repo lines with zero findings.
- `--progress-every N` — print visible progress every N repos; use `0` to disable.
- `--fail-fast` — stop at the first repository error after writing partial output.

When a corpus run finds noisy examples, inspect the source and tune the rule instead of documenting the noise away. Add regression tests for both the intended hit and the noisy allowed case.

## Crash-hunting workflow

For parser/analyzer crashes, prefer fail-fast loops:

1. Print progress.
2. Stop at the first crash.
3. Fix the root cause.
4. Add a regression test.
5. Rerun the corpus slice.

Avoid broad `rescue` fallbacks in analyzers unless the boundary genuinely involves parser or external-tool failures. Prefer explicit shape checks.

## Visualization changes

Visualization code has stricter acceptance criteria because block quality affects user trust. After visualization changes, run:

```bash
mix test test/reach/visualize/block_quality_test.exs
```

For larger changes, smoke-test real codebases such as Elixir, Phoenix, Ecto, and Oban.

## Release workflow

Before a release:

1. Update `CHANGELOG.md`.
2. Run `MIX_ENV=test mix ci`.
3. Bump the version in `mix.exs`.
4. Build docs in the docs environment via the configured Mix aliases/preferred envs.
5. Publish only after local validation is clean.

Patch releases should be small and have a clear user-facing reason.
