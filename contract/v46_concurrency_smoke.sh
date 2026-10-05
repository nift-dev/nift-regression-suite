#!/usr/bin/env bash
# Independent black-box contract: v4.6 worker/concurrency hardening. Recoverable
# worker/future failures replay on repeated join/await; fatal worker failures
# bypass catch; nested pool progress completes; unobserved teardown is safe; and
# worker-owned file resources behave predictably.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Recoverable future/thread failures replay deterministically.
out=$("$NIFT_BIN" -e '
@fn[async](af()) { throw error("future-fail", "user.f") }
h := af()
try { await h } catch(e) { print(e.code + "|" + e.message + "|" + (e.source != "")) }
try { await h } catch(e) { print(e.code + "|" + e.message) }
fn(tf()) { throw error("thread-fail", "user.t") }
w := thread(tf)
try { w.join() } catch(e) { print(e.code + "|" + e.message) }
try { w.join() } catch(e) { print(e.code + "|" + e.message) }')
[ "$out" = $'user.f|future-fail|true\nuser.f|future-fail\nuser.t|thread-fail\nuser.t|thread-fail' ] || { echo "worker replay: $out" >&2; exit 1; }

# Fatal worker failures bypass catch.
fatal_worker(){
  if "$NIFT_BIN" -e "try { $1 } catch(e) { print(\"CAUGHT\") }" >"$t/o" 2>/dev/null; then echo "worker fatal succeeded: $1" >&2; exit 1; fi
  grep -q CAUGHT "$t/o" && { echo "worker fatal caught: $1" >&2; exit 1; } || true
}
fatal_worker 'fn[async](af()) { return 1 / 0 }; h := af(); await h'
fatal_worker 'fn(tf()) { return 1 / 0 }; thread(tf).join()'

# Nested async/thread pool progress completes.
out=$("$NIFT_BIN" -e '
@fn[async](child()) { return 42 }
@fn[async](parent()) { c := child(); return await c }
print(await parent())
fn(wf()) { return 9 }
@fn[async](af()) { t := thread(wf); return t.join() }
print(await af())')
[ "$out" = $'42\n9' ] || { echo "nested progress: $out" >&2; exit 1; }

# An unobserved async failure does not abort the program.
out=$("$NIFT_BIN" -e '@fn[async](af()) { throw error("x", "user.x") }; af(); print("alive")')
[ "$out" = 'alive' ] || { echo "unobserved teardown: $out" >&2; exit 1; }

# Worker-owned file resources complete within the worker.
out=$("$NIFT_BIN" -e 'fn(wf()) { o := ofstream("w.txt"); o.write("made"); o.close(); return 1 }; t := thread(wf); print(t.join()); print(open("w.txt"))')
[ "$out" = $'1\nmade' ] || { echo "worker resource: $out" >&2; exit 1; }

printf 'PASS v4.6 concurrency\n'
