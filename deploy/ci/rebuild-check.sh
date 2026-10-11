#!/usr/bin/env bash
# Rebuild check for the migration runner, against the replica set started by
# start-replica-set.sh. Run from the repository root.
set -euo pipefail

source "$(dirname "$0")/ci-env.sh"
require_disposable_database
RUNNER_TIMEOUT="${RUNNER_TIMEOUT:-90}"

run_migrations() {
  timeout "$RUNNER_TIMEOUT" docker compose --env-file .env.example -f deploy/compose.yml run --rm --build -T sales-db-migrate update 2>&1
}

fail() { echo "FAIL: $1" >&2; exit "${2:-1}"; }

print_output() {
  printf '%s\n' "$1" | CI_ADMIN_PASSWORD="${CI_ADMIN_PASSWORD:-ci-admin-pw}" \
    CI_SALES_APP_PASSWORD="${CI_SALES_APP_PASSWORD:-ci-sales-app-pw}" \
    node "$(dirname "$0")/redact-output.js"
}

# Collections the migrations created (comma-separated), i.e. all but Liquibase's own bookkeeping.
domain_collections() {
  docker exec "$CI_MONGO_CONTAINER" mongosh --quiet "mongodb://admin:${CI_ADMIN_PASSWORD:-ci-admin-pw}@localhost:27017/${MONGODB_DATABASE}?authSource=admin" --eval '
    print(db.getCollectionNames().filter(n => !n.startsWith("DATABASECHANGELOG")).join(","))'
}

echo "== Case 1: first apply on a fresh replica set"
status=0
out=$(run_migrations) || status=$?
if [ "$status" -ne 0 ]; then
  print_output "$out"
  fail "case 1: runner exited $status" "$status"
fi
print_output "$out" | tail -n 12
collections=$(domain_collections) || fail 'case 1: collection query failed'
[ "$collections" = "sale" ] || fail "case 1: expected exactly the sale collection"
echo "PASS case 1: runner succeeded, the sale collection exists"

echo "== Case 2: apply again, expect zero additional changes"
status=0
out=$(run_migrations) || status=$?
if [ "$status" -ne 0 ]; then
  print_output "$out"
  fail "case 2: runner exited $status" "$status"
fi
print_output "$out" | tail -n 12
echo "$out" | grep -Eq 'Run:[[:space:]]+0$' || fail "case 2: update reported changes"
echo "PASS case 2: zero additional changes"

echo "== Case 3: invalid connection string must fail fast and visibly"
start=$(date +%s)
status=0
out=$(MONGODB_URI="mongodb://no-such-host:27017" run_migrations) || status=$?
elapsed=$(( $(date +%s) - start ))
echo "case 3: runner exited $status in ${elapsed}s (outer timeout: ${RUNNER_TIMEOUT}s)"
# Keep the complete sanitized output: an early Compose/build/startup failure
# must be diagnosable, and must never count as the expected connection failure.
print_output "$out"
[ "$status" -ne 0 ] || fail "case 3: runner succeeded against an invalid host"
[ "$status" -ne 124 ] || fail "case 3: runner hung until the ${RUNNER_TIMEOUT}s timeout" "$status"
# GitHub's DNS resolver can fail immediately instead of timing out in server
# selection. Only accept that network diagnostic for the deliberate test host.
grep -Eq 'MongoTimeoutException|MongoServerSelectionError|^MongoNetworkError: getaddrinfo ENOTFOUND no-such-host[[:space:]]*$' <<< "$out" || fail "case 3: failure is not the identifiable connection error" "$status"
echo "PASS case 3: runner failed with exit $status in ${elapsed}s (MongoDB connection error)"
