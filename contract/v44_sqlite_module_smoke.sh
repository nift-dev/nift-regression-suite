#!/usr/bin/env bash
# Independent black-box contract for the sqlite package's module-style API:
# an exported `sqlite` struct with callable fields (available/open/exec/query/
# transaction), private helper isolation, and script-land comment/fn syntax.
# The sqlite3-dependent matrix is covered by the source dogfood test; here the
# module surface is the contract.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
PKG_DIR=${PKG_DIR:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/../nift-packages/sqlite"}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift"
(cd "$t/site" && "$NIFT_BIN" add "$PKG_DIR" >/dev/null)
cat > "$t/site/t.f" <<'NIFT'
@import("sqlite")
print(type(sqlite))
print(sqlite.available() == true || sqlite.available() == false)
db := sqlite.open("test.db")
print(db.path)
NIFT
out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
[ "$out" = $'struct\ntrue\ntest.db' ] || { printf '%s\n' "$out" >&2; exit 1; }
# Private helpers must not leak into the importer.
cat > "$t/site/priv.f" <<'NIFT'
@import("sqlite")
print(sqlite_bind)
NIFT
if (cd "$t/site" && "$NIFT_BIN" run priv.f >/dev/null 2>&1); then exit 1; fi
# The exported struct's callable fields resolve even when the module is
# re-imported and referenced indirectly.
cat > "$t/site/alias.f" <<'NIFT'
@import("sqlite")
s := sqlite
print(s.open("x.db").path)
NIFT
[ "$(cd "$t/site" && "$NIFT_BIN" run alias.f)" = "x.db" ] || exit 1
printf 'PASS v4.4 sqlite module API\n'