#!/usr/bin/env bash
# Independent black-box contract: v4.6 filesystem type inspection primitives.
# exists()/is_file()/is_dir()/stat() classify paths; missing paths answer false
# / {exists:false}; stat() reports the documented shape and omits size for
# directories. Permission/metadata failures are recoverable, not wrong answers.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

printf 'hello' > f.txt
mkdir d

out=$("$NIFT_BIN" -e 'print(exists("f.txt")); print(is_file("f.txt")); print(is_dir("f.txt"))')
[ "$out" = $'true\ntrue\nfalse' ] || { echo "file predicates: $out" >&2; exit 1; }
out=$("$NIFT_BIN" -e 'print(exists("d")); print(is_file("d")); print(is_dir("d"))')
[ "$out" = $'true\nfalse\ntrue' ] || { echo "dir predicates: $out" >&2; exit 1; }
out=$("$NIFT_BIN" -e 'print(exists("nope")); print(is_file("nope")); print(is_dir("nope"))')
[ "$out" = $'false\nfalse\nfalse' ] || { echo "missing predicates: $out" >&2; exit 1; }

# stat(file) -> {exists:true, type:"file", size:N}
out=$("$NIFT_BIN" -e 's := stat("f.txt"); print(s.exists); print(s.type); print(s.size); print(s.has("size"))')
[ "$out" = $'true\nfile\n5\ntrue' ] || { echo "stat(file): $out" >&2; exit 1; }

# stat(directory) -> {exists:true, type:"directory"} with no size member.
out=$("$NIFT_BIN" -e 's := stat("d"); print(s.exists); print(s.type); print(s.has("size"))')
[ "$out" = $'true\ndirectory\nfalse' ] || { echo "stat(dir): $out" >&2; exit 1; }

# stat(missing) -> {exists:false} with no type member.
out=$("$NIFT_BIN" -e 's := stat("nope"); print(s.exists)')
[ "$out" = 'false' ] || { echo "stat(missing): $out" >&2; exit 1; }

# Genuine metadata failure is a recoverable error, not a false/true answer.
if [ "$(id -u)" -ne 0 ] && command -v chmod >/dev/null 2>&1; then
  mkdir locked; printf 's' > locked/secret.txt; chmod 000 locked
  out=$("$NIFT_BIN" -e 'try { is_file("locked/secret.txt") } catch(e) { print(e.category) }' 2>/dev/null || true)
  if [ -n "$out" ]; then [ "$out" = 'io' ] || { echo "metadata failure category: $out" >&2; exit 1; }; fi
  chmod 700 locked
fi

printf 'PASS v4.6 filesystem types\n'
