#!/usr/bin/env bash
# Independent black-box contract: v4.6 bounded long-line diagnostics. A failure
# on a very long (generated/minified) source line renders a bounded excerpt with
# the real message instead of emitting the whole line with a caret padded to the
# original column.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"
command -v python3 >/dev/null 2>&1 || { echo 'SKIP: python3 required for long-line fixture' >&2; exit 0; }

python3 -c "open('long.f','w').write('x := \"' + 'a'*20000 + '\"\nundefined_zzz()\n')"
err=$("$NIFT_BIN" long.f 2>&1 >/dev/null || true)
[ -n "$err" ] || { echo "no diagnostic emitted" >&2; exit 1; }
printf '%s' "$err" | grep -q 'undefined callable' || { echo "message lost: $err" >&2; exit 1; }
size=$(printf '%s' "$err" | wc -c)
[ "$size" -lt 4096 ] || { echo "diagnostic not bounded: $size bytes" >&2; exit 1; }

printf 'PASS v4.6 diagnostics\n'
