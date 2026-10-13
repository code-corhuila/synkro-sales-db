#!/usr/bin/env bash
# Fail fast: a failed assertion or rollback must prevent any reapplication.
set -euo pipefail
source "$(dirname "$0")/ci-env.sh"
source "$(dirname "$0")/check-output.sh"
source "$(dirname "$0")/mongosh.sh"
require_disposable_database
RUNNER_TIMEOUT="${RUNNER_TIMEOUT:-120}"
CASES_DIR="$(cd "$(dirname "$0")/sale" && pwd)"
runner() { timeout "$RUNNER_TIMEOUT" docker compose --env-file .env.example -f deploy/compose.yml run --rm --build -T sales-db-migrate "$@" 2>&1; }
as_admin() { PHASE="${PHASE:-all}" ci_mongosh admin < "$CASES_DIR/$1"; }
as_sales_app() { ci_mongosh sales_app < "$CASES_DIR/$1"; }
check() {
  local label="$1"; shift
  echo "== $label"
  no_fail_lines "$@"
}
changesets=$(grep -rh '^  - changeSet:' 01_ddl 02_dml 03_dcl | wc -l)
apply() {
  local out status=0
  out=$(runner update) || status=$?
  printf '%s\n' "$out"
  [[ $status -eq 0 ]] || return "$status"
  grep -q 'UPDATE SUMMARY' <<< "$out"
}
structure() { PHASE=structure as_admin cases.js; }
second_apply() {
  local out status=0
  out=$(runner update) || status=$?
  printf '%s\n' "$out"
  [[ $status -eq 0 ]] || return "$status"
  grep -Eq 'Run:[[:space:]]+0$' <<< "$out"
}
rollback() {
  local out status=0
  out=$(runner rollback-count --count="$changesets") || status=$?
  printf '%s\n' "$out"
  [[ $status -eq 0 ]] || return "$status"
  ! grep -qi 'failOnError.*false' <<< "$out"
}
check 'apply migrations' apply
check 'case 1: structure, indexes, roles, grant' structure
check 'cases 2-4: validator and unique index' as_admin cases.js
check 'case 5: permissions as sales_app' as_sales_app permissions.js
check "case 6: full rollback of $changesets changesets" rollback
PHASE=absent check 'case 6: no domain objects or grant remain' as_admin cases.js
check 'case 6: re-apply from empty' apply
check 'case 6: same state after re-apply' structure
check 'case 6: second apply changes nothing' second_apply
echo 'ALL SALE CHECKS PASSED'
