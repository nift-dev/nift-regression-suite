#!/usr/bin/env bash
# Independent contract: an unrecognized bare single-token command in nift sh
# falls through to ordinary external executable/PATH resolution (fastfetch, git,
# env, printf, ...), while Nift bindings/functions/builtins keep precedence and
# --no-process stays authoritative. Script-land command-style (word + args)
# also resolves on PATH. Deterministic fixture executable on a temporary PATH.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
case "$NIFT_BIN" in /*) NIFT_ABS="$NIFT_BIN";; *) NIFT_ABS="$(pwd)/$NIFT_BIN";; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
cat > "$t/bin/fixtool" <<'B'
#!/bin/sh
echo "fixtool-ran $1"
B
chmod +x "$t/bin/fixtool"

# bare single token resolves on PATH
out=$(cd "$t" && printf 'fixtool\n' | PATH="$t/bin:$PATH" "$NIFT_ABS" sh 2>/dev/null)
grep -q 'fixtool-ran' <<<"$out" || { echo "$out" >&2; exit 1; }
# Nift precedence: true is a boolean value, a binding shadows an external name
out=$(printf 'true\n' | "$NIFT_ABS" sh 2>/dev/null)
grep -qE '(^| )true$' <<<"$out" || { echo "$out" >&2; exit 1; }
out=$(printf 'fixtool := "shadowed"\nfixtool\n' | "$NIFT_ABS" sh 2>/dev/null)
grep -q '"shadowed"' <<<"$out" || { echo "$out" >&2; exit 1; }
# nonexistent command is reported
out=$(printf 'nonexistentcmdxyz\n' | "$NIFT_ABS" sh 2>&1)
grep -q 'command not found: nonexistentcmdxyz' <<<"$out" || { echo "$out" >&2; exit 1; }
# --no-process rejects the external fallback
if printf 'fixtool\n' | PATH="$t/bin:$PATH" NIFT_NO_PROCESS=1 "$NIFT_ABS" sh 2>/dev/null | grep -q 'fixtool-ran'; then echo "ran under --no-process" >&2; exit 1; fi
# script-land command-style (word + args) resolves on PATH
cat > "$t/cc.f" <<'NIFT'
fixtool one
fixtool one two three
print("cc-done")
NIFT
out=$(cd "$t" && PATH="$t/bin:$PATH" "$NIFT_ABS" run cc.f)
grep -q 'fixtool-ran one' <<<"$out" || { echo "$out" >&2; exit 1; }
grep -q '^cc-done$' <<<"$out" || exit 1
printf 'PASS v4.4 shell bare-command external fallback\n'
