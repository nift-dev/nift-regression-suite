# Nift regression-suite handover

This repository is the canonical implementation-independent behavioral contract
for the Nift v4 family. The current development executable targets Nift 4.1.0 (the
v4.1 template-language development version); it is not an implementation test
directory extracted from the C++ tree.

## Authority and purpose

The runner accepts an arbitrary Nift executable and observes CLI status,
filesystem state, generated output, project metadata, incrementality, and failure
behavior. It must not include private Nift headers or depend on C++ class layout.
A future independent implementation should be able to pass by implementing the
same observable contract.

Current suite behavior and runner files are authoritative. Nift source/tests are
authoritative for implementation internals. Nift's core handover owns product
history; this repository owns black-box contract methodology.

## Cross-repository push ordering

When a change modifies both Nift and this repository, push **Nift first**, verify
the intended Nift commit/version is present on `origin/main`, and only then push
the regression-suite commit that depends on it. The `Contract suite against Nift`
workflow checks out `nift-dev/nift` from its remote `main` branch, so pushing a
new contract first makes CI execute that contract against the previous Nift
revision. A red result in that situation is legitimate but tests the wrong
cross-repository pair.

The v4.0.11 release hit exactly this race: this repository's `837a616` was
pushed while Nift `main` was still v4.0.10, so the workflow built v4.0.10 and
failed on the v4.0.11 `@/* ... */` grammar and version assertion. The subsequent
clean 25/25 run after Nift `main` was current confirmed no suite or Nift
corrective change was warranted. The workflow prints the exact Nift commit and
`nift version` under test so any recurrence is immediately visible in the run
log.

## Layout

- `run-contract.sh`: resolves the candidate executable, creates disposable state,
  and runs all correctness modules, including config-declared project contracts.
- `legacy/`: accumulated historical and ruthless black-box suite; copied before
  execution because it intentionally mutates its fixture.
- `contract/`: focused executable-level modules previously mirrored near Nift.
- `benchmarks/`: optional performance/scaling/RSS guards, intentionally separate
  from correctness.
- `docs/handover/TESTING.md`: detailed contract-development guidance and history.
- `docs/handover/ROADMAP.md`: living suite/production-gate priorities.
- `docs/handover/CONTRACT-HISTORY.md`: detailed contract history and
  institutional context, including failure families, parameter
  interpolation coverage, and production-readiness responsibilities.

The current runner contains the historical/ruthless module plus 24 focused
contract modules, for 25 modules total. The focused layer now includes the v4.0.3
pagination and composable collection-operation contracts, the v4.0.4 long-running
filesystem-recovery contract, the 4.0.2 initializer/platform-target contract, the
v4.0.9 unreadable-source contract (unreadable content/@input/template must
fail with a "not readable" diagnostic and preserve the last successful output),
and the v4.0.10 six-form name-first `@json` and `@markup` directive contracts and the v4.0.11 comment/WPT/Snap-maintenance contract.
All legacy and focused `@json` assertions were migrated to the name-first syntax.
Treat counts as checkpoint facts, not the
quality claim.

## Running

```bash
NIFT_BIN=/absolute/path/to/nift ./run-contract.sh
# or
./run-contract.sh /absolute/path/to/nift
```

Performance entry points are documented by `run-performance.sh` and scripts in
`benchmarks/`. The suite includes both tracked-project load scaling and full-build
output scaling guards; preserve both because separate O(n²) regressions have
existed in those two paths. The source tree additionally carries a direct recovery-epoch
scan-count guard; this suite independently protects the same user-visible recovery
property through `contract/filesystem_recovery_smoke.sh`. Absolute timings and RSS depend on the host; correctness does not.

## Adding behavior

For a bug: reproduce externally, reduce, make deterministic, add the failing
regression, confirm the expected baseline failure, fix Nift separately, run the
focused family, then run the entire contract.

For a deliberate language change: specify the new external behavior first, retain
old tests unless the contract intentionally changes, record the rationale, and
test high-risk interactions rather than one happy path.

Every user-visible Nift behavior change must receive an explicit coverage
accounting before the checkpoint is considered complete: identify its
implementation-local tests and its independent black-box contract module. Add
both when both layers apply. If a layer genuinely cannot test the behavior,
record the reason in the checkpoint report rather than allowing omission by
silence. Confirm the new contract module is listed by `run-contract.sh`; a test
file that the canonical runner never executes is not coverage.

Tests should own machine-checkable behavior. This handover owns why the suite is
structured this way. Individual bugs generally belong in named fixtures/tests and
Git history unless they reveal a durable testing rule.

## Independence and synchronization

Focused modules currently also exist under Nift's implementation repository. The
standalone suite declares itself canonical for the external contract. Before
editing mirrored material, compare current copies and document/automate the
intended synchronization direction. Do not allow silent divergence or couple the
standalone runner to Nift internals for convenience.

## Checkpoint standard

A suite checkpoint can be valuable without source changes: new failure-family
coverage, deterministic fixtures, clearer failure localization, or contract
organization all improve evidence. Report the executable tested, baseline,
modules/assertions, new families, exact failures/skips, environment-sensitive
checks, and repository state.

## Public actions

Local suite changes and validation are authorized development. Do not commit,
push, tag, publish, or redefine public Nift behavior without explicit direction.

## Maintaining this handover

This is living project infrastructure. Review it when runner interfaces, suite
ownership, synchronization, fixture strategy, major failure families, or
production-gate responsibilities change. Correct and consolidate it over time;
do not append a diary. Every substantial checkpoint must review handover and
roadmap impact.

## Project-contract coverage

`contract/contracts_smoke.sh` is the implementation-independent executable contract for config-declared project contracts. It protects lazy JSON namespace resolution, dependency/config remapping, parameter/control-flow integration, collision/shadowing rejection, controlled failure diagnostics, and path containment. Keep it synchronized with the focused Nift source-tree copy without coupling it to Nift internals.

## v4.0.3 shorthand ternary follow-up (2026-08-19)

- The mirrored control-flow contract now covers `$[condition ? true-branch]`, including false-branch laziness and nested shorthand selection, alongside the full `$[condition ? true : false]` form.

## v4.0.3 exactly-once content reconciliation (2026-08-19)

The historical/ruthless fixture was reconciled with the deliberate v4.0.3 rule
that a templated tracked item must execute exactly one `@content` across its
executed template/`@input` graph. The old positive repeated-content fixture is no
longer treated as valid behavior; duplicate content is now an expected failure.
Function-name boundary probes that previously placed several `@content` calls in
one template are isolated into one-build-per-boundary cases so they still protect
tokenization without violating the new contract.

The parameter-interpolation contract also expects the current expression-aware
scalar-parameter diagnostic (`parameter expression must resolve to a scalar value`)
for array/object values. This is an intentional diagnostic reconciliation, not a
loosening of the parameter contract.


## Diagnostic rendering contract follow-up (2026-08-20)

- `contract/diagnostics_smoke.sh` independently protects source-location rendering for parser/build errors.
- The fixture deliberately places an invalid `@path('/assets/css/style.css')` after two leading tabs, then verifies that redirected/plain diagnostics expand tabs deterministically and align the `^` marker with the directive rather than a visually shifted source column.
- The contract also expects an underline spanning the offending call and preserves the existing path-containment diagnostic text. ANSI colour itself remains an implementation-level console test because the black-box contract runs with redirected stderr, where Nift must remain ANSI-free.
## v4.0.4 ternary string-literal regression follow-up (2026-08-20)

- The independent control-flow contract now protects the dogfood-found bug where selected quoted ternary branches leaked their source quote delimiters into rendered output.
- Coverage includes full/shorthand ternaries, true/false branches, single/double quotes, empty and escaped strings, inline HTML attributes, nested ternaries, literal directive-looking strings, selected directive execution and unselected dependency laziness.
- The contract deliberately preserves the existing distinction: quoted scalar branches render as values, while non-literal selected branches remain lazy Nift source.

## Nift v4.1 independent certification coverage (2026-09-15)

The v4.1 contract modules cover the surface added by the template-language
campaign and the defects found by the independent review:

- `v41_template_variables_smoke.sh`, `v41_language_smoke.sh`,
  `v41_operator_smoke.sh`, `v41_inject_dependency.sh` — the original v4.1
  black-box language/operator/injection-dependency contracts.
- `v41_certification_adversarial.sh` — protects the repaired language defects:
  mutation-flag scoping across callables/inject, conditional `@return`, `@for`
  loop-binding shadowing, undefined-callable errors, structured-binding array
  indexing, structured-literal callable/`validate()` arguments, inject
  declaration suppression and callable recursion bounds.
- `v41_duplicate_key_smoke.sh` — independent compatibility assertion that Nift
  rejects duplicate object keys in `.nift/config.json`, `@json`-loaded data,
  `$[x := {...}]` expression literals, inline `@json(name){...}` blocks and
  schema JSON. This guards the historical v4.0.13 contract that the Jsonic++
  v1.0.0 integration temporarily lost (its RFC-preserving default) and that
  Nift restores through its `nift_json::parse` policy wrapper.
