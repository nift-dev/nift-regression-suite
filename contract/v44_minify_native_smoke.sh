#!/usr/bin/env bash
# Independent black-box contract: native script-land Minify++. minify(...)
# must delegate to the embedded Minify++ (no subprocess), provide structured
# {ok,output,error,format,written} results, support string and file modes,
# and keep working under --no-process.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/assets"
printf 'const a = 1;\nconst b = 2;\n' > "$t/assets/app.js"
cat > "$t/s.f" <<'F'
r := minify("const x = 1;   const y = 2;", "js")
print(r.ok)
print(r.output)
print(minify("<div>  <p>x</p> </div>", "html").output)
print(minify("body { color: red;  background: blue; }", "css").output)
F
out=$("$NIFT_BIN" run "$t/s.f")
[ "$(sed -n '1p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '2p' <<<"$out")" = "const x=1;const y=2" ] || exit 1
[ "$(sed -n '3p' <<<"$out")" = "<div> <p>x</p> </div>" ] || exit 1
[ "$(sed -n '4p' <<<"$out")" = "body{color:red;background:blue;}" ] || exit 1
cat > "$t/f.f" <<'F'
print(minify("assets/app.js").ok)
print(exists("assets/app.min.js"))
print(minify("assets/app.js", {"output": "o/c.js"}).ok)
print(exists("o/c.js"))
m := minify("assets/nope.js")
print(m.ok)
print(m.error != "")
F
mkdir -p "$t/o"
out=$(cd "$t" && "$NIFT_BIN" run f.f)
[ "$(sed -n '1p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '2p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '3p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '4p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '5p' <<<"$out")" = "false" ] || exit 1
[ "$(sed -n '6p' <<<"$out")" = "true" ] || exit 1
out=$(NIFT_NO_PROCESS=1 "$NIFT_BIN" run "$t/s.f")
[ "$(sed -n '2p' <<<"$out")" = "const x=1;const y=2" ] || exit 1
printf 'PASS v4.4 native script-land Minify++\n'
