#!/usr/bin/env bash
set -euo pipefail
NIFT=${NIFT_BIN:-${NIFT:-nift}}
CC=${CC:-cc}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/fixture.c" <<'C'
#include <stdint.h>
#include <stddef.h>
typedef int64_t (*cb_i64)(int64_t);
int64_t add_i64(int64_t a, int64_t b) { return a + b; }
double add_f64(double a, double b) { return a + b; }
const char *greeting(void) { return "ffi-ok"; }
void xor_bytes(uint8_t *p, int64_t n) { for (int64_t i = 0; i < n; ++i) p[i] ^= 0xffu; }
struct pair_i32 { int32_t a; int32_t b; };
int64_t pair_sum_ptr(const struct pair_i32 *p) { return (int64_t)p->a + p->b; }
int64_t call_cb(cb_i64 cb, int64_t x) { return cb(x); }
C
case "$(uname -s)" in
  Darwin) LIB="$TMP/libfixture.dylib"; "$CC" -dynamiclib -fPIC "$TMP/fixture.c" -o "$LIB" ;;
  Linux) LIB="$TMP/libfixture.so"; "$CC" -shared -fPIC "$TMP/fixture.c" -o "$LIB" ;;
  *) echo 'SKIP: v4.5 FFI smoke currently requires an ELF or Mach-O host' >&2; exit 0 ;;
esac
cat >"$TMP/test.f" <<'NIFT'
lib := ffi_open(args[0])
print(ffi_call(lib, "add_i64", "i64(i64,i64)", 20, 22))
print(ffi_call(lib, "add_f64", "f64(f64,f64)", 1.25, 2.5))
print(ffi_call(lib, "greeting", "cstr()"))
b := ffi_buffer([1, 2, 3])
ffi_call(lib, "xor_bytes", "void(buffer,i64)", b, 3)
print(ffi_bytes(b).join(","))
p := ffi_struct("i32,i32", [7, 8])
print(ffi_call(lib, "pair_sum_ptr", "i64(buffer)", p))
fn(twice(x)) { return x * 2 }
cb := ffi_callback(twice, "i64(i64)")
print(ffi_call(lib, "call_cb", "i64(callback_i64,i64)", cb, 21))
ffi_close(lib)
NIFT
out=$($NIFT "$TMP/test.f" "$LIB")
[[ "$out" == $'42\n3.75\nffi-ok\n254,253,252\n15\n42' ]] || {
  printf 'unexpected FFI output:\n%s\n' "$out" >&2
  exit 1
}
cat >"$TMP/closed.f" <<'NIFT'
lib := ffi_open(args[0])
ffi_close(lib)
print(ffi_call(lib, "add_i64", "i64(i64,i64)", 1, 2))
NIFT
if $NIFT "$TMP/closed.f" "$LIB" >"$TMP/out" 2>"$TMP/err"; then
  echo 'closed FFI library unexpectedly remained callable' >&2
  exit 1
fi
grep -qi 'closed\|invalid.*library' "$TMP/err"
echo 'v4.5 FFI smoke passed'
