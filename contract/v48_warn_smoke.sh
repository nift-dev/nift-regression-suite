#!/usr/bin/env bash
# Independent black-box contract: first-class warn(...) primitive (v4.8).
# warn(value) emits one canonical "warning: <value>" line to stderr, continues
# execution, leaves stdout untouched, and returns null like print/err. Ordinary
# and prepared (loop/while/function) execution agree; template-driven warnings
# leave the rendered page unchanged. Invalid calls fail like other builtins.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# stdout/stderr separation + continuation.
"$NIFT_BIN" -e 'print("A"); warn("note"); print("B")' >o 2>e
[ "$(cat o)" = $'A\nB' ] || { echo "stdout: $(cat o)" >&2; exit 1; }
[ "$(cat e)" = 'warning: note' ] || { echo "stderr: $(cat e)" >&2; exit 1; }

# warn returns null, mirroring print/err.
out=$("$NIFT_BIN" -e 'print(type(warn("x")))' 2>/dev/null)
[ "$out" = null ] || { echo "warn return: $out" >&2; exit 1; }

# Prepared/ordinary parity: repeated warnings, functions, loops, conditionals.
"$NIFT_BIN" -e 'fn(f()) { warn("in fn") }; f(); for(i : [1,2]) { warn(i) }; if(true) { warn("cond") }' >o 2>e
[ "$(cat e)" = $'warning: in fn\nwarning: 1\nwarning: 2\nwarning: cond' ] || { echo "parity stderr: $(cat e)" >&2; exit 1; }
[ -s o ] && { echo "stdout not empty for warning-only program: $(cat o)" >&2; exit 1; }

# warn accepts the same scalar value class as print/err (null, numbers, bools).
"$NIFT_BIN" -e 'warn(null); warn(7); warn(true)' >/dev/null 2>e
[ "$(cat e)" = $'warning: null\nwarning: 7\nwarning: true' ] || { echo "scalar stderr: $(cat e)" >&2; exit 1; }

# warn obeys the same value rules as print/err.
reject(){ local needle="$1" prog="$2"; if "$NIFT_BIN" -e "$prog" >o 2>e; then echo "accepted: $prog" >&2; exit 1; fi; grep -q "$needle" e || { echo "missing [$needle]: $(cat e)" >&2; exit 1; }; }
reject 'warn: expected one value' 'warn()'
reject 'warn: bytes values cannot be rendered as text' 'warn("x".encode("utf-8"))'
reject 'warn: value is not directly renderable' 'warn([1,2])'

# Template-driven warning: emitted to stderr, rendered page unchanged.
mkdir -p site/.nift site/content site/templates
printf '%s' '{"config": {"content-dir": "content/", "output-dir": "public/", "default-template": "templates/template.html", "build-threads": -1}}' > site/.nift/config.json
printf '%s' '{"tracked": [{"name": "/", "title": "t", "template": "templates/template.html"}]}' > site/.nift/tracked.json
printf '%s\n' '<body>@content</body>' > site/templates/template.html
cat > site/content/index.html <<'E'
@fn(dep()){ warn("old_field is deprecated; use new_field"); return "" }
$[dep()]Hello
E
( cd site && "$NIFT_BIN" build --all >/dev/null 2>"$t/e2" )
[ "$(cat "$t/e2")" = 'warning: old_field is deprecated; use new_field' ] || { echo "template stderr: $(cat "$t/e2")" >&2; exit 1; }
grep -q 'Hello' site/public/index.html || { echo "template output changed" >&2; exit 1; }

printf 'PASS v4.8 warn primitive\n'