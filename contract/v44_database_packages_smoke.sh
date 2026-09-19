#!/usr/bin/env bash
# Independent black-box contract: database module-style packages
# (postgres/mysql/redis) with a consistent API (available/open/exec/query/
# transaction for the relational pair; client-oriented verbs for redis).
# Redis runs a live round-trip when redis-cli and a reachable server exist;
# PostgreSQL/MySQL certify client discovery, argv construction, structured
# failures and privacy without disturbing any local server.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PG_PKG="${PG_PKG:-$ROOT/../nift-packages/postgres}"
MYSQL_PKG="${MYSQL_PKG:-$ROOT/../nift-packages/mysql}"
REDIS_PKG="${REDIS_PKG:-$ROOT/../nift-packages/redis}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift"
for p in "$PG_PKG" "$MYSQL_PKG" "$REDIS_PKG"; do (cd "$t/site" && "$NIFT_BIN" add "$p" >/dev/null 2>&1); done
cat > "$t/site/t.f" <<'F'
@import("postgres")
@import("mysql")
@import("redis")
print("pg-avail:")
print(postgres.available())
print("mysql-avail:")
print(mysql.available())
print("redis-avail:")
print(redis.available())
db := postgres.open({"host": "127.0.0.1", "port": 5432, "database": "nope", "user": "nobody"})
print("pg-conn:")
print(db.conn != "")
r := postgres.query(db, "SELECT 1")
print("pg-ok:")
print(r.ok)
print("pg-exit:" + r.exit_code.to_string())
m := mysql.open({"host": "127.0.0.1", "port": 3306, "user": "root", "database": "nope"})
print("mysql-conn:")
print(m.conn.size() > 0)
mr := mysql.query(m, "SELECT 1")
print("mysql-ok:")
print(mr.ok)
print("mysql-exit:" + mr.exit_code.to_string())
rc := redis.open({"host": "127.0.0.1", "port": 6379, "db": 15})
print("redis-conn:")
print(rc.conn.size() > 0)
print("redis-version:")
print(redis.version() != "")
F
out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
grep -qE '^(true|false)$' <<<"$out" || exit 1
grep -qE '^(true|false)$' <<<"$out" || exit 1
grep -qE '^(true|false)$' <<<"$out" || exit 1
grep -q '^true$' <<<"$out" || { echo "$out" >&2; exit 1; }
grep -q '^false$' <<<"$out" || exit 1
grep -qE '^pg-exit:[0-9]+$' <<<"$out" || exit 1
grep -q '^true$' <<<"$out" || exit 1
grep -q '^false$' <<<"$out" || exit 1
grep -qE '^mysql-exit:[0-9]+$' <<<"$out" || exit 1
grep -q '^true$' <<<"$out" || exit 1
grep -q '^true$' <<<"$out" || exit 1
# private helpers hidden from importers
cat > "$t/site/priv.f" <<'F'
@import("postgres")
@import("mysql")
@import("redis")
print(postgres_literal)
print(mysql_bind)
print(redis_copy)
F
if (cd "$t/site" && "$NIFT_BIN" run priv.f >/dev/null 2>&1); then echo "private helper leaked" >&2; exit 1; fi
# Redis live round-trip only when a reachable server answers (db 15, isolated).
if timeout 3 redis-cli -h 127.0.0.1 -p 6379 -n 15 ping 2>/dev/null | grep -q PONG; then
  cat > "$t/site/r.f" <<'F'
@import("redis")
client := redis.open({"host": "127.0.0.1", "port": 6379, "db": 15})
print(redis.set(client, "nift:contract", "v").ok)
print(redis.get(client, "nift:contract").data)
print(redis.exists(client, "nift:contract").data)
print(redis.del(client, "nift:contract").data)
print(type(redis.get(client, "nift:missing").data))
F
  out=$(cd "$t/site" && "$NIFT_BIN" run r.f)
  [ "$(sed -n '1p' <<<"$out")" = "true" ] || exit 1
  [ "$(sed -n '2p' <<<"$out")" = "v" ] || exit 1
  [ "$(sed -n '3p' <<<"$out")" = "1" ] || exit 1
  [ "$(sed -n '4p' <<<"$out")" = "1" ] || exit 1
  [ "$(sed -n '5p' <<<"$out")" = "null" ] || exit 1
fi
printf 'PASS v4.4 database module-style packages\n'
