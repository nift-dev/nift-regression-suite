#!/usr/bin/env bash
# Independent black-box contract: prepared equality / comparison parity (v4.8).
# Equality must be one canonical deep semantics regardless of where it runs:
# ordinary top-level expressions, assignment RHS, return expressions, and
# script-level if/while conditions all accept the same == and != values
# (arrays, objects, bytes, scalars, nested collections). Precomputed equality
# and direct conditions are interchangeable. Ordering stays numbers/strings
# only: array and object ordering remains invalid everywhere.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

ok(){ local name="$1" prog="$2" exp="$3"; out=$("$NIFT_BIN" -e "$prog" 2>&1); [ "$out" = "$exp" ] || { echo "FAIL $name: got [$out]" >&2; exit 1; }; }

# Ordinary deep equality is the baseline.
ok "ordinary array == object != bytes literal" \
  'print([1,2] == [1,2]); print({"a":1} != {"a":1}); print(bytes([1,2]) == bytes([1,2]))' \
  $'true\nfalse\ntrue'

# Direct if conditions on collections agree with ordinary equality.
ok "direct if array == and !=" 'if([1,2] == [1,2]) { print("a_eq") }
if([1,2] != [1,3]) { print("a_ne") }' $'a_eq\na_ne'
ok "direct if object == and !=" 'if({"k":1} == {"k":1}) { print("o_eq") }
if({"k":1} != {"k":2}) { print("o_ne") }' $'o_eq\no_ne'
ok "direct if bytes == and !=" 'if(bytes([10,20]) == bytes([10,20])) { print("b_eq") }
if(bytes([10]) != bytes([1])) { print("b_ne") }' $'b_eq\nb_ne'
ok "direct if nested collection ==" 'if([[1,[2]],{"k":[3]}] == [[1,[2]],{"k":[3]}]) { print("n_eq") }' "n_eq"
ok "direct if scalars" 'if(null == null) { print("nl") }
if(true == true) { print("bl") }
if(3 == 3) { print("in") }
if(1.5 == 1.5) { print("fl") }
if("a" == "a") { print("st") }' $'nl\nbl\nin\nfl\nst'
ok "numeric coercion parity" 'if(3 == 3.0) { print("num") }
print(3 == 3.0)' $'num\ntrue'
ok "mismatched types are unequal" 'if([1,2] == 1) { print("x") } else { print("ui") }
if(1 == "1") { print("y") } else { print("us") }' $'ui\nus'

# Precomputed equality is interchangeable with the direct condition form.
ok "precomputed/direct parity" 'a := [1,2]
pre := a == [1,2]
if(pre != (a == [1,2])) { print("mismatch") } else { print("match") }' "match"

# Function and loop condition parity.
ok "function condition parity" 'fn(f(x)) { return x == [1,2] }
fn(g()) { if(f([1,2])) { return "yes" } return "no" }
print(g())' "yes"
ok "while/prepared for parity" 'i := 0
while([1,2] == [1,2] && i < 1) { i += 1 }
print(i)
for(i : [0]) { if([1,2] == [1,2]) { print("loop") } }' $'1\nloop'

# Invalid ordered comparisons stay rejected (ordering is not broadened).
reject(){ local name="$1" needle="$2" prog="$3"; if "$NIFT_BIN" -e "$prog" >o 2>e; then echo "FAIL $name accepted" >&2; exit 1; fi; grep -q "$needle" e || { echo "FAIL $name missing [$needle]: $(cat e)" >&2; exit 1; }; }
reject "array ordering rejected" 'ordering comparisons require two numbers or two strings' 'if([1] < [2]) { print("x") }'
reject "object ordering rejected" 'ordering comparisons require two numbers or two strings' 'if({"a":1} > {"a":0}) { print("x") }'

# Template (prepared) execution renders direct collection equality conditions.
mkdir -p site/.nift site/content site/templates
printf '%s' '{"config": {"content-dir": "content/", "output-dir": "public/", "default-template": "templates/template.html", "build-threads": -1}}' > site/.nift/config.json
printf '%s' '{"tracked": [{"name": "/", "title": "t", "template": "templates/template.html"}]}' > site/.nift/tracked.json
printf '%s\n' '<body>@content</body>' > site/templates/template.html
cat > site/content/index.html <<'E'
@if([1,2] == [1,2]){A_EQ}
@if([1,2] != [1,3]){A_NE}
@if({"k":[1,2]} == {"k":[1,2]}){O_EQ}
@if(bytes([10,20]) == bytes([10,20])){B_EQ}
E
( cd site && "$NIFT_BIN" build --all >/dev/null 2>&1 )
for mark in A_EQ A_NE O_EQ B_EQ; do
  grep -q "$mark" site/public/index.html || { echo "FAIL template missing $mark" >&2; exit 1; }
done
# Invalid ordering still fails template builds.
printf '@if([1] < [2]){BAD}\n' > site/content/index.html
if ( cd site && "$NIFT_BIN" build --all >/dev/null 2>&1 ); then echo "FAIL template accepted invalid ordering" >&2; exit 1; fi

printf 'PASS v4.8 comparison parity\n'