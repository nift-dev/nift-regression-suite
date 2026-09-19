#!/usr/bin/env bash
# Independent contract: package transaction() must submit one atomic
# BEGIN...COMMIT batch that rolls back on failure. SQLite is live-certified
# when sqlite3 is present (failed transaction leaves no partial rows);
# PostgreSQL/MySQL are certified deterministically: fake clients log the argv,
# proving a single BEGIN;...;COMMIT; invocation (no per-statement autocommit).
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQLITE_PKG="${SQLITE_PKG:-$ROOT/../nift-packages/sqlite}"
PG_PKG="${PG_PKG:-$ROOT/../nift-packages/postgres}"
MYSQL_PKG="${MYSQL_PKG:-$ROOT/../nift-packages/mysql}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift" "$t/bin"
for p in "$SQLITE_PKG" "$PG_PKG" "$MYSQL_PKG"; do (cd "$t/site" && "$NIFT_BIN" add "$p" >/dev/null 2>&1); done

# --- SQLite live rollback (when sqlite3 present) ---
if command -v sqlite3 >/dev/null 2>&1; then
  cat > "$t/site/t.f" <<'F'
@import("sqlite")
db := sqlite.open("tx.db")
print(sqlite.exec(db, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)").ok)
print(sqlite.exec(db, "INSERT INTO t(name) VALUES('seed')").ok)
tx := sqlite.transaction(db, ["INSERT INTO t(name) VALUES('A')", "INSERT INTO nope VALUES(1)", "INSERT INTO t(name) VALUES('B')"])
print(tx.ok)
r := sqlite.query(db, "SELECT * FROM t")
print(r.rows.size())
print(r.rows[0].name)
F
  out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
  [ "$(sed -n '1p' <<<"$out")" = "true" ] || { echo "$out" >&2; exit 1; }
  [ "$(sed -n '2p' <<<"$out")" = "true" ] || exit 1
  [ "$(sed -n '3p' <<<"$out")" = "false" ] || { echo "$out" >&2; exit 1; }
  [ "$(sed -n '4p' <<<"$out")" = "1" ] || exit 1
  [ "$(sed -n '5p' <<<"$out")" = "seed" ] || exit 1
  echo "sqlite rollback: live-certified (A and B absent after failed transaction)"
else
  echo "sqlite rollback: unavailable locally (no sqlite3)"
fi

# --- Postgres/MySQL deterministic atomic-submission via fake clients ---
cat > "$t/bin/psql" <<'B'
#!/usr/bin/env bash
printf 'PSQL' >> "$FAKE_LOG"
for a in "$@"; do printf ' %s' "$a" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
B
cat > "$t/bin/mysql" <<'B'
#!/usr/bin/env bash
printf 'MYSQL' >> "$FAKE_LOG"
for a in "$@"; do printf ' %s' "$a" >> "$FAKE_LOG"; done
printf '\n' >> "$FAKE_LOG"
B
chmod +x "$t/bin/psql" "$t/bin/mysql"
export FAKE_LOG="$t/log.txt"
cat > "$t/site/atm.f" <<'F'
@import("postgres")
@import("mysql")
db := postgres.open({"host": "h", "database": "d", "user": "u"})
print(postgres.transaction(db, ["INSERT INTO t VALUES(1)", "INSERT INTO t VALUES(2)"]).ok)
m := mysql.open({"host": "h", "user": "u", "database": "d"})
print(mysql.transaction(m, ["INSERT INTO t VALUES(1)", "INSERT INTO t VALUES(2)"]).ok)
F
out=$(cd "$t/site" && PATH="$t/bin:$PATH" "$NIFT_BIN" run atm.f)
[ "$(sed -n '1p' <<<"$out")" = "true" ] || { echo "$out" >&2; exit 1; }
[ "$(sed -n '2p' <<<"$out")" = "true" ] || exit 1
psql_line=$(grep '^PSQL ' "$FAKE_LOG" | tail -1)
mysql_line=$(grep '^MYSQL ' "$FAKE_LOG" | tail -1)
[[ "$psql_line" == *"ON_ERROR_STOP=1"*"-c"*"BEGIN;INSERT INTO t VALUES(1);INSERT INTO t VALUES(2);COMMIT;"* ]] || { echo "psql not atomic: $psql_line" >&2; exit 1; }
[[ "$mysql_line" == *"--execute"*"BEGIN;INSERT INTO t VALUES(1);INSERT INTO t VALUES(2);COMMIT;"* ]] || { echo "mysql not atomic: $mysql_line" >&2; exit 1; }
# a single psql/mysql process is spawned for the whole transaction
[ "$(grep -c '^PSQL ' "$FAKE_LOG")" = "1" ] || { echo "psql spawned multiple times" >&2; exit 1; }
[ "$(grep -c '^MYSQL ' "$FAKE_LOG")" = "1" ] || { echo "mysql spawned multiple times" >&2; exit 1; }
printf 'PASS v4.4 transaction atomicity (sqlite live, postgres/mysql atomic-submission)\n'
