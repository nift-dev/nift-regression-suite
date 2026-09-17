#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:?}"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
run(){ printf '%s\n' "$1" > "$td/t.nift"; "$NIFT_BIN" run "$td/t.nift"; }
A='[{"n":"a","x":1,"tag":"a","tags":["a","b"],"featured":false,"date":2},{"n":"b","x":2,"tag":"b","tags":["b"],"featured":true,"date":1},{"n":"c","x":1,"tag":"a","tags":["a","a"],"featured":true,"date":3}]'
[[ "$(run "a := $A; print(a.partition(v => v.x > 1).matched.first().n)")" == b ]]
[[ "$(run "a := $A; print(a.unique_by(v => v.x).map(v => v.n).join(\",\"))")" == 'a,b' ]]
[[ "$(run "a := $A; print(a.min_by(v => v.date).n); print(a.max_by(v => v.date).n)")" == $'b\nc' ]]
[[ "$(run "a := $A; print(a.count_by(v => v.tag).stringify())")" == '{"a":2,"b":1}' ]]
[[ "$(run 'print([1,2,3,4,5].take(2).stringify()); print([1,2,3].drop(1).stringify()); print([1,2,3].chunk(2).stringify())')" == $'[1,2]\n[2,3]\n[[1,2],[3]]' ]]
[[ "$(run "a := $A; print(a.group_by_each(v => v.tags).get(\"a\").map(v => v.n).join(\",\"))")" == 'a,c' ]]
[[ "$(run "a := $A; print(a.sort_by(v => v.featured, \"desc\", v => v.date, \"desc\").map(v => v.n).join(\",\"))")" == 'c,b,a' ]]
echo 'frontend algebra contract passed'
