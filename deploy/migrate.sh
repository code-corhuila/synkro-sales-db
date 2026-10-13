#!/usr/bin/env bash
# Supported entrypoint: one environment connection, read-only guards, private diagnostics.
set +x +v
set -euo pipefail
cd /liquibase/changelog-root
[[ $# -gt 0 ]] || set -- update
export LIQUIBASE_LOG_LEVEL=info
# The pinned launcher expands JAVA_OPTS into Java arguments. Reject inherited
# JVM injection, including JVM-recognized environment hooks.
unset JAVA_OPTS JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS
case "$1" in
  update)
    [[ $# -eq 1 ]] || { echo 'update accepts no overrides; configure the Compose environment' >&2; exit 2; } ;;
  status)
    [[ $# -eq 1 || ( $# -eq 2 && $2 == --verbose ) ]] || { echo 'status accepts only --verbose' >&2; exit 2; } ;;
  rollback-count)
    [[ $# -eq 2 && $2 =~ ^--count=[0-9]+$ ]] || { echo 'rollback-count requires --count=N' >&2; exit 2; } ;;
  history|validate|--version|--help)
    [[ $# -eq 1 ]] || { echo 'Command accepts no overrides; configure the Compose environment' >&2; exit 2; } ;;
  *) echo 'Unsupported command; use update (without overrides), status, history, validate or rollback-count' >&2; exit 2 ;;
esac
if [[ $1 != --version && $1 != --help && -z ${LIQUIBASE_COMMAND_URL:-} ]]; then
  echo 'ConfigurationError: set LIQUIBASE_COMMAND_URL' >&2
  exit 2
fi
umask 077
diagnostics=$(mktemp -d)
output="$diagnostics/output"
raw="$diagnostics/liquibase"
child=''
cleanup() { rm -f "$output" "$raw"; rmdir "$diagnostics"; }
terminate() {
  if [[ -n $child ]]; then kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
  exit "$1"
}
trap cleanup EXIT
trap 'terminate 130' INT
trap 'terminate 143' TERM
# Capture every subprocess, including startup errors and non-update commands.
# A sanitizer failure publishes a constant diagnostic, never raw data.
run_private() {
  local status=0 sanitized=0
  "$@" > "$output" 2>&1 &
  child=$!
  wait "$child" || status=$?
  child=''
  SALES_DIAGNOSTIC_FILE="$output" mongosh --nodb --quiet --file deploy/publish-output.js 2>/dev/null || sanitized=$?
  if [[ $sanitized -ne 0 ]]; then
    echo 'DiagnosticError: unable to sanitize output' >&2
    [[ $status -ne 0 ]] || status=$sanitized
  fi
  return "$status"
}
if [[ $1 == update ]]; then
  export SALES_VALIDATION_PHASE=preflight
  run_private mongosh --nodb --quiet --file deploy/validate-state.js
  unset SALES_VALIDATION_PHASE
fi
run_private /liquibase/docker-entrypoint.sh "$@"
if [[ $1 == update || $1 == rollback-count ]]; then
  # Preserve RAW analysis semantics before run_private reuses its output file.
  cp "$output" "$raw"
  export SALES_MIGRATION_OUTPUT="$raw" SALES_MIGRATION_COMMAND="$1"
  run_private mongosh --nodb --quiet --file deploy/validate-output.js
fi
if [[ $1 == update ]]; then
  export SALES_VALIDATION_PHASE=postflight
  run_private mongosh --nodb --quiet --file deploy/validate-state.js
fi
