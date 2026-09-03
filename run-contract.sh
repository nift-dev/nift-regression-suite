#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIFT_BIN="${NIFT_BIN:-${1:-nift}}"

if command -v "$NIFT_BIN" >/dev/null 2>&1; then
  NIFT_BIN="$(command -v "$NIFT_BIN")"
elif [[ -x "$NIFT_BIN" ]]; then
  NIFT_BIN="$(cd "$(dirname "$NIFT_BIN")" && pwd)/$(basename "$NIFT_BIN")"
else
  echo "FAIL: NIFT_BIN not found: $NIFT_BIN" >&2
  exit 2
fi
export NIFT_BIN

FAILS=0
MODULES=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nift-contract-suite.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

run_module(){
  local name="$1"; shift
  MODULES=$((MODULES+1))
  local log="$TMP/${MODULES}.log"
  if "$@" >"$log" 2>&1; then
    printf 'PASS  %s\n' "$name"
  else
    printf 'FAIL  %s\n' "$name" >&2
    cat "$log" >&2
    FAILS=$((FAILS+1))
  fi
}

# Historical black-box contract. Run a disposable copy because it intentionally
# mutates project/output state while testing commands and incremental behavior.
LEGACY="$TMP/legacy"
cp -a "$ROOT/legacy" "$LEGACY"
chmod -R u+rwX "$LEGACY"
run_module "historical + ruthless regression contract" \
  bash -c "cd '$LEGACY' && NIFT_BIN='$NIFT_BIN' bash scripts/run-tests.sh"

# Newer contract modules are implementation-independent: each creates temporary
# Nift projects and interacts only through the executable + documented project files.
for test in \
  json_schema_integration_smoke.sh \
  parser_content_smoke.sh \
  diagnostics_smoke.sh \
  comments_smoke.sh \
  json_binding_smoke.sh \
  control_flow_smoke.sh \
  collection_ops_smoke.sh \
  pagination_smoke.sh \
  requirements_smoke.sh \
  path_security_smoke.sh \
  path_safety_smoke.sh \
  metadata_safety_smoke.sh \
  cross_feature_smoke.sh \
  incremental_new_features_smoke.sh \
  parameter_interpolation_smoke.sh \
  contracts_smoke.sh \
  persistence_concurrency_failure_smoke.sh \
  filesystem_recovery_smoke.sh \
  minify_integration_smoke.sh \
  template_optional_smoke.sh \
  init_targets_smoke.sh \
  unreadable_source_smoke.sh
do
  run_module "contract/$test" env NIFT_BIN="$NIFT_BIN" bash "$ROOT/contract/$test"
done

if [[ $FAILS -eq 0 ]]; then
  printf '\nPASS: %d contract modules\n' "$MODULES"
  exit 0
fi
printf '\nFAIL: %d of %d contract modules failed\n' "$FAILS" "$MODULES" >&2
exit 1
