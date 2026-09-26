#!/usr/bin/env bash
set -euo pipefail
PREFIX=${NIFT_EMBED_PREFIX:-}
CC=${CC:-cc}
if [[ -z "$PREFIX" ]]; then
  echo 'SKIP: set NIFT_EMBED_PREFIX to a staged Nift embedding install prefix' >&2
  exit 0
fi
PC="$PREFIX/lib/pkgconfig"
if [[ ! -f "$PC/nift.pc" ]]; then
  echo "FAIL: NIFT_EMBED_PREFIX has no lib/pkgconfig/nift.pc: $PREFIX" >&2
  exit 1
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/consumer.c" <<'C'
#include <nift/c_abi.h>
#include <stdio.h>
#include <string.h>
int main(void) {
  nift_engine *e = nift_engine_new();
  nift_script_result *r = NULL;
  nift_string out = {0};
  if (!e) return 10;
  if (nift_abi_version_major() != 1 || nift_abi_version_minor() < 1) return 11;
  const char *script = "x := 20 + 22; return x;";
  nift_status st = nift_engine_execute(e, script, strlen(script), "<contract>", 10,
                                       NULL, NULL, 0, &r);
  if (st != NIFT_OK || !r || !nift_script_result_ok(r)) return 12;
  if (nift_script_result_value_json(r, &out) != NIFT_OK || out.length != 2 ||
      memcmp(out.data, "42", 2) != 0) return 13;
  nift_script_result_free(r); r = NULL;
  st = nift_engine_evaluate(e, "x", 1, &r);
  if (st != NIFT_OK || !r || !nift_script_result_ok(r)) return 14;
  if (nift_script_result_value_json(r, &out) != NIFT_OK || out.length != 2 ||
      memcmp(out.data, "42", 2) != 0) return 15;
  nift_script_result_free(r);
  nift_engine_free(e);
  return 0;
}
C
export PKG_CONFIG_PATH="$PC${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
CFLAGS=$(pkg-config --cflags nift)
LIBS=$(pkg-config --libs nift)
# shellcheck disable=SC2086
$CC -std=c11 $CFLAGS "$TMP/consumer.c" $LIBS -Wl,-rpath,"$PREFIX/lib" -o "$TMP/consumer"
"$TMP/consumer"
echo 'v4.5 embedding consumer smoke passed'
