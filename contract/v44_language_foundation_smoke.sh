#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/tree/a/deep" "$t/tree/b" "$t/out"
touch "$t/tree/a/one.o" "$t/tree/a/deep/two.o" "$t/tree/b/three.txt"
cat >"$t/test.f" <<F
@fn(pack(head, ...rest)){ return rest }
\$[xs := [1, "two", true]]
print(pack("h", ...xs).size())
\$[f := (...args) => args.size()]
print(f(...xs))
print(min(...[7,2,5]))
print(ls("$t/tree/**/*.o").size())
copy("$t/tree/**/*.o", "$t/out")
print(ls("$t/out/*.o").size())
remove("$t/out/*.o")
\$[obj := {"user_name":"n","user_id":2,"other":false}]
print(obj.pick(["user_*"]).size())
print({"a":1,"b":2,"c":3}.pick(["c","a"]).keys().join(","))
\$[val_copy := copy([1, [2, 3]])]
print(val_copy.size())
\$[rows := [{"name":"A"},{"name":"B"}]]
\$[html := rows.map(row => {<b>\$[row.name]</b>}).join("")]
print(html)
cd("$t/tree/a/deep")
print(exists("../one.o"))
F
out=$($NIFT_BIN run "$t/test.f")
[[ "$out" == *$'3\n3\n2\n2\n2\n2'* ]] || { printf '%s\n' "$out" >&2; exit 1; }
[[ "$out" == *'c,a'* ]] || { printf '%s\n' "$out" >&2; exit 1; }
[[ "$out" == *$'\n2\n'* ]] || { printf '%s\n' "$out" >&2; exit 1; }
[[ "$out" == *'<b>A</b><b>B</b>'* ]] || { printf '%s\n' "$out" >&2; exit 1; }
[[ "$out" == *'true'* ]] || exit 1
printf 'PASS v4.4 language foundation\n'
