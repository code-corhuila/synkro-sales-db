const {test} = require('node:test');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const {sanitize} = require('../../secret-output.js');

test('literal, encoded, mixed escape casing, double encoding and both MongoDB URI schemes are masked', () => {
  const password = `test-${randomUUID()}/:@$%+[]\\!`;
  const encoded = encodeURIComponent(password);
  const uri = `mongodb://admin:${encoded}@server:27017/sales?authSource=admin`;
  const output = sanitize(`Authentication failed ${password}\n${encoded}\n${encoded.replace(/%[0-9A-F]{2}/g, v => v.toLowerCase())}\n${encodeURIComponent(encoded)}\n${uri}\nmongodb+srv://other:unknown@cluster.invalid/sales`, {LIQUIBASE_COMMAND_URL:uri});
  assert.ok(!output.includes(password) && !output.includes('test-'));
  assert.ok(!output.includes('mongodb'));
  assert.ok(output.includes('Authentication failed'));
});
test('malformed URL is sanitized without throwing or obscuring failure class', () => {
  const uri = 'mongodb://admin:test%ZZ@server/sales';
  assert.equal(sanitize(`MongoParseError: ${uri}`, {LIQUIBASE_COMMAND_URL:uri}), 'MongoParseError: [REDACTED]');
});
test('validation consumes the identical environment URI as data and passes its database to the guard', async () => {
  const uri = `mongodb://admin:${encodeURIComponent(`test-${randomUUID()}/:@$%+`)}@server/sales?replicaSet=rs0&authSource=admin`;
  const database = {};
  let connection, validated, output = '';
  const context = {process:{cwd:() => path.resolve(__dirname, '../../..'), env:{LIQUIBASE_COMMAND_URL:uri, SALES_VALIDATION_PHASE:'preflight'}},
    connect: async value => { connection=value; return database; },
    require: file => file.endsWith('migration-state.js') ? {validateState:async (db, phase) => {validated={db,phase};}} : {sanitize},
    print: value => {output+=value;}, quit: () => {throw new Error('unexpected quit');}};
  await vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../validate-state.js'), 'utf8'), context);
  assert.ok(connection === uri, 'shared URI must be passed unchanged');
  assert.equal(validated.db, database);
  assert.equal(validated.phase, 'preflight');
  assert.ok(output.includes('PASS preflight'));
});
test('validation connection failures omit credentials and stack traces', async () => {
  const uri = `mongodb://admin:test-${randomUUID()}@server/sales`;
  let output = '', status;
  await vm.runInNewContext(fs.readFileSync(path.resolve(__dirname, '../../validate-state.js'), 'utf8'), {
    process:{cwd:() => '', env:{LIQUIBASE_COMMAND_URL:uri}},
    connect:async () => {throw new Error(`Authentication failed ${uri}`);},
    require:file => file.endsWith('migration-state.js') ? {} : {sanitize:text => sanitize(text, {LIQUIBASE_COMMAND_URL:uri})},
    print:value => {output+=value;}, quit:code => {status=code;},
  });
  assert.equal(status, 1);
  assert.equal(output, 'Error: Authentication failed [REDACTED]');
});
