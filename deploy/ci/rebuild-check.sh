#!/usr/bin/env bash
# Rebuild check for the migration runner, against the replica set started by
# start-replica-set.sh. Run from the repository root.
set -uo pipefail

export MONGODB_URI="${MONGODB_URI:-mongodb://admin:${CI_ADMIN_PASSWORD:-ci-admin-pw}@synkro-mongo:27017}"
export MONGODB_DATABASE="${MONGODB_DATABASE:-sales}"
export MONGODB_OPTIONS="${MONGODB_OPTIONS:-replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000}"
RUNNER_TIMEOUT="${RUNNER_TIMEOUT:-90}"

run_migrations() {
  timeout "$RUNNER_TIMEOUT" docker compose -f deploy/compose.yml run --rm --build -T sales-db-migrate update 2>&1
}

fail() { echo "FAIL: $*" >&2; exit 1; }

# Collections the migrations created, i.e. all but Liquibase's own bookkeeping.
domain_collections() {
  docker exec synkro-mongo mongosh --quiet "$MONGODB_DATABASE" --eval '
    db.getCollectionNames().filter(n => !n.startsWith("DATABASECHANGELOG")).length'
}

echo "== Case 1: empty changelog on a fresh replica set"
out=$(run_migrations); status=$?
echo "$out" | tail -n 12
[ "$status" -eq 0 ] || fail "case 1: runner exited $status"
[ "$(domain_collections)" = "0" ] || fail "case 1: expected zero collections created by the migrations"
echo "PASS case 1: runner succeeded, zero collections created"

echo "== Case 2: apply again, expect zero additional changes"
out=$(run_migrations); status=$?
echo "$out" | tail -n 12
[ "$status" -eq 0 ] || fail "case 2: runner exited $status"
echo "$out" | grep -Eq 'Run:[[:space:]]+0$' || fail "case 2: update reported changes"
echo "PASS case 2: zero additional changes"

echo "== Case 3: invalid connection string must fail fast and visibly"
start=$(date +%s)
out=$(MONGODB_URI="mongodb://no-such-host:27017" run_migrations); status=$?
elapsed=$(( $(date +%s) - start ))
echo "$out" | grep -E 'MongoTimeoutException|Exception Primary Reason' | head -n 3
[ "$status" -ne 0 ] || fail "case 3: runner succeeded against an invalid host"
[ "$status" -ne 124 ] || fail "case 3: runner hung until the ${RUNNER_TIMEOUT}s timeout"
echo "$out" | grep -q 'MongoTimeoutException' || fail "case 3: failure is not the identifiable connection error"
echo "PASS case 3: runner failed with exit $status in ${elapsed}s (MongoTimeoutException)"
