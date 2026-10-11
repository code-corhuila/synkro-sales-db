const {test} = require('node:test');
const assert = require('node:assert/strict');
const output = (text, command = 'update') => require('../../migration-state.js').validateMigrationOutput(text, command);
test('unexpected suppressed role command fails even if final role exists', () => {
  assert.throws(() => output('Changeset sale-006 failed, but failOnError was false. Error: not authorized'), /suppressed/);
});
test('only expected duplicate role errors are compatible', () => {
  output('Changeset sale-006-create-role-sales-reader failed, but failOnError was false. Error: Command failed with error 51002 (Location51002): \'Role "sales_reader@sales" already exists\'');
  assert.throws(() => output('Changeset sale-006 failed, but failOnError was false. Error: Role "different@other" already exists'), /suppressed/);
});
test('rollback cannot ignore even an otherwise compatible duplicate role error', () => {
  assert.throws(() => output('Changeset sale-006-create-role-sales-reader failed, but failOnError was false. Error: Command failed with error 51002 (Location51002): \'Role "sales_reader@sales" already exists\'', 'rollback-count'), /suppressed/);
});
