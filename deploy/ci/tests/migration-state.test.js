// Expected validator is an independent snapshot of synkro-docs main models.md.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const model = require('./sale-validator.json');
const clone = value => JSON.parse(JSON.stringify(value));
const guardPath = path.resolve(__dirname, '../../migration-state.js');
const guard = () => require(guardPath);
const privileges = actions => [{ resource: { db: 'sales', collection: 'sale' }, actions }];
function state() {
  return {
    collection: { name: 'sale', type: 'collection', options: {
      validationLevel: 'strict', validationAction: 'error', validator: clone(model),
    } },
    roles: ['sales_reader', 'sales_writer'].map(role => ({ role, db: 'sales', roles: [],
      privileges: privileges(role === 'sales_reader' ? ['find'] : ['find', 'insert', 'update']) })),
    user: { user: 'sales_app', roles: [{ role: 'sales_writer', db: 'sales' }] },
    indexes: [
      { name: '_id_', key: { _id: 1 } },
      { name: 'idx_sale_date', key: { date: -1 } },
      { name: 'idx_sale_created_by_date', key: { createdBy: 1, date: -1 } },
      { name: 'idx_sale_customer_id_date', key: { customerId: 1, date: -1 } },
      { name: 'uq_sale_idempotency_key', key: { idempotencyKey: 1 }, unique: true },
    ],
  };
}
function database(s) {
  const admin = { runCommand: () => ({ ok: 1, users: s.user ? [s.user] : [] }) };
  return { getName: () => 'sales', getSiblingDB: () => admin,
    runCommand(command) {
      if (command.listCollections) return { ok: 1, cursor: { id: 0, firstBatch: s.collection ? [s.collection] : [] } };
      if (command.rolesInfo) return { ok: 1, roles: s.roles };
      if (command.listIndexes) return { ok: 1, cursor: { id: 0, firstBatch: s.indexes } };
      throw new Error('unexpected command');
    },
  };
}
test('guard uses the exact approved model', () => assert.deepEqual(guard().collectionOptions().validator, model));
test('fresh database permits preflight, requires final objects', () => {
  const s = state(); s.collection = null; s.roles = []; s.user.roles = []; s.indexes = [];
  guard().validateState(database(s), 'preflight');
  assert.throws(() => guard().validateState(database(s), 'postflight'));
});
test('compatible collection, roles and grant pass without mutations', () => {
  const s = state(); const before = clone(s);
  guard().validateState(database(s), 'preflight'); guard().validateState(database(s), 'postflight');
  assert.deepEqual(s, before);
});
const drift = {
  moderate: s => { s.collection.options.validationLevel = 'moderate'; },
  warn: s => { s.collection.options.validationAction = 'warn'; },
  'missing required field': s => { s.collection.options.validator.$jsonSchema.required.pop(); },
  'wrong monetary type': s => { s.collection.options.validator.$jsonSchema.properties.totalCents.bsonType = 'double'; },
  'wrong nested type': s => { s.collection.options.validator.$jsonSchema.properties.details.items.properties.quantity.bsonType = 'long'; },
  'reader extra action': s => { s.roles[0].privileges[0].actions.push('insert'); },
  'writer remove': s => { s.roles[1].privileges[0].actions.push('remove'); },
  'role inherited privileges': s => { s.roles[1].roles.push({ role: 'readWrite', db: 'other' }); },
  'user another database': s => { s.user.roles.push({ role: 'readWrite', db: 'other' }); },
  'wrong compound index order': s => { s.indexes[2].key = { date: -1, createdBy: 1 }; },
  'wrong index options': s => { s.indexes[4].partialFilterExpression = { active: true }; },
};
for (const [name, mutate] of Object.entries(drift)) test(`rejects ${name} without changing state`, () => {
  const s = state(); mutate(s); const before = clone(s);
  assert.throws(() => guard().validateState(database(s), 'preflight'), /incompatible/);
  assert.deepEqual(s, before);
});
test('unexpected MongoDB command result fails visibly', () => {
  const db = database(state()); db.runCommand = () => ({ ok: 0, code: 13, errmsg: 'not authorized' });
  assert.throws(() => guard().validateState(db, 'preflight'), /not authorized/);
});
test('unexpected MongoDB thrown exception propagates', () => {
  const db = database(state()); db.runCommand = () => { throw new Error('connection closed'); };
  assert.throws(() => guard().validateState(db, 'preflight'), /connection closed/);
});
test('postflight rejects missing role or missing grant', () => {
  const validate = guard().validateState;
  const s = state(); s.roles.pop();
  assert.throws(() => validate(database(s), 'postflight'));
  s.roles = state().roles; s.user.roles = [];
  assert.throws(() => validate(database(s), 'postflight'));
});
test('schema key and required-field ordering do not imply drift', () => {
  const s = state(); s.collection.options.validator.$jsonSchema.required.reverse();
  s.roles[1].privileges[0].actions.reverse();
  guard().validateState(database(s), 'preflight');
});
