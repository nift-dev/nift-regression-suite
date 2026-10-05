#!/usr/bin/env bash
# Independent black-box contract: v4.6 execution-scoped output channels.
# err(value) writes one value per line to stderr with the same value rules as
# print(value) on stdout; the two channels stay separate, including from worker
# threads and async functions.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

"$NIFT_BIN" -e 'print("out"); err("problem")' >"$t/o" 2>"$t/e"
[ "$(cat "$t/o")" = 'out' ] || { echo "stdout: $(cat "$t/o")" >&2; exit 1; }
[ "$(cat "$t/e")" = 'problem' ] || { echo "stderr: $(cat "$t/e")" >&2; exit 1; }

# err() returns null and itself renders null.
out=$("$NIFT_BIN" -e 'print(type(err("x")))' 2>/dev/null)
[ "$out" = 'null' ] || { echo "err return: $out" >&2; exit 1; }

# err obeys the same value rules as print.
reject(){ # <stderr-substring> <program>
  if "$NIFT_BIN" -e "$2" >"$t/o" 2>"$t/e"; then echo "accepted: $2" >&2; exit 1; fi
  grep -q "$1" "$t/e" || { echo "missing '$1' for: $2" >&2; cat "$t/e" >&2; exit 1; }
}
reject 'err: expected one value' 'err()'
reject 'err: bytes values cannot be rendered as text' 'err("x".encode("utf-8"))'
reject 'err: value is not directly renderable' 'err([1,2])'

# Worker and async output reach the process streams, one line each.
out=$("$NIFT_BIN" -e 'fn(worker()) { print("thread-out"); err("thread-err"); return 1 }; t := thread(worker); print(t.join()); @fn[async](future()) { print("async-out"); err("async-err"); return 2 }; f := future(); print(await f)' 2>"$t/e" >"$t/o")
grep -qx 'thread-out' "$t/o" || { echo "missing thread stdout" >&2; exit 1; }
grep -qx 'async-out' "$t/o" || { echo "missing async stdout" >&2; exit 1; }
grep -qx 'thread-err' "$t/e" || { echo "missing thread stderr" >&2; exit 1; }
grep -qx 'async-err' "$t/e" || { echo "missing async stderr" >&2; exit 1; }

printf 'PASS v4.6 output channels\n'
