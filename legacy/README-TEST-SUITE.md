# Nift v4 regression website — v0.5 adversarial pass

This project is derived from the supplied barebones Nift project and is designed to stress the current v4 parser, build graph, project persistence and CLI behaviour.

Run:

```sh
TERM=xterm NIFT_BIN=/path/to/nift ./scripts/run-tests.sh
```

The runner is intentionally quiet on success. It prints only failing assertions and a final PASS/FAIL summary.

The current suite contains:

- 31 positive tracked test pages
- 210 shell assertions/tests
- parser/function-name boundary tests
- nested/relative/special-filename `@input`
- deep tracked/direct `@path`
- all current metadata and `@ent` values
- literal/non-recursive environment output
- expected parser failures
- formatting/parameter edge cases
- CLI aliases and mutation commands
- watch/unwatch reconciliation
- malformed persistent-state probes
- path traversal probes
- dependency/incremental behaviour
- modified/hash/hybrid modes
- long-running hash-mode `build-auto` behaviour

Against the supplied `nift-stripped-v0.5`, the original 146-test suite passes completely. The expanded 210-test pass intentionally exposes new regression candidates; see `TEST-RESULTS-v0.5.md` and `KNOWN-ISSUES-v0.5.md`.

## v0.6 fresh adversarial expansion

The suite now contains **245 assertions/tests**. The original 211/211 baseline remains intact; tests 212+ come from a fresh source-audit/adversarial pass over stripped v0.6. See `NEW-FINDINGS-v0.6.md` for the new candidate/failure groups.
