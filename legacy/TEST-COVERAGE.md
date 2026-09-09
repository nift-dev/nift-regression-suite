# Nift v4 regression-suite coverage

The project is both a browsable test website and a quiet shell regression suite. The supplied v0.5 source was compiled with its own Makefile before testing.

## Positive build website — 31 tracked pages

### Content / input
- direct `@content`
- `@content` reached through an `@input` partial
- repeated `@content`
- project-root `@input`
- relative `@input` from the currently read partial
- nested/recursive inputs
- filenames containing spaces
- quoted input filenames containing commas, parentheses and brackets
- indentation propagation through `@content`

### Function/parser boundaries
- `@content<...` before opening HTML
- `@content</...` before closing HTML
- lower-case function name termination before digits
- termination before `_`, `-`, `:`, and uppercase characters
- uppercase unknown function names remain literal
- literal escaping of `@`, `$`, and `#`
- unknown `@...` and unknown `$[...]` preservation
- comments
- `<pre>` / `<code>` behavior
- semicolon termination
- blank template behavior

### Paths / metadata / environment
- tracked-name `@path`
- root tracked path
- implicit `index.html` target
- direct existing-file `@path`
- direct path containing spaces
- deep nested path matrix
- self-referential tracked path calculation
- all 13 `$[...]` metadata values
- `$(title)` remains literal rather than metadata
- set and unset `@getenv`
- environment output is not recursively parsed as Nift
- every `@ent` mapping currently implemented

### Dependencies / build state
- `@dep` with multiple dependencies
- dependency recording in `.info.json`
- transitive `@input` dependency recording
- shared partial invalidation
- isolated content invalidation
- modified/hash/hybrid incremental modes
- custom content/output extensions
- generated-output permissions

## Expected parser/build failures
- missing `@input`
- input loop
- missing `@path`
- invalid parameter counts
- unknown `@ent`
- zero/missing `@dep`
- template DAG that never consumes content
- unclosed/orphan `<pre>`
- unclosed Nift comment forms
- backtick-quoted `@input` remains unsupported

## CLI / project-state tests
- `version`, `help/about`, `commands/cmds`
- `init` default scaffold; removed `init .html` / `init-html` diagnostics
- `status` display modes
- `info`, `info-all`, `info-names`, `info-tracking`, `info-watching`
- `track`
- `cp/copy`, including custom extensions
- `mv/move`, including custom extensions
- `untrack`, including multiple names
- `rm/del`
- `build`, `build-names`, `build-updated`, `build-all`
- progress/newline options
- invalid options
- project discovery from a nested working directory
- `watch`/`unwatch`
- watched-file auto-tracking/removal
- malformed persisted JSON should fail cleanly rather than abort
- tracked names must remain inside configured content/output roots

## Incremental / long-running tests
- shared dependency invalidates dependants but not unrelated output
- one content edit rebuilds only that output
- explicit dependency invalidation
- mtime-preserving edits: modified vs hash vs hybrid
- deleted output should be regenerated
- unchanged directory dependency should remain stable
- hash-mode `build-auto` should remain stable after multiple edits in one process

## Syntax strictness probes
These deliberately flag likely accidental grammar accepted through the generic parameter reader:
- `@input[...]`
- `@content[]`

If square brackets are intentionally supported for ordinary `@` functions, remove those two regression expectations.

## v0.5 expansion

Additional coverage includes:

- function-name termination at HTML, digits, punctuation and uppercase characters
- quoted `@input` filenames containing comma, parentheses, brackets and repeated spaces
- deeply nested `@path` calculations and direct files containing spaces
- environment values containing literal Nift-looking syntax (must not be reparsed)
- repeated `@content` use in one template
- whitespace before parameter delimiters and multiline formatted calls
- intentionally unsupported backtick quoting
- square-bracket generic-call syntax probes
- CLI aliases (`about`, `cmds`, `copy`, `move`, `del`) plus removed-init diagnostics
- custom extension preservation through copy/move/delete
- multi-name `untrack` and `rm`
- project discovery from nested working directories
- watch auto-track/removal reconciliation
- invalid CLI options
- empty tracking serialization
- JSON escaping in persisted tracked titles
- failure exit statuses for named/updated builds
- deleted-output incremental recovery
- directory dependencies
- malformed persistent JSON robustness
- tracked-name path traversal
- long-running hash-mode `build-auto`
- progress/display-option smoke tests


## v9 ruthless source-audit coverage

The v9 extension adds hostile black-box coverage for:

- duplicate/derived tracking path collisions such as `/` vs `index`;
- absolute/traversal path rejection across tracking and mutation commands;
- non-destructive `track`, `cp` and `mv` behaviour around existing untracked files;
- duplicate targeted build names and same-output concurrency hazards;
- `*.deps.json` invalidation and copy/move/remove lifecycle;
- sub-second modified-mode timestamp changes;
- a deliberately constructed collision for the former 32-bit FNV-1a dependency hash;
- tracking metadata changes (title/template/content/output mapping) as incremental rebuild causes;
- malformed stored hash/page-info state;
- duplicate JSON keys, invalid escapes, malformed surrogate pairs and non-finite numbers;
- lexical `@json` binding scope inside `@if`/`@for`;
- config/tracking validation including fractional thread counts and invalid extensions;
- strict CLI arity and surplus-argument rejection;
- corrupt watch bookkeeping, watched-source name collisions and whole watched-directory removal;
- large status/build summary behaviour and command timing output contracts;
- Makefile header dependency generation.
