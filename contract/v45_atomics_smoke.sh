#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?set NIFT_BIN to the nift executable}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/atomics.f" <<'NIFT'
fn(add_many(x, n)) {
    i := 0
    while(i < n) { x.fetch_add(1); i += 1 }
    return true
}
fn(mark(flag)) { flag.store(true); return true }

x := atomic<int>(0)
a := thread(add_many, x, 750)
b := thread(add_many, x, 750)
c := async(add_many, x, 750)
d := async(add_many, x, 750)
a.join(); b.join(); await(c); await(d)
print(type(x))
print(x.load())
print(x.exchange(7))
print(x.fetch_add(5))
print(x.fetch_sub(2))
print(x.compare_exchange(10, 99))
print(x.load())

flag := atomic<bool>(false)
t := thread(mark, flag)
t.join()
print(type(flag))
print(flag.load())
print(flag.exchange(false))
print(flag.compare_exchange(false, true))
print(flag.load())
NIFT
out=$($NIFT_BIN "$TMP/atomics.f")
[[ "$out" == $'atomic<int>\n3000\n3000\n7\n12\ntrue\n99\natomic<bool>\ntrue\ntrue\ntrue\ntrue' ]] || { printf 'unexpected atomic contract output:\n%s\n' "$out" >&2; exit 1; }
echo 'v4.5 atomics contract passed'
