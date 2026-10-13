const guard = require(process.cwd() + '/deploy/migration-state.js');
(async () => {
  try {
    if (!process.env.LIQUIBASE_COMMAND_URL) throw new Error('set LIQUIBASE_COMMAND_URL');
    const database = await connect(process.env.LIQUIBASE_COMMAND_URL);
    await guard.validateState(database, process.env.SALES_VALIDATION_PHASE);
    print(`PASS ${process.env.SALES_VALIDATION_PHASE}: sale schema, indexes, roles and sales_app`);
  } catch (error) {
    print(require(process.cwd() + '/deploy/secret-output.js').sanitize(`${error.name}: ${error.message}`));
    quit(1);
  }
})();
