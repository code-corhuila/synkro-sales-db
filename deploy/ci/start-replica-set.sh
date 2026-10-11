#!/usr/bin/env bash
# Starts a throwaway single-node replica set `rs0` named like the real instance
# (synkro-mongo on the `platform` network), so the runner's compose file is
# exercised unchanged. Access control is ON, as in the real instance: the
# administrator below runs the migrations and `sales_app` (created by the
# bootstrap of synkro-infra-mongo in the real one) is what the service uses.
# The credentials are throwaway values for CI and local checks only.
set -euo pipefail

ADMIN_PASSWORD="${CI_ADMIN_PASSWORD:-ci-admin-pw}"
SALES_APP_PASSWORD="${CI_SALES_APP_PASSWORD:-ci-sales-app-pw}"

docker network inspect platform > /dev/null 2>&1 || docker network create platform > /dev/null
docker rm -f synkro-mongo > /dev/null 2>&1 || true
# A replica set with access control needs a key file; generate one in the container.
docker run -d --name synkro-mongo --network platform --entrypoint bash mongo:7.0 -c '
  openssl rand -base64 48 > /tmp/keyfile && chmod 400 /tmp/keyfile && chown mongodb /tmp/keyfile &&
  exec docker-entrypoint.sh mongod --replSet rs0 --bind_ip_all --keyFile /tmp/keyfile' > /dev/null

mongosh() { docker exec synkro-mongo mongosh --quiet "$@"; }

for _ in $(seq 1 30); do
  mongosh --eval 'db.adminCommand({ ping: 1 }).ok' 2> /dev/null | grep -q 1 && break
  sleep 1
done
# The member host must be the name the runner dials; the default is the container ID.
mongosh --eval 'rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "synkro-mongo:27017" }] }).ok' > /dev/null
for _ in $(seq 1 30); do
  mongosh --eval 'db.hello().isWritablePrimary' 2> /dev/null | grep -q true && break
  sleep 1
done
# Localhost exception: the first user can be created without authenticating.
mongosh admin --eval "
  db.createUser({ user: 'admin', pwd: '${ADMIN_PASSWORD}', roles: ['root'] });
  db.auth('admin', '${ADMIN_PASSWORD}');
  db.createUser({ user: 'sales_app', pwd: '${SALES_APP_PASSWORD}', roles: [] });" > /dev/null
echo "replica set rs0 ready (access control on; users: admin, sales_app)"
