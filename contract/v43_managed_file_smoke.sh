#!/usr/bin/env bash
set -euo pipefail
NIFT="${NIFT_BIN:?}"
td="$(mktemp -d)"; trap 'rm -rf "$td"' EXIT
printf 'one TARGET\nsecond\n' > "$td/x.txt"
cat > "$td/edit.nift" <<'NIFT'
f := file("x.txt")
print(f.exists())
f.open("rw")
print(f.read_line())
f.seek(0)
f.replace_once("TARGET", "DONE")
f.insert_after("DONE", "!")
print(f.modified())
f.save()
f.close()
NIFT
[[ "$(cd "$td" && "$NIFT" run edit.nift)" == $'true\none TARGET\ntrue' ]]
[[ "$(cat "$td/x.txt")" == $'one DONE!\nsecond' ]]
# Exact-one safety and host cleanup leave the filesystem untouched.
printf 'f := file("x.txt")\nf.open("rw")\nf.replace_once("missing", "bad")\n' > "$td/bad.nift"
! (cd "$td" && "$NIFT" run bad.nift >/dev/null 2>&1)
! grep -q bad "$td/x.txt"
printf 'f := file("x.txt")\nf.open("rw")\nf.append("UNSAVED")\n' > "$td/leak.nift"
! (cd "$td" && "$NIFT" run leak.nift >/dev/null 2>&1)
! grep -q UNSAVED "$td/x.txt"
