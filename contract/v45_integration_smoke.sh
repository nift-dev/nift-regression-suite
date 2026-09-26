#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:-${NIFT:-nift}}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/main.f" <<'NIFT'
fn(add(a, b)) { return a + b }
@fn[async](work(x)) { return x * 2 }
print(cmd.ends_with("main.f"))
print(args.join(","))
print(platform())
t := thread(add, 20, 22)
f := work(21)
print(t.join())
print(await f)
m := mutex(0)
fn(inc(shared)) { shared.lock(); shared.set(shared.get() + 1); shared.unlock(); return true }
a := thread(inc, m)
b := thread(inc, m)
a.join(); b.join()
m.lock(); print(m.get()); m.unlock()
NIFT
out=$($NIFT --platform=android "$TMP/main.f" alpha beta)
[[ "$out" == $'true\nalpha,beta\nandroid\n42\n42\n2' ]] || {
  printf 'unexpected integration output:\n%s\n' "$out" >&2; exit 1;
}
[[ "$(printf 'print(cmd); print(args.length())\n' | "$NIFT" - one two)" == $'<stdin>\n2' ]]
[[ "$("$NIFT" -e 'print(cmd); print(args.join(","))' x y)" == $'<command-line>\nx,y' ]]
echo 'v4.5 integration smoke passed'
