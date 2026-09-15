#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:-nift}
R=$(mktemp -d "${TMPDIR:-/tmp}/nift-v41-dupkey.XXXXXX")
trap 'rm -rf "$R"' EXIT

# v4.0.13 rejected duplicate object keys in every JSON document Nift parsed.
# The Jsonic++ v1.0.0 integration accidentally inherited its RFC-preserving
# default; Nift's nift_json::parse policy wrapper must restore the historical
# contract. These cases are black-box and independent of the implementation.

expect_reject() {
  local name="$1" file="$2"
  if (cd "$R/$name" && "$NIFT" build --all >/dev/null 2>err); then
    echo "FAIL [$name]: duplicate key was accepted in $file" >&2
    exit 1
  fi
  grep -qi 'duplicate object key' "$R/$name/err" || {
    echo "FAIL [$name]: expected a duplicate-key diagnostic, got:" >&2
    cat "$R/$name/err" >&2
    exit 1
  }
}

newproj() {
  local d="$1"
  mkdir -p "$R/$d"
  (cd "$R/$d" && "$NIFT" init >/dev/null)
  printf '@content\n' > "$R/$d/templates/template.html"
}

# 1. .nift/config.json
newproj config
cat > "$R/config/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-dir":"other/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
expect_reject config ".nift/config.json"

# 2. @json-loaded JSON data file
newproj datafile
mkdir -p "$R/datafile/data"
printf '{"a":1,"a":2}\n' > "$R/datafile/data/site.json"
cat > "$R/datafile/content/index.html" <<'E'
@json(site, "data/site.json")
x=$[site.a]
E
expect_reject datafile "data/site.json"

# 3. $[x := {...}] expression literal
newproj exprliteral
cat > "$R/exprliteral/content/index.html" <<'E'
$[x := {"a":1,"a":2}]
E
expect_reject exprliteral '$[x := {...}] expression literal'

# 4. inline @json(name){...} block
newproj inlinejson
cat > "$R/inlinejson/content/index.html" <<'E'
@json(site){
  {"a":1,"a":2}
}
E
expect_reject inlinejson "@json(name){...} inline block"

# 5. schema JSON file with a duplicate key
newproj schema
mkdir -p "$R/schema/schemas"
cat > "$R/schema/schemas/s.schema.json" <<'JSON'
{"type":"object","properties":{"n":{"type":"integer"}},"properties":{"n":{"type":"string"}}}
JSON
printf '{"n": 5}\n' > "$R/schema/data.json"
cat > "$R/schema/content/index.html" <<'E'
@json(site, "schemas/s.schema.json", "data.json")
E
expect_reject schema "schemas/s.schema.json"

echo 'Nift v4.1 duplicate-key compatibility smoke passed'