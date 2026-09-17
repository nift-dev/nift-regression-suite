#!/usr/bin/env bash
# Independent black-box contract for the CP168-CP186 frontend algebra:
# from_entries, index_by, pick, omit, merge_deep, partition, unique_by,
# min_by, max_by, count_by, take, drop, chunk, group_by_each, and compound
# stable directional sort_by. Exercises public behavior through the nift
# executable (run/eval/template) rather than implementation internals.
set -euo pipefail
NIFT_BIN="${NIFT_BIN:?}"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
run(){ printf '%s\n' "$1" > "$td/t.nift"; "$NIFT_BIN" run "$td/t.nift"; }
run_err(){ if "$NIFT_BIN" run <(printf '%s\n' "$1") >/dev/null 2>&1; then echo "expected error: $1" >&2; return 1; fi; }
P='[{"n":"a","x":1,"tag":"a","tags":["a","b"],"featured":false,"date":2},{"n":"b","x":2,"tag":"b","tags":["b"],"featured":true,"date":1},{"n":"c","x":1,"tag":"a","tags":["a","a"],"featured":true,"date":3}]'

# --- object algebra ---
[[ "$(run 'print([{"key":"b","value":2},{"key":"a","value":1}].from_entries().keys().join(","))')" == b,a ]]
[[ "$(run 'print({"a":1,"b":2}.entries().from_entries().size())')" == 2 ]]
run_err 'print([{"key":"a","value":1},{"key":"a","value":2}].from_entries())'
run_err 'print([{"key":"a"}].from_entries())'
run_err 'print([{"key":[1],"value":1}].from_entries())'
[[ "$(run "a := $P; print(a.index_by(v => v.n).get(\"b\").x)")" == 2 ]]
[[ "$(run "a := $P; print(a.index_by(v => v.n).keys().join(\",\"))")" == a,b,c ]]
run_err "print([{\"k\":1},{\"k\":1}].index_by(v => v.k))"
run_err "print([{\"k\":1},{\"k\":1.0}].index_by(v => v.k))"
[[ "$(run 'print({"a":1,"b":2,"c":3}.pick(["c","a"]).keys().join(","))')" == c,a ]]
[[ "$(run 'print({"a":1,"author.name":2}.pick(["author.name"]).keys().join(","))')" == 'author.name' ]]
[[ "$(run 'print({"a":1,"b":2}.omit(["a"]).keys().join(","))')" == b ]]
[[ "$(run 'd := {"a":1,"b":2}
r := d.omit(["a"])
print(d.keys().join(","))')" == a,b ]]
[[ "$(run 'print({"a":{"x":1}}.merge_deep({"a":{"y":2}}).get("a").keys().join(","))')" == x,y ]]
[[ "$(run 'print({"a":[1]}.merge_deep({"a":[2]}).get("a").size())')" == 1 ]]
[[ "$(run 'l := {"a":{"x":1}}
r := l.merge_deep({"a":{"y":2}})
print(l.get("a").keys().join(","))')" == x ]]
run_err 'print({"a":1}.merge_deep([1]))'

# --- collection algebra ---
[[ "$(run "a := $P; print(a.partition(v => v.x > 1).matched.first().n)")" == b ]]
[[ "$(run "a := $P; print(a.partition(v => v.x > 1).unmatched.map(v => v.n).join(\",\"))")" == a,c ]]
run_err 'print([1].partition(x => 1))'
[[ "$(run "a := $P; print(a.unique_by(v => v.x).map(v => v.n).join(\",\"))")" == a,b ]]
[[ "$(run 'print([{"k":{"a":1,"b":2}},{"k":{"b":2,"a":1}}].unique_by(v => v.k).size())')" == 1 ]]
[[ "$(run 'print([{"x":1},{"x":"1"},{"x":1.0}].unique_by(v => v.x).size())')" == 2 ]]
[[ "$(run "a := $P; print(a.min_by(v => v.date).n); print(a.max_by(v => v.date).n)")" == $'b\nc' ]]
[[ "$(run 'print([{"v":1,"n":"a"},{"v":1,"n":"b"}].min_by(x => x.v).n)')" == a ]]
run_err 'print([].min_by(x => x))'
run_err 'print([{"v":1},{"v":"a"}].min_by(x => x.v))'
[[ "$(run "a := $P; print(a.count_by(v => v.tag).stringify())")" == '{"a":2,"b":1}' ]]
[[ "$(run "a := $P; print(a.count_by(v => v.tag).keys().join(\",\"))")" == a,b ]]
[[ "$(run 'print([1,2,3,4,5].take(2).stringify()); print([1,2,3,4].drop(2).stringify()); print([1,2,3,4,5].chunk(2).stringify())')" == $'[1,2]\n[3,4]\n[[1,2],[3,4],[5]]' ]]
[[ "$(run 'print([1,2,3].take(0).size()); print([1,2,3].drop(9).size()); print([1,2,3].chunk(5).size())')" == $'0\n0\n1' ]]
run_err 'print([1].take(-1))'
run_err 'print([1].take(1.5))'
run_err 'print([1].chunk(0))'
[[ "$(run "a := $P; print(a.group_by_each(v => v.tags).get(\"a\").map(v => v.n).join(\",\"))")" == a,c ]]
[[ "$(run "a := $P; print(a.group_by_each(v => v.tags).get(\"b\").map(v => v.n).join(\",\"))")" == a,b ]]
[[ "$(run 'print([{"t":["a","a"]}].group_by_each(x => x.t).get("a").size())')" == 1 ]]
[[ "$(run 'print([{"t":["b"]},{"t":["a"]}].group_by_each(x => x.t).keys().join(","))')" == b,a ]]
run_err 'print([1].group_by_each(x => "a"))'

# --- compound stable directional sort_by ---
[[ "$(run "a := $P; print(a.sort_by(v => v.featured, \"desc\", v => v.date, \"desc\").map(v => v.n).join(\",\"))")" == c,b,a ]]
[[ "$(run 'print([{"k":1,"i":0},{"k":1,"i":1},{"k":0,"i":2}].sort_by(x => x.k).map(x => x.i).join(","))')" == 2,0,1 ]]
[[ "$(run 'print([{"a":1,"b":1},{"a":1,"b":2},{"a":2,"b":0}].sort_by(x => x.a, "asc", x => x.b, "asc").map(x => x.b).join(","))')" == 1,2,0 ]]
[[ "$(run 'print([{"a":1,"b":1},{"a":1,"b":2},{"a":2,"b":0}].sort_by(x => x.a, "desc", x => x.b, "asc").map(x => x.b).join(","))')" == 0,1,2 ]]
[[ "$(run 'print([1,2,3].sort_by(x => x, "desc").join(","))')" == 3,2,1 ]]
run_err 'print([1].sort_by(x => x, "up"))'
run_err 'print([1].sort_by(x => x, desc))'

# --- cross-feature composition ---
[[ "$(run "a := $P; print(a.partition(v => v.featured).matched.sort_by(v => v.date).first().n)")" == b ]]
[[ "$(run "a := $P; print(a.unique_by(v => v.tag).count_by(v => v.x).size())")" == 2 ]]

echo 'frontend algebra contract passed'