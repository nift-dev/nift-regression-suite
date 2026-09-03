#!/usr/bin/env bash
set -u
NIFT_BIN="${NIFT_BIN:?set NIFT_BIN}"
FAILS_BEFORE=${FAILS:-0}; TESTS_BEFORE=${TESTS:-0}
FAILS=${FAILS:-0}; TESTS=${TESTS:-0}
TMP_ROOT=$(mktemp -d /tmp/nift-new-regression.XXXXXX)
fail(){ printf 'FAIL [%03d] %s\n' "$TESTS" "$*" >&2; FAILS=$((FAILS+1)); }
check(){ TESTS=$((TESTS+1)); "$@"; }
contains(){ grep -Fq -- "$2" "$1" || fail "$3"; }
not_contains(){ if grep -Fq -- "$2" "$1"; then fail "$3"; fi; }
exists(){ [[ -e "$1" ]] || fail "$2"; }
not_exists(){ [[ ! -e "$1" ]] || fail "$2"; }
nonzero(){ local label="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?; [[ $rc -ne 0 ]] || fail "$label"; }
zero(){ local label="$1"; shift; "$@" >/dev/null 2>&1; local rc=$?; [[ $rc -eq 0 ]] || fail "$label (rc=$rc)"; }
same_second_newer(){
 local dependency="$1" info="$2" sec
 sec=$(date +%s)
 touch -d "@${sec}.100000000" "$info"
 touch -d "@${sec}.200000000" "$dependency"
}
mkproj(){
 local d="$1" mode="${2:-modified}" threads="${3:-2}"; mkdir -p "$d/.nift" "$d/content" "$d/templates" "$d/public"
 cat >"$d/.nift/config.json" <<JSON
{"config":{"content-dir":"content/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":$threads,"incremental-mode":"$mode"}}
JSON
 cat >"$d/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"Index","template":"templates/template.html"}]}
JSON
 printf 'ROOT-CONTENT\n' >"$d/content/index.html"; printf '@content\n' >"$d/templates/template.html"
}

# -----------------------------------------------------------------------------
# Project config / tracking structural invariants
# -----------------------------------------------------------------------------
P="$TMP_ROOT/cfg-content-empty"; mkproj "$P"; sed -i 's#"content-dir":"content/"#"content-dir":""#' "$P/.nift/config.json"; check nonzero 'empty content-dir accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/cfg-cext"; mkproj "$P"; sed -i 's/"content-ext":".html"/"content-ext":"html"/' "$P/.nift/config.json"; check nonzero 'content-ext without dot accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/cfg-oext"; mkproj "$P"; sed -i 's/"output-ext":".html"/"output-ext":"html"/' "$P/.nift/config.json"; check nonzero 'output-ext without dot accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/cfg-extslash"; mkproj "$P"; sed -i 's/"content-ext":".html"/"content-ext":".x\/y"/' "$P/.nift/config.json"; check nonzero 'content-ext containing path separator accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/cfg-frac"; mkproj "$P"; sed -i 's/"build-threads":2/"build-threads":1.5/' "$P/.nift/config.json"; check nonzero 'fractional build-threads accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/cfg-dupekey"; mkproj "$P"; cat >"$P/.nift/config.json" <<'JSON'
{"config":{"content-dir":"content/","content-dir":"other/","content-ext":".html","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":1,"incremental-mode":"modified"}}
JSON
check nonzero 'duplicate config object key accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"

P="$TMP_ROOT/tracked-dupename"; mkproj "$P"; cat >"$P/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"A","template":"templates/template.html"},{"name":"/","title":"B","template":"templates/template.html"}]}
JSON
check nonzero 'duplicate tracked name accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-rootindex"; mkproj "$P"; cat >"$P/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"/","title":"A","template":"templates/template.html"},{"name":"index","title":"B","template":"templates/template.html"}]}
JSON
check nonzero 'distinct names resolving to same root/index paths accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-folderindex"; mkproj "$P"; cat >"$P/.nift/tracked.json" <<'JSON'
{"tracked":[{"name":"foo/","title":"A","template":"templates/template.html"},{"name":"foo/index","title":"B","template":"templates/template.html"}]}
JSON
check nonzero 'folder/index derived path collision accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-parent"; mkproj "$P"; sed -i 's#"name":"/"#"name":"../escape"#' "$P/.nift/tracked.json"; check nonzero 'tracked.json parent traversal accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-absolute"; mkproj "$P"; python3 -S - "$P/.nift/tracked.json" "$TMP_ROOT/absolute-name" <<'PY'
import json,sys
p,name=sys.argv[1:]; d=json.load(open(p)); d['tracked'][0]['name']=name; json.dump(d,open(p,'w'))
PY
check nonzero 'tracked.json absolute name accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-badext"; mkproj "$P"; python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['tracked'][0]['output-ext']='html'; json.dump(d,open(p,'w'))
PY
check nonzero 'tracked output extension without dot accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-template-content"; mkproj "$P"; python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['tracked'][0]['template']='content/index.html'; json.dump(d,open(p,'w'))
PY
check nonzero 'template path equal to tracked content accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-template-output"; mkproj "$P"; printf 'TEMPLATE\n' >"$P/public/index.html"; python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['tracked'][0]['template']='public/index.html'; json.dump(d,open(p,'w'))
PY
check nonzero 'template path equal to generated output accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"
P="$TMP_ROOT/tracked-dup-root-key"; mkproj "$P"; printf '%s\n' '{"tracked":[],"tracked":[]}' >"$P/.nift/tracked.json"; check nonzero 'duplicate tracked root JSON key accepted' bash -c "cd '$P' && '$NIFT_BIN' info --all"

# -----------------------------------------------------------------------------
# CLI strictness, collisions and non-destructive mutations
# -----------------------------------------------------------------------------
P="$TMP_ROOT/cli"; mkproj "$P"
check nonzero 'build --all ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' build --all stray"
check nonzero 'build ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' build stray"
check nonzero 'status ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' status stray"
check nonzero 'info --all ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' info --all stray"
check nonzero 'info --names ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' info --names stray"
check nonzero 'info --tracking ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' info --tracking stray"
check nonzero 'info --watching ignored stray positional argument' bash -c "cd '$P' && '$NIFT_BIN' info --watching stray"
check nonzero 'build --auto ignored stray positional argument' bash -c "cd '$P' && timeout 2 '$NIFT_BIN' build --auto stray"
check nonzero 'cp accepted an extra positional argument' bash -c "cd '$P' && '$NIFT_BIN' cp / copy extra"
check nonzero 'mv accepted an extra positional argument' bash -c "cd '$P' && '$NIFT_BIN' mv / moved extra"
check nonzero 'track accepted an extra positional argument' bash -c "cd '$P' && '$NIFT_BIN' track extra title templates/template.html ignored"
mkdir -p "$P/content/watch"; check nonzero 'watch accepted an extra positional argument' bash -c "cd '$P' && '$NIFT_BIN' watch content/watch/ .html templates/template.html .html ignored"
check nonzero 'unwatch accepted an extra positional argument' bash -c "cd '$P' && '$NIFT_BIN' unwatch content/watch/ ignored"
P="$TMP_ROOT/init-nodot"; mkdir -p "$P"; check nonzero 'init accepted extension without leading dot' bash -c "cd '$P' && '$NIFT_BIN' init html"
P="$TMP_ROOT/init-path"; mkdir -p "$P"; check nonzero 'init accepted extension containing path separators' bash -c "cd '$P' && '$NIFT_BIN' init '.html/../../x'"

P="$TMP_ROOT/absolute-track"; mkproj "$P"; ABS="$TMP_ROOT/absolute-output"; check nonzero 'track accepted absolute tracked name' bash -c "cd '$P' && '$NIFT_BIN' track '$ABS' title templates/template.html"
P="$TMP_ROOT/absolute-cp"; mkproj "$P"; check nonzero 'cp accepted absolute destination name' bash -c "cd '$P' && '$NIFT_BIN' cp / '$TMP_ROOT/absolute-copy'"
P="$TMP_ROOT/absolute-mv"; mkproj "$P"; check nonzero 'mv accepted absolute destination name' bash -c "cd '$P' && '$NIFT_BIN' mv / '$TMP_ROOT/absolute-move'"
P="$TMP_ROOT/watch-outside"; mkproj "$P"; mkdir -p "$P/templates/w"; check nonzero 'watch accepted directory outside configured content tree' bash -c "cd '$P' && '$NIFT_BIN' watch templates/w/"
P="$TMP_ROOT/watch-absolute"; mkproj "$P"; mkdir -p "$TMP_ROOT/external-watch"; check nonzero 'watch accepted absolute directory' bash -c "cd '$P' && '$NIFT_BIN' watch '$TMP_ROOT/external-watch'"

P="$TMP_ROOT/track-collision"; mkproj "$P"; BEFORE=$(cat "$P/content/index.html"); check nonzero 'track index accepted despite colliding with root page paths' bash -c "cd '$P' && '$NIFT_BIN' track index"; AFTER=$(cat "$P/content/index.html"); TESTS=$((TESTS+1)); [[ "$AFTER" == "$BEFORE" ]] || fail 'rejected track path collision still modified existing root content'
P="$TMP_ROOT/track-existing"; mkproj "$P"; printf 'KEEP-ME' >"$P/content/existing.html"; check zero 'track failed for pre-existing untracked content file' bash -c "cd '$P' && '$NIFT_BIN' track existing"; check contains "$P/content/existing.html" 'KEEP-ME' 'track truncated pre-existing content file'
P="$TMP_ROOT/build-duplicate"; mkproj "$P"; check nonzero 'duplicate target names scheduled same page more than once' bash -c "cd '$P' && '$NIFT_BIN' build / /"
P="$TMP_ROOT/build-mixed"; mkproj "$P"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); printf CHANGED >"$P/content/index.html"; TESTS=$((TESTS+1)); (cd "$P" && "$NIFT_BIN" build / missing >/dev/null 2>&1); rc=$?; [[ $rc -ne 0 ]] || fail 'mixed tracked/untracked targeted build returned success'; check contains "$P/public/index.html" 'CHANGED' 'mixed targeted build failed to build valid requested page'

P="$TMP_ROOT/cp-existing"; mkproj "$P"; printf 'DO-NOT-OVERWRITE' >"$P/content/dest.html"; check nonzero 'cp overwrote pre-existing untracked destination content' bash -c "cd '$P' && '$NIFT_BIN' cp / dest"; check contains "$P/content/dest.html" 'DO-NOT-OVERWRITE' 'cp rejection still modified destination content'
P="$TMP_ROOT/mv-existing"; mkproj "$P"; printf 'DO-NOT-OVERWRITE' >"$P/content/dest.html"; check nonzero 'mv overwrote pre-existing untracked destination content' bash -c "cd '$P' && '$NIFT_BIN' mv / dest"; check contains "$P/content/dest.html" 'DO-NOT-OVERWRITE' 'mv rejection still modified destination content'; check exists "$P/content/index.html" 'rejected mv removed source content'

# Sidecars travel with page lifecycle operations.
P="$TMP_ROOT/cp-sidecar"; mkproj "$P"; mkdir -p "$P/data"; printf D >"$P/data/d.txt"; printf '%s\n' '{"dependencies":["data/d.txt"]}' >"$P/content/index.deps.json"; check zero 'cp with sidecar failed' bash -c "cd '$P' && '$NIFT_BIN' cp / copied"; check exists "$P/content/copied.deps.json" 'cp did not copy *.deps.json sidecar'; TESTS=$((TESTS+1)); cmp -s "$P/content/index.deps.json" "$P/content/copied.deps.json" || fail 'copied sidecar contents differ from source sidecar'
P="$TMP_ROOT/mv-sidecar"; mkproj "$P"; mkdir -p "$P/data"; printf D >"$P/data/d.txt"; printf '%s\n' '{"dependencies":["data/d.txt"]}' >"$P/content/index.deps.json"; check zero 'mv with sidecar failed' bash -c "cd '$P' && '$NIFT_BIN' mv / moved"; check exists "$P/content/moved.deps.json" 'mv did not move *.deps.json sidecar'; check not_exists "$P/content/index.deps.json" 'mv left old *.deps.json sidecar behind'
P="$TMP_ROOT/rm-state"; mkproj "$P"; mkdir -p "$P/data"; printf D >"$P/data/d.txt"; printf '%s\n' '{"dependencies":["data/d.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check exists "$P/.nift/public/index.info.json" 'rm state test failed to create page info baseline'; check zero 'rm failed' bash -c "cd '$P' && '$NIFT_BIN' rm /"; check not_exists "$P/content/index.deps.json" 'rm left *.deps.json sidecar behind'; check not_exists "$P/.nift/public/index.info.json" 'rm left stale page info behind'
P="$TMP_ROOT/mv-state"; mkproj "$P"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check zero 'mv state cleanup command failed' bash -c "cd '$P' && '$NIFT_BIN' mv / moved"; check not_exists "$P/.nift/public/index.info.json" 'mv left stale source page info behind'

# -----------------------------------------------------------------------------
# User dependency sidecar lifecycle / path safety
# -----------------------------------------------------------------------------
P="$TMP_ROOT/sidecar-add"; mkproj "$P"; mkdir -p "$P/data"; printf A >"$P/data/a.txt"; touch -d '2000-01-01' "$P/data/a.txt"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); BEFORE=$(stat -c %Y "$P/public/index.html"); sleep 0.02; printf '%s\n' '{"dependencies":["data/a.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); AFTER=$(stat -c %Y "$P/public/index.html"); TESTS=$((TESTS+1)); [[ "$AFTER" -ge "$BEFORE" && -f "$P/.nift/public/index.info.json" ]] || fail 'adding *.deps.json broke incremental build'; check contains "$P/.nift/public/index.info.json" 'content/index.deps.json' 'sidecar file itself not recorded as dependency'; check contains "$P/log" 'dependency changed: content/index.deps.json' 'adding sidecar did not explain metadata dependency change'
P="$TMP_ROOT/sidecar-edit"; mkproj "$P"; mkdir -p "$P/data"; printf A >"$P/data/a.txt"; printf B >"$P/data/b.txt"; touch -d '2000-01-01' "$P/data/a.txt" "$P/data/b.txt"; printf '%s\n' '{"dependencies":["data/a.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); sleep 0.02; printf '%s\n' '{"dependencies":["data/b.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/.nift/public/index.info.json" 'data/b.txt' 'edited sidecar dependency list not written to page metadata'; check not_contains "$P/.nift/public/index.info.json" 'data/a.txt' 'removed sidecar dependency remained in regenerated page metadata'
P="$TMP_ROOT/sidecar-remove"; mkproj "$P"; mkdir -p "$P/data"; printf A >"$P/data/a.txt"; printf '%s\n' '{"dependencies":["data/a.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); rm "$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check not_contains "$P/.nift/public/index.info.json" 'data/a.txt' 'removed sidecar dependency remained after rebuild'; check contains "$P/log" 'dependency removed: content/index.deps.json' 'removed sidecar did not explain rebuild reason'
P="$TMP_ROOT/sidecar-parent"; mkproj "$P"; printf OUT >"$TMP_ROOT/outside.txt"; printf '%s\n' '{"dependencies":["../outside.txt"]}' >"$P/content/index.deps.json"; check nonzero 'sidecar accepted parent traversal dependency' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/sidecar-absolute"; mkproj "$P"; printf OUT >"$TMP_ROOT/absolute.txt"; python3 -S - "$P/content/index.deps.json" "$TMP_ROOT/absolute.txt" <<'PY'
import json,sys
json.dump({'dependencies':[sys.argv[2]]},open(sys.argv[1],'w'))
PY
check nonzero 'sidecar accepted absolute dependency path' bash -c "cd '$P' && '$NIFT_BIN' build --all"

# Sidecar content itself participates in hash/hybrid modes with preserved mtime.
for MODE in hash hybrid; do
 P="$TMP_ROOT/sidecar-hash-$MODE"; mkproj "$P" "$MODE"; mkdir -p "$P/data"; printf A >"$P/data/a.txt"; printf B >"$P/data/b.txt"; printf '%s\n' '{"dependencies":["data/a.txt"]}' >"$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); cp -p "$P/content/index.deps.json" "$P/stamp"; printf '%s\n' '{"dependencies":["data/b.txt"]}' >"$P/content/index.deps.json"; touch -r "$P/stamp" "$P/content/index.deps.json"; (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); check contains "$P/.nift/public/index.info.json" 'data/b.txt' "$MODE mode missed sidecar content change with preserved mtime"
done

# -----------------------------------------------------------------------------
# Incremental precision, tracking metadata and hash robustness
# -----------------------------------------------------------------------------
P="$TMP_ROOT/rapid-content"; mkproj "$P"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); printf RAPID-CONTENT >"$P/content/index.html"; same_second_newer "$P/content/index.html" "$P/.nift/public/index.info.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/public/index.html" 'RAPID-CONTENT' 'modified mode missed content edit within same second'; check contains "$P/log" 'dependency changed: content/index.html' 'rapid content edit missing rebuild reason'
P="$TMP_ROOT/rapid-template"; mkproj "$P"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); printf 'RAPID-TEMPLATE\n@content\n' >"$P/templates/template.html"; same_second_newer "$P/templates/template.html" "$P/.nift/public/index.info.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/public/index.html" 'RAPID-TEMPLATE' 'modified mode missed template edit within same second'; check contains "$P/log" 'dependency changed: templates/template.html' 'rapid template edit missing rebuild reason'
P="$TMP_ROOT/rapid-dep"; mkproj "$P"; printf D1 >"$P/data.txt"; printf '@dep("data.txt")\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); printf D2 >"$P/data.txt"; same_second_newer "$P/data.txt" "$P/.nift/public/index.info.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/log" 'dependency changed: data.txt' 'modified mode missed explicit dependency edit within same second'
P="$TMP_ROOT/rapid-json"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"value":"ONE"}' >"$P/data/state.json"; printf '@json("data/state.json", state)\n$[state.value]\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); printf '%s\n' '{"value":"TWO"}' >"$P/data/state.json"; same_second_newer "$P/data/state.json" "$P/.nift/public/index.info.json"; (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); check contains "$P/public/index.html" 'TWO' 'modified mode missed @json edit within same second'

P="$TMP_ROOT/title-change"; mkproj "$P"; printf 'TITLE=$[title]\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['tracked'][0]['title']='Changed title'; json.dump(d,open(p,'w'))
PY
(cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/public/index.html" 'TITLE=Changed title' 'tracked title edit did not rebuild output'; check contains "$P/log" 'tracked title changed' 'tracked title edit missing rebuild reason'
P="$TMP_ROOT/template-change"; mkproj "$P"; printf 'OLD\n@content\n' >"$P/templates/template.html"; printf 'NEW\n@content\n' >"$P/templates/other.html"; touch -d '2000-01-01' "$P/templates/other.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['tracked'][0]['template']='templates/other.html'; json.dump(d,open(p,'w'))
PY
(cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/public/index.html" 'NEW' 'tracked template edit did not rebuild output'; check contains "$P/log" 'tracked template changed' 'tracked template edit missing rebuild reason'
P="$TMP_ROOT/contentdir-change"; mkproj "$P"; mkdir -p "$P/newcontent"; printf NEW-CONTENT-DIR >"$P/newcontent/index.html"; touch -d '2000-01-01' "$P/newcontent/index.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); sed -i 's#"content-dir":"content/"#"content-dir":"newcontent/"#' "$P/.nift/config.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/public/index.html" 'NEW-CONTENT-DIR' 'content-dir config change did not rebuild from new source'; check contains "$P/log" 'tracked content path changed' 'content-dir change missing tracking-path rebuild reason'
P="$TMP_ROOT/old-page-info"; mkproj "$P"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); chmod 644 "$P/.nift/public/index.info.json"; python3 -S - "$P/.nift/public/index.info.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d.pop('content',None); d.pop('output',None); json.dump(d,open(p,'w'))
PY
chmod 444 "$P/.nift/public/index.info.json"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/log" 'older metadata format' 'old page metadata format did not force rebuild'

# Known collision pair for the former 32-bit FNV-1a hash.
P="$TMP_ROOT/hash-collision"; mkproj "$P" hash; printf '@content' >"$P/templates/template.html"; python3 -S - "$P/content/index.html" <<'PY'
import sys; open(sys.argv[1],'wb').write(bytes.fromhex('5dec0c861459bc04'))
PY
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); cp -p "$P/content/index.html" "$P/stamp"; python3 -S - "$P/content/index.html" <<'PY'
import sys; open(sys.argv[1],'wb').write(bytes.fromhex('5616c0842221a4ef'))
PY
touch -r "$P/stamp" "$P/content/index.html"; (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); TESTS=$((TESTS+1)); python3 -S - "$P/public/index.html" <<'PY' || fail 'hash mode missed deliberately constructed former 32-bit FNV collision'
import sys
raise SystemExit(0 if open(sys.argv[1],'rb').read().hex()=='5616c0842221a4ef' else 1)
PY
# Corrupt stored hash with valid numeric prefix + garbage; it must be treated as invalid/changed.
P="$TMP_ROOT/hash-state-junk"; mkproj "$P" hash; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); H="$P/.nift/content/index.html.hash"; V=$(tr -d '\r\n' <"$H"); printf '%sjunk\n' "$V" >"$H"; (cd "$P" && "$NIFT_BIN" build >log 2>&1); check contains "$P/log" 'dependency changed: content/index.html' 'stored hash with trailing garbage was accepted as valid'

# -----------------------------------------------------------------------------
# JSON parser / template data edge cases
# -----------------------------------------------------------------------------
json_fail(){ local name="$1" source="$2"; local d="$TMP_ROOT/json-$name"; mkproj "$d"; mkdir -p "$d/data"; printf '%s' "$source" >"$d/data/test.json"; printf '@json("data/test.json", data)\n$[data]\n@content\n' >"$d/templates/template.html"; check nonzero "$name JSON unexpectedly accepted" bash -c "cd '$d' && '$NIFT_BIN' build --all"; }
json_fail duplicate-key '{"x":1,"x":2}'
json_fail number-leading-zero '01'
json_fail number-negative-leading-zero '-01'
json_fail number-fraction '1.'
json_fail number-exponent '1e'
json_fail number-exponent-sign '1e+'
json_fail number-overflow '1e309'
json_fail invalid-escape '"\x"'
json_fail low-surrogate '"\uDE00"'
json_fail high-surrogate-alone '"\uD83D"'
json_fail invalid-surrogate-pair '"\uD83D\u0041"'
json_fail trailing-array-comma '[1,]'
json_fail trailing-object-comma '{"x":1,}'

P="$TMP_ROOT/json-unicode"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"emoji":"\uD83D\uDE00","escaped":"line\nnext"}' >"$P/data/test.json"; printf '@json("data/test.json", data)\n$[data.emoji]\n$[data.escaped]\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check contains "$P/public/index.html" '😀' 'valid JSON surrogate pair did not decode to UTF-8'; TESTS=$((TESTS+1)); python3 -S - "$P/public/index.html" <<'PY' || fail 'valid JSON newline escape did not decode'
import sys
raise SystemExit(0 if 'line\nnext' in open(sys.argv[1],encoding='utf-8').read() else 1)
PY

# -----------------------------------------------------------------------------
# Control-flow scope / condition grammar
# -----------------------------------------------------------------------------
# Multiline @for/@if bodies use their source indentation only for readability.
# Rendered content aligns to the directive insertion point, like @input.
P="$TMP_ROOT/control-indent"; mkproj "$P"; mkdir -p "$P/data" "$P/templates/partials"; printf '%s\n' '{"enabled":true,"disabled":false,"items":[{"name":"one","show":true},{"name":"two","show":false}]}' >"$P/data/site.json"; printf 'PARTIAL-ONE\nPARTIAL-TWO\n' >"$P/templates/partials/two-lines.html"; cat >"$P/templates/template.html" <<'EOF'
@json("data/site.json", site)
<div class="for-block">
    @for(item : site.items) {
        <p>FOR=$[item.name]</p>
    }
</div>
<section>
    @if(site.enabled) {
        <h2>IF-TRUE</h2>
    }
</section>
<section>
    @if(site.disabled) {
        <h2>BAD</h2>
    } else {
        <h2>ELSE-TRUE</h2>
    }
</section>
<main>
    @for(item : site.items) {
        <article>
            @if(item.show) {
                <span>NESTED=$[item.name]</span>
            }
        </article>
    }
</main>
<div>
    @for(item : site.items) {
        <div>
            <span>RELATIVE=$[item.name]</span>
        </div>
    }
</div>
<div>
    @for(item : site.items) {
        @input("templates/partials/two-lines.html")
    }
</div>
<div class="inline-for">@for(item : site.items) {
    <b>$[item.name]</b>
}</div>
<div class="inline-if">@if(site.enabled) {
    <i>INLINE-IF</i>
}</div>
@content
EOF
check zero 'control-flow indentation fixture did not build' bash -c "cd '$P' && '$NIFT_BIN' build --all"
check bash -c "grep -Eq '^    <p>FOR=one</p>$' '$P/public/index.html'" || fail '@for body did not align to directive indentation'
check bash -c "grep -Eq '^    <p>FOR=two</p>$' '$P/public/index.html'" || fail '@for repeated body did not retain directive indentation'
check bash -c "! grep -Fq '        <p>FOR=one</p>' '$P/public/index.html'" || fail '@for preserved structural source indentation'
check bash -c "grep -Eq '^    <h2>IF-TRUE</h2>$' '$P/public/index.html'" || fail '@if body did not align to directive indentation'
check bash -c "grep -Eq '^    <h2>ELSE-TRUE</h2>$' '$P/public/index.html'" || fail '@if else body did not align to directive indentation'
check bash -c "grep -Eq '^    <article>$' '$P/public/index.html'" || fail 'nested @for outer body indentation wrong'
check bash -c "grep -Eq '^        <span>NESTED=one</span>$' '$P/public/index.html'" || fail 'nested @if indentation did not compose'
check bash -c "grep -Eq '^        <span>RELATIVE=one</span>$' '$P/public/index.html'" || fail '@for relative body indentation was not preserved'
check bash -c "grep -Eq '^    PARTIAL-ONE$' '$P/public/index.html'" || fail '@input inside @for first line indentation wrong'
check bash -c "grep -Eq '^    PARTIAL-TWO$' '$P/public/index.html'" || fail '@input inside @for continuation indentation wrong'
check bash -c "grep -Eq '^ {24}<b>two</b></div>$' '$P/public/index.html'" || fail 'inline @for repeated line did not align to insertion column'
check contains "$P/public/index.html" '<div class="inline-for"><b>one</b>' 'inline @for first body did not begin at insertion point'
check contains "$P/public/index.html" '<div class="inline-if"><i>INLINE-IF</i></div>' 'inline @if body did not begin at insertion point'

P="$TMP_ROOT/control-scope"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"items":[1,2],"text":"a==b","neg":-3.5}' >"$P/data/list.json"; printf '%s\n' '{"x":"LOCAL"}' >"$P/data/local.json"; cat >"$P/templates/template.html" <<'NIFT'
@json("data/list.json", list)
@for(item : list.items){@json("data/local.json", local)LOOP=$[item]-$[local.x]
}
@if(true){@json("data/local.json", branch)BRANCH=$[branch.x]
}
AFTER=$[branch]
@if(list.text == "a==b"){OP-IN-STRING
}
@if(list.neg == -3.5){NEGATIVE-NUMBER
}
@if(list.items[0] < list.items[1]){ORDER-LT
}
@if(list.items[0] <= 1){ORDER-LE-EQ
}
@if(list.items[1] > list.items[0]){ORDER-GT
}
@if(list.items[1] >= 2){ORDER-GE-EQ
}
@if(list.neg < 0){ORDER-NEGATIVE
}
@if("alpha" < "beta"){ORDER-STRING-LT
}
@if("beta" >= "beta"){ORDER-STRING-GE-EQ
}
@if("a<b" == "a<b"){ORDER-QUOTED-LT
}
@if("a>=b" == "a>=b"){ORDER-QUOTED-GE
}
@if("literal"){LITERAL-TRUTHY
}
@if(!0){ZERO-FALSEY
}
@content
NIFT
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check contains "$P/public/index.html" 'LOOP=1-LOCAL' '@json inside first loop iteration failed'; check contains "$P/public/index.html" 'LOOP=2-LOCAL' '@json binding leaked and broke second loop iteration'; check contains "$P/public/index.html" 'BRANCH=LOCAL' '@json inside selected if block unavailable'; check contains "$P/public/index.html" 'AFTER=$[branch]' '@json binding declared inside if leaked outside block'; check contains "$P/public/index.html" 'OP-IN-STRING' 'condition parser misread == inside quoted string'; check contains "$P/public/index.html" 'NEGATIVE-NUMBER' 'negative numeric scalar comparison failed'; check contains "$P/public/index.html" 'LITERAL-TRUTHY' 'string literal truthiness failed'; check contains "$P/public/index.html" 'ZERO-FALSEY' 'numeric zero negation truthiness failed'; check contains "$P/public/index.html" 'ORDER-LT' 'numeric < comparison failed'; check contains "$P/public/index.html" 'ORDER-LE-EQ' 'numeric <= equality boundary failed'; check contains "$P/public/index.html" 'ORDER-GT' 'numeric > comparison failed'; check contains "$P/public/index.html" 'ORDER-GE-EQ' 'numeric >= equality boundary failed'; check contains "$P/public/index.html" 'ORDER-NEGATIVE' 'negative numeric ordering failed'; check contains "$P/public/index.html" 'ORDER-STRING-LT' 'string lexicographic < comparison failed'; check contains "$P/public/index.html" 'ORDER-STRING-GE-EQ' 'string lexicographic >= boundary failed'; check contains "$P/public/index.html" 'ORDER-QUOTED-LT' 'condition parser misread < inside quoted string'; check contains "$P/public/index.html" 'ORDER-QUOTED-GE' 'condition parser misread >= inside quoted string'
P="$TMP_ROOT/control-order-mixed"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"n":3}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@if(d.n < "4"){x}\n' >"$P/templates/template.html"; check nonzero 'mixed-type ordering comparison was silently accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/control-order-bool"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"a":true,"b":false}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@if(d.a >= d.b){x}\n' >"$P/templates/template.html"; check nonzero 'boolean ordering comparison was silently accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/control-no-and"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"a":true,"b":true}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@if(d.a && d.b){x}\n' >"$P/templates/template.html"; check nonzero 'unsupported && expression was silently accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/control-no-or"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"a":false,"b":true}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@if(d.a || d.b){x}\n' >"$P/templates/template.html"; check nonzero 'unsupported || expression was silently accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"

# -----------------------------------------------------------------------------
# JSON Schema, loop metadata, and sorted iteration
# -----------------------------------------------------------------------------
P="$TMP_ROOT/schema-valid"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"products":[{"name":"Widget","price":10}]}' >"$P/data/products.json"; cat >"$P/data/products.schema.json" <<'SCHEMA'
{"$schema":"https://json-schema.org/draft/2020-12/schema","$defs":{"product":{"type":"object","required":["name","price"],"properties":{"name":{"type":"string","minLength":1},"price":{"type":"number","minimum":0}},"additionalProperties":false}},"type":"object","required":["products"],"properties":{"products":{"type":"array","items":{"$ref":"#/$defs/product"}}},"additionalProperties":false}
SCHEMA
printf '@json("data/products.json", d, "data/products.schema.json")\n@for(p : d.products){$[loop.index]/$[loop.length]:$[p.name]\n}\n@content\n' >"$P/templates/template.html"; check zero 'valid schema-bound JSON failed to build' bash -c "cd '$P' && '$NIFT_BIN' build --all"; check contains "$P/public/index.html" '1/1:Widget' 'loop metadata unavailable in schema-bound data loop'; check contains "$P/.nift/public/index.info.json" 'data/products.schema.json' 'schema file was not recorded as page dependency'

P="$TMP_ROOT/schema-invalid"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"price":"free"}' >"$P/data/test.json"; printf '%s\n' '{"type":"object","properties":{"price":{"type":"number"}}}' >"$P/data/test.schema.json"; printf '@json("data/test.json", d, "data/test.schema.json")\n' >"$P/templates/template.html"; TESTS=$((TESTS+1)); (cd "$P" && "$NIFT_BIN" build --all >log 2>&1); rc=$?; [[ $rc -ne 0 ]] || fail 'schema type mismatch was accepted'; contains "$P/log" 'at $.price: expected number' 'schema mismatch diagnostic did not identify instance path/type'

P="$TMP_ROOT/schema-required"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{}' >"$P/data/test.json"; printf '%s\n' '{"type":"object","required":["name"]}' >"$P/data/test.schema.json"; printf '@json("data/test.json", d, "data/test.schema.json")\n' >"$P/templates/template.html"; TESTS=$((TESTS+1)); (cd "$P" && "$NIFT_BIN" build --all >log 2>&1); rc=$?; [[ $rc -ne 0 ]] || fail 'schema required member omission was accepted'; contains "$P/log" "required property 'name' is missing" 'required-member schema diagnostic missing'

P="$TMP_ROOT/schema-unsupported"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"email":"a@example.com"}' >"$P/data/test.json"; printf '%s\n' '{"properties":{"email":{"type":"string","format":"email"}}}' >"$P/data/test.schema.json"; printf '@json("data/test.json", d, "data/test.schema.json")\n' >"$P/templates/template.html"; TESTS=$((TESTS+1)); (cd "$P" && "$NIFT_BIN" build --all >log 2>&1); rc=$?; [[ $rc -ne 0 ]] || fail 'unsupported schema keyword was silently ignored'; contains "$P/log" "unsupported JSON Schema keyword 'format'" 'unsupported schema keyword did not produce explicit diagnostic'

P="$TMP_ROOT/schema-incremental"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"price":10}' >"$P/data/test.json"; printf '%s\n' '{"type":"object","properties":{"price":{"type":"number"}}}' >"$P/data/test.schema.json"; printf '@json("data/test.json", d, "data/test.schema.json")\nPRICE=$[d.price]\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); sleep 0.02; printf '%s\n' '{"type":"object","properties":{"price":{"type":"string"}}}' >"$P/data/test.schema.json"; TESTS=$((TESTS+1)); (cd "$P" && "$NIFT_BIN" build >log 2>&1); rc=$?; [[ $rc -ne 0 ]] || fail 'changed schema did not invalidate/revalidate dependent page'; contains "$P/log" 'does not satisfy schema' 'changed schema rebuild did not report validation failure'

P="$TMP_ROOT/loop-sort"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"posts":[{"name":"old","date":"2025","score":1},{"name":"new-a","date":"2026","score":9},{"name":"mid","date":"2025-06","score":5},{"name":"new-b","date":"2026","score":9}],"nums":[10,2,30]}' >"$P/data/test.json"; cat >"$P/templates/template.html" <<'NIFT'
@json("data/test.json", d)
@for(p : d.posts by p.date desc){D=$[loop.index]/$[loop.length]:$[p.name]:$[loop.first]:$[loop.last]|}
@for(p : d.posts by p.score asc){A=$[loop.index0]:$[p.name]|}
@for(n : d.nums by n asc){N=$[n]|}
AFTER=$[loop.index]
@content
NIFT
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check contains "$P/public/index.html" 'D=1/4:new-a:true:false|D=2/4:new-b:false:false|D=3/4:mid:false:false|D=4/4:old:false:true|' 'descending stable string sort / loop metadata failed'; check contains "$P/public/index.html" 'A=0:old|A=1:mid|A=2:new-a|A=3:new-b|' 'ascending numeric sort was not stable'; check contains "$P/public/index.html" 'N=2|N=10|N=30|' 'scalar numeric sort failed'; check contains "$P/public/index.html" 'AFTER=$[loop.index]' 'loop metadata leaked after loop scope'

P="$TMP_ROOT/loop-nested-meta"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"groups":[{"name":"a","items":[1,2]},{"name":"b","items":[3]}]}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@for(g : d.groups){OB=$[loop.index]/$[loop.length]|@for(x : g.items){I=$[loop.index]/$[loop.length]|}OA=$[loop.index]/$[loop.length]|}\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); check contains "$P/public/index.html" 'OB=1/2|I=1/2|I=2/2|OA=1/2|OB=2/2|I=1/1|OA=2/2|' 'nested loop metadata did not shadow/restore correctly'

P="$TMP_ROOT/loop-reserved-json"; mkproj "$P"; mkdir -p "$P/data"; printf '{}\n' >"$P/data/test.json"; printf '@json("data/test.json", loop)\n' >"$P/templates/template.html"; check nonzero 'reserved loop alias accepted by @json' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/loop-reserved-for"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"items":[1]}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@for(loop : d.items){x}\n' >"$P/templates/template.html"; check nonzero 'reserved loop binding accepted by @for' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/sort-mixed"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"items":[{"key":1},{"key":"2"}]}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@for(item : d.items by item.key asc){x}\n' >"$P/templates/template.html"; check nonzero 'mixed-type sort keys were silently accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"
P="$TMP_ROOT/sort-missing-direction"; mkproj "$P"; mkdir -p "$P/data"; printf '%s\n' '{"items":[{"key":1}]}' >"$P/data/test.json"; printf '@json("data/test.json", d)\n@for(item : d.items by item.key){x}\n' >"$P/templates/template.html"; check nonzero 'sort clause without asc/desc was accepted' bash -c "cd '$P' && '$NIFT_BIN' build --all"

# -----------------------------------------------------------------------------
# Watch state / reconciliation
# -----------------------------------------------------------------------------
P="$TMP_ROOT/watch-duplicate-state"; mkproj "$P"; mkdir -p "$P/content/w" "$P/.nift/.watch/content/w"; printf '%s\n' '{"watched":["content/w/","content/w/"]}' >"$P/.nift/.watch/watched.json"; printf '%s\n' '{"exts":[{"content-ext":".html","template":"templates/template.html","output-ext":".html"}]}' >"$P/.nift/.watch/content/w/exts.json"; printf '%s\n' '{"tracked":[]}' >"$P/.nift/.watch/content/w/tracked.json"; check nonzero 'duplicate watched directory state accepted' bash -c "cd '$P' && '$NIFT_BIN' info --watching"
P="$TMP_ROOT/watch-bad-ext"; mkproj "$P"; mkdir -p "$P/content/w" "$P/.nift/.watch/content/w"; printf '%s\n' '{"watched":["content/w/"]}' >"$P/.nift/.watch/watched.json"; printf '%s\n' '{"exts":[{"content-ext":"html","template":"templates/template.html","output-ext":".html"}]}' >"$P/.nift/.watch/content/w/exts.json"; printf '%s\n' '{"tracked":[]}' >"$P/.nift/.watch/content/w/tracked.json"; check nonzero 'invalid watched extension syntax accepted from state' bash -c "cd '$P' && '$NIFT_BIN' info --watching"
P="$TMP_ROOT/watch-corrupt-claim"; mkproj "$P"; mkdir -p "$P/content/w"; (cd "$P" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1); printf '%s\n' '{"tracked":["/"]}' >"$P/.nift/.watch/content/w/tracked.json"; check nonzero 'watch state allowed unrelated tracked page claim' bash -c "cd '$P' && '$NIFT_BIN' build"; TESTS=$((TESTS+1)); grep -Eq '"name"[[:space:]]*:[[:space:]]*"/"' "$P/.nift/tracked.json" || fail 'rejected corrupt watch state still removed root tracked page'
P="$TMP_ROOT/watch-ext-collision"; mkproj "$P"; mkdir -p "$P/content/w"; printf H >"$P/content/w/a.html"; printf M >"$P/content/w/a.md"; (cd "$P" && "$NIFT_BIN" watch content/w/ .html templates/template.html .html >/dev/null 2>&1 && "$NIFT_BIN" watch content/w/ .md templates/template.html .html >/dev/null 2>&1); check nonzero 'two watched files with same stem silently chose one tracked name' bash -c "cd '$P' && '$NIFT_BIN' build"
P="$TMP_ROOT/watch-manual-collision"; mkproj "$P"; mkdir -p "$P/content/w"; printf H >"$P/content/w/a.html"; (cd "$P" && "$NIFT_BIN" track w/a >/dev/null 2>&1); rm "$P/content/w/a.html"; printf M >"$P/content/w/a.md"; (cd "$P" && "$NIFT_BIN" watch content/w/ .md templates/template.html .html >/dev/null 2>&1); check nonzero 'watched alternate extension silently reused incompatible manual tracked name' bash -c "cd '$P' && '$NIFT_BIN' build"
P="$TMP_ROOT/watch-dir-remove"; mkproj "$P"; mkdir -p "$P/content/w"; printf W >"$P/content/w/a.html"; (cd "$P" && "$NIFT_BIN" watch content/w/ >/dev/null 2>&1 && "$NIFT_BIN" build --all >/dev/null 2>&1); check exists "$P/public/w/a.html" 'watch directory removal baseline output missing'; check exists "$P/.nift/public/w/a.info.json" 'watch directory removal baseline page info missing'; rm -rf "$P/content/w"; (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1); TESTS=$((TESTS+1)); ! grep -Fq '"name": "w/a"' "$P/.nift/tracked.json" || fail 'removing entire watched directory left auto-tracked page'; check not_exists "$P/public/w/a.html" 'removing entire watched directory left generated output'; check not_exists "$P/.nift/public/w/a.info.json" 'removing entire watched directory left page build metadata'

# -----------------------------------------------------------------------------
# Requirements recorded by @pathto: existence matters, modification does not
# -----------------------------------------------------------------------------
P="$TMP_ROOT/pathto-req"; mkproj "$P"; mkdir -p "$P/public/assets"; printf 'body{}\n' >"$P/public/assets/generated.css"; printf 'ABOUT\n' >"$P/content/about.html"; (cd "$P" && "$NIFT_BIN" track about >/dev/null 2>&1)
cat >"$P/content/index.html" <<'EOF'
<link href="@pathto('public/assets/generated.css')">
<a href="@pathto('about')">About</a>
EOF
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1)
check contains "$P/.nift/public/index.info.json" '"reqs"' '@pathto did not persist requirements metadata'
check contains "$P/.nift/public/index.info.json" '"public/assets/generated.css"' '@pathto did not record concrete file requirement'
check contains "$P/.nift/public/index.info.json" '"public/about.html"' '@pathto did not record tracked output requirement'
printf 'body{color:red}\n' >"$P/public/assets/generated.css"; (cd "$P" && "$NIFT_BIN" status >status-modified.log 2>&1)
check not_contains "$P/status-modified.log" 'generated.css' 'modified requirement incorrectly invalidated page'
rm "$P/public/assets/generated.css"; (cd "$P" && "$NIFT_BIN" status >status-missing.log 2>&1)
check contains "$P/status-missing.log" 'required path missing: public/assets/generated.css' 'missing @pathto requirement was not reported'
(cd "$P" && "$NIFT_BIN" build >missing-rebuild.log 2>&1 || true)
check contains "$P/missing-rebuild.log" "'public/assets/generated.css' is neither a tracked name nor a file that exists" 'missing req did not flow through normal @pathto rebuild error'

# Missing reqs are rebuild reasons, not pre-build fatal errors. If source has
# changed to remove the reference, build must get the chance to repair it.
cat >"$P/content/index.html" <<'EOF'
<p>reference removed</p>
<a href="@pathto('about')">About</a>
EOF
check zero 'missing req prevented a source change from repairing the page' bash -c "cd '$P' && '$NIFT_BIN' build"
check not_contains "$P/.nift/public/index.info.json" '"public/assets/generated.css"' 'successful repair retained removed req'

# -----------------------------------------------------------------------------
# Cross-feature req/schema/control-flow interactions
# -----------------------------------------------------------------------------
P="$TMP_ROOT/req-branch-swap"; mkproj "$P"; mkdir -p "$P/data" "$P/schemas" "$P/public/assets"
printf A >"$P/public/assets/a.txt"; printf B >"$P/public/assets/b.txt"
printf '{"choice":"a"}\n' >"$P/data/site.json"
printf '%s\n' '{"type":"object","properties":{"choice":{"enum":["a","b"]}}}' >"$P/schemas/site.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/site.json", site, "schemas/site.json")
@if(site.choice == "a"){@pathto('public/assets/a.txt')}else{@pathto('public/assets/b.txt')}
@content
EOF
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1)
check contains "$P/.nift/public/index.info.json" '"public/assets/a.txt"' 'selected @if pathto did not become req'
check not_contains "$P/.nift/public/index.info.json" '"public/assets/b.txt"' 'skipped @if pathto incorrectly became req'
sleep 0.02
printf '{"choice":"b"}\n' >"$P/data/site.json"; (cd "$P" && "$NIFT_BIN" build >/dev/null 2>&1)
check contains "$P/.nift/public/index.info.json" '"public/assets/b.txt"' 'data-driven branch change did not replace req'
check not_contains "$P/.nift/public/index.info.json" '"public/assets/a.txt"' 'old req survived branch change'

P="$TMP_ROOT/req-repair-data"; mkproj "$P"; mkdir -p "$P/data" "$P/public/assets"
printf X >"$P/public/assets/x.txt"; printf '{"show":true}\n' >"$P/data/site.json"
cat >"$P/templates/template.html" <<'EOF'
@json("data/site.json", site)
@if(site.show){@pathto('public/assets/x.txt')}
@content
EOF
(cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1); rm "$P/public/assets/x.txt"; printf '{"show":false}\n' >"$P/data/site.json"
check zero 'missing req blocked data-driven branch repair' bash -c "cd '$P' && '$NIFT_BIN' build"
check not_contains "$P/.nift/public/index.info.json" '"public/assets/x.txt"' 'repaired page retained obsolete req'

# -----------------------------------------------------------------------------
# New feature incremental semantics in hash/hybrid modes
# -----------------------------------------------------------------------------
for MODE in hash hybrid; do
  P="$TMP_ROOT/inc-new-$MODE"; mkproj "$P"; mkdir -p "$P/data" "$P/schemas" "$P/public/assets"
  python3 -S - "$P/.nift/config.json" "$MODE" <<'PY'
import json,sys
p,mode=sys.argv[1:]; d=json.load(open(p)); d["config"]["incremental-mode"]=mode; json.dump(d,open(p,"w"))
PY
  printf X >"$P/public/assets/a.txt"
  printf '{"value":1}\n' >"$P/data/site.json"
  printf '%s\n' '{"type":"object","properties":{"value":{"type":"integer","maximum":5}}}' >"$P/schemas/site.json"
  cat >"$P/templates/template.html" <<'EOF'
@json("data/site.json", site, "schemas/site.json")
<a href="@pathto('public/assets/a.txt')">$[site.value]</a>
@content
EOF
  (cd "$P" && "$NIFT_BIN" build --all >/dev/null 2>&1)

  printf Y >"$P/public/assets/a.txt"
  (cd "$P" && "$NIFT_BIN" status >req-status.log 2>&1)
  check not_contains "$P/req-status.log" 'needs rebuilding' "$MODE mode rebuilt because a req was modified"

  printf '{"value":2}\n' >"$P/data/site.json"
  (cd "$P" && "$NIFT_BIN" status >json-status.log 2>&1)
  check contains "$P/json-status.log" 'needs rebuilding' "$MODE mode missed JSON dependency change"
  check zero "$MODE mode failed JSON dependency rebuild" bash -c "cd '$P' && '$NIFT_BIN' build"

  printf '%s\n' '{"type":"object","properties":{"value":{"type":"integer","maximum":1}}}' >"$P/schemas/site.json"
  check nonzero "$MODE mode missed schema invalidation" bash -c "cd '$P' && '$NIFT_BIN' build"
done

# -----------------------------------------------------------------------------
# Large status/build summaries and command timing contract
# -----------------------------------------------------------------------------
P="$TMP_ROOT/summary"; mkproj "$P"; printf SHARED >"$P/shared.txt"; python3 -S - "$P/.nift/tracked.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p));
for i in range(12): d['tracked'].append({'name':f'p{i}','title':f'P{i}','template':'templates/template.html'})
json.dump(d,open(p,'w'))
PY
for i in $(seq 0 11); do printf 'P%s\n' "$i" >"$P/content/p$i.html"; done; printf '@dep("shared.txt")\n@content\n' >"$P/templates/template.html"; (cd "$P" && "$NIFT_BIN" build --all >build-all.log 2>&1); check contains "$P/build-all.log" 'time taken:' 'build --all omitted elapsed time'; (cd "$P" && "$NIFT_BIN" info --all >info.log 2>&1); check not_contains "$P/info.log" 'time taken:' 'info --all unexpectedly prints build timing'; printf CHANGED >"$P/shared.txt"; (cd "$P" && "$NIFT_BIN" status >status.log 2>&1); check contains "$P/status.log" 'rebuild causes:' 'large status did not summarize rebuild causes'; check contains "$P/status.log" '+8 more' 'large status did not summarize affected page list'; check not_contains "$P/status.log" 'time taken:' 'status unexpectedly prints build timing'; (cd "$P" && "$NIFT_BIN" build >updated.log 2>&1); check contains "$P/updated.log" 'rebuild causes:' 'large build did not summarize rebuild causes'; check contains "$P/updated.log" '+8 more' 'large build did not summarize affected pages'; check contains "$P/updated.log" 'time taken:' 'build omitted elapsed time'

rm -rf "$TMP_ROOT"
RUTHLESS_TESTS=$((TESTS-TESTS_BEFORE))
RUTHLESS_FAILS=$((FAILS-FAILS_BEFORE))
printf 'Ruthless adversarial extension: %d checks, %d failures\n' "$RUTHLESS_TESTS" "$RUTHLESS_FAILS"
