#!/usr/bin/env bash
# Independent black-box contract: v4.6 C ABI 1.3 embedding surface. Compiles a
# C consumer against a staged embedding prefix and certifies the additive 1.2/1.3
# behavior: copied Engine/Context byte inputs, result-owned top-level immutable
# byte views, lazy checked JSON extraction, and execution-scoped stdout/stderr
# sinks captured separately from values.
set -euo pipefail
PREFIX=${NIFT_EMBED_PREFIX:-}
CC=${CC:-cc}
if [[ -z "$PREFIX" ]]; then
  echo 'SKIP: set NIFT_EMBED_PREFIX to a staged Nift embedding install prefix' >&2
  exit 0
fi
PC="$PREFIX/lib/pkgconfig"
[[ -f "$PC/nift.pc" ]] || { echo "FAIL: NIFT_EMBED_PREFIX has no lib/pkgconfig/nift.pc: $PREFIX" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat >"$TMP/consumer.c" <<'C'
#include <nift/c_abi.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int has(const nift_bytes *b, const char *needle) {
  size_t n = strlen(needle);
  if (b->length < n) return 0;
  for (size_t i = 0; i + n <= b->length; i++)
    if (memcmp(b->data + i, needle, n) == 0) return 1;
  return 0;
}

int main(void) {
  nift_engine *e = nift_engine_new();
  nift_script_result *r = NULL;
  nift_bytes b = {0};
  if (!e) return 10;

  /* ABI 1.3 advertises the byte-input and output-sink additions. */
  if (strcmp(nift_abi_version(), NIFT_ABI_VERSION) != 0) return 11;
  if (nift_abi_version_major() != 1 || nift_abi_version_minor() < 3) return 12;

  /* Copied byte input: mutating the caller buffer must not change the value. */
  uint8_t input[3] = {0, 65, 255};
  if (nift_engine_set_bytes(e, "payload", 7, input, 3) != NIFT_OK) return 13;
  input[0] = 99;
  const char *script = "return payload";
  if (nift_engine_execute(e, script, strlen(script), "<contract>", 10, NULL, NULL, 0, &r) != NIFT_OK) return 14;
  if (!r || !nift_script_result_ok(r)) return 15;
  if (nift_script_result_value_bytes(r, &b) != NIFT_OK || b.length != 3 ||
      b.data[0] != 0 || b.data[1] != 65 || b.data[2] != 255) return 16;
  /* A mismatched accessor on a bytes result is an argument error, not a failure. */
  nift_string js = {0};
  if (nift_script_result_value_json(r, &js) != NIFT_ERROR_INVALID_ARGUMENT) return 17;
  nift_script_result_free(r); r = NULL;

  /* Execution-scoped stdout/stderr sinks stay separate from the value. */
  const char *prog = "print(\"out\"); err(\"problem\"); return 7";
  if (nift_engine_execute(e, prog, strlen(prog), "<contract>", 10, NULL, NULL, 0, &r) != NIFT_OK) return 18;
  if (!r || !nift_script_result_ok(r)) return 19;
  nift_bytes so = {0}, se = {0};
  if (nift_script_result_stdout(r, &so) != NIFT_OK || !has(&so, "out")) return 20;
  if (nift_script_result_stderr(r, &se) != NIFT_OK || !has(&se, "problem")) return 21;
  nift_string val = {0};
  if (nift_script_result_value_json(r, &val) != NIFT_OK || val.length != 1 || val.data[0] != '7') return 22;
  nift_script_result_free(r);

  nift_engine_free(e);
  return 0;
}
C
export PKG_CONFIG_PATH="$PC${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
# shellcheck disable=SC2086
$CC -std=c11 $(pkg-config --cflags nift) "$TMP/consumer.c" $(pkg-config --libs nift) \
  -Wl,-rpath,"$PREFIX/lib" -o "$TMP/consumer"
"$TMP/consumer"
echo 'v4.6 embedding consumer smoke passed'
