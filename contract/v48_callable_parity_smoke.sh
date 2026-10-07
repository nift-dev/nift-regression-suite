#!/usr/bin/env bash
# Independent black-box contract: first-class callable value parity under
# prepared execution (v4.8). A named function is a valid value in ordinary
# execution (passed as an argument, stored in a variable, returned through
# identity/pass-through functions). Prepared loop/body and template (prepared)
# execution must preserve that callable identity rather than rejecting a bare
# function name. Lambdas travel correctly. Invalid callable usage (wrong
# arity, invoking a non-callable) still fails.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

ok(){ local name="$1" prog="$2" exp="$3"; out=$("$NIFT_BIN" -e "$prog" 2>&1); [ "$out" = "$exp" ] || { echo "FAIL $name: got [$out]" >&2; exit 1; }; }

# Ordinary baseline.
ok "named callable as argument" 'fn(g()) { return "hi" }
fn(call_it(f)) { return f() }
print(call_it(g))' "hi"
ok "named in variable + returned through identity" 'fn(g()) { return "hi" }
fn(identity_callable(f)) { return f }
f := identity_callable(g)
print(f())' "hi"
ok "pass-through multi-hop" 'fn(g()) { return "ok" }
fn(pass(f)) { return f }
fn(call(f)) { return f() }
print(call(pass(g)))' "ok"

# Prepared execution preserves the same callable semantics.
ok "callable argument inside for" 'fn(g()) { return "hi" }
fn(call_it(f)) { return f() }
for(i : [1, 2]) { print(call_it(g)) }' $'hi\nhi'
ok "callable argument inside while" 'i := 0
fn(g()) { return "hi" }
fn(call_it(f)) { return f() }
while(i < 2) { call_it(g); i = i + 1 }
print("done")' "done"
ok "callable multi-hop inside for" 'fn(g()) { return "ok" }
fn(pass(f)) { return f }
fn(call(f)) { return f() }
for(i : [1]) { print(call(pass(g))) }' "ok"
ok "lambda in prepared + returned callable later" 'fn(mk()) { return (x) => x + 1 }
for(i : [1]) { h := mk(); print(h(41)) }' "42"

# Throwing callables keep their behaviour through preparation.
ok "throwing callable ordinary" 'fn(bad()) { throw error("boom", "user.call") }
fn(call_it(f)) { return f() }
try { call_it(bad) } catch(e) { print(e.message) }' "boom"
ok "throwing callable prepared" 'fn(bad()) { throw error("boom", "user.call") }
fn(call_it(f)) { return f() }
for(i : [1]) { try { call_it(bad) } catch(e) { print(e.message) } }' "boom"

# Invalid callable usage is preserved.
reject(){ local name="$1" needle="$2" prog="$3"; if "$NIFT_BIN" -e "$prog" >o 2>e; then echo "FAIL $name accepted" >&2; exit 1; fi; grep -q "$needle" e || { echo "FAIL $name missing [$needle]: $(cat e)" >&2; exit 1; }; }
reject "wrong arity" 'callable argument count mismatch' 'fn(g()) { return "hi" }
fn(call_it(f)) { return f() }
for(i : [1]) { call_it(g, 1, 2) }'
reject "non-callable invocation" 'undefined callable: f' 'x := 5
fn(call_it(f)) { return f() }
for(i : [1]) { print(call_it(x)) }'

# Template execution: named function passed as value through another function
# and a template lambda variable.
mkdir -p site/.nift site/content site/templates
printf '%s' '{"config": {"content-dir": "content/", "output-dir": "public/", "default-template": "templates/template.html", "build-threads": -1}}' > site/.nift/config.json
printf '%s' '{"tracked": [{"name": "/", "title": "t", "template": "templates/template.html"}]}' > site/.nift/tracked.json
printf '%s\n' '<body>@content</body>' > site/templates/template.html
cat > site/content/index.html <<'E'
@fn(g()){ return "tpl-hi" }
@fn(pass(f)){ return f }
@fn(call_it(f)){ return f() }
$[H := pass(g)]
VIA_H=$[call_it(H)]
$[L := (x) => x + 1]
LAMBDA=$[L(1)]
E
( cd site && "$NIFT_BIN" build --all >/dev/null 2>&1 )
grep -q 'VIA_H=tpl-hi' site/public/index.html || { echo "FAIL template callable pass-through" >&2; exit 1; }
grep -q 'LAMBDA=2' site/public/index.html || { echo "FAIL template lambda" >&2; exit 1; }

printf 'PASS v4.8 callable parity\n'