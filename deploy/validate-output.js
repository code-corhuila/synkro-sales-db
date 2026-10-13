try {
  require(process.cwd() + '/deploy/migration-state.js').validateMigrationOutput(
    require('fs').readFileSync(process.env.SALES_MIGRATION_OUTPUT, 'utf8'), process.env.SALES_MIGRATION_COMMAND);
} catch (error) {
  print(`${error.name}: ${error.message}`);
  quit(1);
}
