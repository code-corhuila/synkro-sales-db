#!/usr/bin/env bash
# Exercise the complete rebuild check without contacting Docker or MongoDB.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
tmp=$(mktemp -d)
trap 'rm -f "$tmp/bin/docker" "$tmp/bin/timeout" "$tmp/output"; rmdir "$tmp/bin" "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *'container inspect'*)
    if [[ "$*" == *'Tmpfs'* ]]; then echo tmpfs; else echo true; fi ;;
  *'compose'*)
    if [[ $MONGODB_URI == mongodb://no-such-host:27017 ]]; then
      [[ $MONGODB_OPTIONS == 'replicaSet=rs0&authSource=admin&serverSelectionTimeoutMS=5000' ]] || exit 90
      case "$MOCK_FAILURE" in
        connection) echo 'MongoServerSelectionError: Server selection timed out after 5000 ms'; exit 1 ;;
        dns) echo 'MongoNetworkError: getaddrinfo ENOTFOUND no-such-host'; exit 1 ;;
        dns-unrelated) echo 'MongoNetworkError: getaddrinfo ENOTFOUND unrelated-host'; exit 19 ;;
        dns-prefix) echo 'MongoNetworkError: getaddrinfo ENOTFOUND no-such-host-backup'; exit 19 ;;
        network-other) echo 'MongoNetworkError: connect ECONNREFUSED no-such-host:27017'; exit 19 ;;
        compose) echo 'Compose interpolation failed: missing MONGODB_DATABASE'; exit 14 ;;
        startup) echo 'OCI runtime create failed: bash executable not found'; exit 127 ;;
        timeout) echo 'MongoServerSelectionError: still waiting'; exit 124 ;;
        unknown)
          echo 'Unrecognized failure from runner'
          echo 'mongodb://test-user:ci%2Fsecret%3A42@no-such-host:27017/sales?authSource=admin'
          echo 'mongodb+srv://test-user:ci%2Fsecret%3A42@cluster.invalid/sales'
          echo "CI_ADMIN_PASSWORD=$CI_ADMIN_PASSWORD"
          echo "CI_SALES_APP_PASSWORD=$CI_SALES_APP_PASSWORD"
          exit 26 ;;
        success) echo 'Unexpected successful connection'; exit 0 ;;
      esac
    else
      echo 'UPDATE SUMMARY'
      if [[ $MOCK_FAILURE == repeat ]]; then echo 'Run: 1'; else echo 'Run: 0'; fi
    fi ;;
  *'exec'*) echo sale ;;
  *) echo "Unexpected Docker invocation: $*"; exit 91 ;;
esac
MOCK
cat > "$tmp/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
[[ $1 == 9 ]] || exit 92
shift
exec "$@"
MOCK
chmod +x "$tmp/bin/docker" "$tmp/bin/timeout"
export PATH="$tmp/bin:$PATH"
export CI_MONGO_CONTAINER=mock-disposable MONGODB_NETWORK=mock-disposable RUNNER_TIMEOUT=9
export CI_ADMIN_PASSWORD='ci/secret:42' CI_SALES_APP_PASSWORD='app-secret-42'
unset MONGODB_URI MONGODB_DATABASE MONGODB_OPTIONS
failed=0
check() {
  local mode=$1 expected=$2 diagnostic=$3 status=0
  MOCK_FAILURE="$mode" bash deploy/ci/rebuild-check.sh > "$tmp/output" 2>&1 || status=$?
  if [[ $status != "$expected" ]] || ! grep -Fq "$diagnostic" "$tmp/output"; then
    echo "FAIL $mode: expected exit $expected and diagnostic '$diagnostic'; got exit $status"
    # Never dump a deliberately secret-bearing fixture on a failing test.
    failed=$((failed + 1))
    return
  fi
  if [[ $mode == unknown ]]; then
    if grep -Eq 'ci/secret:42|ci%2Fsecret%3A42|app-secret-42|test-user|mongodb(\+srv)?://' "$tmp/output" ||
      ! grep -Fq '[REDACTED]' "$tmp/output"; then
      echo 'FAIL unknown: credentials must be redacted in diagnostics'
      failed=$((failed + 1))
      return
    fi
  fi
  echo "PASS $mode: exit $status, expected diagnostic, credentials protected"
}
check connection 0 'PASS case 3:'
check dns 0 'PASS case 3:'
check dns-unrelated 19 'failure is not the identifiable connection error'
check dns-prefix 19 'failure is not the identifiable connection error'
check network-other 19 'failure is not the identifiable connection error'
check compose 14 'Compose interpolation failed: missing MONGODB_DATABASE'
check startup 127 'OCI runtime create failed: bash executable not found'
check timeout 124 'runner hung until the 9s timeout'
check unknown 26 'Unrecognized failure from runner'
check success 1 'runner succeeded against an invalid host'
check repeat 1 'case 2: update reported changes'
[[ $failed -eq 0 ]]
