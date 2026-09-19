#!/usr/bin/env bash
# Independent black-box contract: packages may export a struct or plain-object
# module value whose callable fields are invoked as methods while retaining
# package-private helpers, without leaking those helpers into the importer.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift/packages/vips/src"
printf '{"name":"vips","entry":"src/main.f"}\n' > "$t/site/.nift/packages/vips/manifest.json"
cat > "$t/site/.nift/packages/vips/src/main.f" <<'F'
@fn(scale_helper(x)) { return x * 2 }
@struct(vips_lib) { resize := (w, h) => { return {"w": scale_helper(w), "h": scale_helper(h)} } }
vips := vips_lib()
export(vips)
F
cat > "$t/site/t.f" <<'F'
@import("vips")
r := vips.resize(100, 50)
print(r.w)
print(r.h)
F
[ "$(cd "$t/site" && "$NIFT_BIN" run t.f)" = $'200\n100' ] || exit 1
cat > "$t/site/.nift/packages/vips/src/main.f" <<'F'
@fn(scale_helper(x)) { return x * 2 }
vips := {"resize": (w, h) => { return {"w": scale_helper(w), "h": scale_helper(h)} }}
export(vips)
F
[ "$(cd "$t/site" && "$NIFT_BIN" run t.f)" = $'200\n100' ] || exit 1
cat > "$t/site/t2.f" <<'F'
@import("vips")
print(scale_helper(5))
F
if (cd "$t/site" && "$NIFT_BIN" run t2.f >/dev/null 2>&1); then exit 1; fi
printf 'PASS v4.4 module export\n'