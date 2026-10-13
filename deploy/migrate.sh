#!/usr/bin/env bash
# The supported Compose entrypoint validates BEFORE immutable permissive
# changesets run and AFTER Liquibase succeeds. Direct Liquibase bypasses it.
set -euo pipefail
cd /liquibase/changelog-root
[[ $# -gt 0 ]] || set -- update
# The pinned extension reports suppressed exceptions at INFO; keep that evidence
# available even if a caller configured a quieter log level.
export LIQUIBASE_LOG_LEVEL=info
case "${1:-update}" in
  update|rollback-count)
    # Connection options belong in LIQUIBASE_COMMAND_URL. Disallow command-line
    # overrides that could make Liquibase and mongosh validate different targets.
    if [[ $1 == update ]]; then
      [[ $# -eq 1 ]] || { echo 'update accepts no overrides; configure the Compose environment' >&2; exit 2; }
      : "${LIQUIBASE_COMMAND_URL:?set the migration URL}"
      SALES_VALIDATION_PHASE=preflight mongosh "$LIQUIBASE_COMMAND_URL" --quiet --file deploy/validate-state.js
    fi
    output=$(mktemp)
    trap 'rm -f "$output"' EXIT
    status=0
    /liquibase/docker-entrypoint.sh "$@" > "$output" 2>&1 || status=$?
    cat "$output"
    [[ $status -eq 0 ]] || exit "$status"
    SALES_MIGRATION_OUTPUT="$output" SALES_MIGRATION_COMMAND="$1" mongosh --nodb --quiet --file deploy/validate-output.js
    if [[ $1 == update ]]; then
      SALES_VALIDATION_PHASE=postflight mongosh "$LIQUIBASE_COMMAND_URL" --quiet --file deploy/validate-state.js
    fi
    ;;
  status|history|validate|--version|--help) exec /liquibase/docker-entrypoint.sh "$@" ;;
  *) echo 'Unsupported command; use update (without overrides), status, history, validate or rollback-count' >&2; exit 2 ;;
esac
