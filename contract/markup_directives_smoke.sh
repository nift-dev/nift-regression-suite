#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-markup.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkproj() {
  local d="$1"
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public" "$d/data" "$d/prose"
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

# Inline forms for all three formats and their long aliases.
P="$TMP/inline"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@markup("md") {
  # Markdown
}
@markup("adoc") {
  == AsciiDoc
}
@markup("rst") {
  RST Heading
  ===========
}
@markup("markdown") {
  # Long md
}
@markup("asciidoc") {
  == Long adoc
}
@markup("restructuredtext") {
  Long RST
  ===========
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<h1>Markdown</h1>' "$P/public/index.html"
grep -Fq '<h2>AsciiDoc</h2>' "$P/public/index.html"
grep -Fq 'RST Heading' "$P/public/index.html"
grep -Fq '<h1>Long md</h1>' "$P/public/index.html"
grep -Fq '<h2>Long adoc</h2>' "$P/public/index.html"
grep -Fq 'Long RST' "$P/public/index.html"

# File-backed forms for all three formats.
P="$TMP/file"; mkproj "$P"
printf '# File $[title]\n' >"$P/prose/article.md"
printf '= File $[title]\n' >"$P/prose/article.adoc"
printf 'File RST $[title]\n================\n' >"$P/prose/article.rst"
cat >"$P/templates/template.html" <<'EOF'
@markup("md", "prose/article.md")
@markup("adoc", "prose/article.adoc")
@markup("rst", "prose/article.rst")
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<h1>File Home</h1>' "$P/public/index.html"
grep -Fq '<h1>File Home</h1>' "$P/public/index.html"
grep -Fq 'File RST Home' "$P/public/index.html"
for dep in prose/article.md prose/article.adoc prose/article.rst; do
  grep -Fq "\"$dep\"" "$P/.nift/public/index.info.json"
done

# Template-before-conversion and no-second-pass: escaped directives stay literal.
P="$TMP/no-second-pass"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@json(x) { {"title":"Scoped"} }
@markup("md") {
  Literal \@json(fake){not executed} and \$[not.reparsed].

  Value is $[x.title].

  `\@json(bad){x}` in a code span stays code.
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'Literal @json(fake){not executed} and $[not.reparsed].' "$P/public/index.html"
grep -Fq 'Value is Scoped.' "$P/public/index.html"
grep -Fq '<code>@json(bad){x}</code>' "$P/public/index.html"

# Nift directives and JSON bindings are available inside file-backed markup.
P="$TMP/file-scope"; mkproj "$P"
printf '= Article\n\nThe value is $[x.title].\n' >"$P/prose/article.adoc"
cat >"$P/templates/template.html" <<'EOF'
@json(x) { {"title":"Scoped"} }
@markup("adoc", "prose/article.adoc")
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'The value is Scoped.' "$P/public/index.html"

# Loop-local values are available inside inline and file-backed markup.
P="$TMP/loop"; mkproj "$P"
printf '# Item $[post.title]\n' >"$P/prose/item.md"
cat >"$P/templates/template.html" <<'EOF'
@json(posts) { {"items":[{"title":"a"},{"title":"b"}]} }
@for(post : posts.items){
@markup("md") {
  ## Inline $[post.title]
}
}
@for(post : posts.items){
@markup("md", "prose/item.md")
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<h2>Inline a</h2>' "$P/public/index.html"
grep -Fq '<h2>Inline b</h2>' "$P/public/index.html"
grep -Fq '<h1>Item a</h1>' "$P/public/index.html"
grep -Fq '<h1>Item b</h1>' "$P/public/index.html"

# Multiple @markup directives on one page remain independent.
P="$TMP/multiple"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@markup("md") {
  # One
}
@markup("md") {
  # Two
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
test "$(grep -Fc '<h1>One</h1>' "$P/public/index.html")" -eq 1
test "$(grep -Fc '<h1>Two</h1>' "$P/public/index.html")" -eq 1

# Includes are recorded as dependencies and invalidate the output.
P="$TMP/include-deps"; mkproj "$P"
printf '= Guide\n\ninclude::part.adoc[]\n' >"$P/prose/guide.adoc"
printf 'Included body.\n' >"$P/prose/part.adoc"
cat >"$P/templates/template.html" <<'EOF'
@markup("adoc", "prose/guide.adoc")
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'Included body.' "$P/public/index.html"
grep -Fq '"prose/guide.adoc"' "$P/.nift/public/index.info.json"
grep -Fq '"prose/part.adoc"' "$P/.nift/public/index.info.json"
sleep 1
printf 'Included changed.\n' >"$P/prose/part.adoc"
(cd "$P" && "$NIFT_BIN" build >log 2>&1)
grep -Fq 'prose/part.adoc' "$P/log"
grep -Fq 'Included changed.' "$P/public/index.html"

# Unknown formats, missing sources, traversal and include cycles fail cleanly.
P="$TMP/errors"; mkproj "$P"
printf '@markup("bogus") { x }\n' >"$P/templates/template.html"
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" "unknown format 'bogus'" "unknown format must fail"
printf '@markup("md", "prose/nope.md")\n' >"$P/templates/template.html"
expect_build_failure "$P" "markup: file does not exist" "missing source must fail"
printf '@markup("md", "../outside.md")\n' >"$P/templates/template.html"
expect_build_failure "$P" "path must stay inside the Nift project" "traversal must fail"

P="$TMP/include-cycle"; mkproj "$P"
printf '@markup("adoc", "prose/a.adoc")\n' >"$P/templates/template.html"
printf '= A\n\ninclude::b.adoc[]\n' >"$P/prose/a.adoc"
printf '@markup("adoc", "prose/a.adoc")\n' >"$P/prose/b.adoc"
printf '\n' >"$P/content/index.html"
expect_build_failure "$P" "cycle" "nested markup/include cycle must be detected cleanly"

# Braces inside Markdown code spans and fenced blocks do not corrupt @markup.
P="$TMP/braces"; mkproj "$P"
cat >"$P/templates/template.html" <<'EOF'
@markup("md") {
  ## Braces

  Inline `code { x }` span.

  ```
  function f() { return { a: 1 }; }
  ```
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<code>code { x }</code>' "$P/public/index.html"
grep -Fq 'function f() { return { a: 1 }; }' "$P/public/index.html"

# Cross-feature: JSON selects a markup path inside a JSON-driven loop.
P="$TMP/cross-feature"; mkproj "$P"
printf '# $[page.title]\n' >"$P/prose/post.md"
cat >"$P/templates/template.html" <<'EOF'
@json(schema) {
  {"type":"object","required":["title"]}
}
@json(post, schema) {
  {"title":"$[title]"}
}
@markup("md") {
  # $[post.title]
}
@content
EOF
printf '\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
grep -Fq '<h1>Home</h1>' "$P/public/index.html"

echo 'markup directives contract smoke test passed'
