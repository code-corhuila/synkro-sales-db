// Read-only guard for the immutable HU-VEN-05 definitions. Shared by mongosh
// and Node regression tests; no command here creates or repairs an object.
const fs = require('fs');
const path = require('path');
function collectionOptions() {
  const yaml = fs.readFileSync(path.join(__dirname, '../01_ddl/00_collections/changelog.yaml'), 'utf8');
  const uuid = yaml.match(/value: '([^']+)'/)[1];
  const options = yaml.match(/options: \|\s*([\s\S]*?)\n\s+rollback:/)[1];
  return JSON.parse(options.replace(/\$\{uuid_field\}/g, uuid));
}
// Object key order is irrelevant; only set-valued arrays are sorted. Index
// keys are compared separately because compound key order is significant.
function canonical(value, key = '') {
  if (Array.isArray(value)) {
    const result = value.map(v => canonical(v));
    return ['required', 'actions', 'roles', 'privileges'].includes(key)
      ? result.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b))) : result;
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k], k)]));
  }
  return value;
}
const equal = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
function requireMatch(ok, label) {
  if (!ok) throw new Error(`incompatible or missing ${label}; no automatic repair performed`);
}
async function command(database, request) {
  const result = await database.runCommand(request);
  if (result.ok !== 1) throw new Error(`MongoDB command failed (${result.code}): ${result.errmsg}`);
  return result;
}
const indexDefinitions = [
  {name: '_id_', key: {_id: 1}},
  {name: 'idx_sale_date', key: {date: -1}},
  {name: 'idx_sale_created_by_date', key: {createdBy: 1, date: -1}},
  {name: 'idx_sale_customer_id_date', key: {customerId: 1, date: -1}},
  {name: 'uq_sale_idempotency_key', key: {idempotencyKey: 1}, unique: true},
];
async function validateState(database, phase) {
  if (!['preflight', 'postflight'].includes(phase)) throw new Error('invalid validation phase');
  requireMatch(await database.getName() === 'sales', 'target database (expected sales)');
  const complete = phase === 'postflight';
  const collections = (await command(database, {listCollections: 1, filter: {name: 'sale'}})).cursor.firstBatch;
  const info = collections[0];
  if (info) {
    requireMatch(info.type === 'collection' && equal(info.options, collectionOptions()), 'sale collection validator/options');
    const indexes = (await command(database, {listIndexes: 'sale'})).cursor.firstBatch;
    for (const index of indexes) {
      const wanted = indexDefinitions.find(i => i.name === index.name);
      // v and ns are server metadata, not index definitions.
      const definition = Object.fromEntries(Object.entries(index).filter(([k]) => !['v', 'ns'].includes(k)));
      requireMatch(wanted && equal(definition, wanted) &&
        JSON.stringify(Object.entries(index.key)) === JSON.stringify(Object.entries(wanted.key)), `sale index ${index.name}`);
    }
    if (complete) requireMatch(indexes.length === indexDefinitions.length, 'four sale indexes and _id index');
  } else requireMatch(!complete, 'sale collection');

  const roles = (await command(database, {rolesInfo: [{role: 'sales_reader', db: 'sales'},
    {role: 'sales_writer', db: 'sales'}], showPrivileges: true})).roles;
  for (const name of ['sales_reader', 'sales_writer']) {
    const role = roles.find(r => r.role === name && r.db === 'sales');
    if (!role) { requireMatch(!complete, name); continue; }
    const actions = name === 'sales_reader' ? ['find'] : ['find', 'insert', 'update'];
    requireMatch(equal(role.roles, []) && equal(role.privileges,
      [{resource: {db: 'sales', collection: 'sale'}, actions}]), `${name} privileges/inherited roles`);
  }
  const users = (await command(await database.getSiblingDB('admin'), {usersInfo: 'sales_app', showPrivileges: true})).users;
  requireMatch(users.length === 1, 'bootstrapped sales_app user');
  const expected = [{role: 'sales_writer', db: 'sales'}];
  requireMatch(equal(users[0].roles, expected) || (!complete && equal(users[0].roles, [])), 'sales_app roles');
  // Checking exact direct roles plus each role's exact privileges excludes all
  // inherited access to other collections/databases, without exercising writes.
}
function validateMigrationOutput(text, migrationCommand = 'update') {
  let exception = [];
  for (const line of text.split('\n')) {
    if (/Running Changeset:|SEVERE.*ChangeSet.*encountered an exception/.test(line)) exception = [];
    exception.push(line);
    if (/failOnError.*false/i.test(line)) {
      const role = line.includes('sale-006-create-role-sales-reader') ? 'sales_reader' :
        line.includes('sale-008-create-role-sales-writer') ? 'sales_writer' : null;
      const cause = exception.filter(l => /Command failed with error/.test(l));
      const duplicate = migrationCommand === 'update' && role && cause.length === 1 &&
        /error 51002 \(Location51002\)/.test(cause[0]) &&
        cause[0].includes(`Role "${role}@sales" already exists`);
      if (!duplicate) throw new Error(`unexpected suppressed migration error: ${line}`);
      exception = [];
    }
    if (/^FAIL/.test(line)) throw new Error(`failed migration assertion: ${line}`);
  }
}
module.exports = {collectionOptions, validateState, validateMigrationOutput};
