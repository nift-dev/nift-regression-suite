#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/pkg/src" "$t/site/.nift"
printf '{"name":"demo","entry":"src/main.f"}\n' > "$t/pkg/manifest.json"
printf 'answer := 42\nexport(answer)\n' > "$t/pkg/src/main.f"
(cd "$t/site" && "$NIFT_BIN" add "$t/pkg" >/dev/null)
printf '@import("demo")\nprint(answer)\n' > "$t/site/test.f"
[[ "$(cd "$t/site" && "$NIFT_BIN" run test.f)" == 42 ]]
grep -q '"demo"' "$t/site/manifest.json"
grep -q '"commit": "local"' "$t/site/.nift/packages.lock.json"
(cd "$t/site" && "$NIFT_BIN" remove demo)
[[ ! -e "$t/site/.nift/packages/demo" ]]
printf 'PASS v4.4 packages\n'
