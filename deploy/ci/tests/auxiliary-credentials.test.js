const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
test('bootstrap and verification Docker arguments inherit secret names; helper errors are sanitized and nonzero', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sales-auxiliary-'));
  const password = `sentinel-${randomUUID()}/:@$%+!`;
  const uri = `mongodb://admin:${encodeURIComponent(password)}@exclusive:27017`;
  try {
    fs.writeFileSync(path.join(dir, 'docker'), `#!/usr/bin/env node
const fs = require('fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.ARG_LOG, JSON.stringify(args)+'\\n');
if (args[0] === 'container') {
  if (process.env.GUARD_TEST === '1') { console.log(args.join(' ').includes('Tmpfs') ? 'tmpfs' : 'true'); process.exit(0); }
  process.exit(1);
}
if (args[0] === 'network' && args[1] === 'inspect') process.exit(1);
if (args[0] === 'exec' && args.includes('-i')) {
  fs.readFileSync(0);
  console.log('Authentication failed '+process.env.CI_ADMIN_PASSWORD+' '+process.env.LIQUIBASE_COMMAND_URL);
  process.exit(27);
}
`, {mode:0o755});
    const env = {...process.env, PATH: `${dir.replace(/\\/g, '/')}:${path.dirname(process.execPath).replace(/\\/g, '/')}:${process.env.PATH}`,
      ARG_LOG:path.join(dir, 'args.jsonl'), CI_ADMIN_PASSWORD:password, CI_SALES_APP_PASSWORD:password,
      CI_MONGO_CONTAINER:'exclusive', MONGODB_NETWORK:'exclusive', MONGODB_URI:uri};
    const bootstrap = spawnSync(bash, ['deploy/ci/start-replica-set.sh'], {cwd:root, env, encoding:'utf8', timeout:15000});
    assert.ok(!bootstrap.error && bootstrap.status === 0, 'mock bootstrap must complete');
    const helper = spawnSync(bash, ['-c', 'source deploy/ci/ci-env.sh; source deploy/ci/mongosh.sh; ci_mongosh admin'],
      {cwd:root, env, input:'print("fixture");', encoding:'utf8', timeout:15000});
    assert.equal(helper.status, 27);
    assert.ok(helper.stdout.includes('Authentication failed'));
    const guard = spawnSync(bash, ['-c', 'source deploy/ci/ci-env.sh; require_disposable_database'],
      {cwd:root, encoding:'utf8', timeout:15000, env:{...env, GUARD_TEST:'1', CI_CONNECTION_HOST:'foreign',
        MONGODB_URI:uri.replace('@exclusive:', '@foreign:')}});
    assert.notEqual(guard.status, 0, 'connection helper overrides must never weaken the disposable target check');
    assert.ok((guard.stdout+guard.stderr).includes('Refusing database checks'));
    const calls = fs.readFileSync(path.join(dir, 'args.jsonl'), 'utf8');
    assert.ok(![password, encodeURIComponent(password), uri].some(value => calls.includes(value)), 'captured Docker arguments must omit credentials');
    assert.ok(![password, encodeURIComponent(password), uri].some(value => (bootstrap.stdout+bootstrap.stderr+helper.stdout+helper.stderr).includes(value)), 'auxiliary diagnostics must omit credentials');
    const parsed = calls.trim().split('\n').map(JSON.parse);
    assert.ok(parsed.some(args => args.includes('CI_ADMIN_PASSWORD') && args.includes('CI_SALES_APP_PASSWORD')));
    assert.ok(parsed.some(args => args.includes('LIQUIBASE_COMMAND_URL') && args.includes('--nodb')));
  } finally { fs.rmSync(dir, {recursive:true, force:true}); }
});
