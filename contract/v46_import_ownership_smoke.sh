#!/usr/bin/env bash
# Independent black-box contract: v4.6 relative-import ownership.
# Path-shaped imports resolve exactly once from the source containing the
# import (defining module), never probing and falling back to the project root.
# This module certifies the positive forms (./, ../, bare-path, nested) and the
# negative case that the removed ambiguous root-fallback form is now rejected,
# plus module_path()/package resource paths.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Consumer-root decoy vs owned sibling: `./helper.f` must resolve to the sibling
# owned by the defining module, never the decoy at the project root.
mkdir -p direct/modules/nested
printf 'fn(value()) { return "decoy" }\nexport(value)\n' > direct/helper.f
printf 'fn(value()) { return "owned" }\nexport(value)\n' > direct/modules/helper.f
printf 'fn(two()) { return "nested" }\nexport(two)\n' > direct/modules/two.f
printf '@import("../two.f")\nexport(two)\n' > direct/modules/nested/one.f
cat > direct/modules/main.f <<'F'
@import("./helper.f")
@import("./nested/one.f")
print(value())
print(two())
F
out=$(cd direct && "$NIFT_BIN" modules/main.f)
[ "$out" = $'owned\nnested' ] || { echo "sibling ownership: $out" >&2; exit 1; }

# A missing package-local sibling must NOT fall through to a consumer-root decoy.
mkdir -p site/sub
printf 'fn(decoy()) { return "decoy" }\nexport(decoy)\n' > site/missing.f
printf '@import("./missing.f")\n' > site/sub/main.f
if (cd site && "$NIFT_BIN" sub/main.f >/dev/null 2>&1); then echo "missing sibling fell through to decoy" >&2; exit 1; fi

# Negative: the removed root-fallback form is rejected. From content/index.html
# a bare `content/lib/item.nift` no longer resolves via the project root.
mkdir -p content/lib
printf 'v := 1\nexport(v)\n' > content/lib/item.nift
printf '@import("content/lib/item.nift")\nprint(v)\n' > content/index.html
if "$NIFT_BIN" content/index.html >/dev/null 2>&1; then echo "root-fallback import unexpectedly accepted" >&2; exit 1; fi

# Positive canonical form resolves from the defining source.
printf '@import("lib/item.nift")\nprint(v)\n' > content/index.html
[ "$("$NIFT_BIN" content/index.html)" = '1' ] || { echo "canonical relative import failed" >&2; exit 1; }

# module_path() reports the defining source directory; module_path(rel) joins it.
# It is only meaningful for a file-backed source (deliberately rejected on -e).
printf 'print(module_path() != "")\nprint(module_path("child.f") != "")\n' > mp.f
out=$("$NIFT_BIN" mp.f)
[ "$out" = $'true\ntrue' ] || { echo "module_path(): $out" >&2; exit 1; }
if "$NIFT_BIN" -e 'module_path()' >/dev/null 2>"$t/e"; then echo "module_path() accepted no file source" >&2; exit 1; fi
grep -q 'no file-backed source' "$t/e"

# package_path() requires a package owner, then reports the installed package
# root; module_path() inside the package reports the module's own directory.
printf 'print(package_path())\n' > pkgowner.f
if "$NIFT_BIN" pkgowner.f >/dev/null 2>"$t/e"; then echo "package_path() accepted no package owner" >&2; exit 1; fi
grep -q 'not owned by a package' "$t/e"
mkdir -p site/.nift/packages/demo/src
printf '{"dependencies":{"demo":{"source":"./demo","ref":"local"}}}\n' > site/manifest.json
printf '{"demo":{"source":"./demo","requested":"local","commit":"local"}}\n' > site/.nift/packages.lock.json
printf '{"name":"demo","version":"0.1.0","entry":"src/main.f"}\n' > site/.nift/packages/demo/manifest.json
printf 'print(module_path())\nprint(package_path())\n' > site/.nift/packages/demo/src/main.f
printf '@import("demo")\nprint("ok")\n' > site/t.f
out=$(cd site && "$NIFT_BIN" t.f)
case "$out" in
  *'.nift/packages/demo/src'*'.nift/packages/demo'*'ok'*) : ;;
  *) echo "package/module path: $out" >&2; exit 1 ;;
esac

# Template build honors the same ownership rule (no project-root decoy capture).
mkdir -p tmpl/.nift tmpl/content tmpl/templates/modules tmpl/public
cat > tmpl/.nift/config.json <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/modules/page.html"}}
JSON
cat > tmpl/.nift/tracked.json <<'JSON'
{"tracked":[{"name":"/","title":"relative owner","template":"templates/modules/page.html"}]}
JSON
printf 'body\n' > tmpl/content/index.html
printf '@fn(template_value()) { return "decoy" }\nexport(template_value)\n' > tmpl/templates/helper.f
printf '@fn(template_value()) { return "template-owned" }\nexport(template_value)\n' > tmpl/templates/modules/helper.f
printf '@import("./helper.f")$[template_value()] @content\n' > tmpl/templates/modules/page.html
(cd tmpl && "$NIFT_BIN" build --all >/dev/null)
grep -Fq 'template-owned' tmpl/public/index.html || { echo "template import ownership" >&2; exit 1; }
grep -Fq 'decoy' tmpl/public/index.html && { echo "template decoy captured" >&2; exit 1; } || true

printf 'PASS v4.6 import ownership\n'
