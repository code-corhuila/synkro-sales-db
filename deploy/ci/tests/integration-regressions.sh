#!/usr/bin/env bash
# Destructive fixtures are allowed only in this repository's tmpfs CI instance.
set -euo pipefail
source "$(dirname "$0")/../ci-env.sh"
require_disposable_database
source deploy/ci/check-output.sh
admin() {
  docker exec -i "$CI_MONGO_CONTAINER" mongosh --quiet \
    "mongodb://admin:${CI_ADMIN_PASSWORD:-ci-admin-pw}@localhost:27017/sales?authSource=admin" --file /dev/stdin
}
update() { timeout 120 docker compose --env-file /dev/null -f deploy/compose.yml run --rm -T sales-db-migrate update; }
reset_database() {
  admin <<'JS'
db.dropDatabase();
db.getSiblingDB('admin').updateUser('sales_app', {roles: []});
JS
}
prepare_collection() {
  docker exec -i -e DRIFT="$1" "$CI_MONGO_CONTAINER" mongosh --quiet \
    "mongodb://admin:${CI_ADMIN_PASSWORD:-ci-admin-pw}@localhost:27017/sales?authSource=admin" --file /dev/stdin <<'JS'
const fs = require('fs');
const schema = JSON.parse(fs.readFileSync('/tmp/sale-validator.json', 'utf8'));
const options = {validationLevel: 'strict', validationAction: 'error', validator: schema};
switch (process.env.DRIFT) {
  case 'moderate': options.validationLevel = 'moderate'; break;
  case 'warn': options.validationAction = 'warn'; break;
  case 'required': schema.$jsonSchema.required.pop(); break;
  case 'type': schema.$jsonSchema.properties.totalCents.bsonType = 'double'; break;
}
db.createCollection('sale', options);
db.sale.insertOne({_id: 'drift-sentinel'}, {bypassDocumentValidation: true});
JS
}
snapshot() {
  admin <<'JS'
print(EJSON.stringify({collection: db.getCollectionInfos({name:'sale'})[0], docs: db.sale.find().toArray(),
  roles: db.getRoles({showPrivileges:true}), user: db.getSiblingDB('admin').getUser('sales_app')}));
JS
}
tmp=$(mktemp -d)
trap 'rm -f "$tmp/before" "$tmp/after" "$tmp/update"; rmdir "$tmp"' EXIT
docker cp deploy/ci/tests/sale-validator.json "$CI_MONGO_CONTAINER:/tmp/sale-validator.json"
for drift in moderate warn required type; do
  reset_database
  prepare_collection "$drift"
  snapshot > "$tmp/before"
  if update > "$tmp/update" 2>&1; then echo "FAIL accepted collection drift: $drift"; exit 1; fi
  grep -q incompatible "$tmp/update"
  snapshot > "$tmp/after"
  cmp "$tmp/before" "$tmp/after"
  echo "PASS $drift collection rejected without changing UUID, validator or documents"
done
for role in sales_reader sales_writer; do
  reset_database
  admin <<JS
db.createRole({role: '$role', privileges: [{resource:{db:'sales',collection:'sale'}, actions:['find','remove']}], roles:[]});
JS
  snapshot > "$tmp/before"
  if update > "$tmp/update" 2>&1; then echo "FAIL accepted role drift: $role"; exit 1; fi
  grep -q incompatible "$tmp/update"
  snapshot > "$tmp/after"
  cmp "$tmp/before" "$tmp/after"
  echo "PASS incompatible $role rejected without privilege repair"
done
reset_database
prepare_collection compatible
admin <<'JS'
db.createRole({role:'sales_reader', privileges:[{resource:{db:'sales',collection:'sale'}, actions:['find']}], roles:[]});
db.createRole({role:'sales_writer', privileges:[{resource:{db:'sales',collection:'sale'}, actions:['find','insert','update']}], roles:[]});
JS
no_fail_lines update
admin <<'JS'
if (db.sale.countDocuments({_id:'drift-sentinel'}) !== 1) throw new Error('compatible collection was replaced');
JS
echo 'PASS compatible existing collection and roles migrate safely'

# A real server failure in createRole while compatible roles exist used to be
# suppressed, followed by successful updateRole. enableTestCommands is CI-only.
reset_database
admin <<'JS'
db.createRole({role:'sales_reader', privileges:[{resource:{db:'sales',collection:'sale'}, actions:['find']}], roles:[]});
db.createRole({role:'sales_writer', privileges:[{resource:{db:'sales',collection:'sale'}, actions:['find','insert','update']}], roles:[]});
db.adminCommand({configureFailPoint:'failCommand', mode:{times:1}, data:{failCommands:['createRole'], errorCode:13}});
JS
if update > "$tmp/update" 2>&1; then echo 'FAIL suppressed unexpected createRole error'; exit 1; fi
grep -Eq 'not authorized|failOnError|Unauthorized' "$tmp/update"
admin <<'JS'
db.adminCommand({configureFailPoint:'failCommand', mode:'off'});
JS
echo 'PASS unexpected real createRole failure propagates'
reset_database
echo 'ALL MIGRATION REGRESSIONS PASSED'
