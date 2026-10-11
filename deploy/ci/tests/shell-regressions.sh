#!/usr/bin/env bash
# No real Docker calls: deliberately failing command doubles exercise the scripts.
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root" || exit 1
failed=0
expect() {
  local label="$1"; shift
  if "$@"; then echo "PASS $label"; else echo "FAIL $label"; failed=$((failed + 1)); fi
}
if [[ -f deploy/ci/check-output.sh ]]; then
  source deploy/ci/check-output.sh
else
  eval "$(sed -n '/^no_fail_lines()/p' deploy/ci/sale-check.sh)"
fi
silent_error() { echo 'MongoServerError: connection closed'; return 17; }
assertion_error() { echo 'FAIL validator assertion'; return 0; }
success() { echo 'PASS validator assertion'; return 0; }
rejects_command_error() { ! no_fail_lines silent_error; }
rejects_assertion_error() { ! no_fail_lines assertion_error; }
expect 'nonzero exit without FAIL is rejected' rejects_command_error
expect 'FAIL assertion with exit zero is rejected' rejects_assertion_error
expect 'successful assertions are accepted' no_fail_lines success

tmp=$(mktemp -d)
trap 'rm -f "$tmp/bin/docker" "$tmp/bin/sleep" "$tmp/docker.log" "$tmp/sale.out" "$tmp/start.out"; rmdir "$tmp/bin" "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$*" in
  *'container inspect'*|*'inspect synkro-mongo'*)
    # Safe check scripts require an explicitly disposable labelled container.
    if [[ "$*" == *'Tmpfs'* ]]; then echo 'tmpfs'; else echo 'true'; fi
    exit 0 ;;
  *'compose'*'rollback-count'*)
    if [[ "${MOCK_ROLLBACK_MODE:-exit}" == suppressed ]]; then
      echo 'ChangeSet sale-008 failed, but failOnError was false. Error: rollback denied'; exit 0
    fi
    echo 'MongoServerError: rollback denied'; exit 23 ;;
  *'compose'*) echo 'UPDATE SUMMARY'; echo 'Run: 0'; exit 0 ;;
  *'exec'*) cat >/dev/null; echo 'PASS simulated assertion'; exit 0 ;;
  *'network inspect'*) exit 0 ;;
  *'ps'*) echo 'synkro-mongo'; exit 0 ;;
esac
exit 0
MOCK
chmod +x "$tmp/bin/docker"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/sleep"
export MOCK_LOG="$tmp/docker.log"
export PATH="$tmp/bin:$PATH"
rollback_stops() {
  : > "$MOCK_LOG"
  CI_MONGO_CONTAINER=synkro-mongo bash deploy/ci/sale-check.sh > "$tmp/sale.out" 2>&1
  local status=$?
  [[ $status -ne 0 ]] || return 1
  grep -q 'rollback denied' "$tmp/sale.out" || return 1
  # There must be no update after the rollback command.
  ! awk '/rollback-count/ { rollback=1; next } rollback && /compose.*update/ { bad=1 } END { exit !bad }' "$MOCK_LOG"
}
existing_container_safe() {
  : > "$MOCK_LOG"
  bash deploy/ci/start-replica-set.sh > "$tmp/start.out" 2>&1
  local status=$?
  [[ $status -ne 0 ]] && ! grep -Eq '(^rm |^run |^exec |^restart |^network create)' "$MOCK_LOG"
}
expect 'failed rollback stops before reapplication' rollback_stops
export MOCK_ROLLBACK_MODE=suppressed
expect 'suppressed rollback failure stops before reapplication' rollback_stops
unset MOCK_ROLLBACK_MODE
expect 'bootstrap refuses any existing container before mutation' existing_container_safe
[[ $failed -eq 0 ]]
