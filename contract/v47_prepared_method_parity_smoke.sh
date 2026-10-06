#!/usr/bin/env bash
# Independent black-box contract: prepared-execution method-argument parity
# (v4.7.2 regression). encode("utf-8")/decode("utf-8") must behave identically
# in ordinary execution and inside prepared for/while bodies; invalid encodings
# must remain rejected in both contexts; multibyte UTF-8 must round-trip through
# prepared loops. Externally observable via the CLI exit code and stdout only.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"
run(){ printf '%s\n' "$1" > p.f; "$NIFT_BIN" p.f; }

# encode parity: ordinary and prepared contexts agree.
[ "$(run 'x := "a".encode("utf-8")
print(x.length())')" = 1 ] || { echo "encode top level" >&2; exit 1; }
[ "$(run 'for(i : [1,2,3]) { print("a".encode("utf-8").length()) }')" = $'1\n1\n1' ] || { echo "encode in loop" >&2; exit 1; }
[ "$(run 'i := 1
while(i <= 3) { print("a".encode("utf-8").length()); i = i + 1 }')" = $'1\n1\n1' ] || { echo "encode while loop" >&2; exit 1; }
[ "$(run 'fn(f()) { return "a".encode("utf-8").length() }
print(f())')" = 1 ] || { echo "encode function" >&2; exit 1; }

# decode parity: ordinary and prepared contexts agree.
[ "$(run 'print(bytes([65]).decode("utf-8"))')" = A ] || { echo "decode top level" >&2; exit 1; }
[ "$(run 'for(i : [1,2,3]) { print(bytes([65]).decode("utf-8")) }')" = $'A\nA\nA' ] || { echo "decode in loop" >&2; exit 1; }
[ "$(run 'fn(f()) { return bytes([65]).decode("utf-8") }
print(f())')" = A ] || { echo "decode function" >&2; exit 1; }

# Same prepared native dispatch, separate argument path (bytes slice).
[ "$(run 'for(i : [1]) { print(bytes([1,2,3]).slice(0,1).length()) }')" = 1 ] || { echo "bytes slice in loop" >&2; exit 1; }

# Invalid encodings remain rejected in both contexts with the exact diagnostic.
for code in \
    '"a".encode("utf8")' \
    'for(i : [1]) { "a".encode("utf8") }' \
    '"a".encode("UTF-8")' \
    'bytes([65]).decode("utf8")' \
    'for(i : [1]) { bytes([65]).decode("utf8") }'; do
    printf '%s\n' "$code" > p.f
    if "$NIFT_BIN" p.f >/dev/null 2>err; then echo "invalid encoding accepted: $code" >&2; exit 1; fi
    grep -q "encoding must be exactly 'utf-8'" err || { echo "missing encoding diagnostic: $(head -1 err)" >&2; exit 1; }
done

# Multibyte UTF-8 round-trips through prepared loops.
[ "$(run 'for(i : [1]) {
    print("é".encode("utf-8").decode("utf-8") == "é")
    print("中".encode("utf-8").decode("utf-8") == "中")
    print("😀".encode("utf-8").decode("utf-8") == "😀")
}')" = $'true\ntrue\ntrue' ] || { echo "multibyte in loop" >&2; exit 1; }

printf 'PASS v4.7 prepared method-argument parity\n'