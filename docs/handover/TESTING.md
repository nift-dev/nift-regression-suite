# Nift external-contract testing

## Contract surface

The suite covers externally observable behavior including CLI commands/status,
tracking/configuration, template syntax, content/input/path/metadata semantics,
JSON/Schema/control flow, dependencies and requirements, modified/hash/hybrid
incrementality, watch/persistence/path safety, missing/deleted resources, and
opt-in minification through Nift's public interface.

Internal page metadata is tested only where its persistence affects observable
behavior. Private algorithms and representations are not contractual.

## Reconciled baseline (2026-08-17)

`run-contract.sh` passed all 17 modules against the repository-built Nift 4.0.1
candidate. The result includes the 575-assertion historical/ruthless suite and
16 focused contract modules, including project contracts and optional tracked
templates. The runner's disposable-copy design was confirmed:
the historical tests mutate only a temporary suite copy, while focused modules
create their own temporary projects. Performance/RSS benchmarks and sanitizer
instrumentation were not part of this correctness baseline.

### Current v4.0.3 contract reconciliation (2026-08-19)

The canonical runner now comprises 20 modules: the 578-assertion historical/
ruthless layer plus 19 focused executable-level contract modules. After the
exactly-once `@content` rule landed, historical positive fixtures that executed
content repeatedly were converted to isolated token-boundary probes and an
explicit duplicate-content failure. The focused parser-content contract retains
nested-`@input`, skipped-branch, comment, zero-use, and duplicate-use coverage.

The expression-aware parameter resolver now reports
`parameter expression must resolve to a scalar value` when an array/object is
used in a textual directive parameter. The independent interpolation module was
updated to that deliberate diagnostic while preserving rejection behavior.

### Parameter-interpolation checkpoint

`contract/parameter_interpolation_smoke.sh` deliberately specified the feature
before implementation: its first baseline had two passing boundary checks and
43 expected failures. It now contains 73 passing checks. Preserve the historical
red checkpoint as evidence of test-first development, but treat any current
failure as a regression rather than an expected baseline.

The module covers all semantically textual directive positions, scalar parity
with ordinary `$[...]`, static binding identifiers, source-boundary safety,
one-pass/non-recursive values, literal escaping, nested lexical scope and loop
metadata, skipped branches, dependency/requirement recording, path containment,
modified/hash/hybrid A-to-B input replacement, explicit `@dep` replacement,
dynamic JSON-source replacement, requirement existence semantics, and failed-build
output/metadata preservation plus repair.

The historical runner previously used a predictable PID-named temporary directory.
In the desktop execution environment PIDs can be reused while stale directories
remain, causing unrelated legacy setup failures. It now uses `mktemp -d`; this is
harness isolation hardening and does not alter the external Nift contract.

The focused contract shell scripts also have implementation-local counterparts.
Keep the independent repository canonical for externally observable behavior or
establish another explicit policy, then enforce expected equality mechanically;
do not let two manually maintained copies become competing contracts.

### Init and platform-target contract

Nift 4.0.2 deliberately changes project initialization. `nift init` is the HTML
default, `--ext=.ext` selects a generic content/output extension, and
`--target=<platform>` selects one of the supported static-host presets. The old
positional extension and `init-html` forms are removal diagnostics rather than
compatibility aliases.

`contract/init_targets_smoke.sh` independently checks the default/PHP/neutral
starter families, all nine target project shapes, target-extension rejection,
provider configuration/output artifacts, preservation of an existing `.gitignore`,
and the removed-spelling diagnostics. The historical runner was migrated to the
new default while retaining explicit checks that the removed forms fail.

## Methodology

```text
read implementation or observe bug
→ identify an assumption
→ violate it with the smallest external fixture
→ make it deterministic
→ prove the expected failure
→ retain regression
→ inspect sibling assumptions
→ run the cumulative corpus
```

Bug-family reasoning outranks raw case count. Exit status, which files changed,
whether old output survived, whether state was committed, and what rebuilds are
selected are all part of the contract.

## Coverage accounting gate

For each new user-visible behavior, syntax rule, configuration field, CLI result,
scaffold change, or incremental-state transition, record a two-layer coverage
map before declaring the development checkpoint complete:

```text
behavior or invariant
  -> Nift implementation-local test/target
  -> independent contract module executed by run-contract.sh
```

Do not infer that adding a source-repository shell test updates this standalone
suite. Verify both repository diffs and run the canonical external runner against
the candidate executable. When only one layer applies, document why; “forgot the
other repository” is not an acceptable exception.

## Historical families and lessons

- Quote ambiguity: single/double quotes only; backticks are not Nift quotes.
- Function adjacency such as `@content<`: positive token grammar and boundary
  tests are safer than permissive parsing.
- CSS at-rules: unknown ordinary web syntax should remain transparent.
- Watch initialization and malformed JSON: test complete lifecycle and treat
  persisted state as untrusted.
- Empty tracking/quoted metadata: test zero collections and correct serialization.
- CLI/build-updated failures: non-zero status is required when requested work
  fails.
- Deleted output/directory/hash cache: repeated transitions matter, not only one
  successful build.
- Traversal/collisions: project paths and derived outputs are safety boundaries.
- Sub-second mtimes: control timestamps rather than sleeping.
- Hash collision: hostile construction can invalidate “unlikely” assumptions.
- Dependency sidecars and lexical scope: test lifecycle replacement/restoration.

## Fixture design

Prefer small temporary projects. Cases should establish their own state except
when a multi-step lifecycle is intentional. Control paths, timestamps, contents,
order, environment, and seeds where practical. Keep successful output concise and
failure output localized by module/test identity.

Do not weaken a test because a candidate implementation fails. Determine whether
the contract intentionally changed, the test assumption was wrong, or the
implementation regressed. Record deliberate contract changes.

## `$[...]` textual-parameter family

The upcoming contract should cover:

- whole unquoted value arguments and quoted literal/value composition;
- prefix, suffix, multiple, and adjacent substitutions;
- metadata, JSON strings, nested indexing, loop bindings, shadowing, and skipped
  branches using the existing value grammar;
- single/double quote parity, whitespace accepted by current grammar, and the
  existing literal-dollar escape;
- missing bindings, malformed expressions, empty values, and each JSON type under
  the deliberately chosen type contract;
- values containing quotes, commas, parentheses, `@...`, and `$[...]` remaining
  one-pass data rather than changing argument count or executing syntax;
- no parameter value leaking into document output;
- binding/control-flow identifier positions remaining static;
- path traversal/symlink/containment parity with literal arguments;
- ordinary literal arguments and nearby CSS/JS remaining unchanged.

Directive families should include every verified textual slot: likely `@input`,
`@dep`, `@path`, and `@json` source/schema paths, plus other current directives
only after source classification.

The essential dynamic graph sequence is A→B: selector source and A initially
matter; after a successful switch, selector source and B matter while stale A no
longer causes rebuilding. Test missing target failure, prior output/state
preservation, repair, and relevant incremental modes/watch. Requirements receive
the analogous existence lifecycle.

## Internal/external division

Direct resolver, parser index, string lifetime, scope-stack, and value-type unit
tests belong with Nift C++. The external suite proves end-to-end behavior. Do not
move all coverage to the easier layer.

## Performance and safety

Run performance separately and retain context. Scaling ratios are often more
portable than strict milliseconds. Sanitizer evidence belongs primarily to the
implementation repository, but the external suite is an excellent workload to
run under a sanitized candidate.

## Project contracts

The project-contract module treats config declaration, namespace ownership, `$[...]` resolution, dependency metadata, incremental source/config transitions, and controlled failures as one behavioral surface. The suite intentionally tests malformed unused contracts to prove lazy loading and tests an ordinary unconfigured `$[...]` root so the implementation cannot silently reinterpret every unknown value as a contract.
