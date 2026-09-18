#!/usr/bin/env bash
# Independent black-box contract for the CP204-CP213 final language tranche:
# type()/is_*(), ??, ?. / ?[], destructuring, range and enums, plus the
# interactions the independent review hardened (??/?./?[] in templates,
# safe-access ?? ordering, ternary parity, destructuring duplicates, empty
# enums). Exercises the nift executable only.
set -euo pipefail
: "${NIFT_BIN:?}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
run(){ printf '%s\n' "$1" > "$T/t.nift"; "$NIFT_BIN" run "$T/t.nift"; }
must_error(){ printf '%s\n' "$1" > "$T/e.nift"; if "$NIFT_BIN" run "$T/e.nift" >/dev/null 2>&1; then echo "expected error: $1" >&2; return 1; fi; }

# --- type() / is_*() ---
[[ "$(run 'print(type(null));print(type(true));print(type(1));print(type(1.5));print(type("x"));print(type([1]));print(type({"a":1}));print(type(42.0))')" == $'null\nbool\nint\nfloat\nstring\narray\nobject\nint' ]]
[[ "$(run 'print(is_null(null));print(is_number(1));print(is_int(1));print(is_float(1.5));print(is_string("x"));print(is_array([1]));print(is_object({"a":1}));print(is_enum(null))')" == $'true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse' ]]
must_error 'print(is_defined(null))'
must_error 'print(has_value(null))'

# --- ?? --- (lazy, null-only, chains)
[[ "$(run 'print(null ?? 7);print(3 ?? missing_name);print(false ?? 7);print(0 ?? 7);print("" ?? 7)')" == $'7\n3\nfalse\n0' ]]
[[ "$(run 'print(null ?? null ?? 7)')" == 7 ]]
[[ "$(run 'd := {"x":1}
print(d.x ?? 7)')" == 1 ]]

# --- ?. / ?[] --- (null propagation only, errors survive)
[[ "$(run 'print(null?.x);print(null?["x"]);print({"x":1}?.x);print({"x":2}?["x"]);print({"x":null}?.x)')" == $'null\nnull\n1\n2\nnull' ]]
must_error 'print({}?.typo)'
must_error 'print(42?.x)'
must_error 'post := {"title":"x"}
print(post?.titel)'
# ordering: a?.b ?? c applies ?? after safe access
[[ "$(run 'd := null
print(d?.x ?? 7)')" == 7 ]]
[[ "$(run 'd := {"a":{"b":5}}
print(d?.a?.b ?? 9)')" == 5 ]]
[[ "$(run 'd := null
print(d?.a?.b ?? 9)')" == 9 ]]

# --- ?? / ?. / ?[] and ternary work in TEMPLATES ---
T2="$T/proj"
mkdir -p "$T2/.nift" "$T2/content" "$T2/templates" "$T2/public"
printf '%s' '{"config":{"content-dir":"content/","content-ext":".md","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":-1,"incremental-mode":"modified"}}' > "$T2/.nift/config.json"
printf '%s' '{"tracked":[{"name":"/","title":"Home","template":"templates/template.html"}]}' > "$T2/.nift/tracked.json"
printf '# Home\n' > "$T2/content/index.md"
printf 'A$[null ?? 7]B$[3 ?? 7]C$[null?.x]D$[{"x":1}?.x]E$[true ? "y" : "n"]F$[null?.a?.b ?? 9]G@content' > "$T2/templates/template.html"
(cd "$T2" && "$NIFT_BIN" build --all >/dev/null 2>&1)
grep -q 'A7B3CnullD1EyF9G# Home' "$T2/public/index.html"
printf 'A$[{}?.missing]B@content' > "$T2/templates/template.html"
if (cd "$T2" && "$NIFT_BIN" build --all >/dev/null 2>&1); then echo "template safe access should error" >&2; exit 1; fi

# --- ternary works in run/eval (parity with templates) ---
[[ "$(run 'print(true ? "a" : "b");print(false ? "a" : "b");print([1,2].contains(2) ? "y" : "n")')" == $'a\nb\ny' ]]
[[ "$("$NIFT_BIN" eval '1 == 1 ? "y" : "n"')" == y ]]

# --- destructuring ---
[[ "$(run '[a,b] := [1,2]; print(a); print(b); [a,b] = [3,4]; print(a); print(b)')" == $'1\n2\n3\n4' ]]
[[ "$(run '{heading,date} := {"heading":"Nift","date":2026,"extra":1}; print(heading); print(date)')" == $'Nift\n2026' ]]
[[ "$(run '{a} := {"a":null}; print(a == null)')" == true ]]
# destructuring validates the full pattern/RHS before mutating bindings;
# a failing assignment is rejected outright (abort-on-error model)
must_error 'a := 1; b := 2; [a,b] = [3,4,5]'
must_error '[a,b] := [1]'
must_error '{a,b} := {"a":1}'
must_error '[a,a] := [1,2]'
must_error '[a] := "x"'
must_error '{a,[b]} := {"a":1}'

# --- range ---
[[ "$(run 'print(range(5).join(","));print(range(2,6).join(","));print(range(0,10,2).join(","));print(range(10,0,-2).join(","))')" == $'0,1,2,3,4\n2,3,4,5\n0,2,4,6,8\n10,8,6,4,2' ]]
[[ "$(run 'print(range(6,2).empty());print(range(0).empty());print(range(1).join(","));print(range(-2,2).join(","))')" == $'true\ntrue\n0\n-2,-1,0,1' ]]
[[ "$(run 'print(range(1000000).size())')" == 1000000 ]]
must_error 'print(range(0,5,0))'
must_error 'print(range(2.5))'
must_error 'print(range(0,20000000))'

# --- enums ---
cat > "$T/e.nift" <<'NIFT'
enum State { Draft, Live = 10, Archived }
enum Code { OK = 200, Created, Missing = 404 }
print(State.Draft); print(State.Live.to_int()); print(State.Archived.to_int()); print(type(State.Live)); print(is_enum(State.Live))
print(Code.OK.to_int()); print(Code.Created.to_int()); print(Code.Missing.to_int())
print(State.Draft == State.Draft); print(State.Draft == 0); print(State.Draft == "Draft")
print(State.Draft.to_string())
NIFT
[[ "$("$NIFT_BIN" run "$T/e.nift")" == $'Draft\n10\n11\nenum\ntrue\n200\n201\n404\ntrue\nfalse\nfalse\nDraft' ]]
must_error 'enum Bad { A = 1, B = 1 }'
must_error 'enum Bad { A, A }'
must_error 'enum Bad { }'
cat > "$T/enum-neg.nift" <<'NIFT'
enum T { A = -5, B, C = -2 }
print(T.A.to_int()); print(T.B.to_int()); print(T.C.to_int())
NIFT
[[ "$("$NIFT_BIN" run "$T/enum-neg.nift")" == $'-5\n-4\n-2' ]]

echo 'final language contract passed'