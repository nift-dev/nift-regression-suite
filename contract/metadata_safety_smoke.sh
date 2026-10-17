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
# project must stop satisfying the project-local @path invariant.
P="$TMP/retarget"; mkproj "$P"
printf 'inside\n' >"$P/public/assets/inside.txt"
printf 'outside\n' >"$TMP/outside-target.txt"
ln -s "inside.txt" "$P/public/assets/link.txt"
printf '<a href="@path('"'"'public/assets/link.txt'"'"')">x</a>\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
rm "$P/public/assets/link.txt"
ln -s "$TMP/outside-target.txt" "$P/public/assets/link.txt"
# D-002 (Nift Runtime 2.0): the @path invariant is retained; the status reason
# is now "required output path now resolves outside the project" (previously
# "page build metadata has an invalid requirement") and the rebuild fails with
# the @path containment error.
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'required output path now resolves outside the project: public/assets/link.txt' "$P/status.log"
if (cd "$P" && "$NIFT_BIN" build >rebuild.log 2>&1); then
  echo "retargeted @path requirement unexpectedly rebuilt" >&2; exit 1
fi
grep -Fq '@path path must stay inside the Nift project' "$P/rebuild.log"


# The optimized metadata containment cache is parent-directory based. Retargeting
# a directory symlink outside the project between invocations must still be
# rejected, not just retargeting the final leaf symlink.
P="$TMP/retarget-parent"; mkproj "$P"
mkdir -p "$P/public/inside-dir" "$TMP/outside-dir"
printf 'inside\n' >"$P/public/inside-dir/file.txt"
printf 'outside\n' >"$TMP/outside-dir/file.txt"
ln -s "inside-dir" "$P/public/linkdir"
printf '<a href="@path('"'"'public/linkdir/file.txt'"'"')">x</a>\n' >"$P/content/index.html"
(cd "$P" && "$NIFT_BIN" build --all >/dev/null)
rm "$P/public/linkdir"
ln -s "$TMP/outside-dir" "$P/public/linkdir"
# D-002 (Nift Runtime 2.0): new status reason, same @path rebuild failure.
(cd "$P" && "$NIFT_BIN" status >status.log)
grep -Fq 'required output path now resolves outside the project: public/linkdir/file.txt' "$P/status.log"
if (cd "$P" && "$NIFT_BIN" build >rebuild.log 2>&1); then
  echo "retargeted @path parent requirement unexpectedly rebuilt" >&2; exit 1
fi
grep -Fq '@path path must stay inside the Nift project' "$P/rebuild.log"

echo "Metadata safety smoke test passed"
