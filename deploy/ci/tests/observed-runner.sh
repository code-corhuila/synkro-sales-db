#!/usr/bin/env bash
set -euo pipefail
umask 077
observation=$(mktemp -d)
export OBSERVATION_STOP="$observation/stop" OBSERVATION_COMMAND="$1"
observer=''
# shellcheck disable=SC2329 # Invoked indirectly by the EXIT trap.
cleanup() {
  if [[ -n $observer ]]; then kill "$observer" 2>/dev/null || true; wait "$observer" 2>/dev/null || true; fi
  rm -f "$observation/stop" "$observation/report"
  rmdir "$observation"
}
trap cleanup EXIT
mongosh --nodb --quiet --file deploy/ci/tests/observe-processes.js > "$observation/report" 2>&1 &
observer=$!
for _ in $(seq 1 100); do
  grep -q 'OBSERVER READY' "$observation/report" && break
  kill -0 "$observer" || { echo 'FAIL process observer startup'; exit 1; }
  sleep 0.1
done
grep -q 'OBSERVER READY' "$observation/report" || { echo 'FAIL process observer readiness'; exit 1; }
status=0
bash deploy/migrate.sh "$@" || status=$?
touch "$OBSERVATION_STOP"
observed=0
wait "$observer" || observed=$?
observer=''
# Report consists only of constant results and process names, never cmdlines.
cat "$observation/report"
[[ $observed -eq 0 ]] || exit "$observed"
[[ -z $(find /tmp -maxdepth 2 -type f \( -name output -o -name liquibase \) -print) ]] || { echo 'FAIL diagnostic cleanup'; exit 1; }
exit "$status"
