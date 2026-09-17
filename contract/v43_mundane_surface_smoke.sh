#!/usr/bin/env bash
# Independent black-box contract for the v4.3 mundane surface gap-fills:
# string empty(), numeric abs/floor/ceil/round, literal-array/object
# indexing, html_escape/attr_escape/url_encode output helpers, dynamic
# bracket access certification, and null/missing semantics. Runs only
# against the nift executable (no internal knowledge).
set -euo pipefail
NIFT_BIN="${NIFT_BIN:?}"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
cd "$td"

run(){ printf '%s\n' "$1" > t.nift; "$NIFT_BIN" run t.nift; }
evalx(){ "$NIFT_BIN" eval "$1"; }
must_error(){ if "$NIFT_BIN" run <(printf '%s\n' "$1") >/dev/null 2>&1; then echo "expected error: $1" >&2; return 1; fi; }

# --- string surface: empty + length across run/eval ---
[[ "$(run 'print("".empty()); print("x".empty()); print("".length()); print("x".length())')" == $'true\nfalse\n0\n1' ]]
[[ "$(evalx '"".empty()')" == true ]]

# --- string surface certified existing ---
[[ "$(run 'print("Hello".starts_with("He")); print("Hello".ends_with("lo")); print("Hello".contains("ell"))')" == $'true\ntrue\ntrue' ]]
[[ "$(run 'print("|" + "  x  ".trim() + "|"); print("|" + "  x  ".trim_start() + "|"); print("|" + "  x  ".trim_end() + "|")')" == $'|x|\n|x  |\n|  x|' ]]
[[ "$(run 'print("AbC".to_lower()); print("AbC".to_upper())')" == $'abc\nABC' ]]
[[ "$(run 'print("a,b,c".split(",").join("|")); print("Hello".replace("l","L"))')" == $'a|b|c\nHeLLo' ]]
[[ "$(run 'print("42".to_int()); print("3.14".to_double()); print(42.to_string())')" == $'42\n3.14\n42' ]]

# --- object membership: has/get + missing-vs-null distinction ---
[[ "$(run 'print({"a":1,"b":2}.has("a")); print({"a":1}.has("z"))')" == $'true\nfalse' ]]
[[ "$(run 'print({"a":null}.has("a"))')" == true ]]
[[ "$(run 'print({"a":1}.get("a")); print({"a":1}.get("z")); print({"a":1}.get("z", 5))')" == $'1\nnull\n5' ]]
[[ "$(run 'print({"a":1}.keys().join(",")); print({"a":1}.values().join(","))')" == $'a\n1' ]]

# --- dynamic bracket access: certified computed access through run/eval ---
[[ "$(run 'd := {"title":"Hello"}
k := "title"
print(d[k])')" == Hello ]]
[[ "$(run 'd := {"a":{"b":2}}
k := "b"
print(d["a"][k])')" == 2 ]]
[[ "$(evalx '{"a":{"b":3}}["a"]["b"]')" == 3 ]]
[[ "$(run 'a := [10,20,30]
print(a[1])')" == 20 ]]

# --- literal-array/object indexing (added) ---
[[ "$(evalx '[1,2,3][1]')" == 2 ]]
[[ "$(evalx '{"a":1}["a"]')" == 1 ]]
[[ "$(evalx '[[1,2],[3,4]][1][0]')" == 3 ]]

# --- array membership ---
[[ "$(run 'print([1,2,3].contains(2)); print([].contains(1)); print(["a","b"].contains("a"))')" == $'true\nfalse\ntrue' ]]
[[ "$(run 'print([1,2,3].indexOf(2)); print([1,2,3].indexOf(9))')" == $'1\n-1' ]]

# --- length/empty across string/array/object ---
[[ "$(run 'print("".length()); print("x".empty())')" == $'0\nfalse' ]]
[[ "$(run 'print([].empty()); print([1].length()); print({}.empty()); print({"a":1}.size())')" == $'true\n1\ntrue\n1' ]]

# --- numeric basics (added): abs/floor/ceil/round; conversions ---
[[ "$(run 'print((-3).abs()); print((3.7).floor()); print((3.7).ceil()); print((3.5).round()); print((2.4).round())')" == $'3\n3\n4\n4\n2' ]]
[[ "$(run 'print((3.5).to_string()); print("7".to_int())')" == $'3.5\n7' ]]
must_error 'print((3.5).floor("x"))'
must_error 'print("x".to_int())'

# --- html text escaping (added) ---
[[ "$(run 'print(html_escape("<b>& x</b>"))')" == '&lt;b&gt;&amp; x&lt;/b&gt;' ]]
[[ "$(run 'print(html_escape("café"))')" == 'café' ]]
[[ "$(run 'print(html_escape("a\"b'\''c"))')" == 'a"b'"'"'c' ]]

# --- attr escaping (added): both quote styles ---
[[ "$(run 'print(attr_escape("a\"b&c"))')" == 'a&quot;b&amp;c' ]]
[[ "$(run "print(attr_escape(\"a'b&c\"))")" == "a&#39;b&amp;c" ]]

# --- url component encoding (added): RFC 3986, not form encoding ---
[[ "$(run 'print(url_encode("a b/c?d=e&f"))')" == 'a%20b%2Fc%3Fd%3De%26f' ]]
[[ "$(run 'print(url_encode("café 100%"))')" == 'caf%C3%A9%20100%25' ]]
[[ "$(run 'print(url_encode("already_ok-~."))')" == 'already_ok-~.' ]]

# --- composition wall ---
[[ "$(run 'posts := [{"title":"Alpha"},{"title":"Beta"}]
print(html_escape(posts.first().title).to_upper())')" == ALPHA ]]
[[ "$(run 'print([1,2,3].filter(x => x > 1).empty())')" == false ]]
[[ "$(run 'posts := [{"title":"Alpha"},{"title":"Beta"},{"title":"Gamma"}]
print(posts.take(2).map(p => p.title.to_lower()).join(","))')" == alpha,beta ]]

# --- null model ---
[[ "$(run 'print(null == null)')" == true ]]
[[ "$(evalx 'null')" == null ]]
must_error 'print(missing_name)'
must_error 'd := {"a":1}
print(d.missing)'
must_error 'd := {"a":1}
print(d["z"])'

echo "mundane surface contract passed"