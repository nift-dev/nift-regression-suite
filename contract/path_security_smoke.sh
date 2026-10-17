#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-path-security.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/project"
mkdir -p "$P/.nift" "$P/content" "$P/templates" "$P/public/assets"
cat >"$P/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
cat >"$P/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Home","template":"templates/template.html"}]}
JSON
printf '\n' >"$P/content/index.html"
printf 'outside\n' >"$TMP/outside.txt"

printf '<a href="@path('"'"'../outside.txt'"'"')">escape</a>\n@content\n' >"$P/templates/template.html"
if (cd "$P" && "$NIFT_BIN" build --all >log 2>&1); then
  echo "@path traversal unexpectedly succeeded" >&2; exit 1
fi
grep -Fq '@path path must stay inside the Nift project' "$P/log"

# D-002 (Nift Runtime 2.0): @dep outside the project is no longer refused; the
# external file is tracked like any dependency and an edit to it invalidates the
# page. (Previously: "dep: path must stay inside the Nift project".) The @path
# containment check above is retained.
printf '@dep("../outside.txt")\nDEP-OK\n@content\n' >"$P/templates/template.html"
(cd "$P" && "$NIFT_BIN" build --all >log 2>&1) || { cat "$P/log" >&2; echo "@dep outside the project failed to build" >&2; exit 1; }
grep -Fq 'DEP-OK' "$P/public/index.html"
(cd "$P" && "$NIFT_BIN" status >status.log 2>&1)
grep -Fq 'up to date' "$P/status.log"
sleep 1
printf 'outside edited\n' >"$TMP/outside.txt"
(cd "$P" && "$NIFT_BIN" status >status.log 2>&1) || true
grep -Fq 'dependency changed: ../outside.txt' "$P/status.log"
(cd "$P" && "$NIFT_BIN" build >/dev/null)
(cd "$P" && "$NIFT_BIN" status >status.log 2>&1)
grep -Fq 'up to date' "$P/status.log"

printf 'ok\n' >"$P/public/assets/a.txt"
cat >"$P/templates/template.html" <<'EOF'
<a href="@path('public/assets/a.txt')">ok</a>
@dep("public/assets/a.txt")
@content
EOF
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'assets/a.txt' "$P/public/index.html"
grep -Fq '"public/assets/a.txt"' "$P/.nift/public/index.info.json"

echo "Path security smoke test passed"
