#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"; "$NIFT" init >/dev/null
B(){ tr -d '[:space:]' < public/index.html; }

# --- @script: current scope, native declarations, control flow, returns. ---
cat > content/index.html <<'EOT'
$[outer := 2]
@script {
  outer += 3
  fn(dbl(x)) { return x * 2 }
  struct(box) { v := 1; fn(box(v)) { v = v } fn(get()) { return v } }
  b := box(7)
  total := 0
  for(i : [1,2,3]) { if(i == 2) { continue }; total += i }
  return "R:$[dbl(outer)]/$[b.get()]/$[total]"
}
$[outer]
EOT
"$NIFT" build --all >/dev/null
o=$(B); [[ "$o" == *"R:10/7/4"* ]] && [[ "$o" == *"5"* ]]

# Bare return renders nothing; return null renders the null value.
cat > content/index.html <<'EOT'
A@script { return }B@script { return null }C
EOT
"$NIFT" build --all >/dev/null
[[ "$(B)" == *"ABnullC"* ]]

# Returned source-looking strings are values and are never reparsed.
cat > content/index.html <<'EOT'
@script { return "@if(x){<b>}@for(y:[1]){}" }
EOT
"$NIFT" build --all >/dev/null
[[ "$(B)" == *"@if(x){<b>}@for(y:[1]){}"* ]]

# Returned strings still undergo normal literal interpolation (real semantics),
# so an undefined interpolated name is an error rather than silent text.
cat > content/index.html <<'EOT'
@script { return "@if(x){$[undefined_name]}" }
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "undefined interpolation succeeded" >&2; exit 1; fi

# Statements that do not resolve are errors in script land.
cat > content/index.html <<'EOT'
@script { not_a_defined_binding }
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "unknown script statement succeeded" >&2; exit 1; fi

# --- @import isolation and live-binding exports. ---
mkdir -p content/lib
cat > content/lib/counter.nift <<'EOT'
count := 0
increment := () => ++count
export(count)
export(increment)
EOT
cat > content/index.html <<'EOT'
$[unrelated := 100]
@import("content/lib/counter.nift")
$[count],$[increment()],$[count]
EOT
"$NIFT" build --all >/dev/null
[[ "$(B)" == *"0,1,1"* ]]

# The imported script cannot resolve caller bindings.
cat > content/lib/snoop.nift <<'EOT'
leak := secret_binding
export(leak)
EOT
cat > content/index.html <<'EOT'
$[secret_binding := 7]@import("content/lib/snoop.nift")
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "import leaked caller scope" >&2; exit 1; fi

# Atomic validation: a missing export or a caller-name collision fails the
# whole import and leaves the caller unchanged.
cat > content/lib/missing.nift <<'EOT'
x := 1
export(does_not_exist)
EOT
cat > content/index.html <<'EOT'
@import("content/lib/missing.nift")$[marker := 5]$[marker]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "missing-export import succeeded" >&2; exit 1; fi
cat > content/lib/collide.nift <<'EOT'
value := 2
export(value)
EOT
cat > content/index.html <<'EOT'
$[value := 9]@import("content/lib/collide.nift")$[value]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "colliding export import succeeded" >&2; exit 1; fi

# return expression is rejected in an import; bare return is early success.
cat > content/lib/badret.nift <<'EOT'
return 5
EOT
cat > content/index.html <<'EOT'
@import("content/lib/badret.nift")
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "import value return succeeded" >&2; exit 1; fi
cat > content/lib/early.nift <<'EOT'
v := 8
export(v)
return
v = 9
EOT
cat > content/index.html <<'EOT'
@import("content/lib/early.nift")$[v]
EOT
"$NIFT" build --all >/dev/null
[[ "$(B)" == *"8"* ]]

# Import cycles fail deterministically.
mkdir -p content/cyc
cat > content/cyc/a.nift <<'EOT'
@import("b.nift")
EOT
cat > content/cyc/b.nift <<'EOT'
@import("a.nift")
EOT
cat > content/index.html <<'EOT'
@import("content/cyc/a.nift")
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "import cycle succeeded" >&2; exit 1; fi

# --- Array/string ergonomics (black box). ---
cat > content/index.html <<'EOT'
$[a := [1,2,3,4]]
$[a.join("-")]
$[s := a.slice(1,3)]$[s.join("")]
$[r := a.splice(1,2,[8,9])]$[r.join("")]
$[a.join("")]
$[a.reverse()]$[a.join("")]
$[t := "abcdef"]$[t.substr(2,3)]
EOT
"$NIFT" build --all >/dev/null
o=$(B)
[[ "$o" == *"1-2-3-4"* ]]
[[ "$o" == *"23"* ]]
[[ "$o" == *"23"* ]]
[[ "$o" == *"1894"* ]]
[[ "$o" == *"4981"* ]]
[[ "$o" == *"cde"* ]]

# Deliberate string concatenation: chains, left-associativity, no coercion.
cat > content/index.html <<'EOT'
$["a" + "b" + "c"]
$[1 + 2 + "x"]
$["x" + 1 + 2]
$["n=" + 3]
$[1 == "1"]
$[x := 6]$[(z := 5) + 1]$[z]
EOT
"$NIFT" build --all >/dev/null
o=$(B)
[[ "$o" == *"abc"* ]]
[[ "$o" == *"3x"* ]]
[[ "$o" == *"x12"* ]]
[[ "$o" == *"n=3"* ]]
[[ "$o" == *"false"* ]]
[[ "$o" == *"65"* ]]

# --- Console and host boundaries. ---
cat > content/index.html <<'EOT'
$[read()]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "read() allowed during build" >&2; exit 1; fi
cat > content/index.html <<'EOT'
$[cd("/tmp")]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "cd() allowed during build" >&2; exit 1; fi
cat > content/index.html <<'EOT'
$[remove("..")]
EOT
if "$NIFT" build --all >/dev/null 2>&1; then echo "remove escaped project" >&2; exit 1; fi

# --- CLI: nift run and nift sh (black box). ---
printf 'print("run-ok")\n' > run1.nift
[[ "$("$NIFT" run run1.nift)" == 'run-ok' ]]
printf 'return 42\n' > run2.nift
[[ "$("$NIFT" run run2.nift)" == '42' ]]
printf 'this_is_not_defined\n' > run3.nift
if "$NIFT" run run3.nift >/dev/null 2>&1; then echo "undefined run statement exited zero" >&2; exit 1; fi
printf 'print("missing-file")\n' > run4.nift
if "$NIFT" run does-not-exist.nift >/dev/null 2>&1; then echo "missing run file exited zero" >&2; exit 1; fi
printf 'who := read()\nprint("got:" + who)\n' > run5.nift
[[ "$(printf 'hello\n' | "$NIFT" run run5.nift)" == 'got:hello' ]]
# nift sh: persistent bindings and error recovery in one session.
repl=$(cd "$R" && printf 'x := 4\nprint(x)\nprint(undefined_thing)\nprint(x + 1)\nquit\n' | "$NIFT" sh 2>&1 || true)
grep -q '^4$' <<<"$repl" || grep -q '4' <<<"$repl"
grep -q '5' <<<"$repl"