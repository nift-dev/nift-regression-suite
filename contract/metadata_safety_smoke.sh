#!/usr/bin/env bash
set -euo pipefail
NIFT_BIN="${NIFT_BIN:-$(pwd)/nift}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-meta-safety.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkproj(){
  local d="$1"
  mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public/assets" "$d/data"
  cat >"$d/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
  cat >"$d/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Home","template":"templates/template.html"}]}
JSON
  printf '@content\n' >"$d/templates/template.html"
}

# D-002 (Nift Runtime 2.0): page-info dependency/requirement paths outside the
# project are no longer "invalid"; status evaluates them like any other path.
# (Previously: "invalid dependency" / "invalid requirement".) The project is
# nested one level so "../../" resolves inside this test's temp dir.
P="$TMP/corrupt/project"; mkproj "$P"
printf '<p>ok</p>\n' >"$P/content/index.html"
printf 'secret\n' >"$TMP/outside-secret.txt"
printf 'required\n' >"$TMP/outside-required.txt"
sleep 1
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
chmod u+w "$P/.nift/public/index.info.json"
python3 -S - "$P/.nift/public/index.info.json" <<'PY2'
import json,sys
p=sys.argv[1]; d=json.load(open(p))
d["dependencies"]=["../../outside-secret.txt"]
d["reqs"]=["../../outside-required.txt"]
json.dump(d,open(p,"w"))
PY2
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'up to date' "$P/status.log"
if grep -Fq 'invalid' "$P/status.log"; then echo "external page-info path reported invalid" >&2; exit 1; fi
sleep 1
printf 'secret edited\n' >"$TMP/outside-secret.txt"
rm "$TMP/outside-required.txt"
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'dependency changed: ../../outside-secret.txt' "$P/status.log"
grep -Fq 'required path missing: ../../outside-required.txt' "$P/status.log"
if grep -Fq 'invalid' "$P/status.log"; then echo "external page-info path reported invalid" >&2; exit 1; fi

# A req symlink that was safe at build time but is later retargeted outside the
# project is permitted by default; explicit root still rejects it.
P="$TMP/retarget"; mkproj "$P"
printf 'inside\n' >"$P/public/assets/inside.txt"
printf 'outside\n' >"$TMP/outside-target.txt"
ln -s "inside.txt" "$P/public/assets/link.txt"
printf '<a href="@path('"'"'public/assets/link.txt'"'"')">x</a>\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
rm "$P/public/assets/link.txt"
ln -s "$TMP/outside-target.txt" "$P/public/assets/link.txt"
# Unrestricted cached requirements remain valid after retargeting.
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'up to date' "$P/status.log"
(cd "$P" && "$NIFT_BIN" build >rebuild.log 2>&1)
# Enabling explicit restriction must revalidate that same cached requirement.
if (cd "$P" && NIFT_FS_ROOT="$P" "$NIFT_BIN" build >restricted.log 2>&1); then
  echo 'explicit-root cached retarget unexpectedly succeeded: public/assets/link.txt' >&2; exit 1
fi
grep -Fq 'path escapes configured filesystem root' "$P/restricted.log"
if (cd "$P" && NIFT_FS_ROOT="$P" "$NIFT_BIN" build --all >forced.log 2>&1); then
  echo 'explicit-root forced retarget unexpectedly succeeded: public/assets/link.txt' >&2; exit 1
fi
grep -Fq 'path escapes configured filesystem root' "$P/forced.log"


# The optimized metadata containment cache is parent-directory based. Retargeting
# a directory symlink outside the project between invocations must still be
# permitted by default and rejected with explicit root, like the leaf case.
P="$TMP/retarget-parent"; mkproj "$P"
mkdir -p "$P/public/inside-dir" "$TMP/outside-dir"
printf 'inside\n' >"$P/public/inside-dir/file.txt"
printf 'outside\n' >"$TMP/outside-dir/file.txt"
ln -s "inside-dir" "$P/public/linkdir"
printf '<a href="@path('"'"'public/linkdir/file.txt'"'"')">x</a>\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
rm "$P/public/linkdir"
ln -s "$TMP/outside-dir" "$P/public/linkdir"
# Unrestricted cached requirements remain valid after retargeting.
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'up to date' "$P/status.log"
(cd "$P" && "$NIFT_BIN" build >rebuild.log 2>&1)
# Enabling explicit restriction must revalidate that same cached requirement.
if (cd "$P" && NIFT_FS_ROOT="$P" "$NIFT_BIN" build >restricted.log 2>&1); then
  echo 'explicit-root cached retarget unexpectedly succeeded: public/linkdir/file.txt' >&2; exit 1
fi
grep -Fq 'path escapes configured filesystem root' "$P/restricted.log"
if (cd "$P" && NIFT_FS_ROOT="$P" "$NIFT_BIN" build --all >forced.log 2>&1); then
  echo 'explicit-root forced retarget unexpectedly succeeded: public/linkdir/file.txt' >&2; exit 1
fi
grep -Fq 'path escapes configured filesystem root' "$P/forced.log"

echo "Metadata safety smoke test passed"
