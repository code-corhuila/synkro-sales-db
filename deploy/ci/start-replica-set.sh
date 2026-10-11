#!/usr/bin/env bash
# Starts a throwaway single-node replica set `rs0` named like the real instance
# (synkro-mongo on the `platform` network), so the runner's compose file is
# exercised unchanged. No access control: CI only; the real one has it.
set -euo pipefail

docker network inspect platform > /dev/null 2>&1 || docker network create platform > /dev/null
docker rm -f synkro-mongo > /dev/null 2>&1 || true
docker run -d --name synkro-mongo --network platform mongo:7.0 --replSet rs0 --bind_ip_all > /dev/null

mongosh() { docker exec synkro-mongo mongosh --quiet "$@"; }

for _ in $(seq 1 30); do
  mongosh --eval 'db.adminCommand({ ping: 1 }).ok' 2> /dev/null | grep -q 1 && break
  sleep 1
done
# The member host must be the name the runner dials; the default is the container ID.
mongosh --eval 'rs.initiate({ _id: "rs0", members: [{ _id: 0, host: "synkro-mongo:27017" }] }).ok' > /dev/null
for _ in $(seq 1 30); do
  mongosh --eval 'db.hello().isWritablePrimary' 2> /dev/null | grep -q true && { echo "replica set rs0 ready"; exit 0; }
  sleep 1
done
echo "replica set rs0 did not become primary" >&2
exit 1
