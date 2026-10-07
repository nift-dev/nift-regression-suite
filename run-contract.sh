#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIFT_BIN="${NIFT_BIN:-${1:-nift}}"

if [[ "$NIFT_BIN" == */* && -x "$NIFT_BIN" ]]; then
  NIFT_BIN="$(cd "$(dirname "$NIFT_BIN")" && pwd)/$(basename "$NIFT_BIN")"
elif command -v "$NIFT_BIN" >/dev/null 2>&1; then
  NIFT_BIN="$(command -v "$NIFT_BIN")"
else
  echo "FAIL: NIFT_BIN not found: $NIFT_BIN" >&2
  exit 2
fi
export NIFT_BIN

# Contract modules deliberately change directory. Keep host-supplied artifact
# paths stable across those directory changes, including the documented
# NIFT_BIN=../nift/nift invocation from this repository.
if [[ -n "${NIFT_EMBED_PREFIX:-}" ]]; then
  if [[ ! -d "$NIFT_EMBED_PREFIX" ]]; then
    echo "FAIL: NIFT_EMBED_PREFIX not found: $NIFT_EMBED_PREFIX" >&2
    exit 2
  fi
  NIFT_EMBED_PREFIX="$(cd "$NIFT_EMBED_PREFIX" && pwd)"
  export NIFT_EMBED_PREFIX
fi

# Optional expected candidate version (e.g. 4.6.0). When supplied by the hosted
# workflow or a local release-validation run, the historical version assertion
# checks it exactly; when absent, only a well-formed semantic version is
# required. Never bake the current release number into historical modules.
if [[ -n "${NIFT_EXPECT_VERSION:-}" ]]; then
  NIFT_EXPECT_VERSION="${NIFT_EXPECT_VERSION#v}"
  export NIFT_EXPECT_VERSION
fi

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
# Nift projects and interacts only through the executable + documented artifacts.
CONTRACT_TESTS=(
  json_schema_integration_smoke.sh
  parser_content_smoke.sh
  diagnostics_smoke.sh
  comments_smoke.sh
  json_binding_smoke.sh
  control_flow_smoke.sh
  collection_ops_smoke.sh
  pagination_smoke.sh
  requirements_smoke.sh
  path_alias_smoke.sh
  path_security_smoke.sh
  path_safety_smoke.sh
  metadata_safety_smoke.sh
  cross_feature_smoke.sh
  incremental_new_features_smoke.sh
  parameter_interpolation_smoke.sh
  contracts_smoke.sh
  persistence_concurrency_failure_smoke.sh
  filesystem_recovery_smoke.sh
  minify_integration_smoke.sh
  template_optional_smoke.sh
  init_targets_smoke.sh
  unreadable_source_smoke.sh
  json_six_forms_smoke.sh
  markup_directives_smoke.sh
  v41_template_variables_smoke.sh
  v41_language_smoke.sh
  v41_operator_smoke.sh
  v41_inject_dependency.sh
  v41_duplicate_key_smoke.sh
  v41_certification_adversarial.sh
  v42_structs_smoke.sh
  v42_numeric_literals_smoke.sh
  v43_language_smoke.sh
  v43_scripting_io_smoke.sh
  v43_scripting_inspection_smoke.sh
  v43_scripting_ergonomics_smoke.sh
  v43_managed_file_smoke.sh
  v43_managed_file_editing_smoke.sh
  v43_scripting_smoke.sh
  v43_typed_content_taxonomy_smoke.sh
  v43_frontend_algebra_smoke.sh
  v43_final_language_smoke.sh
  v43_object_expressions_smoke.sh
  v43_hierarchy_smoke.sh
  v43_mundane_surface_smoke.sh
  v44_language_foundation_smoke.sh
  v44_execution_shell_smoke.sh
  v44_packages_smoke.sh
  v44_automation_smoke.sh
  v44_hooks_smoke.sh
  v44_restricted_smoke.sh
  v44_package_hardening_smoke.sh
  v44_module_export_smoke.sh
  v44_minify_native_smoke.sh
  v44_executable_script_smoke.sh
  v44_shell_bare_command_smoke.sh
  v45_cli_invocation_smoke.sh
  v45_host_introspection_smoke.sh
  v45_target_smoke.sh
  v45_jobs_background_smoke.sh
  v45_job_control_smoke.sh
  v45_threads_smoke.sh
  v45_mutex_smoke.sh
  v45_atomics_smoke.sh
  v45_async_smoke.sh
  v45_ffi_smoke.sh
  v45_embed_consumer_smoke.sh
  v45_integration_smoke.sh
  v46_bytes_ffi_smoke.sh
  v46_bytes_smoke.sh
  v46_cli_smoke.sh
  v46_concurrency_smoke.sh
  v46_diagnostics_smoke.sh
  v46_embed_consumer_smoke.sh
  v46_exact_numbers_smoke.sh
  v46_filesystem_types_smoke.sh
  v46_import_ownership_smoke.sh
  v46_output_channels_smoke.sh
  v46_package_graph_smoke.sh
  v46_package_metadata_smoke.sh
  v46_recoverable_errors_smoke.sh
  v46_runtime_utilities_smoke.sh
  v46_streams_smoke.sh
  v47_deep_expression_smoke.sh
  v47_prepared_method_parity_smoke.sh
  v48_package_combined_fixture_smoke.sh
  v48_warn_smoke.sh
)

# Fail closed when a contract file is added but not wired into the canonical runner.
declare -A WIRED=()
for test in "${CONTRACT_TESTS[@]}"; do WIRED["$test"]=1; done
ORPHANS=()
for path in "$ROOT"/contract/*.sh; do
  test="$(basename "$path")"
  [[ ${WIRED[$test]+yes} ]] || ORPHANS+=("$test")
done
if (( ${#ORPHANS[@]} )); then
  printf 'FAIL: contract modules not wired into run-contract.sh:\n' >&2
  printf '  %s\n' "${ORPHANS[@]}" >&2
  exit 2
fi

for test in "${CONTRACT_TESTS[@]}"; do
  run_module "contract/$test" env NIFT_BIN="$NIFT_BIN" bash "$ROOT/contract/$test"
done

if [[ $FAILS -eq 0 ]]; then
  printf '\nPASS: %d contract modules\n' "$MODULES"
  exit 0
fi
printf '\nFAIL: %d of %d contract modules failed\n' "$FAILS" "$MODULES" >&2
exit 1
