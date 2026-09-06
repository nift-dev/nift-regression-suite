# Nift v4 Contract Regression Suite

This is the canonical **implementation-independent** regression suite for the
Nift v4 contract. The current development executable targets Nift 4.0.12.

It does **not** compile or include Nift implementation source. Point it at any
candidate Nift executable:

```bash
NIFT_BIN=/path/to/nift ./run-contract.sh
# or
./run-contract.sh /path/to/nift
```

## What "contract" means here

Tests exercise Nift from the outside:

- CLI commands and exit status;
- project config/tracking formats;
- template language behavior;
- content/input/path/metadata semantics;
- JSON, JSON Schema, loops/conditions and dependency behavior;
- incremental modified/hash/hybrid behavior;
- watch/tracking/path safety and persistence behavior;
- internal page metadata only where its observable persistence contract matters;
- opt-in minification behavior through Nift's public configuration/CLI contract.

The suite deliberately does **not** call C++ classes/functions, include Nift
headers, rely on private object layout, or require a particular internal
algorithm. A different Nift implementation should pass if it implements the
same externally observable contract.

## Layers

`legacy/` contains the accumulated historical + ruthless black-box suite
(the accumulated historical/ruthless assertions against the 4.0.2 development checkpoint).
Every `@json` assertion in it was migrated from the retired path-first syntax to
the current name-first contract; the full historical module passes against the
reviewed 4.0.10 candidate.

`contract/` contains the later focused executable-level contract modules that
were previously kept beside the Nift source tree.

`contract/parameter_interpolation_smoke.sh` is the 73-check contract for `$[...]`
interpolation in textual `@function(...)` parameters. It was written red before
implementation and now passes with the other focused modules. Its history
preserves that test-first checkpoint. It was migrated to the name-first `@json`
contract along with the rest of the suite.

`contract/json_six_forms_smoke.sh` is the black-box contract for the six
name-first `@json` forms: `@json(name, path)`, `@json(name, schema-path, path)`,
`@json(name, schema-name, path)` and the three inline forms. It also covers
inline templating, named-schema reuse, immutable binding and failed-validation
non-binding, collisions, the schema-name-versus-schema-path disambiguation
(quoted arguments are paths; bare identifiers are existing binding names and
never fall back to files), lazy branches, loop scope, path safety and
incremental data/schema invalidation.

`contract/markup_directives_smoke.sh` is the black-box contract for `@markup`
inline and file-backed conversion of Markdown, AsciiDoc and reStructuredText,
their long aliases, template-before-conversion and the no-second-pass guarantee,
JSON and loop bindings inside markup, include dependency recording and
invalidation, unknown-format/missing-source/traversal/cycle failures, and brace
handling in Markdown code spans and fenced blocks.

`contract/filesystem_recovery_smoke.sh` protects the long-running recovery contract:
a dead-owner transactional temp created after an earlier build-pass scan may remain
while `build-auto` is idle, but must be removed on the next relevant output pass
without restarting Nift; live-owner temps remain protected. The test is shaped to
fail the previous once-per-process cleanup implementation.

`contract/template_optional_smoke.sh` protects the externally observable
template-less tracked-entry contract: parsed direct content, compatibility with
the historical empty-string form, templated/template-less dependency replacement,
and scaffold output.

`contract/init_targets_smoke.sh` protects the 4.0.2 initializer contract: the
zero-argument HTML default, explicit generic extensions, PHP/neutral starter
families, all named platform targets, target-extension rejection, generated
provider files, and the deliberate removal diagnostics for positional extensions
and `init-html`.

`benchmarks/` contains optional scaling/performance/RSS regression guards.
`full_build_scaling_benchmark.py` specifically protects full-build output work
from superlinear per-file filesystem behavior; it was added after transactional
stale-temp recovery accidentally made flat full builds O(n²). Performance is
kept separate from correctness because absolute timings and RSS are
machine/platform dependent.

Implementation-level C++ tests (for example direct JSON/JSON-Schema unit tests)
remain with the Nift source repository and are intentionally not duplicated
here, because those tests validate one implementation rather than the Nift
contract.

### Project contracts

The canonical runner includes `contract/contracts_smoke.sh`, covering config-declared project-wide JSON contracts, namespace collision rules, lazy loading, incremental dependency/config remapping, and controlled failures.
