#!/usr/bin/env bash
# Independent black-box contract for v4.4 package hardening: manifest entry
# path traversal is rejected, duplicate add is refused, and package-private
# bindings never leak into the importer while exported functions keep their
# private module context.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift" "$t/evil"
printf '{"name":"evil","entry":"../../escape.f"}\n' > "$t/evil/manifest.json"
printf 'print("pwned")\n' > "$t/escape.f"
evil=$(cd "$t/site" && "$NIFT_BIN" add "$t/evil" 2>&1 || true)
grep -q 'package entry escapes the package directory' <<<"$evil"
mkdir -p "$t/pkg/src"
printf '{"name":"demo","entry":"src/main.f"}\n' > "$t/pkg/manifest.json"
printf 'v := 1\nexport(v)\n' > "$t/pkg/src/main.f"
(cd "$t/site" && "$NIFT_BIN" add "$t/pkg" >/dev/null 2>&1)
dup=$(cd "$t/site" && "$NIFT_BIN" add "$t/pkg" 2>&1 || true)
grep -q "already a dependency" <<<"$dup"
mkdir -p "$t/site/.nift/packages/iso/src"
printf '{"name":"iso","entry":"src/main.f"}\n' > "$t/site/.nift/packages/iso/manifest.json"
printf 'secret_helper := "hidden"\n@fn(public_fn(x)){ return x + 1 }\nexport(public_fn)\n' > "$t/site/.nift/packages/iso/src/main.f"
printf '@import("iso")\nprint(public_fn(1))\n' > "$t/site/t.f"
[ "$(cd "$t/site" && "$NIFT_BIN" run t.f)" = "2" ] || exit 1
printf '@import("iso")\nprint(secret_helper)\n' > "$t/site/t2.f"
if (cd "$t/site" && "$NIFT_BIN" run t2.f >/dev/null 2>&1); then exit 1; fi
printf 'PASS v4.4 package hardening\n'