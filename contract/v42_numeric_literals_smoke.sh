#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"; "$NIFT" init >/dev/null

# Nift v4.2 numeric literal typing is lexical: integer forms infer int, the
# fractional/exponent forms (0.0, 8.0, 8.5, 1e3) infer double even when the
# value is integral. Inferred binding/field types stay stable; injected JSON
# numbers keep their established representation.

cat > content/index.html <<'EOT'
$[a := 0]
$[a = 8]
a=$[a]
$[b := 0.0]
$[b = 8.5]
b=$[b]
$[c := 8.0]
$[c = 9.5]
c=$[c]
$[d := 1e3]
$[d = 2.5]
d=$[d]
@struct(stats) {
 private count := 0
 private total := 0.0
 fn(add(value)) { count = count + 1; total = total + value }
 fn(count()) { return count }
 fn(total()) { return total }
 fn(average()) { if(count == 0) { return 0.0 }; return total / count }
}
$[s := stats()]
$[s.add(8.5)]
$[s.add(9.0)]
$[s.add(7.5)]
count=$[s.count()] total=$[s.total()] avg=$[s.average()]
EOT
"$NIFT" build --all >/dev/null
out=$(tr -d '[:space:]' < public/index.html)
[[ "$out" == *"a=8"* ]]
[[ "$out" == *"b=8.5"* ]]
[[ "$out" == *"c=9.5"* ]]
[[ "$out" == *"d=2.5"* ]]
[[ "$out" == *"count=3"* ]]
[[ "$out" == *"total=25"* ]]
[[ "$out" == *"avg=8.333"* ]]

# Double bindings reject int reassignment; int bindings reject double reassignment.
cat > content/index.html <<'EOT'
$[f := 0.0]
$[f = 3]
EOT
! "$NIFT" build --all >/dev/null 2>&1
cat > content/index.html <<'EOT'
$[g := 8]
$[g = 8.5]
EOT
! "$NIFT" build --all >/dev/null 2>&1

# copy/deepcopy preserve the inferred field forms.
cat > content/index.html <<'EOT'
@struct(metric) { low := 0.0; high := 10 }
$[m := metric()]
$[c := copy(m)]
$[d := deepcopy(m)]
$[c.low = 2.5]
$[d.high = 42]
c=$[c.low] d=$[d.high] m=$[m.low]
EOT
"$NIFT" build --all >/dev/null
out=$(tr -d '[:space:]' < public/index.html)
[[ "$out" == *"c=2.5"* ]]
[[ "$out" == *"d=42"* ]]
[[ "$out" == *"m=0"* ]]