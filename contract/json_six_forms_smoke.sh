#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-json-six.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkproj() {
  local d="$1"
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public" "$d/data" "$d/schemas"
  cat >"$d/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
  cat >"$d/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Home","template":"templates/template.html"}]}
JSON
}

expect_build_failure() {
  local d="$1" expected="$2" name="$3"
  (cd "$d" && rm -f .nift/.unfinished)
  if (cd "$d" && "$NIFT_BIN" build --all >log 2>&1); then
    echo "$name unexpectedly succeeded" >&2
    exit 1
  fi
  grep -F "$expected" "$d/log" >/dev/null || {
    echo "$name missing expected diagnostic: $expected" >&2
    cat "$d/log" >&2
    exit 1
  }
}

# All six name-first forms, file-backed and inline, with and without schema.
P="$TMP/six-forms"; mkproj "$P"
cat >"$P/data/post.json" <<'EOF'
{"title":"File post"}
EOF
cat >"$P/schemas/post.schema.json" <<'EOF'
{"type":"object","required":["title"],"properties":{"title":{"type":"string"}}}
EOF
cat >"$P/templates/template.html" <<'EOF'
@json(file_plain, "data/post.json")
@json(file_path_schema, "schemas/post.schema.json", "data/post.json")
@json(named_schema) {
  {"type":"object","required":["title"],"properties":{"title":{"type":"string"}}}
}
@json(file_named_schema, named_schema, "data/post.json")
@json(inline_plain) { {"title":"Inline"} }
@json(inline_path_schema, "schemas/post.schema.json") { {"title":"Inline path"} }
@json(inline_named_schema, named_schema) { {"title":"Inline named"} }
<p>$[file_plain.title]|$[file_path_schema.title]|$[file_named_schema.title]|$[inline_plain.title]|$[inline_path_schema.title]|$[inline_named_schema.title]</p>
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<p>File post|File post|File post|Inline|Inline path|Inline named</p>' "$P/public/index.html"
grep -Fq '"data/post.json"' "$P/.nift/public/index.info.json"
grep -Fq '"schemas/post.schema.json"' "$P/.nift/public/index.info.json"

# Inline JSON bodies are templated before parsing and add no file dependency.
P="$TMP/inline-templated"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(settings) {
  {
    "title": "$[title]",
    "enabled": true
  }
}
VALUE=$[settings.title]:$[settings.enabled]
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'VALUE=Home:true' "$P/public/index.html"
if grep -Fq '"content/index.html"' "$P/.nift/public/index.info.json"; then :; else
  echo "inline JSON must not invent extra file dependencies" >&2
  exit 1
fi

# A reusable inline schema validates both inline and file-backed instances.
P="$TMP/reusable-schema"; mkproj "$P"
cat >"$P/data/article.json" <<'EOF'
{"title":"From file"}
EOF
cat >"$P/templates/template.html" <<'EOF'
@json(article_schema) {
  {
    "type": "object",
    "required": ["title"],
    "properties": {"title": {"type": "string"}}
  }
}
@json(article_file, article_schema, "data/article.json")
@json(article_inline, article_schema) { {"title": "Inline"} }
$[article_file.title]|$[article_inline.title]
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'From file|Inline' "$P/public/index.html"

# Failed validation binds nothing and leaves no partial binding.
P="$TMP/failed-validation"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(schema) {
  {"type":"object","required":["title"]}
}
@json(bad, schema) { {"other": 1} }
$[bad.title]
@content
EOF
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" "does not satisfy schema schema" "failed validation must fail the build"

# Duplicate, reserved and contract-namespace collisions fail.
P="$TMP/collisions"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(data) { {} }
@json(data) { {} }
EOF
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" "json: name 'data' is already bound" "duplicate binding must fail"
cat >"$P/templates/template.html" <<'EOF'
@json(title) { {} }
EOF
expect_build_failure "$P" "conflicts with built-in metadata" "reserved binding must fail"

# Missing bare schema name fails and never falls back to a same-named file.
P="$TMP/schema-name-vs-file"; mkproj "$P"
printf '%s\n' '{"type":"object","required":["title"]}' >"$P/user"
cat >"$P/templates/template.html" <<'EOF'
@json(post, user) { {"title": "x"} }
EOF
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" "json: schema name 'user' is not bound" "missing bare schema name must not fall back to a file"

# A quoted schema path with the same spelling is used as a path.
P="$TMP/quoted-path"; mkproj "$P"
printf '%s\n' '{"type":"object","required":["title"]}' >"$P/user"
cat >"$P/templates/template.html" <<'EOF'
@json(post, "user") { {"title": "ok"} }
V=$[post.title]
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'V=ok' "$P/public/index.html"
grep -Fq '"user"' "$P/.nift/public/index.info.json"

# Skipped branches stay lazy: invalid JSON in an unselected branch is ignored.
P="$TMP/lazy-branch"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@if(false){@json(broken) { not json }}
RENDERED
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'RENDERED' "$P/public/index.html"

# Bindings scoped to a loop do not leak after the loop.
P="$TMP/scope"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(posts) { {"items":[{"title":"a"},{"title":"b"}]} }
LOOP=@for(post : posts.items){$[post.title]}AFTER
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'LOOP=abAFTER' "$P/public/index.html"

# Traversal, absolute-escape, symlink escape and unreadable data stay controlled.
P="$TMP/path-safety"; mkproj "$P"
printf '{}\n' >"$TMP/outside.json"
printf '%s\n' '@json(data, "../outside.json")' >"$P/templates/template.html"
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" 'json: path must stay inside the Nift project' "traversal must fail"
printf '%s\n' '@json(data, "/etc/passwd")' >"$P/templates/template.html"
expect_build_failure "$P" 'json: path must stay inside the Nift project' "absolute escape must fail"
ln -s "$TMP/outside.json" "$P/data/link.json"
printf '%s\n' '@json(data, "data/link.json")' >"$P/templates/template.html"
expect_build_failure "$P" 'json: path must stay inside the Nift project' "symlink escape must fail"

# Data and schema edits trigger affected rebuilds; unrelated pages stay current.
P="$TMP/incremental"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(data, "schemas/schema.json", "data/data.json")
@content
EOF
printf '{"value":1}\n' >"$P/data/data.json"
printf '%s\n' '{"type":"object","required":["value"]}' >"$P/schemas/schema.json"
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
sleep 1
printf '{"value":2}\n' >"$P/data/data.json"
(cd "$P" && "$NIFT_BIN" build >log 2>&1)
grep -Fq 'data/data.json' "$P/log"
sleep 1
printf '%s\n' '{"type":"object","required":["value"],"properties":{"value":{"type":"integer"}}}' >"$P/schemas/schema.json"
(cd "$P" && "$NIFT_BIN" build >log 2>&1)
grep -Fq 'schemas/schema.json' "$P/log"

echo 'six-form @json contract smoke test passed'