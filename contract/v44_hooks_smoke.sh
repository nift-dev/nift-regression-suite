#!/usr/bin/env bash
# Independent black-box contract for v4.4 build hooks: project hooks in
# .nift/config.json and per-file hooks in .nift/tracked.json run as native
# Nift scripts with the lifecycle project-pre -> affected-file-pre/render/post
# -> project-post, additive generic + mode-specific matching, incremental
# behaviour and failure propagation.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/.nift" "$t/content" "$t/templates" "$t/public" "$t/scripts"
cat > "$t/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/main.html","pre build":"scripts/pre.f","post build":"scripts/post.f","pre build -all":"scripts/preall.f","post build -all":"scripts/postall.f"}}
JSON
cat > "$t/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Home","template":"templates/main.html"},{"name":"about","title":"About","template":"templates/main.html","post build":"scripts/filepost.f"}]}
JSON
printf 'home\n' > "$t/content/index.html"
printf 'about\n' > "$t/content/about.html"
printf '<div>@content</div>\n' > "$t/templates/main.html"
printf 'print("PRE=" + getenv("NIFT_HOOK_MODE"))\n' > "$t/scripts/pre.f"
printf 'print("POST")\n' > "$t/scripts/post.f"
printf 'print("PREALL")\n' > "$t/scripts/preall.f"
printf 'print("POSTALL")\n' > "$t/scripts/postall.f"
printf 'print("FILEPOST=" + getenv("NIFT_HOOK_TARGET"))\n' > "$t/scripts/filepost.f"

out=$(cd "$t" && "$NIFT_BIN" build --all 2>&1)
grep -q '^PRE=all$' <<<"$out"
grep -q '^PREALL$' <<<"$out"
grep -q '^FILEPOST=about$' <<<"$out"
grep -q '^POST$' <<<"$out"
grep -q '^POSTALL$' <<<"$out"
out2=$(cd "$t" && "$NIFT_BIN" build 2>&1)
grep -q '^PRE=updated$' <<<"$out2"
grep -q '^POST$' <<<"$out2"
! grep -q '^PREALL$\|^POSTALL$\|^FILEPOST=' <<<"$out2"
# A failing project pre hook aborts the build before any render.
printf '{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/main.html","pre build":"scripts/bad.f"}}\n' > "$t/.nift/config.json"
printf 'undefined_function_xyz()\n' > "$t/scripts/bad.f"
bad=$(cd "$t" && "$NIFT_BIN" build --all 2>&1 || true)
if grep -q 'built successfully' <<<"$bad"; then exit 1; fi
grep -q 'build hook .* failed' <<<"$bad"
printf 'PASS v4.4 hooks\n'