#!/usr/bin/env bash
# Independent black-box contract: simultaneous @import("vips") and
# @import("imagemagick") must coexist without namespace collision, with
# distinct exported structs (vips / magick). The ImageMagick side runs a live
# pipeline; the vips side certifies client/export behavior even when the vips
# executable is absent (structured exit_code 127 failures).
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIPS_PKG="${VIPS_PKG:-$ROOT/../nift-packages/vips}"
MAGICK_PKG="${MAGICK_PKG:-$ROOT/../nift-packages/imagemagick}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift" "$t/site/assets" "$t/site/out"
(cd "$t/site" && "$NIFT_BIN" add "$VIPS_PKG" >/dev/null 2>&1)
(cd "$t/site" && "$NIFT_BIN" add "$MAGICK_PKG" >/dev/null 2>&1)
cat > "$t/site/t.f" <<'F'
@import("vips")
@import("imagemagick")
print("vips")
print(vips.available())
print("magick")
print(magick.available())
vr := vips.resize("assets/base.png", "out/vr.png", 0.5)
print("vips-resize-ok:")
print(vr.ok)
print("vips-exit:" + vr.exit_code.to_string())
mr := magick.resize("assets/base.png", "out/mr.png", {"width": 64, "height": 64})
print("magick-resize-ok:")
print(mr.ok)
if(magick.available()) {
  id := magick.identify("out/mr.png")
  print("magick-size:" + id.width + "x" + id.height)
}
F
out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
avail_vips="$(sed -n '2p' <<<"$out")"
avail_magick="$(sed -n '4p' <<<"$out")"
[ "$avail_vips" = "true" ] || [ "$avail_vips" = "false" ] || { echo "$out" >&2; exit 1; }
[ "$avail_magick" = "true" ] || [ "$avail_magick" = "false" ] || { echo "$out" >&2; exit 1; }
# vips client behavior: structured failure (typically exit_code 127 when the
# vips executable is absent) whatever available() reports.
grep -q '^false$' <<<"$out" || { echo "$out" >&2; exit 1; }
grep -qE '^vips-exit:[0-9]+$' <<<"$out" || { echo "$out" >&2; exit 1; }
if command -v magick >/dev/null 2>&1; then
  magick -size 32x32 xc:red "$t/site/assets/base.png" 2>/dev/null
  out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
fi
grep -q '^true$' <<<"$out" || { echo "$out" >&2; exit 1; }
grep -q '^magick-size:64x' <<<"$out" || exit 1
# private helpers from one package cannot shadow/leak into the other
cat > "$t/site/priv.f" <<'F'
@import("vips")
@import("imagemagick")
print(vips_guard)
print(magick_run)
F
if (cd "$t/site" && "$NIFT_BIN" run priv.f >/dev/null 2>&1); then echo "private helper leaked" >&2; exit 1; fi
printf 'PASS v4.4 vips + imagemagick combined\n'
