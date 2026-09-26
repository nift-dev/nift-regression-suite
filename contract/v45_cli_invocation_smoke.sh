#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?set NIFT_BIN}
case "$NIFT_BIN" in /*) BIN="$NIFT_BIN";; *) BIN="$(cd "$(dirname "$NIFT_BIN")" && pwd)/$(basename "$NIFT_BIN")";; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
printf 'print("direct")\n' > "$t/hello.f"
[ "$("$BIN" "$t/hello.f")" = "direct" ]
out=$(printf 'x := 9\nx\nexit\n' | "$BIN")
grep -qx '9' <<<"$out"
if "$BIN" run "$t/hello.f" >"$t/run.out" 2>&1; then exit 1; fi
grep -q "unknown command 'run' and path does not exist" "$t/run.out"
if "$BIN" sh >"$t/sh.out" 2>&1; then exit 1; fi
grep -q "unknown command 'sh' and path does not exist" "$t/sh.out"
echo 'PASS v4.5 unified CLI invocation contract'
