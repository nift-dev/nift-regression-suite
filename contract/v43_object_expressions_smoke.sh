#!/usr/bin/env bash
# Independent black-box contract for expression-valued object literals
# (post-review v4.3 composition fix). {"key": expr} mirrors array literals:
# values are Nift expressions preserving runtime types; pure JSON keeps the
# JSON fast path. Covers enum composition, nesting, optionality inside values,
# duplicate-key/trailing-comma/single-quoted-key errors, evaluation-once,
# serialization (enum -> backing integer), and template/run/eval parity.
set -euo pipefail
: "${NIFT_BIN:?}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
run(){ printf '%s\n' "$1" > "$T/t.nift"; "$NIFT_BIN" run "$T/t.nift"; }
must_error(){ printf '%s\n' "$1" > "$T/e.nift"; if "$NIFT_BIN" run "$T/e.nift" >/dev/null 2>&1; then echo "expected error: $1" >&2; return 1; fi; }

# --- basic expression values ---
[[ "$(run 'x := 5
print({"value": x}.value)')" == 5 ]]
[[ "$(run 'x := 5
print({"value": x + 3}.value)')" == 8 ]]
[[ "$(run 'label := "Nift"
print({"name": label, "length": label.length()}.length)')" == 4 ]]
[[ "$(run 'f := (x => x * 2)
print({"v": f(3)}.v)')" == 6 ]]
[[ "$(run 'print({"count": range(10).size()}.count)')" == 10 ]]
[[ "$(run 'print({"tags": ["A","B"]}.tags.join(","))')" == A,B ]]
[[ "$(run 'print({"missing": null}.missing == null)')" == true ]]

# --- enum composition ---
cat > "$T/e.nift" <<'NIFT'
enum Status { Draft, Published }
post := {"title": "Hello", "status": Status.Published}
print(post.status)
print(post.status.to_int())
print(type(post.status))
NIFT
[[ "$("$NIFT_BIN" run "$T/e.nift")" == $'Published\n1\nenum' ]]

# --- nesting ---
[[ "$(run 'x := 2
obj := {"nested": {"value": x + 1}, "items": [x, x + 1]}
print(obj.nested.value); print(obj.items.join(","))')" == $'3\n2,3' ]]
[[ "$(run 'enum S { A, B }
obj := {"nested": {"s": S.B}}
print(obj.nested.s.to_int())')" == 1 ]]

# --- optionality inside values ---
[[ "$(run 'print({"t": null ?? "fb"}.t)')" == fb ]]
[[ "$(run 'x := null
print({"t": x ?? "fb"}.t)')" == fb ]]
[[ "$(run 'x := null
print({"t": x?.y ?? "fb"}.t)')" == fb ]]
[[ "$(run 'd := {"a": {"b": 5}}
print({"v": d?.a?.b}.v)')" == 5 ]]
# missing key through ?. remains an error even inside an object value
must_error 'd := {}
print({"v": d?.x}.v)'
[[ "$(run 'print({"t": (false ? "a" : "b")}.t)')" == b ]]

# --- evaluation once, left-to-right ---
[[ "$(run 'n := 0
f := (() => { n++; return n })
o := {"a": f(), "b": f()}
print(o.a); print(o.b); print(n)')" == $'1\n2\n2' ]]

# --- value types preserved ---
[[ "$(run 'obj := {"a": null, "b": true, "c": 42, "d": 1.5, "e": "s", "f": [1,2], "g": {"h": 1}}
print(type(obj.a));print(type(obj.b));print(type(obj.c));print(type(obj.d));print(type(obj.e));print(type(obj.f));print(type(obj.g))')" == $'null\nbool\nint\nfloat\nstring\narray\nobject' ]]

# --- object concatenation composes ---
[[ "$(run 'label := "Nift"
print({"a": label}.a + "|" + {"a": label}.a)')" == 'Nift|Nift' ]]
[[ "$(run 'print({"a": {"b": 2}}["a"].b)')" == 2 ]]
[[ "$(run 'print([{"x":1},{"x":2}][1].x)')" == 2 ]]

# --- errors / malformed ---
must_error 'x := 1
print({"a": x, "a": 2})'
must_error 'x := 1
print({"a": x,})'
must_error "print({'a': 1})"
must_error 'print({"a": })'
must_error 'print({"a" 1})'
must_error 'print({"a": missing_binding})'
must_error 'print({"a": {"b": missing_binding}})'

# --- JSON fast path preserved ---
[[ "$(run 'print({"a":"line\nnext"}.a.replace("\n","|"))')" == 'line|next' ]]
[[ "$(run 'print({"a":123456789012345678901234567890}.a)')" == 123456789012345678901234567890 ]]
[[ "$(run 'print({"a":1e10}.a)')" == 10000000000 ]]
[[ "$(run 'print({"a":1,"b":2}.a)')" == 1 ]]

# --- serialization: enum -> backing integer ---
cat > "$T/ser.nift" <<'NIFT'
enum Status { Draft, Published }
post := {"title": "Hello", "status": Status.Published}
print(post.stringify())
st := ofstream("o.jsonl")
st.write_val(post)
close(st)
print(open("o.jsonl"))
NIFT
# Run from the temp dir so the relative o.jsonl fixture stays out of the repo root.
[[ "$(cd "$T" && "$NIFT_BIN" run ser.nift)" == $'{"title":"Hello","status":1}\n{"title":"Hello","status":1}' ]]

# --- template parity ---
T2="$T/proj"
mkdir -p "$T2/.nift" "$T2/content" "$T2/templates" "$T2/public"
printf '%s' '{"config":{"content-dir":"content/","content-ext":".md","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":-1,"incremental-mode":"modified"}}' > "$T2/.nift/config.json"
printf '%s' '{"tracked":[{"name":"/","title":"Home","template":"templates/template.html"}]}' > "$T2/.nift/tracked.json"
printf '# Home\n' > "$T2/content/index.md"
printf '%s' 'A$[x := 5]$[{"value": x}.value]B$[{"t": null ?? "fb"}.t]C@enum(Status){ Draft, Published }D$[{"s": Status.Published}.s]E@content' > "$T2/templates/template.html"
(cd "$T2" && "$NIFT_BIN" build --all >/dev/null 2>&1)
grep -q 'A5BfbCDPublishedE# Home' "$T2/public/index.html"

# --- eval parity ---
[[ "$("$NIFT_BIN" eval '{"value": 5}.value')" == 5 ]]
"$NIFT_BIN" eval --json '{"t": null ?? "fb"}' | grep -q '"t": "fb"'

echo 'object expression literals contract passed'