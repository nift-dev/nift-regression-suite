#!/usr/bin/env bash
# Independent contract: package parameter binders are conservative textual
# substitution. $n placeholders (postgres/mysql) and ? (sqlite) must be
# replaced only OUTSIDE string literals, quoted identifiers and comments;
# a $1 must never alter a $10. Postgres/MySQL are certified deterministically
# via fake clients that log the bound SQL; SQLite live via sqlite3.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_PKG="${PG_PKG:-$ROOT/../nift-packages/postgres}"
MYSQL_PKG="${MYSQL_PKG:-$ROOT/../nift-packages/mysql}"
SQLITE_PKG="${SQLITE_PKG:-$ROOT/../nift-packages/sqlite}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift" "$t/bin"
for p in "$PG_PKG" "$MYSQL_PKG" "$SQLITE_PKG"; do (cd "$t/site" && "$NIFT_BIN" add "$p" >/dev/null 2>&1); done

# --- SQLite live binding (when sqlite3 present) ---
if command -v sqlite3 >/dev/null 2>&1; then
  cat > "$t/site/s.f" <<'F'
@import("sqlite")
db := sqlite.open("b.db")
print(sqlite.query(db, "SELECT ? AS v", "hello").rows[0].v)
print(sqlite.query(db, "SELECT 'a?b' AS lit, ? AS v", "outer").rows[0].lit)
print(sqlite.query(db, "SELECT ? AS v", "O'Brien").rows[0].v)
print(sqlite.query(db, "SELECT ? IS NULL AS v", null).rows[0].v)
print(sqlite.query(db, "SELECT ? AS v", true).rows[0].v)
print(sqlite.query(db, "SELECT ? AS v", 42).rows[0].v)
print(sqlite.query(db, "SELECT ? AS v", "DROP TABLE x --").rows[0].v)
F
  out=$(cd "$t/site" && "$NIFT_BIN" run s.f)
  [ "$(sed -n '1p' <<<"$out")" = "hello" ] || { echo "$out" >&2; exit 1; }
  [ "$(sed -n '2p' <<<"$out")" = "a?b" ] || exit 1
  [ "$(sed -n '3p' <<<"$out")" = "O'Brien" ] || exit 1
  [ "$(sed -n '4p' <<<"$out")" = "1" ] || exit 1
  [ "$(sed -n '5p' <<<"$out")" = "1" ] || exit 1
  [ "$(sed -n '6p' <<<"$out")" = "42" ] || exit 1
  [ "$(sed -n '7p' <<<"$out")" = "DROP TABLE x --" ] || exit 1
  echo "sqlite binding: live-certified"
else
  echo "sqlite binding: unavailable locally (no sqlite3)"
fi

# --- Postgres/MySQL deterministic binding via fake clients ---
for tool in psql mysql; do cat > "$t/bin/$tool" <<B
#!/usr/bin/env bash
printf '$tool' >> "\$FAKE_LOG"
for a in "\$@"; do printf ' %s' "\$a" >> "\$FAKE_LOG"; done
printf '\n' >> "\$FAKE_LOG"
exit 0
B
chmod +x "$t/bin/$tool"; done
export FAKE_LOG="$t/log.txt"
cat > "$t/site/b.f" <<'F'
@import("postgres")
@import("mysql")
db := postgres.open({"host": "h", "database": "d", "user": "u"})
print(postgres.query(db, "SELECT $1, $10, 'lit $1', \"id $1\" FROM t WHERE x = $1", "A").ok)
print(postgres.query(db, "SELECT $2, $1 FROM t", "A", "B").ok)
print(postgres.query(db, "SELECT * FROM t -- c $1", "A").ok)
print(postgres.exec(db, "INSERT INTO t VALUES('O''Brien', $1)", "it's").ok)
print(postgres.exec(db, "INSERT INTO t VALUES('x', $1)", "a\\b").ok)
m := mysql.open({"host": "h", "user": "u", "database": "d"})
print(mysql.query(m, "SELECT $1, $10, 'lit $1', \"id $1\" FROM t WHERE x = $1", "A").ok)
print(mysql.query(m, "SELECT $2, $1 FROM t", "A", "B").ok)
F
out=$(cd "$t/site" && PATH="$t/bin:$PATH" "$NIFT_BIN" run b.f)
for i in 1 2 3 4 5 6 7; do [ "$(sed -n "${i}p" <<<"$out")" = "true" ] || { echo "$out" >&2; exit 1; }; done
grep -q 'SELECT .A., \$10, .lit \$1., .id \$1. FROM t WHERE x = .A.' <<<"$(cat "$FAKE_LOG")" || { echo "pg \$1/\$10 corruption" >&2; cat "$FAKE_LOG" >&2; exit 1; }
grep -q "SELECT 'B', 'A' FROM t" <<<"$(cat "$FAKE_LOG")" || exit 1
grep -q -- "-- c \$1" <<<"$(cat "$FAKE_LOG")" || exit 1
grep -q "VALUES('O''Brien', 'it''s')" <<<"$(cat "$FAKE_LOG")" || exit 1
grep -q "VALUES('x', 'a\\\\b')" <<<"$(cat "$FAKE_LOG")" || { echo "backslash binding failed" >&2; cat "$FAKE_LOG" >&2; exit 1; }
printf 'PASS v4.4 conservative parameter binding\n'
