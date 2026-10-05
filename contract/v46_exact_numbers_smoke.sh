#!/usr/bin/env bash
# Independent black-box contract: v4.6 exact-number (StrNumber) semantics.
# Runtime numbers retain an exact decimal spelling when a double conversion
# would lose JSON-number meaning, so large integers and exact decimals print,
# compare and JSON-round-trip correctly while ordinary double behavior (and
# deliberate int64 overflow diagnostics) is preserved.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

# Exact integer beyond IEEE-754 exact range prints and compares exactly.
out=$("$NIFT_BIN" -e 'print(9007199254740993); print(type(9007199254740993)); print(9007199254740993 == 9007199254740992); print(9007199254740993 > 9007199254740992); print(9007199254740992 == 9007199254740992.0); print(9007199254740993 == 9007199254740992.0)')
[ "$out" = $'9007199254740993\nint\nfalse\ntrue\ntrue\nfalse' ] || { echo "exact integer: $out" >&2; exit 1; }

# Repeated increment stays exact.
out=$("$NIFT_BIN" -e 'x := 9007199254740992; i := 0; while(i < 10) { x += 1; i += 1 }; print(x)')
[ "$out" = '9007199254741002' ] || { echo "increment: $out" >&2; exit 1; }

# int64 boundary is exact; overflow is a deterministic diagnostic.
out=$("$NIFT_BIN" -e 'print(9223372036854775806 + 1)')
[ "$out" = '9223372036854775807' ] || { echo "int64 boundary: $out" >&2; exit 1; }
if "$NIFT_BIN" -e 'print(9223372036854775807 + 1)' >"$t/o" 2>"$t/e"; then echo "overflow accepted" >&2; exit 1; fi
grep -q 'signed 64-bit integer overflow' "$t/e"

# A double literal at 2^63 remains double.
out=$("$NIFT_BIN" -e 'x := 9223372036854775808.0; print(x + 1)')
[ "$out" = '9.223372036854776e+18' ] || { echo "double at 2^63: $out" >&2; exit 1; }

# Exact tiny decimals keep their spelling and type.
out=$("$NIFT_BIN" -e 'print(1e-1000); print(type(1e-1000)); print(-1e-1000)')
[ "$out" = $'1e-1000\nfloat\n-1e-1000' ] || { echo "tiny decimals: $out" >&2; exit 1; }

# Integer literals beyond signed 64-bit are rejected at parse time.
if "$NIFT_BIN" eval '18446744073709551615' >"$t/o" 2>"$t/e"; then echo "out-of-range literal accepted" >&2; exit 1; fi
grep -q 'integer literal outside signed 64-bit range' "$t/e"

# eval --json preserves exact spelling and canonicalizes redundant exponents.
[ "$("$NIFT_BIN" eval --json '9007199254740993')" = '9007199254740993' ]
[ "$("$NIFT_BIN" eval --json '1e-1000')" = '1e-1000' ]
[ "$("$NIFT_BIN" eval --json '1.23000e+5')" = '123000' ]

# JSON data injection round-trips arbitrary precision through a real build.
"$NIFT_BIN" init >/dev/null
printf '{"big":123456789012345678901234567890,"u64":18446744073709551615,"i64":9223372036854775807,"two53":9007199254740993,"tiny":1e-1000,"dec":0.1}\n' > data.json
printf '@json(d, "data.json")\n$[d.big] $[d.u64] $[d.i64] $[d.two53] $[d.tiny] $[d.dec] $[d.two53 + 1]\n' > content/index.html
"$NIFT_BIN" build --all >/dev/null
rendered=$(tr -d '\n' < public/index.html)
case "$rendered" in
  *'123456789012345678901234567890 18446744073709551615 9223372036854775807 9007199254740993 1e-1000 0.1 9007199254740994'*) : ;;
  *) echo "JSON round-trip: $rendered" >&2; exit 1 ;;
esac

printf 'PASS v4.6 exact numbers\n'
