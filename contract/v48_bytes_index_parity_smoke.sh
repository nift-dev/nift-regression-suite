#!/usr/bin/env bash
# Independent black-box contract: bytes variable/computed-index parity (v4.8).
# A bytes value must accept a computed (variable/expression) index everywhere an
# array does in ordinary and prepared execution; bounds/type errors are
# preserved. Externally observable through the CLI only.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"
run(){ printf '%s\n' "$2" > p.f; out=$("$NIFT_BIN" p.f 2>&1); [ "$out" = "$3" ] || { echo "FAIL $1: [$out]" >&2; exit 1; }; }
run "top-level variable index" 'b := bytes([10,20,30]); i := 1
print(b[i])' "20"
run "function parameter index" 'fn(f(v, j)) { return v[j] }
b := bytes([10,20,30])
print(f(b, 1))' "20"
run "loop body (prepared) index" 'b := bytes([10,20,30])
for(i : [1]) { print(b[i]) }' "20"
run "method-call argument index" 'b := bytes([10,20,30]); out := []
for(i : [0,1,2]) { out.push(b[i]) }
print(out.size())' "3"
run "assignment RHS index" 'b := bytes([10,20,30]); i := 1
x := b[i]
print(x)' "20"
run "array computed-index parity preserved" 'a := [10,20,30]; i := 1
print(a[i])' "20"

expect_fail(){ # <name> <needle> <program>
  local name="$1" needle="$2" prog="$3"
  printf '%s\n' "$prog" > p.f
  if "$NIFT_BIN" p.f >/dev/null 2>err; then echo "FAIL $name: accepted" >&2; exit 1; fi
  grep -q "$needle" err || { echo "FAIL $name missing [$needle]: $(cat err)" >&2; exit 1; }
}
expect_fail "bytes index out of range" "bytes index 9 is out of range" 'b := bytes([10,20,30]); i := 9
print(b[i])'
expect_fail "bytes index type error" "bytes indices must be non-negative integers" 'b := bytes([10,20,30]); i := "x"
print(b[i])'
expect_fail "array index out of range preserved" "is out of range" 'a := [10,20,30]; i := 9
print(a[i])'

# Template (prepared) execution.
mkdir -p site/.nift site/content site/templates
printf '%s' '{"config": {"content-dir": "content/", "output-dir": "public/", "default-template": "templates/template.html", "build-threads": -1}}' > site/.nift/config.json
printf '%s' '{"tracked": [{"name": "/", "title": "t", "template": "templates/template.html"}]}' > site/.nift/tracked.json
printf '%s\n' '<body>@content</body>' > site/templates/template.html
cat > site/content/index.html <<'E'
@fn(byte_at()){ b := bytes([10,20,30]); i := 1; return b[i] }
v=$[byte_at()]
E
( cd site && "$NIFT_BIN" build --all >/dev/null 2>err )
grep -q 'v=20' site/public/index.html || { echo "FAIL template bytes variable index: $(cat err)" >&2; exit 1; }

printf 'PASS v4.8 bytes indexing parity\n'