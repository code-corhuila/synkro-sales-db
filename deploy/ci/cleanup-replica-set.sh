#!/usr/bin/env bash
set -euo pipefail
source deploy/ci/ci-env.sh
require_disposable_database
owner=$(docker container inspect --format '{{index .Config.Labels "com.synkro.sales-db.test-run"}}' "$CI_MONGO_CONTAINER")
[[ $owner == "$CI_MONGO_CONTAINER" ]] || { echo 'Refusing cleanup: test ownership mismatch'; exit 1; }
docker rm -f "$CI_MONGO_CONTAINER" > /dev/null
owner=$(docker network inspect --format '{{index .Labels "com.synkro.sales-db.test-run"}}' "$MONGODB_NETWORK")
if [[ $owner == "$CI_MONGO_CONTAINER" ]]; then docker network rm "$MONGODB_NETWORK" > /dev/null; fi
echo 'PASS cleanup: only owned disposable container and network removed; no volumes'
