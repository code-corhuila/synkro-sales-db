#!/usr/bin/env bash
# No real Docker calls: deliberately failing command doubles exercise the scripts.
set -uo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
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
ignored_error() { echo 'Changeset sale-006 failed, but failOnError was false. Error: not authorized'; return 0; }
rejects_command_error() { ! no_fail_lines silent_error; }
rejects_assertion_error() { ! no_fail_lines assertion_error; }
expect 'nonzero exit without FAIL is rejected' rejects_command_error
expect 'FAIL assertion with exit zero is rejected' rejects_assertion_error
expect 'successful assertions are accepted' no_fail_lines success
rejects_ignored_error() { ! no_fail_lines ignored_error; }
expect 'unexpected suppressed Liquibase failure is rejected' rejects_ignored_error

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$*" in
  *'container inspect'*|*'inspect synkro-mongo'*)
    # Safe check scripts require an explicitly disposable labelled container.
    echo 'true'; exit 0 ;;
  *'compose'*'rollback-count'*) echo 'MongoServerError: rollback denied'; exit 23 ;;
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
expect 'bootstrap refuses any existing container before mutation' existing_container_safe
[[ $failed -eq 0 ]]
