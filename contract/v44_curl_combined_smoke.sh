#!/usr/bin/env bash
# Independent black-box contract for the curl package and the combined
# curl+sqlite integration: two simultaneous package imports, a direct exported
# function (request) plus two exported structs (curl, sqlite), private helper
# isolation, process execution from both packages, and structured values
# crossing package boundaries. Runs offline against a local HTTP server.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURL_PKG="${CURL_PKG:-$ROOT/../nift-packages/curl}"
SQLITE_PKG="${SQLITE_PKG:-$ROOT/../nift-packages/sqlite}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/site/.nift"
(cd "$t/site" && "$NIFT_BIN" add "$CURL_PKG" >/dev/null 2>&1)
(cd "$t/site" && "$NIFT_BIN" add "$SQLITE_PKG" >/dev/null 2>&1)

PORT=$((18000 + RANDOM % 2000))
python3 - "$PORT" <<'PYEOF' &
import http.server, sys
port = int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code=200, body=b"ok"):
        self.send_response(code); self.send_header("Content-Type", "text/plain")
        self.send_header("Set-Cookie", "a=1"); self.send_header("Set-Cookie", "b=2")
        self.end_headers()
        if self.command != "HEAD": self.wfile.write(body)
    def do_HEAD(self): self._send(200 if self.path != "/notfound" else 404)
    def do_GET(self):
        if self.path == "/notfound": self._send(404, b"nope"); return
        if self.path == "/unicode": self._send(200, "héllo ünïcode".encode()); return
        self._send(200, b"from-api")
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        self._send(200, self.rfile.read(n))
    def do_PUT(self):
        n = int(self.headers.get("Content-Length", 0)); self._send(200, self.rfile.read(n))
    def do_DELETE(self): self._send(200, b"deleted")
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PYEOF
SERVER_PID=$!
trap 'rm -rf "$t"; kill $SERVER_PID 2>/dev/null' EXIT
sleep 1

cat > "$t/site/t.f" <<EOF
@import("curl")
@import("sqlite")
r := request("http://127.0.0.1:$PORT/")
print(r.body)
print(r.headers.get("set-cookie"))
print(delete("http://127.0.0.1:$PORT/").body)
print(curl.version().contains("curl"))
db := sqlite.open("cache.db")
sqlite.exec(db, "CREATE TABLE IF NOT EXISTS responses(status INTEGER, body TEXT)")
sqlite.exec(db, "INSERT INTO responses VALUES(?, ?)", r.status, r.body)
rows := sqlite.query(db, "SELECT * FROM responses")
print(rows.rows.size())
print(rows.rows[0].body)
EOF
out=$(cd "$t/site" && "$NIFT_BIN" run t.f)
[ "$out" = $'from-api\na=1; b=2\ndeleted\ntrue\n1\nfrom-api' ] || { printf 'unexpected:\n%s\n' "$out" >&2; exit 1; }
# Private helpers of neither package are visible to the importer.
for pkg in curl sqlite; do
  if [ "$pkg" = curl ]; then helper=curl_parse_headers; else helper=sqlite_bind; fi
  printf '@import("%s")\nprint(%s)\n' "$pkg" "$helper" > "$t/site/p.f"
  if (cd "$t/site" && "$NIFT_BIN" run p.f >/dev/null 2>&1); then echo "private $pkg helper leaked" >&2; exit 1; fi
done
printf 'PASS v4.4 curl + sqlite combined\n'