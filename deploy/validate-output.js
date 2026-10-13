try {
  require(process.cwd() + '/deploy/migration-state.js').validateMigrationOutput(
    require('fs').readFileSync(process.env.SALES_MIGRATION_OUTPUT, 'utf8'), process.env.SALES_MIGRATION_COMMAND);
} catch (error) {
  print(require(process.cwd() + '/deploy/secret-output.js').sanitize(`${error.name}: ${error.message}`));
  quit(1);
}
