#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-contract-template-optional.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

P="$TMP/project"
mkdir -p "$P/.nift" "$P/content" "$P/templates" "$P/public"
cat >"$P/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/default.html","build-threads":1,"incremental-mode":"hash"}}
JSON
cat >"$P/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Home"}]}
JSON
cat >"$P/content/index.html" <<'EOF'
@if(true){<main>$[title]</main>}
EOF

# Omission parses content as the top-level Nift source, not as a literal copy.
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<main>Home</main>' "$P/public/index.html"
python3 -S - "$P/.nift/public/index.info.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["template"] == "", d
assert d["dependencies"] == ["content/index.html"], d
PY

# Adding a template establishes that dependency and preserves @content behavior.
printf '<body>@content</body>\n' >"$P/templates/page.html"
python3 -S - "$P/.nift/tracked.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["tracked"][0]["template"] = "templates/page.html"
json.dump(d, open(p, "w"))
PY
(cd "$P" && "$NIFT_BIN" build >/dev/null)
grep -Fq '<body><main>Home</main>' "$P/public/index.html"
grep -Fq '"templates/page.html"' "$P/.nift/public/index.info.json"

# Removing the template removes the old incremental relationship.
python3 -S - "$P/.nift/tracked.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["tracked"][0]["template"]
json.dump(d, open(p, "w"))
PY
(cd "$P" && "$NIFT_BIN" build >/dev/null)
! grep -Fq '"templates/page.html"' "$P/.nift/public/index.info.json"
printf '<body>changed</body>\n' >"$P/templates/page.html"
(cd "$P" && "$NIFT_BIN" status >status.log)
! grep -Fq 'needs rebuilding' "$P/status.log"

# The historical empty-string form remains a compatible template-less alias.
python3 -S - "$P/.nift/tracked.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["tracked"][0]["template"] = ""
json.dump(d, open(p, "w"))
PY
(cd "$P" && "$NIFT_BIN" status >empty.log)
! grep -Fq 'needs rebuilding' "$P/empty.log"

# New scaffolds omit ceremonial CSS/JavaScript identity templates.
S="$TMP/scaffold"
mkdir "$S"
(cd "$S" && "$NIFT_BIN" init >/dev/null)
python3 -S - "$S/.nift/tracked.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assets = {item["name"]: item for item in d["tracked"] if item["name"].startswith("assets/")}
assert "template" not in assets["assets/css/style"], assets
assert "template" not in assets["assets/js/script"], assets
PY
test ! -e "$S/templates/template.css"
test ! -e "$S/templates/template.js"

echo "Optional tracked template contract passed"
