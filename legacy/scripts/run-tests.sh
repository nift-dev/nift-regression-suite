#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NIFT_BIN="${NIFT_BIN:-nift}"
FAILS=0
TESTS=0
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nift-v04-tests.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail(){ printf 'FAIL [test %03d]: %s\n' "$TESTS" "$*" >&2; FAILS=$((FAILS+1)); }
pass(){ :; }
run_test(){ TESTS=$((TESTS+1)); "$@"; }
contains(){ local f="$1" x="$2" n="$3"; grep -Fq -- "$x" "$f" || fail "$n (missing: $x)"; }
not_contains(){ local f="$1" x="$2" n="$3"; if grep -Fq -- "$x" "$f"; then fail "$n (unexpected: $x)"; fi; }
regex(){ local f="$1" x="$2" n="$3"; grep -Eq -- "$x" "$f" || fail "$n (regex: $x)"; }
exists(){ [[ -e "$1" ]] || fail "$2 (missing: $1)"; }
not_exists(){ [[ ! -e "$1" ]] || fail "$2 (unexpected: $1)"; }

if ! command -v "$NIFT_BIN" >/dev/null 2>&1 && [[ ! -x "$NIFT_BIN" ]]; then
  echo "FAIL: NIFT_BIN not found: $NIFT_BIN" >&2
  exit 2
fi

cd "$ROOT" || exit 2
export NIFT_TEST_VALUE='hello-env'
export NIFT_TEST_LITERAL='@content $[title] <tag>& literal'

TESTS=$((TESTS+1)); "$NIFT_BIN" version >"$TMP_ROOT/version.log" 2>&1 || fail 'nift version failed'
grep -Fq 'v4.0.10' "$TMP_ROOT/version.log" || fail 'nift version did not report v4.0.10'
TESTS=$((TESTS+1)); "$NIFT_BIN" commands >"$TMP_ROOT/commands.log" 2>&1 || fail 'nift commands failed'
grep -Eq '^\s{2}build\b' "$TMP_ROOT/commands.log" || fail 'nift commands missing build entry'

# Full positive build. Suppress all successful Nift output.
BUILD_LOG="$TMP_ROOT/build-all.log"
if ! "$NIFT_BIN" build --all >"$BUILD_LOG" 2>&1; then
  fail "build --all positive suite failed; log follows"
  cat "$BUILD_LOG" >&2
fi

# Basic content/template behavior.
run_test contains public/basic/content.html 'BASIC-CONTENT' '@content inserts page content'
run_test contains public/basic/content.html '<title>Basic Content · Nift v4 regression suite</title>' 'template metadata title renders'
run_test contains public/basic/content-in-partial.html 'CONTENT-IN-PARTIAL' '@content works inside an input partial'
run_test contains public/basic/content-in-partial.html '<slot>' '@content partial wrapper rendered'


# @input: project-root, nested, relative-to-read-file, spaces, recursive.
run_test contains public/input/basic.html 'SHARED-PARTIAL-v1' '@input project-root path'
run_test contains public/input/basic.html 'RELATIVE-PARENT-BEGIN' '@input nested parent'
run_test contains public/input/basic.html 'RELATIVE-CHILD' '@input resolves relative to current input file'
run_test contains public/input/basic.html 'SPACE-FILE' '@input quoted path containing spaces'
run_test contains public/input/basic.html 'DEEP-A' '@input deep nested file'
[[ "$(grep -Fc 'RELATIVE-CHILD' public/input/basic.html)" -eq 2 ]] || fail '@input recursive/relative child expected twice'


# @input quoted edge filenames.
run_test contains public/input/special-filenames.html 'COMMA-FILE' '@input quoted filename containing comma'
run_test contains public/input/special-filenames.html 'PAREN-FILE' '@input quoted filename containing parentheses'
run_test contains public/input/special-filenames.html 'BRACKET-FILE' '@input quoted filename containing brackets'
run_test contains public/input/special-filenames.html 'DOUBLE-SPACE-FILE' '@input quoted filename containing multiple spaces'

# Indentation derived from current output line.
run_test contains public/input/indent.html '    line-one' '@content first line inherits insertion indentation'
run_test contains public/input/indent.html '    line-two' '@content subsequent lines inherit insertion indentation'
run_test contains public/input/indent.html '      line-three' '@content preserves additional source indentation'

# @pathto tracked names, implicit index, direct files, self.
run_test contains public/paths/direct.html 'ROOT=../' '@pathto root tracked name'
run_test contains public/paths/direct.html 'BASIC=../basic/content.html' '@pathto nested tracked page'
run_test contains public/paths/direct.html 'NESTED=nested/' '@pathto implicit index strips index.html'
run_test contains public/paths/direct.html 'ASSET=../assets/existing.txt' '@pathto existing direct file'
run_test contains public/paths/direct.html 'SELF=./direct.html' '@pathto current tracked page'


# @pathto from a deeply nested output.
run_test contains public/paths/deep/level/page.html 'ROOT=../../../' '@pathto deep page to root'
run_test contains public/paths/deep/level/page.html 'BASIC=../../../basic/content.html' '@pathto deep page to tracked file'
run_test contains public/paths/deep/level/page.html 'NESTED=../../nested/' '@pathto deep page to tracked index'
run_test contains public/paths/deep/level/page.html 'ASSET=../../../assets/existing.txt' '@pathto deep page to direct asset'
run_test contains public/paths/deep/level/page.html 'SPACE_ASSET=../../../assets/file with spaces.txt' '@pathto direct asset containing spaces'
run_test contains public/paths/deep/level/page.html 'SELF=./page.html' '@pathto deep page to itself'

# Metadata exact/static fields + dynamic format fields.
M=public/metadata/all.html
run_test contains "$M" 'TITLE=Metadata Test' '$[title]'
run_test contains "$M" 'NAME=metadata/all' '$[name]'
run_test contains "$M" 'CONTENT=content/metadata/all.html' '$[content-path]'
run_test contains "$M" 'OUTPUT=public/metadata/all.html' '$[output-path]'
run_test contains "$M" 'TEMPLATE=templates/metadata.html' '$[template-path]'
run_test contains "$M" 'DOLLAR_PAREN=$(title)' '$(title) remains literal and is not treated as metadata'
run_test not_contains "$M" 'DOLLAR_PAREN=Metadata Test' '$(title) must not resolve to title metadata'
run_test regex "$M" '^TIME=[0-9]{2}:[0-9]{2}:[0-9]{2}$' '$[build-time] format'
run_test regex "$M" '^UTCTIME=[0-9]{2}:[0-9]{2}:[0-9]{2}$' '$[build-UTC-time] format'
run_test regex "$M" '^YYYY=[0-9]{4}$' '$[build-YYYY] format'
run_test regex "$M" '^YY=[0-9]{2}$' '$[build-YY] format'
run_test regex "$M" '^OS=(Linux|Windows|OSX|FreeBSD|Unknown)$' '$[build-OS] recognized shape'

# getenv.
run_test contains public/environment.html 'SET=hello-env' '@getenv set variable'
run_test contains public/environment.html 'UNSET=' '@getenv unset variable yields empty string'


run_test contains public/environment-literal.html 'RAW=@content $[title] <tag>& literal' '@getenv output is literal and not reparsed'

# Every @ent mapping currently implemented.
while IFS= read -r expected; do
  [[ -z "$expected" ]] && continue
  TESTS=$((TESTS+1))
  grep -Fqx -- "$expected" public/entities.html || fail "@ent mapping mismatch: $expected"
done < tests/expected/entities.txt

# Escaping and unknown calls are preserved literally.
run_test contains public/escaping.html 'AT=@literal' 'escaped @ outputs literal @'
run_test contains public/escaping.html 'DOLLAR=$literal' 'escaped $ outputs literal $'
run_test contains public/escaping.html 'HASH=#literal' 'escaped # outputs literal #'
run_test contains public/escaping.html 'UNKNOWN=@not-a-real-function' 'unknown @ function preserved'
run_test contains public/escaping.html 'META_UNKNOWN=$[not-real]' 'unknown metadata preserved'

# Comments/current parser behavior.
run_test not_contains public/comments.html 'raw single line removed' '@# raw single-line comment removed'
run_test not_contains public/comments.html 'raw single line removed too' '@// raw single-line comment removed'
run_test not_contains public/comments.html 'raw multiline @ent' '<#-- raw multiline comment removed without processing'
run_test contains public/comments.html 'ordinary slash-star text &excl;' 'ordinary /* text is not a Nift comment and is still parsed normally'

# pre behavior.
run_test contains public/pre.html '&lt;div>raw tag becomes escaped inside pre&lt;/div>' '<pre> escapes opening angle brackets'
run_test contains public/pre.html '<code>&lt;b>code tag handling&lt;/b></code>' '<code> tags remain inside pre while inner tags escape'

# @dep and dependency info files.
run_test contains public/dependencies/a.html 'DEP-CONTENT-A' '@dep page builds'
run_test contains .nift/public/dependencies/a.info.json 'data/dep-a.txt' '@dep recorded first explicit dependency'
run_test contains .nift/public/dependencies/a.info.json 'data/dep-b.txt' '@dep recorded second explicit dependency'
run_test contains .nift/public/input/basic.info.json 'templates/partials/relative-child.html' '@input dependency recorded transitively'

# Semicolon terminator, blank template, custom extensions.
run_test contains public/semicolon.html 'X&excl;Y' 'semicolon after template call is consumed'
run_test contains public/blank.html 'BLANK-TEMPLATE-CONTENT &excl;' 'blank template parses content directly'
run_test exists public/custom/text.txt 'custom output extension created'
run_test contains public/custom/text.txt 'CUSTOM-TEXT-CONTENT' 'custom content/output extension content'

# Generated output preserves the source content file's permissions (skip where
# stat mode differs/unavailable).
if command -v stat >/dev/null 2>&1; then
  TESTS=$((TESTS+1))
  source_mode="$(stat -c '%a' content/basic/content.html 2>/dev/null || true)"
  mode="$(stat -c '%a' public/basic/content.html 2>/dev/null || true)"
  [[ -n "$source_mode" && "$mode" == "$source_mode" ]] ||
    fail "generated output expected mode $source_mode (the source content file's permissions), got '$mode'"
fi

# ----- Incremental dependency graph tests -----
mtime(){ stat -c '%Y' "$1"; }
sleep 1.1
A0=$(mtime public/shared/a.html); B0=$(mtime public/shared/b.html); U0=$(mtime public/unrelated.html)
printf '\nSHARED-PARTIAL-v2\n' >> templates/partials/shared.html
if ! "$NIFT_BIN" build >/dev/null 2>"$TMP_ROOT/incremental-shared.err"; then fail 'incremental shared-partial build failed'; cat "$TMP_ROOT/incremental-shared.err" >&2; fi
A1=$(mtime public/shared/a.html); B1=$(mtime public/shared/b.html); U1=$(mtime public/unrelated.html)
TESTS=$((TESTS+3))
[[ "$A1" -gt "$A0" ]] || fail 'shared partial change did not rebuild shared/a'
[[ "$B1" -gt "$B0" ]] || fail 'shared partial change did not rebuild shared/b'
[[ "$U1" -eq "$U0" ]] || fail 'shared partial change unexpectedly rebuilt unrelated page'
# restore partial and rebuild baseline quietly
printf 'SHARED-PARTIAL-v1\n' > templates/partials/shared.html
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'failed restoring shared partial baseline'

sleep 1.1
A0=$(mtime public/shared/a.html); B0=$(mtime public/shared/b.html)
printf '\nEDIT-ONE\n' >> content/shared/a.html
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'incremental single-content build failed'
A1=$(mtime public/shared/a.html); B1=$(mtime public/shared/b.html)
TESTS=$((TESTS+2))
[[ "$A1" -gt "$A0" ]] || fail 'single content edit did not rebuild its output'
[[ "$B1" -eq "$B0" ]] || fail 'single content edit unexpectedly rebuilt sibling output'
# restore content
printf 'SHARED-A\n' > content/shared/a.html
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'failed restoring shared/a baseline'

# Explicit @dep should invalidate both pages that declare it.
sleep 1.1
D0=$(mtime public/dependencies/a.html); E0=$(mtime public/dependencies/b.html); U0=$(mtime public/unrelated.html)
printf 'DEP-A-v2\n' > data/dep-a.txt
"$NIFT_BIN" build >/dev/null 2>&1 || fail '@dep incremental build failed'
D1=$(mtime public/dependencies/a.html); E1=$(mtime public/dependencies/b.html); U1=$(mtime public/unrelated.html)
TESTS=$((TESTS+3))
[[ "$D1" -gt "$D0" ]] || fail '@dep change did not rebuild dependencies/a'
[[ "$E1" -gt "$E0" ]] || fail '@dep change did not rebuild dependencies/b'
[[ "$U1" -eq "$U0" ]] || fail '@dep change unexpectedly rebuilt unrelated page'
printf 'DEP-A-v1\n' > data/dep-a.txt
"$NIFT_BIN" build >/dev/null 2>&1 || fail 'failed restoring @dep baseline'

# ----- Expected failure harness -----
make_failure_project(){
  local name="$1" template="$2" content="$3"
  local d="$TMP_ROOT/fail-$name"
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public"
  cat > "$d/.nift/config.json" <<'EOF'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/t.html","build-threads":1,"incremental-mode":"modified"}}
EOF
  cat > "$d/.nift/tracked.json" <<'EOF'
{"tracked":[{"name":"/","title":"Failure fixture","template":"templates/t.html"}]}
EOF
  printf '%s' "$template" > "$d/templates/t.html"
  printf '%s' "$content" > "$d/content/index.html"
  printf '%s' "$d"
}
expect_failure(){
  local name="$1" needle="$2" template="$3" content="${4:-CONTENT}"
  TESTS=$((TESTS+1))
  local d log rc
  d=$(make_failure_project "$name" "$template" "$content")
  log="$d/log"
  (cd "$d" && "$NIFT_BIN" build --all >"$log" 2>&1); rc=$?
  # Parser/build failures are identified by the expected diagnostic and lack of output.
  # Exit-status propagation is tested separately below as a regression requirement.
  grep -Fq -- "$needle" "$log" || { fail "$name: expected diagnostic missing: $needle"; cat "$log" >&2; return; }
  [[ ! -f "$d/public/index.html" ]] || fail "$name: output file was written despite expected parser/build failure"
}

expect_failure 'input-missing' 'path does not exist' $'@input("does-not-exist.html")\n@content\n'
expect_failure 'input-loop' 'would result in an input loop' $'@input("templates/t.html")\n@content\n'
expect_failure 'pathto-missing' 'is neither a tracked name nor a file that exists' $'@pathto("no/such/target")\n@content\n'
expect_failure 'content-params' 'content: expected 0 parameters' $'@content("bad")\n'
expect_failure 'input-zero-params' 'input: expected 1 parameter' $'@input()\n@content\n'
expect_failure 'getenv-two-params' 'getenv: expected 1 parameter' $'@getenv("A","B")\n@content\n'
expect_failure 'ent-invalid' 'do not currently have an entity value' $'@ent("not-an-entity")\n@content\n'
expect_failure 'dep-zero' 'dep: expected parameters' $'@dep()\n@content\n'
expect_failure 'dep-missing' 'failed as dependency does not exist' $'@dep("missing.dep")\n@content\n'
expect_failure 'content-not-used' 'must execute exactly one @content' $'template deliberately omits content\n'
expect_failure 'content-used-twice' 'may be executed exactly once' $'@content\n@content\n' 'REPEAT-MARKER\n'
expect_failure 'unclosed-pre' 'has no following </pre> close tag' $'<pre>\n@content\n'
expect_failure 'orphan-pre-close' 'close tag has no preceding' $'</pre>\n@content\n'
expect_failure 'unclosed-raw-comment' "open comment '<#--' has no close '--#>'" $'<#-- never closes\n@content\n'


# Surrounding formatting whitespace should not become part of a quoted parameter.
# These are deliberately ordinary formatting styles a user may write.
expect_success_output(){
  local name="$1" expected="$2" template="$3" content="${4:-CONTENT}"
  TESTS=$((TESTS+1))
  local d log
  d=$(make_failure_project "$name" "$template" "$content")
  log="$d/log"
  if ! (cd "$d" && "$NIFT_BIN" build --all >"$log" 2>&1); then
    fail "$name: expected build success"
    return
  fi
  grep -Fq -- "$expected" "$d/public/index.html" || fail "$name: expected output missing: $expected"
}

d=$(make_failure_project 'input-trailing-space' $'@input("templates/child.html" )\n@content\n' 'CONTENT\n')
printf 'CHILD-TRAILING-SPACE\n' >"$d/templates/child.html"
TESTS=$((TESTS+1))
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) ||
   ! grep -Fq 'CHILD-TRAILING-SPACE' "$d/public/index.html" 2>/dev/null; then
  fail '@input quoted parameter with whitespace before ) includes whitespace in the path'
fi

d=$(make_failure_project 'input-multiline-param' $'@input(\n  "templates/child.html"\n)\n@content\n' 'CONTENT\n')
printf 'CHILD-MULTILINE\n' >"$d/templates/child.html"
TESTS=$((TESTS+1))
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) ||
   ! grep -Fq 'CHILD-MULTILINE' "$d/public/index.html" 2>/dev/null; then
  fail '@input multiline formatting includes newline/whitespace in quoted path parameter'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'pathto-trailing-space' $'PATH=@pathto("/" )\n@content\n' 'CONTENT\n')
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) ||
   ! grep -Fq 'PATH=./' "$d/public/index.html" 2>/dev/null; then
  fail '@pathto quoted parameter with whitespace before ) is not trimmed'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'ent-trailing-space' $'ENTITY=@ent("!" )\n@content\n' 'CONTENT\n')
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) ||
   ! grep -Fq 'ENTITY=&excl;' "$d/public/index.html" 2>/dev/null; then
  fail '@ent quoted parameter with whitespace before ) is not trimmed'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'getenv-trailing-space' $'ENV=@getenv("NIFT_TEST_VALUE" )\n@content\n' 'CONTENT\n')
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) ||
   ! grep -Fq 'ENV=hello-env' "$d/public/index.html" 2>/dev/null; then
  fail '@getenv quoted parameter with whitespace before ) silently looks up the wrong variable'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'dep-whitespace' $'@dep("dep-a.txt" , "dep-b.txt" )!\n@content\n' 'CONTENT\n')
printf 'A\n' >"$d/dep-a.txt"; printf 'B\n' >"$d/dep-b.txt"
if ! (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  fail '@dep parameters with normal whitespace around comma/close bracket are not trimmed'
fi

# Backticks are deliberately unsupported as quote delimiters.
TESTS=$((TESTS+1))
d=$(make_failure_project 'backtick-unsupported' $'@input(`templates/child.html`)\n@content\n' 'CONTENT\n')
printf 'CHILD\n' >"$d/templates/child.html"
if (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  fail 'backtick-quoted @input unexpectedly behaves as supported public quote syntax'
fi

# Square brackets are reserved for $[...] metadata in the intended public syntax.
# Generic @ functions accepting them is likely accidental reuse of read_params().
TESTS=$((TESTS+1))
d=$(make_failure_project 'square-bracket-input' $'@input["templates/child.html"]\n@content\n' 'CONTENT\n')
printf 'CHILD\n' >"$d/templates/child.html"
if (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  fail '@input[...] is accepted even though public function-call syntax uses parentheses (syntax-strictness candidate)'
fi

# @content has no parameters, so '[' terminates the function name and the
# following [] is ordinary output text. This is a function-name boundary case,
# not square-bracket function-call syntax.
expect_success_output 'square-bracket-content' 'CONTENT[]' $'@content[]\n' 'CONTENT'


# A build command that reports a failed tracked file should conventionally return non-zero
# so CI/shell scripts can detect failure.
TESTS=$((TESTS+1))
d=$(make_failure_project 'failed-build-exit-status' $'@input("missing")\n@content\n' 'CONTENT\n')
(cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1); rc=$?
[[ $rc -ne 0 ]] || fail 'build --all returns exit status 0 even when a tracked build fails (CI-detection bug candidate)'

# Backticks are intentionally NOT treated as string-quote syntax by this suite.
# Public string/path examples use only single and double quotes.

# Function-name boundary probes.
# The exactly-once @content contract means each boundary form is isolated in its
# own tracked build rather than combining several @content executions in one template.
# Only lower-case letters belong to an @ function name; punctuation, digits,
# underscores and uppercase letters terminate it.
expect_success_output 'content-before-digit' 'BOUNDARY-CONTENT1' $'@content1\n' 'BOUNDARY-CONTENT'
expect_success_output 'content-before-underscore' 'BOUNDARY-CONTENT_suffix' $'@content_suffix\n' 'BOUNDARY-CONTENT'
expect_success_output 'content-before-dash' 'BOUNDARY-CONTENT-after' $'@content-after\n' 'BOUNDARY-CONTENT'
expect_success_output 'content-before-colon' 'BOUNDARY-CONTENT:after' $'@content:after\n' 'BOUNDARY-CONTENT'
expect_success_output 'content-before-uppercase-suffix' 'BOUNDARY-CONTENTX' $'@contentX\n' 'BOUNDARY-CONTENT'
expect_success_output 'uppercase-function-literal' 'UPPER_NAME=@Content' $'UPPER_NAME=@Content\n@content\n' 'BOUNDARY-CONTENT'

# A zero-parameter @content call should stop before ordinary HTML markup.
# These remain isolated so boundary regressions cannot make the main positive website unbuildable.

TESTS=$((TESTS+1))
d=$(make_failure_project 'content-before-open-tag' $'<main>
@content<div id="after">AFTER-CONTENT</div>
</main>
' 'BOUNDARY-CONTENT
')
if (cd "$d" && "$NIFT_BIN" build --all >"$d/out" 2>"$d/err"); then
  if [[ -f "$d/public/index.html" ]] &&
     grep -Fq 'BOUNDARY-CONTENT' "$d/public/index.html" &&
     grep -Fq '<div id="after">AFTER-CONTENT</div>' "$d/public/index.html"; then
    :
  else
    fail '@content immediately followed by an opening HTML tag did not split at < (function-name boundary bug candidate)'
  fi
else
  fail '@content immediately followed by an opening HTML tag fails to build (function-name boundary bug candidate)'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'content-before-close-tag' $'<main>
@content</main>
' 'BOUNDARY-CONTENT
')
if (cd "$d" && "$NIFT_BIN" build --all >"$d/out" 2>"$d/err"); then
  if [[ -f "$d/public/index.html" ]] &&
     grep -Fq 'BOUNDARY-CONTENT' "$d/public/index.html" &&
     grep -Fq '</main>' "$d/public/index.html"; then
    :
  else
    fail '@content immediately followed by a closing HTML tag did not split at < (function-name boundary bug candidate)'
  fi
else
  fail '@content immediately followed by a closing HTML tag fails to build (function-name boundary bug candidate)'
fi

TESTS=$((TESTS+1))
d=$(make_failure_project 'content-before-html-comment' $'@content<!-- AFTER-CONTENT-COMMENT -->
' 'BOUNDARY-CONTENT
')
if (cd "$d" && "$NIFT_BIN" build --all >"$d/out" 2>"$d/err"); then
  if [[ -f "$d/public/index.html" ]] &&
     grep -Fq 'BOUNDARY-CONTENT' "$d/public/index.html" &&
     grep -Fq '<!-- AFTER-CONTENT-COMMENT -->' "$d/public/index.html"; then
    :
  else
    fail '@content immediately followed by an HTML comment did not split at < (function-name boundary bug candidate)'
  fi
else
  fail '@content immediately followed by an HTML comment fails to build (function-name boundary bug candidate)'
fi

# ----- CLI mutation smoke tests in isolated copy -----
CLI="$TMP_ROOT/cli"
mkdir -p "$CLI"
cp -a .nift content templates public "$CLI/" 2>/dev/null || true
(cd "$CLI" && chmod -R u+w . >/dev/null 2>&1)
cli(){ (cd "$CLI" && "$NIFT_BIN" "$@" >/dev/null 2>"$TMP_ROOT/cli.err"); }
TESTS=$((TESTS+1)); cli track cli-new 'CLI New' || fail 'CLI track failed'; [[ -f "$CLI/content/cli-new.html" ]] || fail 'CLI track did not create content file'
printf 'CLI NEW CONTENT\n' > "$CLI/content/cli-new.html"
TESTS=$((TESTS+1)); cli build cli-new || fail 'CLI build name failed'; [[ -f "$CLI/public/cli-new.html" ]] || fail 'CLI build name did not create output'
TESTS=$((TESTS+1)); cli cp cli-new cli-copy || fail 'CLI cp failed'; [[ -f "$CLI/content/cli-copy.html" ]] || fail 'CLI cp did not copy content'
TESTS=$((TESTS+1)); cli mv cli-copy cli-moved || fail 'CLI mv failed'; [[ -f "$CLI/content/cli-moved.html" ]] || fail 'CLI mv did not move content'
TESTS=$((TESTS+1)); cli untrack cli-moved || fail 'CLI untrack failed'; [[ -f "$CLI/content/cli-moved.html" ]] || fail 'CLI untrack unexpectedly removed content'
TESTS=$((TESTS+1)); cli rm cli-new || fail 'CLI rm failed'; [[ ! -f "$CLI/content/cli-new.html" ]] || fail 'CLI rm did not remove content'

# init smoke test
INIT="$TMP_ROOT/init"; mkdir -p "$INIT"
TESTS=$((TESTS+1))
if ! (cd "$INIT" && "$NIFT_BIN" init >/dev/null 2>"$TMP_ROOT/init.err"); then
  fail 'nift init failed'
else
  [[ -f "$INIT/.nift/config.json" ]] || fail 'init missing config.json'
  [[ -f "$INIT/.nift/tracked.json" ]] || fail 'init missing tracked.json'
  [[ -f "$INIT/public/index.html" ]] || fail 'init did not build public/index.html'
fi

# ----- Incremental mode semantics -----
test_hash_detection(){
  local mode="$1" should_rebuild="$2"
  local d="$TMP_ROOT/mode-$mode"
  cp -a "$ROOT" "$d"
  chmod -R u+w "$d" >/dev/null 2>&1 || true
  # Ensure the copied project has a clean baseline and requested mode.
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$mode mode baseline build failed"; return; }
  cp -p "$d/content/unrelated.html" "$d/stamp"
  before=$(stat -c '%Y' "$d/public/unrelated.html")
  printf 'HASH-MODE-CHANGED\n' > "$d/content/unrelated.html"
  touch -r "$d/stamp" "$d/content/unrelated.html"
  sleep 1.1
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$mode mode incremental build failed"; return; }
  after=$(stat -c '%Y' "$d/public/unrelated.html")
  TESTS=$((TESTS+1))
  if [[ "$should_rebuild" == yes ]]; then
    [[ "$after" -gt "$before" ]] || fail "$mode mode failed to detect content change with preserved mtime"
  else
    [[ "$after" -eq "$before" ]] || fail "$mode mode unexpectedly detected hash-only change"
  fi
}
test_hash_detection modified no
test_hash_detection hash yes
test_hash_detection hybrid yes

# Info commands should work on the isolated CLI project.
for cmd in "info --all" "info --names" "info --tracking" "info --watching" "status"; do
  TESTS=$((TESTS+1)); cli $cmd || fail "CLI $cmd failed"
done

# Watch/unwatch smoke test using a content subdirectory.
mkdir -p "$CLI/content/watch-fixture"
printf 'WATCHED\n' > "$CLI/content/watch-fixture/a.html"
TESTS=$((TESTS+1)); cli watch content/watch-fixture/ || fail 'CLI watch failed'
TESTS=$((TESTS+1))
(cd "$CLI" && "$NIFT_BIN" info --watching >"$TMP_ROOT/watching.log" 2>&1) || fail 'CLI info --watching after watch failed'
grep -Fq 'content/watch-fixture/' "$TMP_ROOT/watching.log" || fail 'info --watching does not see directory just added by watch (new .nift/.watch vs old .nift/.watchinfo path bug candidate)'
TESTS=$((TESTS+1)); cli unwatch content/watch-fixture/ || fail 'CLI unwatch failed'



# More CLI/Watch coverage in isolated projects.
TESTS=$((TESTS+1)); cli info cli-new custom/text >/dev/null 2>&1 || fail 'CLI info with multiple names failed'

# copy/move aliases should preserve custom content/output extensions.
TESTS=$((TESTS+1)); cli copy custom/text custom/copied-text || fail 'CLI copy alias/custom extension failed'
[[ -f "$CLI/content/custom/copied-text.txt" ]] || fail 'copy did not preserve custom content extension'
TESTS=$((TESTS+1)); cli build custom/copied-text || fail 'build copied custom-extension item failed'
[[ -f "$CLI/public/custom/copied-text.txt" ]] || fail 'copy did not preserve custom output extension'
TESTS=$((TESTS+1)); cli move custom/copied-text custom/moved-text || fail 'CLI move alias/custom extension failed'
[[ -f "$CLI/content/custom/moved-text.txt" ]] || fail 'move did not preserve custom content extension'
TESTS=$((TESTS+1)); cli del custom/moved-text || fail 'CLI del alias failed'
[[ ! -f "$CLI/content/custom/moved-text.txt" ]] || fail 'del alias did not remove custom-extension content'

# Multiple untrack names should remove both tracking entries while preserving content.
TESTS=$((TESTS+1))
(cd "$CLI" && "$NIFT_BIN" track multi-u-one >/dev/null 2>&1 && "$NIFT_BIN" track multi-u-two >/dev/null 2>&1)
(cd "$CLI" && "$NIFT_BIN" untrack multi-u-one multi-u-two >/dev/null 2>&1) || fail 'untrack multiple names failed'
grep -Fq '"name": "multi-u-one"' "$CLI/.nift/tracked.json" && fail 'untrack multiple left first name tracked'
grep -Fq '"name": "multi-u-two"' "$CLI/.nift/tracked.json" && fail 'untrack multiple left second name tracked'
[[ -f "$CLI/content/multi-u-one.html" && -f "$CLI/content/multi-u-two.html" ]] || fail 'untrack multiple removed content files'

# Running a project command from a nested subdirectory should locate the project root.
TESTS=$((TESTS+1))
(cd "$CLI/content/groups" && "$NIFT_BIN" info --names >/dev/null 2>&1) || fail 'project discovery from nested subdirectory failed'

# Watch should auto-track new matching files on the next build and remove tracking/output
# when a previously auto-tracked source disappears.
TESTS=$((TESTS+1))
WA="$TMP_ROOT/watch-auto"
mkdir -p "$WA"
(cd "$WA" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$WA/content/articles"
printf '@content\n' >"$WA/templates/article.html"
(cd "$WA" && "$NIFT_BIN" watch content/articles/ .md templates/article.html .html >/dev/null 2>&1) || fail 'watch custom extension setup failed'
printf 'WATCH-AUTO\n' >"$WA/content/articles/first.md"
if ! (cd "$WA" && "$NIFT_BIN" build >"$TMP_ROOT/watch-auto.log" 2>&1); then
  fail 'first build after watch fails because .nift/.watch/<dir>/tracked.json has not been initialized'
else
  grep -Fq '"name": "articles/first"' "$WA/.nift/tracked.json" || fail 'watch did not auto-track new matching file'
  [[ -f "$WA/public/articles/first.html" ]] || fail 'watch auto-tracked file did not build expected output'
  rm -f "$WA/content/articles/first.md"
  if (cd "$WA" && "$NIFT_BIN" build >/dev/null 2>&1); then
    grep -Fq '"name": "articles/first"' "$WA/.nift/tracked.json" && fail 'watch kept tracking a removed auto-tracked content file'
    [[ ! -e "$WA/public/articles/first.html" ]] || fail 'watch did not remove output for removed auto-tracked content file'
  else
    fail 'watch removal reconciliation build failed after successful auto-track'
  fi
fi

# Removed init spellings must fail clearly.
TESTS=$((TESTS+1))
IH="$TMP_ROOT/init-html"; mkdir -p "$IH"
if (cd "$IH" && "$NIFT_BIN" init-html >"$TMP_ROOT/init-html.out" 2>"$TMP_ROOT/init-html.err"); then
  fail 'removed init-html command still succeeds'
else
  grep -Fq "command 'init-html' has been removed" "$TMP_ROOT/init-html.err" || fail 'init-html removal diagnostic missing'
fi

TESTS=$((TESTS+1))
IP="$TMP_ROOT/init-positional"; mkdir -p "$IP"
if (cd "$IP" && "$NIFT_BIN" init .html >"$TMP_ROOT/init-positional.out" 2>"$TMP_ROOT/init-positional.err"); then
  fail 'removed positional init extension still succeeds'
else
  grep -Fq 'positional init arguments are no longer supported' "$TMP_ROOT/init-positional.err" || fail 'positional init removal diagnostic missing'
fi

# Invalid options on commands that explicitly enumerate options should fail cleanly.
for badcmd in "status" "build" "build --all"; do
  TESTS=$((TESTS+1))
  if (cd "$CLI" && "$NIFT_BIN" "$badcmd" -definitely-invalid >/dev/null 2>&1); then
    fail "$badcmd accepts an unknown option"
  fi
done

TESTS=$((TESTS+1))
if (cd "$CLI" && "$NIFT_BIN" definitely-not-a-command >/dev/null 2>&1); then
  fail 'unknown command returns success'
fi


# ----- Additional v0.5 source-driven regression probes -----

# CLI aliases that are intentionally implemented.
TESTS=$((TESTS+1)); "$NIFT_BIN" about >"$TMP_ROOT/about.log" 2>&1 || fail 'about alias failed'
TESTS=$((TESTS+1)); "$NIFT_BIN" cmds >"$TMP_ROOT/cmds.log" 2>&1 || fail 'cmds alias failed'

# Progress/display options should not crash or hang. In particular this exercises
# build_progress(), whose phase-transition path is easy to get wrong. Run in a
# fresh init'd project (the shared CLI fixture intentionally contains pages with
# missing dependencies that make a full build fail by design).
PROJ="$TMP_ROOT/progress"; mkdir -p "$PROJ"
(cd "$PROJ" && "$NIFT_BIN" init >/dev/null 2>&1)
for cmdline in "status -p" "build -p" "build --all -p"; do
  TESTS=$((TESTS+1))
  (cd "$PROJ" && "$NIFT_BIN" $cmdline >"$TMP_ROOT/progress.log" 2>&1) || fail "$cmdline failed"
done

# rm advertises/accepts multiple names at the dispatcher level. Both must actually
# be removed, rather than argv[2] being processed repeatedly.
TESTS=$((TESTS+1))
RMCLI="$TMP_ROOT/rm-multiple"
cp -a "$CLI" "$RMCLI"
(cd "$RMCLI" && "$NIFT_BIN" track rm-one >/dev/null 2>&1 && "$NIFT_BIN" track rm-two >/dev/null 2>&1)
printf 'ONE\n' >"$RMCLI/content/rm-one.html"
printf 'TWO\n' >"$RMCLI/content/rm-two.html"
(cd "$RMCLI" && "$NIFT_BIN" build rm-one rm-two >/dev/null 2>&1)
(cd "$RMCLI" && "$NIFT_BIN" rm rm-one rm-two >"$TMP_ROOT/rm-multiple.log" 2>&1)
if grep -Fq '"name": "rm-one"' "$RMCLI/.nift/tracked.json" ||
   grep -Fq '"name": "rm-two"' "$RMCLI/.nift/tracked.json" ||
   [[ -e "$RMCLI/content/rm-one.html" || -e "$RMCLI/content/rm-two.html" ]]; then
  fail 'rm with multiple names does not remove every supplied name (argv indexing bug candidate)'
fi

# Saving an empty tracking set must still produce valid JSON that the next Nift
# invocation can reopen.
TESTS=$((TESTS+1))
EMPTY="$TMP_ROOT/empty-tracking"
mkdir -p "$EMPTY"
(cd "$EMPTY" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$EMPTY" && "$NIFT_BIN" untrack / assets/css/style assets/js/script >/dev/null 2>&1) || fail 'untracking all initial files failed'
python3 -S -m json.tool "$EMPTY/.nift/tracked.json" >/dev/null 2>&1 || fail 'saving zero tracked files produces invalid tracked.json'
(cd "$EMPTY" && "$NIFT_BIN" info --all >/dev/null 2>&1) || fail 'Nift cannot reopen project after all files are untracked'

# Titles with one quote type are explicitly accepted by track(), so save_tracking()
# must JSON-escape them instead of corrupting tracked.json.
TESTS=$((TESTS+1))
QUOTED="$TMP_ROOT/quoted-title"
mkdir -p "$QUOTED"
(cd "$QUOTED" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$QUOTED" && "$NIFT_BIN" track quote-title 'He said "Hi"' >/dev/null 2>&1) || fail 'track rejected title containing only double quotes'
python3 -S -m json.tool "$QUOTED/.nift/tracked.json" >/dev/null 2>&1 || fail 'track title containing double quotes corrupts tracked.json (JSON escaping bug candidate)'
(cd "$QUOTED" && "$NIFT_BIN" info quote-title >/dev/null 2>&1) || fail 'project cannot reopen after quoted title is saved'

# A requested untracked name is an unsuccessful targeted build and should be
# detectable by shell/CI.
TESTS=$((TESTS+1))
if (cd "$CLI" && "$NIFT_BIN" build definitely-not-tracked >"$TMP_ROOT/build-untracked.log" 2>&1); then
  fail 'build of an untracked requested name returns success status'
fi

# A parser failure in build must propagate a non-zero status and must not
# report that every requested file built successfully.
TESTS=$((TESTS+1))
BN="$TMP_ROOT/build-name-failure"
mkdir -p "$BN"
(cd "$BN" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '@input("missing-build-name-file")' '@content' >"$BN/templates/template.html"
if (cd "$BN" && "$NIFT_BIN" build / >"$TMP_ROOT/build-name-failure.log" 2>&1); then
  fail 'targeted build returns success status when parser/build fails (build_names failure propagation bug candidate)'
fi
grep -Fq 'all 1 specified files built successfully' "$TMP_ROOT/build-name-failure.log" &&
  fail 'targeted failed build misleadingly reports all specified files built successfully'

# build must propagate failures too.
TESTS=$((TESTS+1))
BU="$TMP_ROOT/build-failure"
mkdir -p "$BU"
(cd "$BU" && "$NIFT_BIN" init >/dev/null 2>&1)
sleep 1.1
printf '%s\n' '@input("missing-updated-file")' '@content' >"$BU/templates/template.html"
if (cd "$BU" && "$NIFT_BIN" build >"$TMP_ROOT/build-failure.log" 2>&1); then
  fail 'build returns success status after an updated page fails to build'
fi

# If generated output disappears while the info/dependency state remains,
# build should recreate it.
TESTS=$((TESTS+1))
MISSOUT="$TMP_ROOT/missing-output"
mkdir -p "$MISSOUT"
(cd "$MISSOUT" && "$NIFT_BIN" init >/dev/null 2>&1)
rm -f "$MISSOUT/public/index.html"
(cd "$MISSOUT" && "$NIFT_BIN" build >/dev/null 2>&1) || fail 'build failed while checking missing output'
[[ -f "$MISSOUT/public/index.html" ]] || fail 'build considers a deleted generated output up to date'

# @dep accepts paths (path_exists), so an unchanged directory dependency should
# not be classified as removed and rebuilt on every incremental check.
TESTS=$((TESTS+1))
DEPDIR="$TMP_ROOT/dep-directory"
mkdir -p "$DEPDIR/.nift" "$DEPDIR/content" "$DEPDIR/templates" "$DEPDIR/public" "$DEPDIR/data-dir"
cat >"$DEPDIR/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
cat >"$DEPDIR/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"dep-dir","template":"templates/template.html"}]}
JSON
printf 'CONTENT\n' >"$DEPDIR/content/index.html"
printf '%s\n' '@dep("data-dir")!' '@content' >"$DEPDIR/templates/template.html"
(cd "$DEPDIR" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'directory @dep initial build failed'
before=$(stat -c %Y "$DEPDIR/public/index.html")
sleep 1.1
(cd "$DEPDIR" && "$NIFT_BIN" build >"$TMP_ROOT/dep-dir.log" 2>&1) || fail 'directory @dep incremental check failed'
after=$(stat -c %Y "$DEPDIR/public/index.html")
[[ "$after" -eq "$before" ]] || fail 'unchanged directory @dep is treated as removed/updated on every incremental build'

# Malformed persistent JSON should produce a controlled non-zero diagnostic, not
# abort via a RapidJSON assertion.
check_no_abort(){
  local label="$1"; shift
  TESTS=$((TESTS+1))
  local had_errexit=0
  case $- in *e*) had_errexit=1; set +e ;; esac
  ( "$@" >"$TMP_ROOT/no-abort.log" 2>&1 ) 2>/dev/null
  local rc=$?
  if [[ $had_errexit -eq 1 ]]; then set -e; fi
  if [[ $rc -ge 128 || $rc -lt 0 ]]; then
    fail "$label aborts/crashes instead of returning a controlled error"
  elif [[ $rc -eq 0 ]]; then
    fail "$label unexpectedly succeeds"
  fi
}

MAL="$TMP_ROOT/malformed-tracked"
mkdir -p "$MAL"
(cd "$MAL" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '{"tracked":[123]}' >"$MAL/.nift/tracked.json"
check_no_abort 'tracked.json with non-object array member' bash -c "cd '$MAL' && '$NIFT_BIN' info --all"

MW="$TMP_ROOT/malformed-watch"
mkdir -p "$MW"
(cd "$MW" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$MW/.nift/.watch"
printf '%s\n' 'not json' >"$MW/.nift/.watch/watched.json"
check_no_abort 'malformed watched.json' bash -c "cd '$MW' && '$NIFT_BIN' info --watching"

ME="$TMP_ROOT/malformed-watch-ext"
mkdir -p "$ME"
(cd "$ME" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$ME/content/w"
(cd "$ME" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1) || fail 'watch setup for malformed exts probe failed'
printf '%s\n' 'not json' >"$ME/.nift/.watch/content/w/exts.json"
check_no_abort 'malformed watched exts.json' bash -c "cd '$ME' && '$NIFT_BIN' info --watching"

# build should reject unknown options and options with no names.
TESTS=$((TESTS+1))
if (cd "$CLI" && "$NIFT_BIN" build -definitely-invalid cli-new >"$TMP_ROOT/build-option.log" 2>&1); then
  fail 'build accepts an unknown leading option'
fi
TESTS=$((TESTS+1))
if (cd "$CLI" && "$NIFT_BIN" build -p >"$TMP_ROOT/build-no-names.log" 2>&1); then
  fail 'build accepts an option with no tracked names'
fi


# build-threads=0 must either be rejected or still build correctly. Silently spawning
# zero workers and reporting success without outputs is not acceptable.
TESTS=$((TESTS+1))
ZERO="$TMP_ROOT/zero-build-threads"
mkdir -p "$ZERO"
(cd "$ZERO" && "$NIFT_BIN" init >/dev/null 2>&1)
rm -f "$ZERO/public/index.html"
sed -i 's/"build-threads":[[:space:]]*-1/"build-threads": 0/' "$ZERO/.nift/config.json"
had_errexit=0
case $- in *e*) had_errexit=1; set +e ;; esac
(cd "$ZERO" && "$NIFT_BIN" build --all >"$TMP_ROOT/zero-threads.log" 2>&1)
zero_rc=$?
if [[ $had_errexit -eq 1 ]]; then set -e; fi
if [[ $zero_rc -eq 0 && ! -f "$ZERO/public/index.html" ]]; then
  fail 'build-threads=0 reports success while spawning no workers and producing no requested output'
fi

# A tracked name must not escape content/output roots using ../ components.
TESTS=$((TESTS+1))
TRAV_PARENT="$TMP_ROOT/traversal-parent"
TRAV="$TRAV_PARENT/project"
mkdir -p "$TRAV"
(cd "$TRAV" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$TRAV" && "$NIFT_BIN" track ../escape 'Traversal probe' >"$TMP_ROOT/traversal.log" 2>&1); then
  fail 'track accepts ../ name that escapes configured content/output directories'
fi
[[ ! -e "$TRAV_PARENT/escape.html" ]] || fail 'tracking ../escape created a file outside the project content/output roots'

# ---------------------------------------------------------------------------
# v0.8 adversarial expansion
# ---------------------------------------------------------------------------

# User-defined *.deps.json must reject malformed/structurally invalid JSON
# without allowing RapidJSON assertions to abort the process.
make_bad_user_deps_case(){
  local label="$1"
  local json="$2"
  local d="$TMP_ROOT/user-deps-bad-$TESTS"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1) || return
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || return
  printf '%s\n' "$json" >"$d/content/index.deps.json"
  check_no_abort "$label" bash -c "cd '$d' && '$NIFT_BIN' build"
}
make_bad_user_deps_case 'user deps JSON with array root aborts/crashes instead of returning controlled error' '[123]'
make_bad_user_deps_case 'malformed user deps JSON aborts/crashes instead of returning controlled error' '{"dependencies":['

# Hash and hybrid modes should honour user-defined dependencies just as parser
# @dep dependencies do. Preserve mtime so only the hash can detect the edit.
make_user_dep_hash_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/user-dep-$mode"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label setup failed"; return; }
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  mkdir -p "$d/data"
  printf 'ONE\n' >"$d/data/user.txt"
  printf '%s\n' '{"dependencies":["data/user.txt"]}' >"$d/content/index.deps.json"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label baseline build failed"; return; }
  local before oldtime after
  before=$(stat -c %Y "$d/public/index.html")
  oldtime=$(stat -c %y "$d/data/user.txt")
  sleep 1.1
  printf 'TWO\n' >"$d/data/user.txt"
  touch -d "$oldtime" "$d/data/user.txt"
  TESTS=$((TESTS+1))
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -gt "$before" ]] || fail "$label misses user-defined dependency content change when mtime is preserved"
}
make_user_dep_hash_case hash 'hash-mode user-defined dependency'
make_user_dep_hash_case hybrid 'hybrid-mode user-defined dependency'

# Directory @dep hashing must include child contents, not just entry names.
make_dirdep_content_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/dirdep-content-$mode"
  mkdir -p "$d/content" "$d/templates" "$d/public" "$d/data-dir"
  mkdir -p "$d/.nift"
  cat >"$d/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"$mode"}}
JSON
  cat >"$d/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"dirdep","template":"templates/template.html"}]}
JSON
  printf 'CONTENT\n' >"$d/content/index.html"
  printf 'A\n' >"$d/data-dir/a.txt"
  printf '%s\n' '@dep("data-dir")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label baseline build failed"; return; }
  local before oldtime after
  before=$(stat -c %Y "$d/public/index.html")
  oldtime=$(stat -c %y "$d/data-dir/a.txt")
  sleep 1.1
  printf 'B\n' >"$d/data-dir/a.txt"
  touch -d "$oldtime" "$d/data-dir/a.txt"
  TESTS=$((TESTS+1))
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -gt "$before" ]] || fail "$label does not rebuild when existing file contents change inside directory @dep"
}
make_dirdep_content_case hash 'hash-mode directory @dep child-content change'
make_dirdep_content_case hybrid 'hybrid-mode directory @dep child-content change'

# Nested directory members must participate recursively in directory hashes.
make_dirdep_nested_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/dirdep-nested-$mode"
  mkdir -p "$d/content" "$d/templates" "$d/public" "$d/data-dir/sub" "$d/.nift"
  cat >"$d/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"$mode"}}
JSON
  printf '%s\n' '{"tracked":[{"name":"/","title":"nested","template":"templates/template.html"}]}' >"$d/.nift/tracked.json"
  printf 'CONTENT\n' >"$d/content/index.html"
  printf 'A\n' >"$d/data-dir/sub/a.txt"
  printf '%s\n' '@dep("data-dir")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label baseline build failed"; return; }
  local before oldtime after
  before=$(stat -c %Y "$d/public/index.html")
  oldtime=$(stat -c %y "$d/data-dir/sub/a.txt")
  sleep 1.1
  printf 'B\n' >"$d/data-dir/sub/a.txt"
  touch -d "$oldtime" "$d/data-dir/sub/a.txt"
  TESTS=$((TESTS+1))
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -gt "$before" ]] || fail "$label misses nested child-content change inside directory @dep"
}
make_dirdep_nested_case hash 'hash-mode recursive directory @dep'
make_dirdep_nested_case hybrid 'hybrid-mode recursive directory @dep'

# tracked.json may be valid while generated page info JSON is not: all strings
# emitted into .info.json need JSON escaping too.
TESTS=$((TESTS+1))
INFOQUOTE="$TMP_ROOT/info-title-quote"
mkdir -p "$INFOQUOTE"
(cd "$INFOQUOTE" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$INFOQUOTE" && "$NIFT_BIN" track quote-title 'A "quoted" title' >/dev/null 2>&1) || fail 'quoted-title info setup track failed'
if (cd "$INFOQUOTE" && "$NIFT_BIN" build quote-title >/dev/null 2>&1); then
  python3 -S -m json.tool "$INFOQUOTE/.nift/public/quote-title.info.json" >/dev/null 2>&1 || fail 'quoted title corrupts generated page info JSON'
else
  fail 'quoted-title page failed to build'
fi

TESTS=$((TESTS+1))
INFONAME="$TMP_ROOT/info-name-quote"
mkdir -p "$INFONAME"
(cd "$INFONAME" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$INFONAME" && "$NIFT_BIN" track 'q"name' >/dev/null 2>&1); then
  (cd "$INFONAME" && "$NIFT_BIN" build 'q"name' >/dev/null 2>&1) || fail 'quoted-name page failed to build'
  python3 -S -m json.tool "$INFONAME/.nift/public/q\"name.info.json" >/dev/null 2>&1 || fail 'quoted tracked name corrupts generated page info JSON'
fi

# cp/mv currently pre-escape the in-memory name and save_tracking escapes it
# again. Verify accepted quoted names round-trip as the same tracked name.
make_copy_move_quote_roundtrip(){
  local op="$1"
  local label="$2"
  local d="$TMP_ROOT/${op}-quote-roundtrip"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  TESTS=$((TESTS+1))
  if (cd "$d" && "$NIFT_BIN" "$op" / 'q"x' >/dev/null 2>&1); then
    local ilog="$TMP_ROOT/${op}-quote-info.log"
    (cd "$d" && "$NIFT_BIN" info 'q"x' >"$ilog" 2>&1) || true
    grep -Fq 'Nift is not tracking' "$ilog" && fail "$label double-escapes quoted destination so it cannot be reopened by the same name"
  fi
}
make_copy_move_quote_roundtrip cp 'cp quoted-name round trip'
make_copy_move_quote_roundtrip mv 'mv quoted-name round trip'


# Template paths and @input dependency paths are also serialized into page
# .info.json and need the same escaping as tracked.json.
TESTS=$((TESTS+1))
INFOTPL="$TMP_ROOT/info-template-quote"
mkdir -p "$INFOTPL"
(cd "$INFOTPL" && "$NIFT_BIN" init >/dev/null 2>&1)
cp "$INFOTPL/templates/template.html" "$INFOTPL/templates/q\"template.html"
if (cd "$INFOTPL" && "$NIFT_BIN" track qtpl 'Quoted template' 'templates/q"template.html' >/dev/null 2>&1); then
  (cd "$INFOTPL" && "$NIFT_BIN" build qtpl >/dev/null 2>&1) || fail 'quoted-template page failed to build'
  python3 -S -m json.tool "$INFOTPL/.nift/public/qtpl.info.json" >/dev/null 2>&1 || fail 'quoted template path corrupts generated page info JSON'
fi

TESTS=$((TESTS+1))
INFOINPUT="$TMP_ROOT/info-input-quote"
mkdir -p "$INFOINPUT/content" "$INFOINPUT/templates" "$INFOINPUT/partials" "$INFOINPUT/.nift"
cat >"$INFOINPUT/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
printf '%s\n' '{"tracked":[{"name":"/","title":"inputquote","template":"templates/template.html"}]}' >"$INFOINPUT/.nift/tracked.json"
printf 'CONTENT\n' >"$INFOINPUT/content/index.html"
printf 'PARTIAL\n' >"$INFOINPUT/partials/q\"input.html"
printf '%s\n' '@input("partials/q\"input.html")!' '@content' >"$INFOINPUT/templates/template.html"
if (cd "$INFOINPUT" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  python3 -S -m json.tool "$INFOINPUT/.nift/public/index.info.json" >/dev/null 2>&1 || fail 'quoted @input path corrupts generated page info JSON'
fi

# Adding a file below an already-present nested subdirectory must also change a
# recursive directory dependency hash.
make_dirdep_nested_add_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/dirdep-nested-add-$mode"
  mkdir -p "$d/content" "$d/templates" "$d/public" "$d/data-dir/sub" "$d/.nift"
  cat >"$d/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"$mode"}}
JSON
  printf '%s\n' '{"tracked":[{"name":"/","title":"nested-add","template":"templates/template.html"}]}' >"$d/.nift/tracked.json"
  printf 'CONTENT\n' >"$d/content/index.html"
  printf 'A\n' >"$d/data-dir/sub/a.txt"
  printf '%s\n' '@dep("data-dir")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label baseline build failed"; return; }
  local before after
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  printf 'B\n' >"$d/data-dir/sub/b.txt"
  TESTS=$((TESTS+1))
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -gt "$before" ]] || fail "$label misses file addition inside nested subdirectory"
}
make_dirdep_nested_add_case hash 'hash-mode recursive directory @dep nested addition'
make_dirdep_nested_add_case hybrid 'hybrid-mode recursive directory @dep nested addition'

# Watch metadata strings other than watchDir must also be escaped if accepted.
TESTS=$((TESTS+1))
WEXTQUOTE="$TMP_ROOT/watch-ext-quote"
mkdir -p "$WEXTQUOTE/content/w"
(cd "$WEXTQUOTE" && "$NIFT_BIN" init >/dev/null 2>&1)
printf 'X\n' >"$WEXTQUOTE/content/w/a.\"x"
if (cd "$WEXTQUOTE" && "$NIFT_BIN" watch content/w/ '."x' templates/template.html .html >/dev/null 2>&1); then
  python3 -S -m json.tool "$WEXTQUOTE/.nift/.watch/content/w/exts.json" >/dev/null 2>&1 || fail 'quoted watched content extension corrupts exts.json'
fi

TESTS=$((TESTS+1))
WOUTQUOTE="$TMP_ROOT/watch-output-ext-quote"
mkdir -p "$WOUTQUOTE/content/w"
(cd "$WOUTQUOTE" && "$NIFT_BIN" init >/dev/null 2>&1)
printf 'X\n' >"$WOUTQUOTE/content/w/a.html"
if (cd "$WOUTQUOTE" && "$NIFT_BIN" watch content/w/ .html templates/template.html '."out' >/dev/null 2>&1); then
  python3 -S -m json.tool "$WOUTQUOTE/.nift/.watch/content/w/exts.json" >/dev/null 2>&1 || fail 'quoted watched output extension corrupts exts.json'
fi

# A dependency filename containing quotes is legal on POSIX; if accepted by
# @dep it must not corrupt the generated dependencies array in page info.
TESTS=$((TESTS+1))
DEPQUOTE="$TMP_ROOT/dep-path-quote"
mkdir -p "$DEPQUOTE/content" "$DEPQUOTE/templates" "$DEPQUOTE/data" "$DEPQUOTE/.nift"
cat >"$DEPQUOTE/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
printf '%s\n' '{"tracked":[{"name":"/","title":"depquote","template":"templates/template.html"}]}' >"$DEPQUOTE/.nift/tracked.json"
printf 'CONTENT\n' >"$DEPQUOTE/content/index.html"
printf 'DEP\n' >"$DEPQUOTE/data/q\"dep.txt"
printf '%s\n' '@dep("data/q\"dep.txt")!' '@content' >"$DEPQUOTE/templates/template.html"
if (cd "$DEPQUOTE" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  python3 -S -m json.tool "$DEPQUOTE/.nift/public/index.info.json" >/dev/null 2>&1 || fail 'quoted @dep path corrupts generated page info JSON'
fi


# Hash-mode build --auto: after two separate edits in one long-running process,
# the second rebuild must refresh hash state so it does not rebuild forever.
TESTS=$((TESTS+1))
AUTO="$TMP_ROOT/build-auto-hash"
mkdir -p "$AUTO"
(cd "$AUTO" && "$NIFT_BIN" init >/dev/null 2>&1)
sed -i 's/"incremental-mode":[[:space:]]*"modified"/"incremental-mode": "hash"/' "$AUTO/.nift/config.json"
(cd "$AUTO" && "$NIFT_BIN" build --all >/dev/null 2>&1)
(cd "$AUTO" && "$NIFT_BIN" build --auto >"$TMP_ROOT/build-auto.log" 2>&1) &
auto_pid=$!
sleep 0.4
printf 'AUTO-CHANGE-1\n' >"$AUTO/content/index.html"
sleep 0.7
printf 'AUTO-CHANGE-2\n' >"$AUTO/content/index.html"
sleep 0.8
t1=$(stat -c %Y "$AUTO/public/index.html")
sleep 0.7
t2=$(stat -c %Y "$AUTO/public/index.html")
kill "$auto_pid" >/dev/null 2>&1 || true
wait "$auto_pid" >/dev/null 2>&1 || true
[[ "$t2" -eq "$t1" ]] || fail 'hash-mode build --auto keeps rebuilding after a second edit (hash cache not refreshed candidate)'



# -----------------------------------------------------------------------------
# v0.6 fresh adversarial/code-review additions
# -----------------------------------------------------------------------------

# info with multiple requested names should report each requested name exactly once.
TESTS=$((TESTS+1))
INFO_MULTI="$TMP_ROOT/info-multi"
mkdir -p "$INFO_MULTI"
(cd "$INFO_MULTI" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$INFO_MULTI" && "$NIFT_BIN" track second 'Second page' >/dev/null 2>&1)
(cd "$INFO_MULTI" && "$NIFT_BIN" info / second >"$TMP_ROOT/info-multi.log" 2>&1) || fail 'info with multiple names failed'
python3 -S - "$TMP_ROOT/info-multi.log" <<'PY' || fail 'info repeats requested names instead of reporting each once'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    doc = json.load(f)
names = [entry.get("name") for entry in doc.get("tracked", [])]
raise SystemExit(0 if names == ["/", "second"] else 1)
PY

# Watch metadata structural corruption must be rejected without RapidJSON aborts.
WATCH_STRUCT="$TMP_ROOT/watch-struct"
mkdir -p "$WATCH_STRUCT/content/w"
(cd "$WATCH_STRUCT" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$WATCH_STRUCT" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1) || fail 'watch structural-corruption setup failed'
printf '%s\n' '{"watched":[123]}' >"$WATCH_STRUCT/.nift/.watch/watched.json"
check_no_abort 'watched.json with non-string array member' bash -c "cd '$WATCH_STRUCT' && '$NIFT_BIN' info --watching"

make_bad_exts_case(){
  local label="$1" json="$2" dir="$TMP_ROOT/exts-struct-${TESTS}"
  mkdir -p "$dir/content/w"
  (cd "$dir" && "$NIFT_BIN" init >/dev/null 2>&1)
  (cd "$dir" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1) || { TESTS=$((TESTS+1)); fail "$label setup failed"; return; }
  printf '%s\n' "$json" >"$dir/.nift/.watch/content/w/exts.json"
  check_no_abort "$label" bash -c "cd '$dir' && '$NIFT_BIN' info --watching"
}
make_bad_exts_case 'watched exts.json with non-object array member' '{"exts":[123]}'
make_bad_exts_case 'watched exts.json entry missing content-ext' '{"exts":[{"template":"templates/template.html","output-ext":".html"}]}'
make_bad_exts_case 'watched exts.json entry with non-string content-ext' '{"exts":[{"content-ext":7,"template":"templates/template.html","output-ext":".html"}]}'
make_bad_exts_case 'watched exts.json entry missing template' '{"exts":[{"content-ext":".html","output-ext":".html"}]}'
make_bad_exts_case 'watched exts.json entry with non-string template' '{"exts":[{"content-ext":".html","template":false,"output-ext":".html"}]}'
make_bad_exts_case 'watched exts.json entry missing output-ext' '{"exts":[{"content-ext":".html","template":"templates/template.html"}]}'
make_bad_exts_case 'watched exts.json entry with non-string output-ext' '{"exts":[{"content-ext":".html","template":"templates/template.html","output-ext":[]}]}'

# Saving user-controlled strings must leave persistent JSON valid.
TESTS=$((TESTS+1))
QNAME="$TMP_ROOT/quote-name"
mkdir -p "$QNAME"
(cd "$QNAME" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$QNAME" && "$NIFT_BIN" track 'quo"te' 'Quote name' >/dev/null 2>&1); then
  python3 -S -m json.tool "$QNAME/.nift/tracked.json" >/dev/null 2>&1 || fail 'track name containing double quote corrupts tracked.json'
  (cd "$QNAME" && "$NIFT_BIN" info 'quo"te' >/dev/null 2>&1) || fail 'project cannot reopen after quoted tracked name is saved'
fi

TESTS=$((TESTS+1))
QWATCH="$TMP_ROOT/quote-watch"
mkdir -p "$QWATCH/content/q\"dir"
(cd "$QWATCH" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$QWATCH" && "$NIFT_BIN" watch 'content/q"dir/' >/dev/null 2>&1); then
  python3 -S -m json.tool "$QWATCH/.nift/.watch/watched.json" >/dev/null 2>&1 || fail 'watch directory containing double quote corrupts watched.json'
  (cd "$QWATCH" && "$NIFT_BIN" info --watching >/dev/null 2>&1) || fail 'watch list cannot reopen after quoted directory is saved'
fi

# mv/cp should enforce the same project-root traversal rule as track.
TESTS=$((TESTS+1))
CPTRAV_PARENT="$TMP_ROOT/cp-traversal-parent"
CPTRAV="$CPTRAV_PARENT/project"
mkdir -p "$CPTRAV"
(cd "$CPTRAV" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$CPTRAV" && "$NIFT_BIN" cp / ../copied-outside >"$TMP_ROOT/cp-traversal.log" 2>&1); then
  fail 'cp accepts ../ destination that escapes configured content/output directories'
fi
[[ ! -e "$CPTRAV_PARENT/copied-outside.html" ]] || fail 'cp ../ destination created content outside project root'

TESTS=$((TESTS+1))
MVTRAV_PARENT="$TMP_ROOT/mv-traversal-parent"
MVTRAV="$MVTRAV_PARENT/project"
mkdir -p "$MVTRAV"
(cd "$MVTRAV" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$MVTRAV" && "$NIFT_BIN" mv / ../moved-outside >"$TMP_ROOT/mv-traversal.log" 2>&1); then
  fail 'mv accepts ../ destination that escapes configured content/output directories'
fi
[[ ! -e "$MVTRAV_PARENT/moved-outside.html" ]] || fail 'mv ../ destination moved content outside project root'

# cp/mv names containing quotes must not corrupt tracked.json if accepted.
TESTS=$((TESTS+1))
CPQUOTE="$TMP_ROOT/cp-quote"
mkdir -p "$CPQUOTE"
(cd "$CPQUOTE" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$CPQUOTE" && "$NIFT_BIN" cp / 'copy"quote' >/dev/null 2>&1); then
  python3 -S -m json.tool "$CPQUOTE/.nift/tracked.json" >/dev/null 2>&1 || fail 'cp destination containing double quote corrupts tracked.json'
fi

TESTS=$((TESTS+1))
MVQUOTE="$TMP_ROOT/mv-quote"
mkdir -p "$MVQUOTE"
(cd "$MVQUOTE" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$MVQUOTE" && "$NIFT_BIN" mv / 'move"quote' >/dev/null 2>&1); then
  python3 -S -m json.tool "$MVQUOTE/.nift/tracked.json" >/dev/null 2>&1 || fail 'mv destination containing double quote corrupts tracked.json'
fi

# tracked.json optional fields with wrong types must not crash and should be ignored/rejected cleanly.
TESTS=$((TESTS+1))
OPTJSON="$TMP_ROOT/optional-json-types"
mkdir -p "$OPTJSON"
(cd "$OPTJSON" && "$NIFT_BIN" init >/dev/null 2>&1)
python3 -S - <<PY2
import json
p='$OPTJSON/.nift/tracked.json'
d=json.load(open(p))
d['tracked'][0]['content-ext']=17
d['tracked'][0]['output-ext']=False
json.dump(d,open(p,'w'))
PY2
had_errexit=0
case $- in *e*) had_errexit=1; set +e ;; esac
(cd "$OPTJSON" && "$NIFT_BIN" info --all >/dev/null 2>&1)
opt_rc=$?
if [[ $had_errexit -eq 1 ]]; then set -e; fi
[[ $opt_rc -lt 128 ]] || fail 'tracked.json wrong-type optional extension fields crash Nift'

# Valid but structurally malformed config values should be handled without crashes.
TESTS=$((TESTS+1))
CFGSTRUCT="$TMP_ROOT/config-struct"
mkdir -p "$CFGSTRUCT"
(cd "$CFGSTRUCT" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '{"config":[]}' >"$CFGSTRUCT/.nift/config.json"
check_no_abort 'config.json with non-object config member' bash -c "cd '$CFGSTRUCT' && '$NIFT_BIN' info --all"

# Parser recursion: a direct and indirect @input loop must fail cleanly, not hang/crash.
TESTS=$((TESTS+1))
LOOP="$TMP_ROOT/input-loop"
mkdir -p "$LOOP"
(cd "$LOOP" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '@input("templates/template.html")' >"$LOOP/templates/template.html"
had_errexit=0
case $- in *e*) had_errexit=1; set +e ;; esac
timeout 5 bash -c "cd '$LOOP' && '$NIFT_BIN' build --all" >/dev/null 2>&1
loop_rc=$?
if [[ $had_errexit -eq 1 ]]; then set -e; fi
[[ $loop_rc -ne 0 && $loop_rc -ne 124 && $loop_rc -lt 128 ]] || fail 'direct @input loop hangs/crashes instead of failing cleanly'

TESTS=$((TESTS+1))
ILOOP="$TMP_ROOT/indirect-input-loop"
mkdir -p "$ILOOP/templates"
(cd "$ILOOP" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '@input("templates/a.html")' >"$ILOOP/templates/template.html"
printf '%s\n' '@input("templates/b.html")' >"$ILOOP/templates/a.html"
printf '%s\n' '@input("templates/a.html")' >"$ILOOP/templates/b.html"
had_errexit=0
case $- in *e*) had_errexit=1; set +e ;; esac
timeout 5 bash -c "cd '$ILOOP' && '$NIFT_BIN' build --all" >/dev/null 2>&1
iloop_rc=$?
if [[ $had_errexit -eq 1 ]]; then set -e; fi
[[ $iloop_rc -ne 0 && $iloop_rc -ne 124 && $iloop_rc -lt 128 ]] || fail 'indirect @input loop hangs/crashes instead of failing cleanly'

# Watch should reject a directory path that lexically begins in content/ but normalizes outside it.
TESTS=$((TESTS+1))
WESC="$TMP_ROOT/watch-escape"
mkdir -p "$WESC/content" "$WESC/outside"
(cd "$WESC" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$WESC" && "$NIFT_BIN" watch 'content/../outside/' >"$TMP_ROOT/watch-escape.log" 2>&1); then
  fail 'watch accepts content/../ path that escapes configured content directory'
fi

# build should reject every unknown leading option, not silently treat it as progress mode.
for badopt in -x --bad --progress; do
  TESTS=$((TESTS+1))
  if (cd "$INFO_MULTI" && "$NIFT_BIN" build "$badopt" / >/dev/null 2>&1); then
    fail "build accepts unknown option $badopt"
  fi
done

# Commands that mutate tracking should preserve valid JSON across ordinary backslash/newline-like titles.
TESTS=$((TESTS+1))
ESCJSON="$TMP_ROOT/json-escape-more"
mkdir -p "$ESCJSON"
(cd "$ESCJSON" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$ESCJSON" && "$NIFT_BIN" track slash-title 'C:\tmp\site' >/dev/null 2>&1) || fail 'track title with backslashes failed'
python3 -S -m json.tool "$ESCJSON/.nift/tracked.json" >/dev/null 2>&1 || fail 'track title containing backslashes corrupts tracked.json'
(cd "$ESCJSON" && "$NIFT_BIN" info slash-title >"$TMP_ROOT/slash-title.log" 2>&1) || fail 'project cannot reopen title containing backslashes'
python3 -S - "$TMP_ROOT/slash-title.log" <<'PY' || fail 'tracked title backslashes do not round-trip through JSON'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    doc = json.load(f)
tracked = doc.get("tracked", [])
raise SystemExit(0 if len(tracked) == 1 and tracked[0].get("title") == r"C:\tmp\site" else 1)
PY


# Additional v0.6 probes from second source-audit pass.
# Embedded traversal is just as dangerous as a name beginning with ../.
for spec in 'track:nested/../../escape' 'cp:nested/../../copyescape' 'mv:nested/../../moveescape'; do
  op=${spec%%:*}; dest=${spec#*:}
  TESTS=$((TESTS+1))
  PARENT="$TMP_ROOT/${op}-embedded-traversal-parent"
  PROJ="$PARENT/project"
  mkdir -p "$PROJ"
  (cd "$PROJ" && "$NIFT_BIN" init >/dev/null 2>&1)
  if [[ $op == track ]]; then
    (cd "$PROJ" && "$NIFT_BIN" track "$dest" 'Traversal' >/dev/null 2>&1); rc=$?
  else
    (cd "$PROJ" && "$NIFT_BIN" "$op" / "$dest" >/dev/null 2>&1); rc=$?
  fi
  [[ $rc -ne 0 ]] || fail "$op accepts embedded ../ traversal that escapes configured directories"
done

# Watch traversal with a deeper lexical prefix should also be rejected.
TESTS=$((TESTS+1))
WESC2="$TMP_ROOT/watch-escape-deep"
mkdir -p "$WESC2/content/sub" "$WESC2/outside"
(cd "$WESC2" && "$NIFT_BIN" init >/dev/null 2>&1)
if (cd "$WESC2" && "$NIFT_BIN" watch 'content/sub/../../outside/' >/dev/null 2>&1); then
  fail 'watch accepts nested ../ path that escapes configured content directory'
fi

# Hash-mode directory dependencies should detect directory membership changes.
make_dirdep_mode_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/dirdep-$mode"
  TESTS=$((TESTS+1))
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public" "$d/data-dir"
  cat >"$d/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"$mode"}}
JSON
  cat >"$d/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"dirdep","template":"templates/template.html"}]}
JSON
  printf 'CONTENT\n' >"$d/content/index.html"
  printf '%s\n' '@dep("data-dir")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  printf 'new\n' >"$d/data-dir/new.txt"
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -gt "$before" ]] || fail "$label does not rebuild when a file is added to directory @dep"
}
make_dirdep_mode_case hash 'hash-mode directory @dep'
make_dirdep_mode_case hybrid 'hybrid-mode directory @dep'

# Watch custom extension state must survive save/reopen and keep the right paths.
TESTS=$((TESTS+1))
WCUSTOM="$TMP_ROOT/watch-custom-ext"
mkdir -p "$WCUSTOM/content/docs"
(cd "$WCUSTOM" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '@content' >"$WCUSTOM/templates/md-template.html"
printf 'MARKDOWNISH\n' >"$WCUSTOM/content/docs/a.md"
(cd "$WCUSTOM" && "$NIFT_BIN" watch content/docs/ .md templates/md-template.html .txt >/dev/null 2>&1) || fail 'custom-extension watch setup failed'
(cd "$WCUSTOM" && "$NIFT_BIN" build >/dev/null 2>&1) || fail 'custom-extension watch first build failed'
[[ -f "$WCUSTOM/public/docs/a.txt" ]] || fail 'custom-extension watch did not produce configured output extension'
(cd "$WCUSTOM" && "$NIFT_BIN" info docs/a >"$TMP_ROOT/watch-custom-info.log" 2>&1) || fail 'custom-extension watched page cannot reopen from tracked.json'
grep -Fq 'content/docs/a.md' "$TMP_ROOT/watch-custom-info.log" || fail 'custom watched content extension not persisted in tracked.json'
grep -Fq 'public/docs/a.txt' "$TMP_ROOT/watch-custom-info.log" || fail 'custom watched output extension not persisted in tracked.json'

# Structurally duplicate watch metadata should not silently change meaning.
TESTS=$((TESTS+1))
WDUP="$TMP_ROOT/watch-duplicate-ext"
mkdir -p "$WDUP/content/w"
(cd "$WDUP" && "$NIFT_BIN" init >/dev/null 2>&1)
(cd "$WDUP" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1)
cat >"$WDUP/.nift/.watch/content/w/exts.json" <<'JSON'
{"exts":[{"content-ext":".html","template":"templates/template.html","output-ext":".html"},{"content-ext":".html","template":"templates/template.html","output-ext":".txt"}]}
JSON
if (cd "$WDUP" && "$NIFT_BIN" info --watching >/dev/null 2>&1); then
  fail 'duplicate content-extension entries in watched exts.json are silently accepted'
fi

# init should not accept an extension that makes its own config JSON invalid.
TESTS=$((TESTS+1))
INITQUOTE="$TMP_ROOT/init-quote-ext"
mkdir -p "$INITQUOTE"
if (cd "$INITQUOTE" && "$NIFT_BIN" init '.\"bad' >/dev/null 2>&1); then
  python3 -S -m json.tool "$INITQUOTE/.nift/config.json" >/dev/null 2>&1 || fail 'init accepts extension containing quote then writes invalid config.json'
fi



# -----------------------------------------------------------------------------
# v0.9 fresh adversarial/code-review additions
# -----------------------------------------------------------------------------

# Directory dependencies must not be perpetually dirty in hash/hybrid modes.
make_unchanged_dirdep_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/v09-unchanged-dirdep-$mode"
  TESTS=$((TESTS+1))
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  mkdir -p "$d/data-dir"
  printf 'A\n' >"$d/data-dir/a.txt"
  printf '%s\n' '@dep("data-dir")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  local before after
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label unchanged update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -eq "$before" ]] || fail "$label rebuilds an unchanged directory dependency"
}
make_unchanged_dirdep_case hash 'hash-mode directory @dep'
make_unchanged_dirdep_case hybrid 'hybrid-mode directory @dep'

# Hash mode should ignore a pure mtime touch when dependency contents are unchanged;
# hybrid mode should still detect the mtime change.
make_touch_only_dep_case(){
  local mode="$1"
  local should_rebuild="$2"
  local label="$3"
  local d="$TMP_ROOT/v09-touch-dep-$mode"
  TESTS=$((TESTS+1))
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  printf 'UNCHANGED\n' >"$d/data.txt"
  printf '%s\n' '@dep("data.txt")!' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  local before after
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  touch "$d/data.txt"
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  if [[ "$should_rebuild" == yes ]]; then
    [[ "$after" -gt "$before" ]] || fail "$label misses mtime-only dependency change"
  else
    [[ "$after" -eq "$before" ]] || fail "$label rebuilds when only dependency mtime changed but content hash is unchanged"
  fi
}
make_touch_only_dep_case hash no 'hash-mode @dep'
make_touch_only_dep_case hybrid yes 'hybrid-mode @dep'

# Apply the same mode semantics to sidecar *.deps.json dependencies.
make_touch_only_userdep_case(){
  local mode="$1"
  local should_rebuild="$2"
  local label="$3"
  local d="$TMP_ROOT/v09-touch-userdep-$mode"
  TESTS=$((TESTS+1))
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  mkdir -p "$d/data"
  printf 'UNCHANGED\n' >"$d/data/user.txt"
  printf '%s\n' '{"dependencies":["data/user.txt"]}' >"$d/content/index.deps.json"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  local before after
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  touch "$d/data/user.txt"
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  if [[ "$should_rebuild" == yes ]]; then
    [[ "$after" -gt "$before" ]] || fail "$label misses mtime-only user dependency change"
  else
    [[ "$after" -eq "$before" ]] || fail "$label rebuilds when only user dependency mtime changed but content hash is unchanged"
  fi
}
make_touch_only_userdep_case hash no 'hash-mode user-defined dependency'
make_touch_only_userdep_case hybrid yes 'hybrid-mode user-defined dependency'

# User-defined directory dependencies should also remain quiet while unchanged.
make_unchanged_userdirdep_case(){
  local mode="$1"
  local label="$2"
  local d="$TMP_ROOT/v09-unchanged-userdir-$mode"
  TESTS=$((TESTS+1))
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  mkdir -p "$d/data-dir"
  printf 'A\n' >"$d/data-dir/a.txt"
  printf '%s\n' '{"dependencies":["data-dir"]}' >"$d/content/index.deps.json"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  local before after
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label unchanged update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  [[ "$after" -eq "$before" ]] || fail "$label rebuilds an unchanged user-defined directory dependency"
}
make_unchanged_userdirdep_case hash 'hash-mode user-defined directory dependency'
make_unchanged_userdirdep_case hybrid 'hybrid-mode user-defined directory dependency'

# Directly verify that a directory's stored hash incorporates existing child contents.
# This avoids an always-dirty incremental path making a child-change rebuild test pass accidentally.
TESTS=$((TESTS+1))
DHASH="$TMP_ROOT/v09-directory-hash-content"
mkdir -p "$DHASH"
(cd "$DHASH" && "$NIFT_BIN" init >/dev/null 2>&1)
sed -i 's/"incremental-mode": "modified"/"incremental-mode": "hash"/' "$DHASH/.nift/config.json"
mkdir -p "$DHASH/data-dir"
printf 'A\n' >"$DHASH/data-dir/a.txt"
printf '%s\n' '@dep("data-dir")!' '@content' >"$DHASH/templates/template.html"
if (cd "$DHASH" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  h1=$(cat "$DHASH/.nift/data-dir.hash" 2>/dev/null || true)
  printf 'B-DIFFERENT\n' >"$DHASH/data-dir/a.txt"
  (cd "$DHASH" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'directory hash child-content second build failed'
  h2=$(cat "$DHASH/.nift/data-dir.hash" 2>/dev/null || true)
  [[ -n "$h1" && -n "$h2" && "$h1" != "$h2" ]] || fail 'directory hash does not incorporate existing child file contents'
else
  fail 'directory hash child-content baseline build failed'
fi

# Nested child contents must likewise contribute to a recursive directory hash.
TESTS=$((TESTS+1))
DNHASH="$TMP_ROOT/v09-directory-hash-nested"
mkdir -p "$DNHASH"
(cd "$DNHASH" && "$NIFT_BIN" init >/dev/null 2>&1)
sed -i 's/"incremental-mode": "modified"/"incremental-mode": "hash"/' "$DNHASH/.nift/config.json"
mkdir -p "$DNHASH/data-dir/sub"
printf 'A\n' >"$DNHASH/data-dir/sub/a.txt"
printf '%s\n' '@dep("data-dir")!' '@content' >"$DNHASH/templates/template.html"
if (cd "$DNHASH" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  h1=$(cat "$DNHASH/.nift/data-dir.hash" 2>/dev/null || true)
  printf 'B-DIFFERENT\n' >"$DNHASH/data-dir/sub/a.txt"
  (cd "$DNHASH" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'recursive directory hash second build failed'
  h2=$(cat "$DNHASH/.nift/data-dir.hash" 2>/dev/null || true)
  [[ -n "$h1" && -n "$h2" && "$h1" != "$h2" ]] || fail 'recursive directory hash does not incorporate nested child contents'
else
  fail 'recursive directory hash baseline build failed'
fi


# Renaming a child while preserving identical contents must still change the
# directory hash; the directory structure is part of the dependency state.
TESTS=$((TESTS+1))
DRENAME="$TMP_ROOT/v09-directory-hash-rename"
mkdir -p "$DRENAME"
(cd "$DRENAME" && "$NIFT_BIN" init >/dev/null 2>&1)
sed -i 's/"incremental-mode": "modified"/"incremental-mode": "hash"/' "$DRENAME/.nift/config.json"
mkdir -p "$DRENAME/data-dir"
printf 'SAME\n' >"$DRENAME/data-dir/a.txt"
printf '%s\n' '@dep("data-dir")!' '@content' >"$DRENAME/templates/template.html"
if (cd "$DRENAME" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  h1=$(cat "$DRENAME/.nift/data-dir.hash" 2>/dev/null || true)
  mv "$DRENAME/data-dir/a.txt" "$DRENAME/data-dir/b.txt"
  (cd "$DRENAME" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'directory hash rename second build failed'
  h2=$(cat "$DRENAME/.nift/data-dir.hash" 2>/dev/null || true)
  [[ -n "$h1" && -n "$h2" && "$h1" != "$h2" ]] || fail 'directory hash ignores child filename/rename when contents are unchanged'
else
  fail 'directory hash rename baseline build failed'
fi

TESTS=$((TESTS+1))
DNRENAME="$TMP_ROOT/v09-directory-hash-nested-rename"
mkdir -p "$DNRENAME"
(cd "$DNRENAME" && "$NIFT_BIN" init >/dev/null 2>&1)
sed -i 's/"incremental-mode": "modified"/"incremental-mode": "hash"/' "$DNRENAME/.nift/config.json"
mkdir -p "$DNRENAME/data-dir/sub-a"
printf 'SAME\n' >"$DNRENAME/data-dir/sub-a/a.txt"
printf '%s\n' '@dep("data-dir")!' '@content' >"$DNRENAME/templates/template.html"
if (cd "$DNRENAME" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  h1=$(cat "$DNRENAME/.nift/data-dir.hash" 2>/dev/null || true)
  mv "$DNRENAME/data-dir/sub-a" "$DNRENAME/data-dir/sub-b"
  (cd "$DNRENAME" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'directory hash nested rename second build failed'
  h2=$(cat "$DNRENAME/.nift/data-dir.hash" 2>/dev/null || true)
  [[ -n "$h1" && -n "$h2" && "$h1" != "$h2" ]] || fail 'recursive directory hash ignores nested directory rename when contents are unchanged'
else
  fail 'directory hash nested rename baseline build failed'
fi



# Pure hash mode should likewise ignore mtime-only changes to the tracked page's
# own content/template files; hybrid mode intentionally reacts to either signal.
make_touch_core_file_case(){
  local mode="$1"
  local target="$2"
  local should_rebuild="$3"
  local label="$4"
  local d="$TMP_ROOT/v09-touch-core-$mode-$target"
  TESTS=$((TESTS+1))
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1) || { fail "$label baseline build failed"; return; }
  local file before after
  if [[ "$target" == content ]]; then file="$d/content/index.html"; else file="$d/templates/template.html"; fi
  before=$(stat -c %Y "$d/public/index.html")
  sleep 1.1
  touch "$file"
  (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1) || { fail "$label update check failed"; return; }
  after=$(stat -c %Y "$d/public/index.html")
  if [[ "$should_rebuild" == yes ]]; then
    [[ "$after" -gt "$before" ]] || fail "$label misses mtime-only change"
  else
    [[ "$after" -eq "$before" ]] || fail "$label rebuilds on mtime-only change despite unchanged content hash"
  fi
}
make_touch_core_file_case hash content no 'hash-mode tracked content'
make_touch_core_file_case hybrid content yes 'hybrid-mode tracked content'
make_touch_core_file_case hash template no 'hash-mode template'
make_touch_core_file_case hybrid template yes 'hybrid-mode template'


# @json(path, name) and chained JSON data access.
JSOND="$TMP_ROOT/json-bindings"
mkdir -p "$JSOND"
(cd "$JSOND" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$JSOND/data"
cat >"$JSOND/data/site.json" <<'JSON'
{
  "name": "Nift",
  "version": 4,
  "enabled": true,
  "nothing": null,
  "empty": "",
  "example": [
    {"test": "zero"},
    {"test": "one"},
    {"test": "two"},
    {
      "test": "three",
      "deep": {
        "items": [
          {"value": 10},
          {"value": 20},
          {"value": 30, "flags": [false, true]}
        ]
      }
    }
  ]
}
JSON
cat >"$JSOND/templates/template.html" <<'EOF'
@json(site, "data/site.json")
NAME=$[site.name]
VERSION=$[site.version]
BOOL=$[site.enabled]
NULL=$[site.nothing]
EMPTY=<$[site.empty]>
CHAIN=$[site.example[3].deep.items[2].value]
CHAINBOOL=$[site.example[3].deep.items[2].flags[1]]
@input("json-child.html")
@content
EOF
cat >"$JSOND/templates/json-child.html" <<'EOF'
NESTED=$[site.example[3].test]
EOF
TESTS=$((TESTS+1))
(cd "$JSOND" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail '@json basic/chained build failed'
run_test contains "$JSOND/public/index.html" 'NAME=Nift' '@json string value'
run_test contains "$JSOND/public/index.html" 'VERSION=4' '@json numeric value'
run_test contains "$JSOND/public/index.html" 'BOOL=true' '@json boolean value'
run_test contains "$JSOND/public/index.html" 'NULL=null' '@json null value'
run_test contains "$JSOND/public/index.html" 'EMPTY=<>' '@json empty string value'
run_test contains "$JSOND/public/index.html" 'CHAIN=30' '@json arbitrary object/array chaining'
run_test contains "$JSOND/public/index.html" 'CHAINBOOL=true' '@json chained array after object access'
run_test contains "$JSOND/public/index.html" 'NESTED=three' '@json binding visible inside nested @input'
run_test contains "$JSOND/.nift/public/index.info.json" 'data/site.json' '@json automatically records JSON file dependency'

make_json_failure_case(){
  local name="$1" expected="$2" template="$3" data="${4:-}"
  local d="$TMP_ROOT/json-fail-$name"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  mkdir -p "$d/data"
  if [[ -n "$data" ]]; then printf '%s\n' "$data" >"$d/data/test.json"; fi
  printf '%s\n' "$template" >"$d/templates/template.html"
  TESTS=$((TESTS+1))
  if (cd "$d" && "$NIFT_BIN" build --all >log 2>&1); then
    fail "$name unexpectedly succeeded"
  elif ! grep -Fq -- "$expected" "$d/log"; then
    fail "$name did not report expected error: $expected"
  fi
}

make_json_failure_case malformed-json 'json: failed to parse data/test.json' \
  '@json(data, "data/test.json")' '{"broken":'
make_json_failure_case duplicate-json-alias "json: name 'data' is already bound" \
  $'@json(data, "data/test.json")\n@json(data, "data/test.json")' '{}'
make_json_failure_case invalid-json-alias 'json: name must be an identifier' \
  '@json(bad-name, "data/test.json")' '{}'
make_json_failure_case reserved-json-alias 'conflicts with built-in metadata' \
  '@json(title, "data/test.json")' '{}'
make_json_failure_case missing-json-member "has no member 'missing'" \
  $'@json(data, "data/test.json")\n$[data.missing]' '{"present":1}'
make_json_failure_case json-index-out-of-range 'JSON array index 3 is out of range' \
  $'@json(data, "data/test.json")\n$[data.items[3]]' '{"items":[1]}'
make_json_failure_case json-index-non-array 'because it is not an array' \
  $'@json(data, "data/test.json")\n$[data.item[0]]' '{"item":{"x":1}}'
make_json_failure_case json-member-non-object 'because the current JSON value is not an object' \
  $'@json(data, "data/test.json")\n$[data.items.foo]' '{"items":[1]}'
make_json_failure_case render-json-array 'cannot render JSON array' \
  $'@json(data, "data/test.json")\n$[data.items]' '{"items":[1,2]}'
make_json_failure_case render-json-object 'cannot render JSON object' \
  $'@json(data, "data/test.json")\n$[data.item]' '{"item":{"x":1}}'

JSONMISS="$TMP_ROOT/json-missing-file"
mkdir -p "$JSONMISS"
(cd "$JSONMISS" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '%s\n' '@json(data, "data/nope.json")' >"$JSONMISS/templates/template.html"
TESTS=$((TESTS+1))
if (cd "$JSONMISS" && "$NIFT_BIN" build --all >log 2>&1); then
  fail '@json missing file unexpectedly succeeded'
else
  grep -Fq 'json: file does not exist: data/nope.json' "$JSONMISS/log" || fail '@json missing file error is not informative'
fi

JSONTRAV="$TMP_ROOT/json-traversal/project"
mkdir -p "$JSONTRAV"
(cd "$JSONTRAV" && "$NIFT_BIN" init >/dev/null 2>&1)
printf '{}\n' >"$TMP_ROOT/json-traversal/outside.json"
printf '%s\n' '@json(data, "../outside.json")' >"$JSONTRAV/templates/template.html"
TESTS=$((TESTS+1))
if (cd "$JSONTRAV" && "$NIFT_BIN" build --all >log 2>&1); then
  fail '@json traversal unexpectedly succeeded'
else
  grep -Fq 'json: path must stay inside the Nift project' "$JSONTRAV/log" || fail '@json traversal error is not informative'
fi

# JSON files are ordinary page dependencies for incremental builds.
JSONINC="$TMP_ROOT/json-incremental-modified"
mkdir -p "$JSONINC"
(cd "$JSONINC" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$JSONINC/data"
printf '{"value":"one"}\n' >"$JSONINC/data/state.json"
printf '%s\n' '@json(data, "data/state.json")' 'VALUE=$[data.value]' '@content' >"$JSONINC/templates/template.html"
(cd "$JSONINC" && "$NIFT_BIN" build --all >/dev/null 2>&1)
before=$(stat -c %Y "$JSONINC/public/index.html")
sleep 1.1
printf '{"value":"two"}\n' >"$JSONINC/data/state.json"
TESTS=$((TESTS+1))
if ! (cd "$JSONINC" && "$NIFT_BIN" build >/dev/null 2>&1); then
  fail 'modified-mode @json dependency update check failed'
else
  after=$(stat -c %Y "$JSONINC/public/index.html")
  [[ "$after" -gt "$before" ]] || fail 'modified-mode @json dependency change did not rebuild'
  grep -Fq 'VALUE=two' "$JSONINC/public/index.html" || fail 'modified-mode @json rebuild did not use updated JSON'
fi

make_json_hash_case(){
  local mode="$1"
  local d="$TMP_ROOT/json-incremental-$mode"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  sed -i "s/\"incremental-mode\": \"modified\"/\"incremental-mode\": \"$mode\"/" "$d/.nift/config.json"
  mkdir -p "$d/data"
  printf '{"value":"one"}\n' >"$d/data/state.json"
  printf '%s\n' '@json(data, "data/state.json")' 'VALUE=$[data.value]' '@content' >"$d/templates/template.html"
  (cd "$d" && "$NIFT_BIN" build --all >/dev/null 2>&1)
  cp -p "$d/data/state.json" "$d/original.json"
  printf '{"value":"two"}\n' >"$d/data/state.json"
  touch -r "$d/original.json" "$d/data/state.json"
  TESTS=$((TESTS+1))
  if ! (cd "$d" && "$NIFT_BIN" build >/dev/null 2>&1); then
    fail "$mode-mode @json preserved-mtime update check failed"
  elif ! grep -Fq 'VALUE=two' "$d/public/index.html"; then
    fail "$mode-mode @json dependency misses content change with preserved mtime"
  fi
}
make_json_hash_case hash
make_json_hash_case hybrid



# @if(...) { ... } / else if (...) { ... } / else { ... }
# and @for(...) { ... } structured control flow over bound JSON values.
CF="$TMP_ROOT/control-flow"
mkdir -p "$CF"
(cd "$CF" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$CF/data"
cat >"$CF/data/site.json" <<'JSON'
{
  "enabled": true,
  "disabled": false,
  "type": "article",
  "count": 3,
  "low": 2,
  "high": 7,
  "word_a": "alpha",
  "word_b": "beta",
  "nothing": null,
  "nonempty_array": [1],
  "empty_array_truth": [],
  "nonempty_object": {"x":1},
  "empty_object_truth": {},
  "lhs": "same",
  "rhs": "same",
  "items": [
    {"name":"one","show":true,"type":"article","tags":["a","b"]},
    {"name":"two","show":false,"type":"note","tags":[]},
    {"name":"three","show":true,"type":"article","tags":["c"]}
  ],
  "empty_array": [],
  "empty_object": {},
  "object": {
    "alpha":{"value":1},
    "beta":{"value":2},
    "gamma":{"value":3}
  }
}
JSON
cat >"$CF/templates/template.html" <<'EOF'
@json(site, "data/site.json")
@if(site.enabled){IF_TRUE
}
@if(!site.disabled){IF_NEGATED_TRUE
}
@if(site.type == "article"){IF_STRING_EQ
}
@if(site.type != "note"){IF_STRING_NE
}
@if(site.count == 3){IF_NUMBER_EQ
}
@if(site.low < site.high){IF_NUMBER_LT
}
@if(site.low <= 2){IF_NUMBER_LE
}
@if(site.high > site.low){IF_NUMBER_GT
}
@if(site.high >= 7){IF_NUMBER_GE
}
@if(site.word_a < site.word_b){IF_STRING_LT
}
@if(site.word_b >= "beta"){IF_STRING_GE
}
@if(site.enabled == true){IF_BOOL_EQ
}
@if(site.nothing == null){IF_NULL_EQ
}
@if(site.disabled){BAD_IF
}else if(site.type == "note"){BAD_ELSE_IF_1
}else if(site.count == 2){BAD_ELSE_IF_2
}else if(site.type == "article"){ELSE_IF_SELECTED
}else{BAD_ELSE
}
@if(site.disabled){BAD_PLAIN_ELSE
}else{PLAIN_ELSE_SELECTED
}
@for(item : site.items){
ITEM=$[item.name]
@if(item.show){SHOW=$[item.name]
}else{HIDE=$[item.name]
}
@if(item.type == "article"){ARTICLE=$[item.name]
}
@for(tag : item.tags){TAG=$[item.name]:$[tag]
}
}
@for((key, val) : site.object){
OBJ=$[key]:$[val.value]
}
@for(item : site.empty_array){EMPTY_ARRAY_BAD
}
@for((key, val) : site.empty_object){EMPTY_OBJECT_BAD
}
@if(site.nonempty_array){NONEMPTY_ARRAY_TRUE
}
@if(!site.empty_array_truth){EMPTY_ARRAY_FALSEY
}
@if(site.nonempty_object){NONEMPTY_OBJECT_TRUE
}
@if(!site.empty_object_truth){EMPTY_OBJECT_FALSEY
}
@if(site.lhs == site.rhs){PATH_COMPARE
}
@if(false){@input("this-file-deliberately-does-not-exist.html")
}else{SKIPPED_INVALID_BRANCH
}
@if(true){QUOTED_BRACE="}"
}
@for(item:site.items){NOSPACE=$[item.name]
}
@for((key,val):site.object){NOSPACE_OBJ=$[key]
}
@content
EOF
TESTS=$((TESTS+1))
(cd "$CF" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'control-flow baseline build failed'
run_test contains "$CF/public/index.html" 'IF_TRUE' '@if truthy bool'
run_test contains "$CF/public/index.html" 'IF_NEGATED_TRUE' '@if !bool'
run_test contains "$CF/public/index.html" 'IF_STRING_EQ' '@if string equality'
run_test contains "$CF/public/index.html" 'IF_STRING_NE' '@if string inequality'
run_test contains "$CF/public/index.html" 'IF_NUMBER_EQ' '@if number equality'
run_test contains "$CF/public/index.html" 'IF_NUMBER_LT' '@if numeric less-than'
run_test contains "$CF/public/index.html" 'IF_NUMBER_LE' '@if numeric less-than-or-equal boundary'
run_test contains "$CF/public/index.html" 'IF_NUMBER_GT' '@if numeric greater-than'
run_test contains "$CF/public/index.html" 'IF_NUMBER_GE' '@if numeric greater-than-or-equal boundary'
run_test contains "$CF/public/index.html" 'IF_STRING_LT' '@if lexicographic string less-than'
run_test contains "$CF/public/index.html" 'IF_STRING_GE' '@if lexicographic string greater-than-or-equal'
run_test contains "$CF/public/index.html" 'IF_BOOL_EQ' '@if boolean equality'
run_test contains "$CF/public/index.html" 'IF_NULL_EQ' '@if null equality'
run_test contains "$CF/public/index.html" 'ELSE_IF_SELECTED' '@if unlimited else-if chain selects later branch'
run_test contains "$CF/public/index.html" 'PLAIN_ELSE_SELECTED' '@if plain else selected'
run_test not_contains "$CF/public/index.html" 'BAD_' '@if skips unselected branches'
run_test contains "$CF/public/index.html" 'ITEM=one' '@for array first item'
run_test contains "$CF/public/index.html" 'ITEM=two' '@for array second item'
run_test contains "$CF/public/index.html" 'ITEM=three' '@for array third item'
run_test contains "$CF/public/index.html" 'SHOW=one' '@if inside @for true branch'
run_test contains "$CF/public/index.html" 'SHOW=three' '@if inside @for later true branch'
run_test contains "$CF/public/index.html" 'HIDE=two' '@if inside @for else branch'
run_test contains "$CF/public/index.html" 'ARTICLE=one' '@if JSON string comparison inside @for'
run_test contains "$CF/public/index.html" 'ARTICLE=three' '@if JSON string comparison inside @for later item'
run_test contains "$CF/public/index.html" 'TAG=one:a' 'nested @for over child array first value'
run_test contains "$CF/public/index.html" 'TAG=one:b' 'nested @for over child array second value'
run_test contains "$CF/public/index.html" 'TAG=three:c' 'nested @for over later child array'
run_test contains "$CF/public/index.html" 'OBJ=alpha:1' '@for object first key/value'
run_test contains "$CF/public/index.html" 'OBJ=beta:2' '@for object second key/value'
run_test contains "$CF/public/index.html" 'OBJ=gamma:3' '@for object third key/value'
run_test not_contains "$CF/public/index.html" 'EMPTY_ARRAY_BAD' '@for empty array emits nothing'
run_test not_contains "$CF/public/index.html" 'EMPTY_OBJECT_BAD' '@for empty object emits nothing'
run_test contains "$CF/public/index.html" 'NONEMPTY_ARRAY_TRUE' '@if non-empty array truthiness'
run_test contains "$CF/public/index.html" 'EMPTY_ARRAY_FALSEY' '@if empty array falsey with negation'
run_test contains "$CF/public/index.html" 'NONEMPTY_OBJECT_TRUE' '@if non-empty object truthiness'
run_test contains "$CF/public/index.html" 'EMPTY_OBJECT_FALSEY' '@if empty object falsey with negation'
run_test contains "$CF/public/index.html" 'PATH_COMPARE' '@if compares one JSON path with another'
run_test contains "$CF/public/index.html" 'SKIPPED_INVALID_BRANCH' '@if skipped branch is not parsed'
run_test contains "$CF/public/index.html" 'QUOTED_BRACE="}"' '@if balanced-block parser ignores quoted brace'
run_test contains "$CF/public/index.html" 'NOSPACE=one' '@for accepts colon syntax without surrounding spaces'
run_test contains "$CF/public/index.html" 'NOSPACE_OBJ=alpha' '@for object pair colon syntax without surrounding spaces'

# Control-flow block indentation follows the directive insertion point, just like @input.
CFI="$TMP_ROOT/control-flow-indentation"
mkdir -p "$CFI"
(cd "$CFI" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$CFI/data" "$CFI/templates/partials"
cat >"$CFI/data/site.json" <<'JSON'
{"enabled":true,"disabled":false,"items":[{"name":"one","show":true},{"name":"two","show":false}]}
JSON
cat >"$CFI/templates/partials/two-lines.html" <<'EOF'
PARTIAL-ONE
PARTIAL-TWO
EOF
cat >"$CFI/templates/template.html" <<'EOF'
@json(site, "data/site.json")
<div class="for-block">
    @for(item : site.items) {
        <p>FOR=$[item.name]</p>
    }
</div>
<section class="if-block">
    @if(site.enabled) {
        <h2>IF-TRUE</h2>
    }
</section>
<section class="else-block">
    @if(site.disabled) {
        <h2>BAD-IF</h2>
    } else {
        <h2>ELSE-TRUE</h2>
    }
</section>
<main>
    @for(item : site.items) {
        <article>
            @if(item.show) {
                <span>NESTED=$[item.name]</span>
            }
        </article>
    }
</main>
<div class="relative">
    @for(item : site.items) {
        <div>
            <span>RELATIVE=$[item.name]</span>
        </div>
    }
</div>
<div class="input-in-loop">
    @for(item : site.items) {
        @input("templates/partials/two-lines.html")
    }
</div>
<div class="inline-for">@for(item : site.items) {
    <b>$[item.name]</b>
}</div>
<div class="inline-if">@if(site.enabled) {
    <i>INLINE-IF</i>
}</div>
@content
EOF
TESTS=$((TESTS+1))
(cd "$CFI" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'control-flow indentation build failed'
run_test regex "$CFI/public/index.html" '^    <p>FOR=one</p>$' '@for body aligns to directive indentation'
run_test regex "$CFI/public/index.html" '^    <p>FOR=two</p>$' '@for repeated body keeps directive indentation'
run_test not_contains "$CFI/public/index.html" '        <p>FOR=one</p>' '@for does not preserve structural source indentation'
run_test regex "$CFI/public/index.html" '^    <h2>IF-TRUE</h2>$' '@if true body aligns to directive indentation'
run_test regex "$CFI/public/index.html" '^    <h2>ELSE-TRUE</h2>$' '@if else body aligns to original directive indentation'
run_test not_contains "$CFI/public/index.html" '        <h2>ELSE-TRUE</h2>' '@if else does not preserve structural source indentation'
run_test regex "$CFI/public/index.html" '^    <article>$' 'nested @for outer body aligns to outer directive'
run_test regex "$CFI/public/index.html" '^        <span>NESTED=one</span>$' 'nested @if indentation composes from current insertion point'
run_test regex "$CFI/public/index.html" '^        <span>RELATIVE=one</span>$' '@for preserves indentation relative to dedented block body'
run_test regex "$CFI/public/index.html" '^    PARTIAL-ONE$' '@input inside @for inherits loop insertion indentation'
run_test regex "$CFI/public/index.html" '^    PARTIAL-TWO$' '@input inside @for indents subsequent input lines consistently'
run_test regex "$CFI/public/index.html" '^ {24}<b>two</b></div>$' 'inline @for aligns repeated lines to directive insertion column'
run_test contains "$CFI/public/index.html" '<div class="inline-for"><b>one</b>' 'inline @for first body begins at directive insertion point'
run_test contains "$CFI/public/index.html" '<div class="inline-if"><i>INLINE-IF</i></div>' 'inline @if body begins at directive insertion point'

# Loop variables are scoped and nested loops can shadow then restore them.
CFS="$TMP_ROOT/control-flow-shadow"
mkdir -p "$CFS"
(cd "$CFS" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$CFS/data"
cat >"$CFS/data/site.json" <<'JSON'
{"groups":[{"name":"g1","items":[{"name":"a"},{"name":"b"}]},{"name":"g2","items":[{"name":"c"}]}]}
JSON
cat >"$CFS/templates/template.html" <<'EOF'
@json(site, "data/site.json")
@for(item : site.groups){
OUTER1=$[item.name]
@for(item : item.items){INNER=$[item.name]
}
OUTER2=$[item.name]
}
AFTER=$[item]
@content
EOF
TESTS=$((TESTS+1))
(cd "$CFS" && "$NIFT_BIN" build --all >/dev/null 2>&1) || fail 'control-flow shadowing build failed'
run_test contains "$CFS/public/index.html" 'OUTER1=g1' '@for outer binding first group'
run_test contains "$CFS/public/index.html" 'OUTER2=g1' '@for restores outer binding after nested shadow'
run_test contains "$CFS/public/index.html" 'OUTER1=g2' '@for outer binding second group'
run_test contains "$CFS/public/index.html" 'OUTER2=g2' '@for restores outer binding after nested shadow second group'
run_test contains "$CFS/public/index.html" 'INNER=a' '@for nested shadow item a'
run_test contains "$CFS/public/index.html" 'INNER=b' '@for nested shadow item b'
run_test contains "$CFS/public/index.html" 'INNER=c' '@for nested shadow item c'
run_test contains "$CFS/public/index.html" 'AFTER=$[item]' '@for binding does not leak outside block'

make_control_failure(){
  local name="$1" expected="$2" template="$3" data="{}"
  if [[ $# -ge 4 ]]; then data="$4"; fi
  local d="$TMP_ROOT/control-fail-$name"
  mkdir -p "$d"
  (cd "$d" && "$NIFT_BIN" init >/dev/null 2>&1)
  mkdir -p "$d/data"
  printf '%s\n' "$data" >"$d/data/site.json"
  printf '%s\n' "$template" >"$d/templates/template.html"
  TESTS=$((TESTS+1))
  if (cd "$d" && "$NIFT_BIN" build --all >log 2>&1); then
    fail "$name unexpectedly succeeded"
  elif ! grep -Fq -- "$expected" "$d/log"; then
    fail "$name did not report expected error: $expected"
  fi
}

make_control_failure if-no-close "@if has no matching ')'" '@if(site.enabled{hello' '{"enabled":true}'
make_control_failure if-no-block "@if(...) must be followed by a '{...}' block" '@if(site.enabled) hello' '{"enabled":true}'
make_control_failure if-unclosed-block "@if block has no matching '}'" '@if(site.enabled){hello' '{"enabled":true}'
make_control_failure if-missing-member "has no member 'missing'" $'@json(site, "data/site.json")\n@if(site.missing){x}' '{}'
make_control_failure if-object-comparison '@if comparisons are only supported for scalar JSON values' $'@json(site, "data/site.json")\n@if(site.obj == site.obj){x}' '{"obj":{"x":1}}'
make_control_failure if-order-mixed '@if ordering comparisons require two numbers or two strings of the same type' $'@json(site, "data/site.json")\n@if(site.n < "4"){x}' '{"n":3}'
make_control_failure if-order-bool '@if ordering comparisons require two numbers or two strings of the same type' $'@json(site, "data/site.json")\n@if(site.a >= site.b){x}' '{"a":true,"b":false}'
make_control_failure for-no-in "@for header must contain ':'" $'@json(site, "data/site.json")\n@for(item site.items){x}' '{"items":[]}'
make_control_failure for-array-bad-binding 'array @for syntax is @for(item : array)' $'@json(site, "data/site.json")\n@for((a,b) : site.items){x}' '{"items":[]}'
make_control_failure for-object-bad-binding 'object @for syntax is @for((key, val) : object)' $'@json(site, "data/site.json")\n@for(item : site.obj){x}' '{"obj":{"a":1}}'
make_control_failure for-object-same-bindings 'object @for key and value bindings must be distinct identifiers' $'@json(site, "data/site.json")\n@for((x, x) : site.obj){x}' '{"obj":{"a":1}}'
make_control_failure for-scalar '@for can only iterate over JSON arrays or objects' $'@json(site, "data/site.json")\n@for(item : site.value){x}' '{"value":1}'
make_control_failure for-unclosed-block "@for block has no matching '}'" $'@json(site, "data/site.json")\n@for(item : site.items){x' '{"items":[]}'
make_control_failure for-reserved-binding "conflicts with built-in metadata" $'@json(site, "data/site.json")\n@for(title : site.items){x}' '{"items":[1]}'
make_control_failure duplicate-plain-else "plain else must be the final branch" $'@json(site, "data/site.json")\n@if(false){a}else{b}else{c}' '{}'

# Control flow remains dependency-aware through @json and therefore rebuilds
# when data changes.
CFI="$TMP_ROOT/control-flow-incremental"
mkdir -p "$CFI"
(cd "$CFI" && "$NIFT_BIN" init >/dev/null 2>&1)
mkdir -p "$CFI/data"
printf '{"show":true,"items":["one"]}\n' >"$CFI/data/state.json"
cat >"$CFI/templates/template.html" <<'EOF'
@json(state, "data/state.json")
@if(state.show){VISIBLE
}else{HIDDEN
}
@for(item : state.items){ITEM=$[item]
}
@content
EOF
(cd "$CFI" && "$NIFT_BIN" build --all >/dev/null 2>&1)
before=$(stat -c %Y "$CFI/public/index.html")
sleep 1.1
printf '{"show":false,"items":["two","three"]}\n' >"$CFI/data/state.json"
TESTS=$((TESTS+1))
if ! (cd "$CFI" && "$NIFT_BIN" build >/dev/null 2>&1); then
  fail 'control-flow JSON dependency incremental build failed'
else
  after=$(stat -c %Y "$CFI/public/index.html")
  [[ "$after" -gt "$before" ]] || fail 'control-flow JSON dependency did not trigger rebuild'
  grep -Fq 'HIDDEN' "$CFI/public/index.html" || fail 'updated @if branch did not render after JSON change'
  grep -Fq 'ITEM=two' "$CFI/public/index.html" || fail 'updated @for data first item missing after JSON change'
  grep -Fq 'ITEM=three' "$CFI/public/index.html" || fail 'updated @for data second item missing after JSON change'
  ! grep -Fq 'VISIBLE' "$CFI/public/index.html" || fail 'old @if branch remained after JSON change'
fi


# Final summary only. No success chatter before this.
# Ruthless source-audit/adversarial extension.
source "$(dirname "$0")/ruthless-adversarial.sh"

if [[ $FAILS -eq 0 ]]; then
  printf 'PASS: %d assertions/tests\n' "$TESTS"
  exit 0
else
  printf 'FAIL: %d of %d assertions/tests failed\n' "$FAILS" "$TESTS" >&2
  exit 1
fi
