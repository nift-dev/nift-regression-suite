#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:?}; R=$(mktemp -d); trap 'rm -rf "$R"' EXIT; cd "$R"; "$NIFT" init >/dev/null
cat > content/index.html <<'EOT'
@struct(counter) {
 private n := 0
 fn(counter(start)) { n = start }
 private fn(step()) { n = n + 1 }
 fn(add(k)) { i := 0; while(i < k) { step(); i = i + 1 } }
 fn(value()) { return n }
}
$[a := counter(2)]$[b := a]$[b.add(3)]$[a.value()]
$[c := copy(a)]$[c.add(1)]/$[a.value()]/$[c.value()]
$[d := deepcopy(a)]$[d.add(2)]/$[a.value()]/$[d.value()]
EOT
"$NIFT" build --all >/dev/null
out=$(tr -d '[:space:]' < public/index.html)
[[ "$out" == *"56/5/67/5/7"* ]]
