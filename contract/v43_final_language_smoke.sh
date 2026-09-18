#!/usr/bin/env bash
set -euo pipefail
: "${NIFT_BIN:?}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
run(){ printf '%s\n' "$1" > "$T/t.nift"; "$NIFT_BIN" run "$T/t.nift"; }
[[ "$(run 'print(type(null));print(type(1));print(type(1.5));print(is_null(null));print(is_number(1))')" == $'null\nint\nfloat\ntrue\ntrue' ]]
[[ "$(run 'print(null ?? "fallback");print("ok" ?? missing_name);print(null?.x);print({"x":1}?.x)')" == $'fallback\nok\nnull\n1' ]]
! run 'print({}?.typo)' >/dev/null 2>&1
[[ "$(run '[a,b] := [1,2]; {x,y} := {"x":3,"y":4,"extra":5}; print(a+b+x+y)')" == 10 ]]
[[ "$(run 'print(range(0,7,2).join(","));print(range(5,0,-2).join(","))')" == $'0,2,4,6\n5,3,1' ]]
cat > "$T/e.nift" <<'NIFT'
enum State { Draft, Live = 10, Archived }
print(State.Draft); print(State.Live.to_int()); print(State.Archived.to_int()); print(type(State.Live)); print(is_enum(State.Live))
NIFT
[[ "$("$NIFT_BIN" run "$T/e.nift")" == $'Draft\n10\n11\nenum\ntrue' ]]
echo 'final language contract passed'
