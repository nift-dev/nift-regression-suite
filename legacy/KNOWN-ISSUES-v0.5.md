# Regression findings against `nift-stripped-v0.5`

The main positive website builds successfully. The shell suite deliberately remains red while the behaviours below are reproducible.

## Confirmed/high-confidence bugs

### Parameter whitespace is retained after a quoted value
Calls such as:

```text
@input("templates/child.html" )
@path("/" )
@ent("!" )
@getenv("NIFT_TEST_VALUE" )
@dep("a.txt" , "b.txt" )
```

retain the whitespace between the closing quote and comma/closing parenthesis in the parsed parameter. `read_params()` calls `skip_whitespace()` only after the whitespace has already been appended to `param`, and `unquote()` therefore no longer sees matching quotes at the two ends.

The same issue breaks normally formatted multiline calls such as:

```text
@input(
    "templates/child.html"
)
```

This affects multiple public functions through the shared parameter reader.

### First build after `watch` fails
`WatchList::save()` creates `watched.json` and the per-directory `exts.json`, but does not create the per-directory `tracked.json`. `ProjectInfo::check_watch_dirs()` immediately parses that missing file as JSON, so the first subsequent `build` fails with:

```text
watching tracked file is not a valid json document
```

### `rm` with multiple names repeatedly uses the first name
The dispatcher loops over arguments but pushes `argv[2]` each time instead of `argv[i]`.

### Saving an empty tracking set corrupts `tracked.json`
`save_tracking()` seeks backwards to remove a trailing comma even when there were no tracked entries. Untracking all initial entries therefore produces invalid JSON.

### Tracking a title containing `"` can corrupt `tracked.json`
`save_tracking()` writes strings directly inside JSON quotes without escaping them. The CLI validation only rejects values containing both quote types, so a title containing only `"` is accepted and then makes invalid JSON.

### Targeted builds do not propagate failure status
`ProjectInfo::build_names()` reports failed/untracked requested names but returns `0`. This affects both a requested untracked name and a parser failure in a specifically requested tracked page.

### `build-updated` does not propagate a build failure
An updated tracked page can fail during parsing/building while the top-level command still exits successfully.

### Deleted generated output can be considered up-to-date
After a successful build, deleting a generated output while leaving its `.nift` info/dependency state intact does not necessarily cause `build-updated` to recreate the missing file.

### Directory `@dep` is internally inconsistent
The parser accepts dependencies using `path_exists()`, which permits directories, but incremental dependency checking treats the directory as absent/removed, causing an unchanged directory dependency to trigger rebuilding.

### Malformed persistent JSON can abort the process
Several malformed-but-parseable structures reach unchecked RapidJSON accessors and trigger assertions rather than controlled Nift errors. Reproductions are included for:
- a non-object member inside `tracked.json`'s `tracked` array;
- malformed `.nift/.watch/watched.json`;
- malformed watched-directory `exts.json`.

### Hash-mode `build-auto` can rebuild forever after a later edit
A long-running `build-auto -s` in `hash` mode handles the first change, but after a later change it can repeatedly classify the same content dependency as modified and rebuild on every poll.

## Syntax / policy candidates for you to decide

### Generic `@` calls accept square brackets
The shared parser accepts `@input[...]` and `@content[]` even though the public v4 syntax uses parentheses and `$[...]` owns the square-bracket form. The suite treats these as failures so you can decide whether to tighten v4 syntax.

### `build-names` accepts unknown options / option-only calls
Any leading `-...` token is skipped as though it were an option. Unrecognised options fall through to a default build mode, and an option can be supplied without any names.

### Tracked names can contain `../`
`track ../escape ...` is currently accepted, allowing content/output paths derived from a tracked name to escape their configured roots. The suite treats this as an unsafe-name candidate.

## Confirmed v0.5 fix from the previous suite

The simplified lower-case-only function-name parser fixes the `@content<...` boundary problem. Tests now cover `<`, closing tags, HTML comments, digits, `_`, `-`, `:`, uppercase suffixes and uppercase function names.
