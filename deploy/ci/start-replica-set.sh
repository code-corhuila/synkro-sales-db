#!/usr/bin/env bash
# Creates a new throwaway replica set; never replaces an existing container.
set -euo pipefail
source "$(dirname "$0")/ci-env.sh"

# An unavailable daemon is not an absent container.
docker info > /dev/null
if docker container inspect "$CI_MONGO_CONTAINER" > /dev/null 2>&1; then
  echo "Refusing to replace existing container: $CI_MONGO_CONTAINER" >&2
  exit 1
fi
docker network inspect "$MONGODB_NETWORK" > /dev/null 2>&1 || \
  docker network create --label "com.synkro.sales-db.test-run=$CI_MONGO_CONTAINER" "$MONGODB_NETWORK" > /dev/null
docker run -d --name "$CI_MONGO_CONTAINER" --network "$MONGODB_NETWORK" \
  --label com.synkro.sales-db.disposable=true \
  --label "com.synkro.sales-db.test-run=$CI_MONGO_CONTAINER" \
  --tmpfs /data/db --tmpfs /data/configdb --entrypoint bash mongo:7.0 -c '
  openssl rand -base64 48 > /tmp/keyfile && chmod 400 /tmp/keyfile && chown mongodb /tmp/keyfile &&
  exec docker-entrypoint.sh mongod --replSet rs0 --bind_ip_all --keyFile /tmp/keyfile --setParameter enableTestCommands=1' > /dev/null

mongosh() { docker exec "$CI_MONGO_CONTAINER" mongosh --quiet "$@"; }
wait_for() {
  local expression="$1"
  for _ in $(seq 1 30); do
    if mongosh --eval "if (!($expression)) quit(1)" > /dev/null 2>&1; then return 0; fi
    sleep 1
  done
  echo "MongoDB readiness timed out: $expression" >&2
  return 1
}
wait_for 'db.adminCommand({ping:1}).ok === 1'
docker exec -e CI_MONGO_CONTAINER "$CI_MONGO_CONTAINER" mongosh --quiet --eval '
  const result = rs.initiate({_id:"rs0", members:[{_id:0, host:process.env.CI_MONGO_CONTAINER+":27017"}]});
  if (result.ok !== 1) throw new Error(JSON.stringify(result));' > /dev/null
wait_for 'db.hello().isWritablePrimary'
docker exec -e CI_ADMIN_PASSWORD -e CI_SALES_APP_PASSWORD \
  "$CI_MONGO_CONTAINER" mongosh --quiet admin --eval '
  db.createUser({user:"admin", pwd:process.env.CI_ADMIN_PASSWORD, roles:["root"]});
  db.auth("admin", process.env.CI_ADMIN_PASSWORD);
  db.createUser({user:"sales_app", pwd:process.env.CI_SALES_APP_PASSWORD, roles:[]});' > /dev/null
echo "replica set rs0 ready in $CI_MONGO_CONTAINER (tmpfs; access control on)"
