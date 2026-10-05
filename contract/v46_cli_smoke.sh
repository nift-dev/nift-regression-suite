#!/usr/bin/env bash
# Independent black-box contract: v4.6 CLI command surface. Unified script
# invocation (plain nift REPL, `nift file.f`, `-e`/`-c`/`-i`/`-`, `eval`),
# `commands` aliases, the package command group, and the explicit removal of the
# old `run`/`sh`/`path` commands and historical build/info verbs.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Version reports the expected candidate version (release-aware input) or, when
# no expectation is supplied, a well-formed semantic version.
ver=$("$NIFT_BIN" version)
if [ -n "${NIFT_EXPECT_VERSION:-}" ]; then
  [ "$ver" = "Nift v${NIFT_EXPECT_VERSION#v}" ] || { echo "version: $ver (expected v${NIFT_EXPECT_VERSION#v})" >&2; exit 1; }
else
  printf '%s' "$ver" | grep -Eq '^Nift v[0-9]+\.[0-9]+\.[0-9]+$' || { echo "version not semantic: $ver" >&2; exit 1; }
fi

# commands/cmds/--help/-h are equivalent and exclude removed verbs.
for form in commands cmds --help -h; do
  "$NIFT_BIN" "$form" >"$t/c" 2>&1 || { echo "nift $form failed" >&2; exit 1; }
  grep -q 'build \[names...\]' "$t/c" || { echo "nift $form missing build" >&2; exit 1; }
  grep -q 'packages' "$t/c" || { echo "nift $form missing packages" >&2; exit 1; }
  grep -qE '^\s+run\b|^\s+sh\b' "$t/c" && { echo "nift $form lists removed verb" >&2; exit 1; } || true
done

# Unknown / removed top-level commands are explicit fatal diagnostics.
for name in help run sh path; do
  if "$NIFT_BIN" "$name" >/dev/null 2>"$t/e"; then echo "nift $name unexpectedly succeeded" >&2; exit 1; fi
  grep -q "unknown command '$name' and path does not exist" "$t/e" || { echo "$name diagnostic: $(cat "$t/e")" >&2; exit 1; }
done
if "$NIFT_BIN" build-all >/dev/null 2>"$t/e"; then echo "build-all unexpectedly succeeded" >&2; exit 1; fi
grep -q "command 'build-all' has been removed" "$t/e"

# Inline, alias, stdin and REPL execution.
[ "$("$NIFT_BIN" -e 'print(1 + 1)')" = '2' ]
[ "$("$NIFT_BIN" -c 'print(2 + 2)')" = '4' ]
[ "$(printf 'print(3 + 3)\n' | "$NIFT_BIN" -)" = '6' ]
[ "$(printf 'print(5)\nexit\n' | "$NIFT_BIN")" = '5' ]

# eval prints values; failures use exit 2 and the `eval:` prefix.
[ "$("$NIFT_BIN" eval '1 + 2')" = '3' ]
if "$NIFT_BIN" eval '1 / 0' >/dev/null 2>"$t/e"; then echo "eval 1/0 succeeded" >&2; exit 1; fi
grep -q '^eval: ' "$t/e"

# eval --capabilities prints the exact capability contract.
caps=$("$NIFT_BIN" eval --capabilities)
[ "$caps" = '{"command":"eval","contract":1,"json_output":true,"project_context":true,"value_methods":["keys","values","entries","has","get","merge","map","filter","find","find_index","sort_by","unique","flatten","sum","min","max","group_by"]}' ] || { echo "capabilities: $caps" >&2; exit 1; }

# Script `cmd`/`args` identity values: -e is <command-line>, stdin is <stdin>,
# and a file reports its own script path.
printf 'print(cmd)\n' > idfile.f
[ "$("$NIFT_BIN" -e 'print(cmd)')" = '<command-line>' ]
[ "$(printf 'print(cmd)\n' | "$NIFT_BIN" -)" = '<stdin>' ]
[ "$("$NIFT_BIN" idfile.f)" = 'idfile.f' ]

printf 'PASS v4.6 CLI\n'
