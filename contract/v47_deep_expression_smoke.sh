#!/usr/bin/env bash
# Independent black-box contract: deep-expression parser robustness (v4.7).
# A large flat binary chain must parse and evaluate; genuinely pathological
# syntactic nesting must fail with a controlled parser diagnostic, never a
# segfault / stack overflow. Externally observable via the CLI exit code and
# stderr only.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"
run(){ printf '%s\n' "$1" > p.f; "$NIFT_BIN" p.f; }
gen(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
op,term,n=sys.argv[1],sys.argv[2],int(sys.argv[3])
print(f" {op} ".join([term]*n))
PY
}

# Large flat binary chains evaluate correctly.
[ "$(run "x := $(gen + 1 10000)
print(x)")" = 10000 ] || { echo "flat + chain" >&2; exit 1; }
[ "$(run "x := $(gen '&&' true 10000)
print(x)")" = true ] || { echo "flat && chain" >&2; exit 1; }
[ "$(run "x := $(gen '||' true 10000)
print(x)")" = true ] || { echo "flat || chain" >&2; exit 1; }

# Deep paren nesting.
p=$(python3 -c 'print("("*8000+"7"+")"*8000)')
[ "$(run "x := $p
print(x)")" = 7 ] || { echo "paren nesting" >&2; exit 1; }

# True nesting up to 64 is supported.
[ "$(run "$(python3 -c 'print("print("+"!"*64+"true)")')")" = true ] || { echo "nesting 64" >&2; exit 1; }
[ "$(run "fn(id(x)) { return x }
print($(python3 -c 'print("id("*64+"1"+")"*64)'))")" = 1 ] || { echo "call nesting 64" >&2; exit 1; }

# Operator semantics preserved.
[ "$(run 'print(1 + 2 * 3 - 4)')" = 3 ] || { echo "precedence" >&2; exit 1; }
[ "$(run 'print(20 - 5 - 3)')" = 12 ] || { echo "associativity" >&2; exit 1; }
[ "$(run 'print("a" + -1)
print(1 - -2)')" = $'a-1\n3' ] || { echo "unary sign" >&2; exit 1; }

# Pathological nesting: controlled diagnostic, never a crash.
for src in "$(python3 -c 'print("x := "+"!"*5000+"true")')" "$(python3 -c 'print("fn(f(x)) { return x }")
print("x := "+"f("*5000+"1"+")"*5000)')"; do
  printf '%s\n' "$src" > p.f
  if "$NIFT_BIN" p.f >/dev/null 2>err; then echo "nesting unexpectedly succeeded" >&2; exit 1; fi
  rc=$?
  { [ "$rc" != 139 ] && [ "$rc" != 134 ]; } || { echo "nesting crashed (rc=$rc)" >&2; exit 1; }
  grep -qiE 'parser limit|nesting|too large' err || { echo "no controlled diagnostic: $(head -1 err)" >&2; exit 1; }
done

printf 'PASS v4.7 deep expression\n'
