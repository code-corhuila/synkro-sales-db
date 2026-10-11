#!/usr/bin/env bash
# Sale collection check: structure, validator, indexes, permissions and full
# rebuild, against the replica set started by start-replica-set.sh. Run from the
# repository root. Case numbers match HU-VEN-05.
set -uo pipefail

ADMIN_PASSWORD="${CI_ADMIN_PASSWORD:-ci-admin-pw}"
SALES_APP_PASSWORD="${CI_SALES_APP_PASSWORD:-ci-sales-app-pw}"
export MONGODB_URI="${MONGODB_URI:-mongodb://admin:${ADMIN_PASSWORD}@synkro-mongo:27017}"
export MONGODB_DATABASE="${MONGODB_DATABASE:-sales}"
export MONGODB_OPTIONS="${MONGODB_OPTIONS:-replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000}"
RUNNER_TIMEOUT="${RUNNER_TIMEOUT:-120}"
CASES_DIR="$(cd "$(dirname "$0")/sale" && pwd)"

runner() { timeout "$RUNNER_TIMEOUT" docker compose -f deploy/compose.yml run --rm --build -T sales-db-migrate "$@" 2>&1; }
# Run a script from deploy/ci/sale in mongosh, as the administrator or as sales_app.
as_admin() { docker exec -i -e PHASE="${PHASE:-all}" synkro-mongo mongosh --quiet --file /dev/stdin \
  "mongodb://admin:${ADMIN_PASSWORD}@localhost:27017/sales?authSource=admin" < "$CASES_DIR/$1"; }
as_sales_app() { docker exec -i synkro-mongo mongosh --quiet --file /dev/stdin \
  "mongodb://sales_app:${SALES_APP_PASSWORD}@localhost:27017/sales?authSource=admin" < "$CASES_DIR/$1"; }

failures=0
check() { # check <label> <command...>
  local label="$1"; shift
  echo "== $label"
  "$@" || { echo "FAILED: $label"; failures=$((failures + 1)); }
}
# `mongosh < file` does not propagate quit(n) reliably; fail on any FAIL line.
no_fail_lines() { local out; out=$("$@" 2>&1); echo "$out"; ! grep -q '^FAIL' <<< "$out"; }

# One changeset per `- changeSet:` entry; the rollback below undoes all of them.
changesets=$(grep -rh '^  - changeSet:' 01_ddl 02_dml 03_dcl | wc -l)

apply() { local out; out=$(runner update); echo "$out" | tail -n 8; echo "$out" | grep -q 'UPDATE SUMMARY'; }
structure() { PHASE=structure no_fail_lines as_admin cases.js; }

check "apply from empty"                          apply
check "case 1: structure, indexes, roles, grant"  structure
check "cases 2-4: validator and unique index"     no_fail_lines as_admin cases.js
check "case 5: permissions as sales_app"          no_fail_lines as_sales_app permissions.js

echo "== case 6: full rollback of $changesets changesets"
runner rollback-count --count="$changesets" | tail -n 6
PHASE=absent no_fail_lines as_admin cases.js || failures=$((failures + 1))

check "case 6: re-apply from empty"               apply
check "case 6: same state after re-apply"         structure
check "case 6: second apply changes nothing"      bash -c "$(declare -f runner); export RUNNER_TIMEOUT='$RUNNER_TIMEOUT'; runner update | grep -Eq 'Run:[[:space:]]+0$'"

[ "$failures" -eq 0 ] && echo "ALL SALE CHECKS PASSED" || { echo "$failures SALE CHECK GROUP(S) FAILED"; exit 1; }
