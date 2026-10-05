#!/usr/bin/env bash
# Independent black-box contract: v4.6 runtime utilities. epoch()/sleep(),
# timer() stopwatch identity and state machine, secure_random_bytes() sizing and
# limits, and the restricted transfer/rendering boundaries of these values.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# epoch() returns an integer millisecond timestamp; sleep(ms) blocks and returns null.
[ "$("$NIFT_BIN" -e 'print(type(epoch()))')" = 'int' ]
"$NIFT_BIN" -e 'e := epoch(); if(e < 1000000000000) { throw error("epoch too small") }' >/dev/null
[ "$("$NIFT_BIN" -e 'print(type(sleep(0)))')" = 'null' ]

# Invalid time arguments are rejected.
reject(){ if "$NIFT_BIN" -e "$2" >/dev/null 2>"$t/e"; then echo "accepted: $2" >&2; exit 1; fi; grep -q "$1" "$t/e" || { echo "missing '$1' for: $2" >&2; cat "$t/e" >&2; exit 1; }; }
reject 'epoch: expected no arguments' 'epoch(1)'
reject 'sleep: expected one millisecond duration' 'sleep()'
reject 'sleep: expected one millisecond duration' 'sleep(1, 2)'
reject 'non-negative signed 64-bit integer' 'sleep(-1)'
reject 'non-negative signed 64-bit integer' 'sleep(0.5)'
reject 'non-negative signed 64-bit integer' 'sleep("1")'

# timer() baseline and state machine.
out=$("$NIFT_BIN" -e 't := timer(); print(type(t)); print(t.elapsed()); print(t.running()); print(t.paused()); print(type(t.start())); sleep(2); t.stop(); print(t.elapsed() >= 0); print(type(t.reset()))')
[ "$out" = $'timer\n0\nfalse\nfalse\nnull\ntrue\nnull' ] || { echo "timer baseline: $out" >&2; exit 1; }

out=$("$NIFT_BIN" -e '
t := timer()
t.start(); print(t.running()); print(t.paused())
t.pause(); print(t.running()); print(t.paused())
t.resume(); print(t.running()); print(t.paused())
t.stop(); print(t.running()); print(t.paused())
t.reset(); print(t.elapsed())')
[ "$out" = $'true\nfalse\nfalse\ntrue\ntrue\nfalse\nfalse\nfalse\n0' ] || { echo "timer state machine: $out" >&2; exit 1; }

# Timer identity is preserved across alias/copy/deepcopy; distinct timers differ.
out=$("$NIFT_BIN" -e '
t := timer(); alias := t; copied := copy(t); deep := deepcopy(t); other := timer()
print(alias == t && copied == t && deep == t); print(other != t)')
[ "$out" = $'true\ntrue' ] || { echo "timer identity: $out" >&2; exit 1; }

# Timers cannot be serialized or transferred to workers.
if "$NIFT_BIN" eval 'timer()' >/dev/null 2>"$t/e"; then echo "timer serialized" >&2; exit 1; fi
grep -q 'timer values are not serializable' "$t/e"
reject 'non-transferable timer' 'mutex(timer())'
reject 'non-transferable timer' 'fn(id(x)){return x}; thread(id, {"nested":[timer()]})'
reject 'non-transferable timer' 'fn(wt()){return timer()}; thread(wt).join()'

# secure_random_bytes() sizing, unpredictability, and hard limit.
out=$("$NIFT_BIN" -e 'e := secure_random_bytes(0); a := secure_random_bytes(32); b := secure_random_bytes(32); print(type(e)); print(e.size()); print(a.size()); print(a == b)')
[ "$out" = $'bytes\n0\n32\nfalse' ] || { echo "secure random: $out" >&2; exit 1; }
[ "$("$NIFT_BIN" -e 'print(secure_random_bytes(10000000).size())')" = '10000000' ]
reject 'expected one byte count' 'secure_random_bytes()'
reject 'expected one byte count' 'secure_random_bytes(1, 2)'
reject 'non-negative integer' 'secure_random_bytes(-1)'
reject 'non-negative integer' 'secure_random_bytes(0.5)'
reject 'exceeds 10000000 bytes' 'print(secure_random_bytes(10000001).size())'

printf 'PASS v4.6 runtime utilities\n'
