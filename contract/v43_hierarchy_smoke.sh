#!/usr/bin/env bash
# Independent black-box contract for the intrinsic page hierarchy:
# parent/children/ancestors/descendants/siblings, root and missing-parent
# semantics, deterministic ordering, composition, template/script/eval parity,
# and incremental invalidation through the nift executable.
set -euo pipefail
NIFT_BIN="${NIFT_BIN:?}"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
cd "$td"
mkdir -p .nift content/docs/advanced templates public
printf '{"config":{"content-dir":"content/","content-ext":".md","output-dir":"public/","output-ext":".html","default-template":"templates/template.html","build-threads":-1,"incremental-mode":"modified"}}' > .nift/config.json
printf '@content' > templates/plain.html
printf 'SIB:<!--$[page.siblings.size()]-->|@content' > templates/hier.html
printf '{"tracked":[{"name":"/","title":"Home","template":"templates/plain.html"},{"name":"about","title":"About","template":"templates/plain.html"},{"name":"docs","title":"Docs","template":"templates/hier.html"},{"name":"docs/advanced","title":"Advanced","template":"templates/hier.html"},{"name":"docs/advanced/guide","title":"Guide","template":"templates/plain.html"},{"name":"docs/basics","title":"Basics","template":"templates/plain.html"}]}' > .nift/tracked.json
printf '# Home\n' > content/index.md
printf '# About\n' > content/about.md
printf '# Docs\n' > content/docs.md
printf '# Advanced\n' > content/docs/advanced.md
printf '# Guide\n' > content/docs/advanced/guide.md
printf '# Basics\n' > content/docs/basics.md

run(){ printf '%s\n' "$1" > t.nift; "$NIFT_BIN" run t.nift; }
must_error(){ if "$NIFT_BIN" run <(printf '%s\n' "$1") >/dev/null 2>&1; then echo "expected error: $1" >&2; return 1; fi; }

[[ "$(run 'print(page("docs/advanced/guide").parent.title)')" == Advanced ]]
[[ "$(run 'print(page("/").parent)')" == null ]]
[[ "$(run 'print(page("about").parent.title)')" == Home ]]
[[ "$(run 'print(page("docs").children.map(c => c.title).join(","))')" == Advanced,Basics ]]
[[ "$(run 'print(page("docs/advanced/guide").ancestors.map(a => a.title).join(","))')" == Advanced,Docs,Home ]]
[[ "$(run 'print(page("docs").descendants.map(d => d.title).join(","))')" == Advanced,Guide,Basics ]]
[[ "$(run 'print(page("docs/basics").siblings.map(s => s.title).join(","))')" == Advanced ]]
[[ "$(run 'print(page("/").children.map(c => c.title).join(","))')" == About,Docs ]]
[[ "$(run 'print(page("docs").children[0].title)')" == Advanced ]]
[[ "$(run 'p := page("docs/advanced")
print(p.parent.children.filter(c => c.title != "Basics").map(c => c.title).join(","))')" == Advanced ]]
[[ "$(run 'print(page("docs/basics").children.size()); print(page("docs/basics").descendants.size())')" == $'0\n0' ]]
[[ "$(run 'print(page("docs/advanced").siblings.size())')" == 1 ]]
must_error 'print(page(".."))'
must_error 'print(page("/etc/passwd"))'
must_error 'p := page("/")
print(p.parent.title)'

# template current-page binding + eval parity
"$NIFT_BIN" build --all >/dev/null 2>&1
grep -q 'SIB:<!--1-->' public/docs/advanced.html
! grep -q 'SIB:' public/docs/basics.html
grep -q 'SIB:<!--1-->' public/docs.html

# incremental: add a child -> hierarchy consumers rebuild via compact fingerprint
python3 - <<'PY'
import json
tr=json.load(open('.nift/tracked.json'))
tr['tracked'].append({'name':'docs/new','title':'New','template':'templates/plain.html'})
json.dump(tr,open('.nift/tracked.json','w'))
PY
printf '# New\n' > content/docs/new.md
"$NIFT_BIN" build >/dev/null 2>&1
grep -q 'SIB:<!--2-->' public/docs/advanced.html
# ordinary page carries no hierarchy dependency
python3 - <<'PY'
import json
assert '.nift/hierarchy.fingerprint' not in json.load(open('.nift/public/index.info.json'))['dependencies']
assert '.nift/hierarchy.fingerprint' in json.load(open('.nift/public/docs/advanced.info.json'))['dependencies']
PY

echo 'hierarchy contract passed'