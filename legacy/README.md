# Nift deep regression test suite — v9

This is the current black-box regression suite for Nift, validated against the v1.0.15 C++ implementation.

The suite combines the long-running historical regression baseline with a source-audit-driven ruthless adversarial layer. It intentionally tests the compiled executable through real projects, files, persistent state and CLI invocations rather than relying only on isolated unit tests.

## Running

```bash
NIFT_BIN=/path/to/nift ./scripts/run-tests.sh
```

The historical suite contains mtime-sensitive and long-running `build-auto` cases, so a complete run takes materially longer than ordinary unit tests.

## Ruthless adversarial extension

Version 12 adds JSON Schema validation, loop metadata and stable `@for(... by ... asc|desc)` sorting coverage. The historical main regression runner contains **386 checks**, and the ruthless source-audit/adversarial extension now contains **178 checks**, for **556 black-box checks** across the two layers. The new v12 feature-specific adversarial extension passes 178/178 against rewrite v1.0.18; the long-running 386-check main layer remains the established baseline and is kept separate from that fresh result.

`scripts/ruthless-adversarial.sh` adds hostile cases that happy-path suites tend to miss, including:

- duplicate and derived content/output path collisions;
- non-destructive `track`, `cp` and `mv` behaviour;
- dependency-sidecar invalidation and copy/move/remove lifecycle;
- sub-second modified-mode incremental changes;
- a deliberately constructed collision for Nift's former 32-bit FNV-1a dependency hash;
- malformed JSON, duplicate keys, numeric overflow and Unicode/surrogate errors;
- lexical JSON binding scope inside `@if` / `@for`;
- corrupt watch bookkeeping, watched-name collisions and complete watched-directory removal;
- strict CLI arity and configuration/tracking validation;
- title/template/content/output metadata changes forcing incremental rebuilds;
- large `status` / build summary behaviour and timing-output contracts.

Raw check counts are not presented here as a quality score. Many numbered cases validate several independent outcomes; the useful measure is the breadth and specificity of the behaviours and historical bug reproductions that remain permanently covered.



### Requirements coverage

The ruthless extension verifies that ordinary `@path(...)` targets are persisted as internal `reqs`: modifying a req alone does not invalidate a page; deleting it marks the page for rebuilding; a changed template/content file can then remove the broken reference and rebuild successfully; if the source still references the missing target, failure comes from the ordinary `@path` parser error. Tracked outputs are also recorded as reqs. There is no public `@req` directive or `*.reqs.json` sidecar.
