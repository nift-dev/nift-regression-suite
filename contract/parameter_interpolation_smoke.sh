#!/usr/bin/env bash
set -uo pipefail

NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-param-interpolation.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

FAILS=0
CHECKS=0

pass(){ CHECKS=$((CHECKS+1)); }
fail(){ CHECKS=$((CHECKS+1)); FAILS=$((FAILS+1)); printf 'FAIL: %s\n' "$*" >&2; }

expect_file_contains(){
  local file="$1" text="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq -- "$text" "$file"; then pass; else fail "$label"; fi
}

expect_file_not_contains(){
  local file="$1" text="$2" label="$3"
  if [[ -f "$file" ]] && ! grep -Fq -- "$text" "$file"; then pass; else fail "$label"; fi
}

expect_build_success(){
  local dir="$1" label="$2"
  if (cd "$dir" && "$NIFT_BIN" build --all >build.log 2>&1); then pass
  else fail "$label"; [[ -f "$dir/build.log" ]] && sed -n '1,80p' "$dir/build.log" >&2; fi
}

expect_build_failure(){
  local dir="$1" expected="$2" label="$3"
  if (cd "$dir" && "$NIFT_BIN" build --all >build.log 2>&1); then
    fail "$label (unexpected success)"
  elif grep -Fq -- "$expected" "$dir/build.log"; then pass
  else fail "$label (missing diagnostic: $expected)"; sed -n '1,80p' "$dir/build.log" >&2; fi
}

make_project(){
  local dir="$1" mode="${2:-modified}"
  mkdir -p "$dir/.nift" "$dir/content" "$dir/templates/partials" \
           "$dir/public/assets" "$dir/data" "$dir/schemas"
  cat >"$dir/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"$mode"}}
JSON
  cat >"$dir/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Param Contract","template":"templates/template.html"}]}
JSON
  printf 'CONTENT\n' >"$dir/content/index.html"
}

# All currently textual @function arguments share the ordinary $[...] scalar
# contract. Source argument boundaries are fixed before interpolation: commas,
# quotes, parentheses, @ operations and produced $[...] text remain inert data.
P="$TMP/textual"
make_project "$P"
cat >"$P/data/selectors.json" <<'JSON'
{
  "partial":"partials/card.html",
  "layout":"feature",
  "left":"fea",
  "right":"ture",
  "dep":"selected",
  "dep2":"second",
  "asset":"app-B7K2pQ",
  "dataset":"chosen",
  "schema":"chosen.schema",
  "env":"NIFT_PARAMETER_VALUE",
  "entity":"section",
  "number":4,
  "enabled":true,
  "nothing":null,
  "empty":"",
  "weird":"data/value,with('quote')and(paren).txt",
  "operation":"@ent(section)",
  "produced":"$[selector.partial]",
  "items":[{"file":"one"},{"file":"two"}],
  "groups":[{"file":"outer","items":[{"file":"inner"}]}]
}
JSON
printf 'CARD\n' >"$P/templates/partials/card.html"
printf 'FEATURE\n' >"$P/templates/partials/feature.html"
printf 'ONE\n' >"$P/templates/partials/one.html"
printf 'TWO\n' >"$P/templates/partials/two.html"
printf 'ROW1\n' >"$P/templates/partials/row-1.html"
printf 'ROW2\n' >"$P/templates/partials/row-2.html"
printf 'OUTER\n' >"$P/templates/partials/outer.html"
printf 'INNER\n' >"$P/templates/partials/inner.html"
printf 'OPERATION-DATA\n' >"$P/templates/@ent(section)"
printf 'PRODUCED-DOLLAR-DATA\n' >"$P/templates/\$[selector.partial]"
printf 'ESCAPED-DOLLAR-DATA\n' >"$P/templates/\$[selector.layout].html"
printf x >"$P/data/selected.txt"
printf x >"$P/data/second.txt"
printf x >"$P/data/4.txt"
printf x >"$P/data/true.txt"
printf x >"$P/data/null.txt"
printf x >"$P/data/Param Contract.txt"
printf x >"$P/data/value,with('quote')and(paren).txt"
printf x >"$P/public/assets/app-B7K2pQ.js"
printf '{"message":"CHOSEN"}\n' >"$P/data/chosen.json"
printf '{"type":"object","required":["message"],"properties":{"message":{"type":"string"}}}\n' >"$P/schemas/chosen.schema.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selectors.json", selector)
@json("data/$[selector.dataset].json", chosen, "schemas/$[selector.schema].json")
WHOLE=@input($[selector.partial])
DOUBLE=@input("partials/$[selector.layout].html")
SINGLE=@input('partials/$[selector.layout].html')
ADJACENT=@input("partials/$[selector.left]$[selector.right].html")
@dep("data/$[selector.dep].txt", 'data/$[selector.dep2].txt')
@dep("data/$[selector.number].txt", "data/$[selector.enabled].txt", "data/$[selector.nothing].txt")
@dep("data/$[title].txt")
@dep("$[selector.weird]")
PATH=@pathto("public/assets/$[selector.asset].js")
PATHFILE=@pathtofile('public/assets/$[selector.asset].js')
ENV=@getenv("$[selector.env]")
ENTITY=@ent($[selector.entity])
JSON=$[chosen.message]
OP=@input($[selector.operation])
PRODUCED=@input($[selector.produced])
ESCAPED=@input("\$[selector.layout].html")
@for(item : selector.items){LOOP=@input("partials/$[item.file].html")
INDEX=@input("partials/row-$[loop.index].html")
}
@for(item : selector.groups){OUTER1=@input("partials/$[item.file].html")
@for(item : item.items){INNER=@input("partials/$[item.file].html")
}
OUTER2=@input("partials/$[item.file].html")
}
@if(false){@input("partials/$[selector.missing].html")
}
EMPTY=<$[selector.empty]>
@content
EOF
if (cd "$P" && NIFT_PARAMETER_VALUE='ENV-VALUE' "$NIFT_BIN" build --all >build.log 2>&1); then pass
else fail 'textual directives accept parameter interpolation'; sed -n '1,100p' "$P/build.log" >&2; fi
OUT="$P/public/index.html"
for expected in \
  CARD FEATURE 'PATH=assets/app-B7K2pQ.js' 'PATHFILE=assets/app-B7K2pQ.js' \
  'ENV=ENV-VALUE' 'ENTITY=&sect;' 'JSON=CHOSEN' OPERATION-DATA \
  PRODUCED-DOLLAR-DATA ESCAPED-DOLLAR-DATA ONE TWO ROW1 ROW2 OUTER INNER CONTENT
do expect_file_contains "$OUT" "$expected" "textual interpolation output contains $expected"; done
expect_file_not_contains "$OUT" 'selector.layout' 'parameter values do not leak unresolved into output'
INFO="$P/.nift/public/index.info.json"
for dep in data/selectors.json data/chosen.json schemas/chosen.schema.json \
           templates/partials/card.html templates/partials/feature.html \
           data/selected.txt data/second.txt data/4.txt data/true.txt data/null.txt \
           'data/Param Contract.txt' "data/value,with('quote')and(paren).txt"
do expect_file_contains "$INFO" "\"$dep\"" "resolved dependency recorded: $dep"; done
expect_file_contains "$INFO" '"public/assets/app-B7K2pQ.js"' 'resolved requirement recorded'

# Binding identifiers are grammar, not dynamic text. Textual JSON source and
# schema arguments interpolate; the alias position remains a static identifier.
P="$TMP/dynamic-binding"
make_project "$P"
printf '{"binding":"dynamic"}\n' >"$P/data/selector.json"
printf '{}\n' >"$P/data/value.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@json("data/value.json", $[selector.binding])
EOF
expect_build_failure "$P" 'json: name must be an identifier' 'JSON binding names remain static grammar'

# Values follow ordinary rendering types: scalars are textual; arrays and
# objects cannot be rendered into a textual function parameter.
for kind in array object; do
  P="$TMP/type-$kind"; make_project "$P"
  if [[ "$kind" == array ]]; then value='["x"]'; diagnostic='parameter expression must resolve to a scalar value'
  else value='{"x":1}'; diagnostic='parameter expression must resolve to a scalar value'; fi
  printf '{"value":%s}\n' "$value" >"$P/data/selector.json"
  cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@dep($[selector.value])
EOF
  expect_build_failure "$P" "$diagnostic" "$kind values are rejected as textual parameters"
done

# A bound missing member is a value-resolution error. A malformed expression
# must fail cleanly rather than corrupting following parser state.
P="$TMP/missing"; make_project "$P"
printf '{}\n' >"$P/data/selector.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@dep("data/$[selector.missing].txt")
EOF
expect_build_failure "$P" "has no member 'missing'" 'missing member reports value-resolution failure'

P="$TMP/malformed"; make_project "$P"
printf '{}\n' >"$P/data/selector.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@dep("data/$[selector.value.txt")
<p>AFTER-MALFORMED</p>
EOF
if (cd "$P" && "$NIFT_BIN" build --all >build.log 2>&1); then
  fail 'malformed interpolation unexpectedly succeeds'
else pass; fi

# Interpolated traversal remains subject to the outer operation's containment
# rules; value provenance never grants a privileged path.
P="$TMP/traversal"; make_project "$P"
printf '{"path":"../outside.txt"}\n' >"$P/data/selector.json"
printf outside >"$TMP/outside.txt"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@dep($[selector.path])
EOF
expect_build_failure "$P" 'dep: path must stay inside the Nift project' 'interpolated traversal is rejected'

# Dynamic dependency sets are replaced after a successful A -> B transition in
# all incremental modes. The selector and current target matter; stale A does not.
for mode in modified hash hybrid; do
  P="$TMP/input-$mode"; make_project "$P" "$mode"
  printf 'A\n' >"$P/templates/partials/a.html"
  printf 'B\n' >"$P/templates/partials/b.html"
  printf '{"partial":"a"}\n' >"$P/data/selector.json"
  cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@input("partials/$[selector.partial].html")
@content
EOF
  if (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
    expect_file_contains "$P/public/index.html" A "$mode dynamic input initially selects A"
    sleep 1
    printf '{"partial":"b"}\n' >"$P/data/selector.json"
    if (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); then pass; else fail "$mode selector A -> B rebuild succeeds"; fi
    expect_file_contains "$P/public/index.html" B "$mode dynamic input switches to B"
    expect_file_contains "$P/.nift/public/index.info.json" 'templates/partials/b.html' "$mode records B dependency"
    expect_file_not_contains "$P/.nift/public/index.info.json" 'templates/partials/a.html' "$mode removes stale A dependency"
    sleep 1
    printf 'A2\n' >"$P/templates/partials/a.html"
    (cd "$P" && "$NIFT_BIN" status >status-a.log 2>&1)
    if grep -Fq 'needs rebuilding' "$P/status-a.log"; then fail "$mode stale A still invalidates page"; else pass; fi
    sleep 1
    printf 'B2\n' >"$P/templates/partials/b.html"
    (cd "$P" && "$NIFT_BIN" status >status-b.log 2>&1)
    if grep -Fq 'needs rebuilding' "$P/status-b.log"; then pass; else fail "$mode current B does not invalidate page"; fi
  else
    fail "$mode dynamic input baseline build succeeds"
  fi
done

# Explicit @dep selection uses the same successful-build replacement semantics.
P="$TMP/dynamic-dep"; make_project "$P" modified
printf a >"$P/data/a.txt"; printf b >"$P/data/b.txt"
printf '{"dep":"a"}\n' >"$P/data/selector.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@dep("data/$[selector.dep].txt")
@content
EOF
if (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  sleep 1; printf '{"dep":"b"}\n' >"$P/data/selector.json"
  (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1)
  expect_file_contains "$P/.nift/public/index.info.json" 'data/b.txt' 'dynamic dep records B'
  expect_file_not_contains "$P/.nift/public/index.info.json" 'data/a.txt' 'dynamic dep removes A'
else fail 'dynamic dep baseline build succeeds'; fi

# Dynamic requirements replace A with B, ignore asset byte changes, and become
# invalid when the selected asset disappears.
P="$TMP/requirements"; make_project "$P" modified
printf a >"$P/public/assets/a.js"; printf b >"$P/public/assets/b.js"
printf '{"asset":"a"}\n' >"$P/data/selector.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
<script src="@pathto('public/assets/$[selector.asset].js')"></script>
@content
EOF
if (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  sleep 1; printf '{"asset":"b"}\n' >"$P/data/selector.json"
  (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1)
  expect_file_contains "$P/.nift/public/index.info.json" 'public/assets/b.js' 'dynamic requirement records B'
  expect_file_not_contains "$P/.nift/public/index.info.json" 'public/assets/a.js' 'dynamic requirement removes A'
  sleep 1; printf changed >"$P/public/assets/b.js"
  (cd "$P" && "$NIFT_BIN" status >status-bytes.log 2>&1)
  if grep -Fq 'needs rebuilding' "$P/status-bytes.log"; then fail 'requirement byte change invalidates page'; else pass; fi
  rm "$P/public/assets/b.js"
  (cd "$P" && "$NIFT_BIN" status >status-missing.log 2>&1)
  if grep -Fq 'required path missing: public/assets/b.js' "$P/status-missing.log"; then pass; else fail 'missing dynamic requirement invalidates page'; fi
else fail 'dynamic requirement baseline build succeeds'; fi

# Dynamic JSON source dependencies replace A with B rather than accumulating.
P="$TMP/dynamic-json"; make_project "$P" modified
printf '{"source":"a"}\n' >"$P/data/selector.json"
printf '{"value":"A"}\n' >"$P/data/a.json"
printf '{"value":"B"}\n' >"$P/data/b.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@json("data/$[selector.source].json", selected)
$[selected.value]
@content
EOF
if (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  sleep 1; printf '{"source":"b"}\n' >"$P/data/selector.json"
  (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1)
  expect_file_contains "$P/public/index.html" B 'dynamic JSON switches to B'
  expect_file_contains "$P/.nift/public/index.info.json" 'data/b.json' 'dynamic JSON records B'
  expect_file_not_contains "$P/.nift/public/index.info.json" 'data/a.json' 'dynamic JSON removes A'
else fail 'dynamic JSON baseline build succeeds'; fi

# Failed resolution/operation preserves the previous successful output and page
# metadata; repairing the selector recovers without deleting internal state.
P="$TMP/failure-recovery"; make_project "$P" modified
printf 'GOOD-A\n' >"$P/templates/partials/a.html"
printf 'GOOD-B\n' >"$P/templates/partials/b.html"
printf '{"partial":"a"}\n' >"$P/data/selector.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/selector.json", selector)
@input("partials/$[selector.partial].html")
@content
EOF
if (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); then
  cp "$P/public/index.html" "$P/output.before"
  cp "$P/.nift/public/index.info.json" "$P/info.before"
  sleep 1; printf '{"partial":"missing"}\n' >"$P/data/selector.json"
  if (cd "$P" && "$NIFT_BIN" build >failed.log 2>&1); then fail 'missing dynamic input unexpectedly succeeds'; else pass; fi
  if cmp -s "$P/output.before" "$P/public/index.html"; then pass; else fail 'failed dynamic build changed last good output'; fi
  if cmp -s "$P/info.before" "$P/.nift/public/index.info.json"; then pass; else fail 'failed dynamic build changed last good metadata'; fi
  printf '{"partial":"b"}\n' >"$P/data/selector.json"
  if (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); then pass; else fail 'repaired dynamic input does not recover'; fi
  expect_file_contains "$P/public/index.html" GOOD-B 'repaired dynamic input emits B'
else fail 'failure-recovery baseline build succeeds'; fi

if [[ $FAILS -eq 0 ]]; then
  printf 'Parameter interpolation contract passed: %d checks\n' "$CHECKS"
  exit 0
fi
printf 'Parameter interpolation contract failed: %d of %d checks\n' "$FAILS" "$CHECKS" >&2
exit 1
