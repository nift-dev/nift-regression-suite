#!/usr/bin/env bash
set -euo pipefail
: "${NIFT_BIN:?}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/io.nift" <<'NIFT'
make_dir("d")
out := ofstream("d/x")
out.write_line("alpha")
out.write("beta")
close(out)
in := ifstream("d/x")
print(in.read_line())
print(in.read_all())
close(in)
print(exists("d/x"))
whole := open("d/x")
return whole.substr(0, 5)
NIFT
out=$(cd "$TMP" && "$NIFT_BIN" run io.nift)
[[ "$out" == $'alpha\nbeta\ntrue\nalpha' ]]
cat > "$TMP/vals" <<'EOFV'
true 7 2.5 "x" [1,2]
EOFV
cat > "$TMP/vals.nift" <<'NIFT'
s := ifstream("vals")
print(s.read_val())
print(s.read_val())
print(s.read_val())
print(s.read_val())
a := s.read_val()
print(a.join(":"))
close(s)
NIFT
[[ "$(cd "$TMP" && "$NIFT_BIN" run vals.nift)" == $'true\n7\n2.5\nx\n1:2' ]]
