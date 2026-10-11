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
const exception = (role, code, message) => `
Running Changeset: 03_dcl/00_roles/changelog.yaml::sale-006-create-role-sales-reader::SergioAndres17
[time] SEVERE [liquibase.changelog] ChangeSet 03_dcl/00_roles/changelog.yaml::sale-006-create-role-sales-reader::SergioAndres17 encountered an exception.
liquibase.exception.DatabaseException: Could not execute
    at liquibase.nosql.executor.NoSqlExecutor.execute(NoSqlExecutor.java:194)
Caused by: com.mongodb.MongoCommandException: Command failed with error ${code} (Location${code}): '${message || `Role "${role}@sales" already exists`}'
    at com.mongodb.internal.connection.ProtocolHelper.getCommandFailureException(ProtocolHelper.java:175)
[time] INFO [liquibase.changelog] Changeset 03_dcl/00_roles/changelog.yaml::sale-006-create-role-sales-reader::SergioAndres17 failed, but failOnError was false.  Error: Could not execute
`;
test('compatible duplicate is recognized in the real multiline Liquibase exception format', () => {
  output(exception('sales_reader', 51002));
});
test('the corresponding multiline unexpected MongoDB failure is rejected', () => {
  assert.throws(() => output(exception('sales_reader', 13, 'not authorized')), /suppressed/);
});
test('a previous compatible exception cannot conceal a later unexpected failure', () => {
  assert.throws(() => output(exception('sales_reader', 51002) + exception('sales_reader', 13, 'not authorized')), /suppressed/);
});
