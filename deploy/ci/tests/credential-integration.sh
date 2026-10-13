#!/usr/bin/env bash
# Real image + real authenticated disposable replica set. No skips or fallback.
set -euo pipefail
source deploy/ci/ci-env.sh
require_disposable_database
umask 077
tmp=$(mktemp -d)
trap 'rm -f "$tmp/output"; rmdir "$tmp"' EXIT
runner() {
  timeout 90 docker compose --env-file .env.example -f deploy/compose.yml run --rm -T \
    -e CI_ADMIN_PASSWORD --entrypoint bash sales-db-migrate deploy/ci/tests/observed-runner.sh "$@"
}
assert_clean() {
  node deploy/ci/tests/assert-secret-free.js < "$tmp/output"
}
for command in update update 'status --verbose' history validate; do
  # The fixed list contains only public command names, never interpolated data.
  read -r -a args <<< "$command"
  status=0
  runner "${args[@]}" > "$tmp/output" 2>&1 || status=$?
  assert_clean
  if [[ $status -ne 0 ]]; then cat "$tmp/output"; echo 'FAIL real credential regression'; exit 1; fi
  grep -q 'PASS real process arguments' "$tmp/output" || { cat "$tmp/output"; echo 'FAIL missing observer evidence'; exit 1; }
  echo "PASS credentials and process arguments: $command"
done
for command in update status; do
for failure in authentication connection; do
  status=0
  if [[ $failure == authentication ]]; then
    MONGODB_URI=$(CI_ADMIN_PASSWORD="${CI_ADMIN_PASSWORD}-wrong" node deploy/ci/connection.js) \
      timeout 90 docker compose --env-file .env.example -f deploy/compose.yml run --rm -T sales-db-migrate "$command" > "$tmp/output" 2>&1 || status=$?
  else
    MONGODB_URI=$(CI_CONNECTION_HOST=no-such-host node deploy/ci/connection.js) \
      timeout 90 docker compose --env-file .env.example -f deploy/compose.yml run --rm -T sales-db-migrate "$command" > "$tmp/output" 2>&1 || status=$?
  fi
  assert_clean
  [[ $status -ne 0 && $status -ne 124 ]] || { echo "FAIL $failure failure status"; exit 1; }
  if [[ $failure == authentication ]]; then grep -qi 'Authentication' "$tmp/output";
  else grep -Eq 'MongoServerSelectionError|MongoNetworkError|MongoTimeoutException' "$tmp/output"; fi
  echo "PASS sanitized bounded $command $failure failure"
done
done
