#!/usr/bin/env bash
# Independent black-box contract: v4.6 FFI byte bridges. ffi_buffer accepts
# strings/bytes/byte arrays as a native buffer, ffi_snapshot_bytes copies it
# back to an immutable bytes value without mutating the source bytes, and
# ffi_bytes exposes the buffer as an array. Uses a tiny self-contained C fixture.
set -euo pipefail
NIFT_BIN=${NIFT_BIN:?}
CC=${CC:-cc}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT; cd "$t"

case "$(uname -s)" in
  Darwin) EXT=dylib ;;
  MINGW*|MSYS*|CYGWIN*) EXT=dll ;;
  *) EXT=so ;;
esac
cat > fixture.c <<'C'
#include <stddef.h>
void contract_xor(unsigned char* p, size_t n, unsigned char key) {
  size_t i; for (i = 0; i < n; i++) p[i] = (unsigned char)(p[i] ^ key);
}
C
if ! "$CC" -std=c99 -fPIC -shared fixture.c -o "libcontract.$EXT" 2>"$t/cc.err"; then
  echo 'SKIP: no working C toolchain for the FFI bytes fixture' >&2; cat "$t/cc.err" >&2; exit 0
fi
LIB="$t/libcontract.$EXT"

out=$("$NIFT_BIN" -e "
lib := ffi_open(\"$LIB\")
src := bytes([1,2,3])
buf := ffi_buffer(src)
snap := ffi_snapshot_bytes(buf)
print(type(snap)); print(snap == src)
ffi_call(lib, \"contract_xor\", \"void(buffer,u64,u8)\", buf, 3, 255)
after := ffi_snapshot_bytes(buf)
print(after[0]); print(after[1]); print(after[2])
print(src == bytes([1,2,3]))
print(type(ffi_bytes(buf))); print(ffi_bytes(buf) == [254,253,252])
print(ffi_snapshot_bytes(ffi_buffer(\"A\")) == bytes([65]))")
[ "$out" = $'bytes\ntrue\n254\n253\n252\ntrue\narray\ntrue\ntrue' ] || { echo "ffi bytes: $out" >&2; exit 1; }

reject(){ if "$NIFT_BIN" -e "$2" >/dev/null 2>"$t/e"; then echo "accepted: $2" >&2; exit 1; fi; grep -q "$1" "$t/e" || { echo "missing '$1' for: $2" >&2; cat "$t/e" >&2; exit 1; }; }
reject 'expected string, bytes, or byte array' 'ffi_buffer(1)'
reject 'expected buffer handle' 'ffi_snapshot_bytes()'
reject 'expected buffer handle' 'ffi_snapshot_bytes(bytes([1]))'

printf 'PASS v4.6 bytes ffi\n'
