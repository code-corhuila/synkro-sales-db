const guard = require(process.cwd() + '/deploy/migration-state.js');
(async () => {
  try {
    await guard.validateState(db, process.env.SALES_VALIDATION_PHASE);
    print(`PASS ${process.env.SALES_VALIDATION_PHASE}: sale schema, indexes, roles and sales_app`);
  } catch (error) {
    print(`${error.name}: ${error.message}`);
    quit(1);
  }
})();
