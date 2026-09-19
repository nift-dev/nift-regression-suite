#!/usr/bin/env bash
# Independent black-box contract: the imagemagick package exports a module-style
# value named `magick` (package name != exported name). Exercises a live
# resize/crop/rotate/convert/identify pipeline and verifies private helpers stay
# hidden. Skips the live pipeline if the magick executable is unavailable.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGICK_PKG="${MAGICK_PKG:-$ROOT/../nift-packages/imagemagick}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift" "$t/site/assets" "$t/site/out"
(cd "$t/site" && "$NIFT_BIN" add "$MAGICK_PKG" >/dev/null 2>&1)
cat > "$t/site/imp.f" <<'F'
@import("imagemagick")
print(magick.available())
F
imp_out=$(cd "$t/site" && "$NIFT_BIN" run imp.f)
if [ "$imp_out" != "true" ]; then
  if [ "$imp_out" != "false" ]; then echo "unexpected: $imp_out" >&2; exit 1; fi
  echo "magick executable unavailable; skipping live pipeline"
  printf 'PASS v4.4 imagemagick package -> magick export\n'
  exit 0
fi
if command -v magick >/dev/null 2>&1; then
  magick -size 800x600 gradient:red-blue "$t/site/assets/base.png" 2>/dev/null
fi
cat > "$t/site/t.f" <<'F'
@import("imagemagick")
r := magick.resize("assets/base.png", "out/r.png", {"width": 200, "height": 200})
print(r.ok)
id := magick.identify("out/r.png")
print(id.width + "x" + id.height + " " + id.format)
c := magick.crop("assets/base.png", "out/c.png", {"width": 100, "height": 80, "left": 10, "top": 20})
print(c.ok)
id2 := magick.identify("out/c.png")
print(id2.width + "x" + id2.height)
print(magick.rotate("assets/base.png", "out/rot.png", 90).ok)
print(magick.convert("assets/base.png", "out/base.jpg").ok)
id3 := magick.identify("out/base.jpg")
print(id3.format)
print(magick.compose("assets/base.png", "out/r.png", "out/comp.png", {"gravity": "center"}).ok)
print(magick.identify("out/missing.png").ok)
print(magick.available())
print(magick.version() != "")
F
out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
[ "$(sed -n '1p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '2p' <<<"$out")" = "200x150 PNG" ] || exit 1
[ "$(sed -n '3p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '4p' <<<"$out")" = "100x80" ] || exit 1
[ "$(sed -n '5p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '6p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '7p' <<<"$out")" = "JPEG" ] || exit 1
[ "$(sed -n '8p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '9p' <<<"$out")" = "false" ] || exit 1
[ "$(sed -n '10p' <<<"$out")" = "true" ] || exit 1
[ "$(sed -n '11p' <<<"$out")" = "true" ] || exit 1
cat > "$t/site/priv.f" <<'F'
@import("imagemagick")
print(magick_run)
F
if (cd "$t/site" && "$NIFT_BIN" run priv.f >/dev/null 2>&1); then echo "private helper leaked" >&2; exit 1; fi
printf 'PASS v4.4 imagemagick package -> magick export\n'
