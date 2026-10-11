const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {randomUUID} = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const shellPath = value => value.replace(/\\/g, '/');

function run(args = ['update'], mode = 'success', configured = true) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sales-credentials-'));
  const secret = `sentinel-${randomUUID()}/:@$%+!`;
  const uri = `mongodb://admin:${encodeURIComponent(secret)}@fixture:27017/sales?authSource=admin`;
  try {
    fs.mkdirSync(path.join(dir, 'bin'));
    fs.mkdirSync(path.join(dir, 'tmp'));
    // Relocate only the two image-specific paths; execute the real runner body.
    fs.writeFileSync(path.join(dir, 'runner.sh'), fs.readFileSync(path.join(root, 'deploy/migrate.sh'), 'utf8')
      .replaceAll('/liquibase/changelog-root', shellPath(root))
      .replaceAll('/liquibase/docker-entrypoint.sh', shellPath(path.join(dir, 'liquibase'))));
    const double = `#!/usr/bin/env node
const fs = require('fs'), vm = require('vm');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.ARG_LOG, JSON.stringify({tool: process.argv[1], args, phase:process.env.SALES_VALIDATION_PHASE})+'\\n');
if (process.argv[1].endsWith('liquibase')) {
  const stat = fs.statSync('/dev/null');
  console.log('Authentication diagnostic '+process.env.TEST_SECRET+' '+encodeURIComponent(process.env.TEST_SECRET)+' '+process.env.LIQUIBASE_COMMAND_URL);
  if (process.env.TEST_MODE === 'liquibase-error') process.exit(19);
  if (process.env.TEST_MODE === 'suppressed') console.log('Changeset sale-006 failed, but failOnError was false. Error: not authorized '+process.env.LIQUIBASE_COMMAND_URL);
  else console.log('UPDATE SUMMARY\\nRun: 0');
} else {
  const file = args[args.indexOf('--file')+1];
  if (file.endsWith('validate-state.js')) {
    console.log('MongoServerSelectionError: '+process.env.TEST_SECRET+' '+process.env.LIQUIBASE_COMMAND_URL);
    if (process.env.TEST_MODE === process.env.SALES_VALIDATION_PHASE+'-error') process.exit(17);
  } else {
    global.print = console.log;
    global.quit = code => process.exit(code);
    vm.runInThisContext(fs.readFileSync(file, 'utf8'), {filename:file});
  }
}
`;
    // On Windows Node cannot stat a POSIX device; no fixture needs that call.
    for (const file of ['bin/mongosh', 'liquibase']) fs.writeFileSync(path.join(dir, file), double.replace("  const stat = fs.statSync('/dev/null');\n", ''), {mode: 0o755});
    const result = spawnSync(bash, [shellPath(path.join(dir, 'runner.sh')), ...args], {
      cwd: root, encoding: 'utf8', timeout: 15000,
      env: {...process.env, PATH: `${shellPath(path.join(dir, 'bin'))}:${shellPath(path.dirname(process.execPath))}:${process.env.PATH}`,
        LIQUIBASE_COMMAND_URL: configured ? uri : '', TEST_SECRET: secret, TEST_MODE: mode,
        ARG_LOG: path.join(dir, 'args.jsonl'), TMPDIR: shellPath(path.join(dir, 'tmp'))},
    });
    const calls = fs.existsSync(path.join(dir, 'args.jsonl')) ? fs.readFileSync(path.join(dir, 'args.jsonl'), 'utf8').trim().split('\n').map(JSON.parse) : [];
    const output = result.stdout + result.stderr;
    // Never include secret-bearing captured data in assertion messages.
    assert.ok(!result.error, 'runner must execute within the limit');
    assert.ok(![secret, encodeURIComponent(secret), uri].some(s => JSON.stringify(calls).includes(s)), 'captured process arguments must omit credentials');
    assert.ok(![secret, encodeURIComponent(secret), uri].some(s => output.includes(s)), 'published output must omit credentials');
    assert.equal(fs.readdirSync(path.join(dir, 'tmp')).length, 0, 'diagnostic files must be cleaned');
    return {status: result.status, output, calls};
  } finally { fs.rmSync(dir, {recursive:true, force:true}); }
}

test('preflight, Liquibase and postflight arguments and success output protect credentials', () => {
  const result = run();
  assert.equal(result.status, 0);
  assert.deepEqual(result.calls.filter(c => c.phase && c.args.includes('deploy/validate-state.js')).map(c => c.phase), ['preflight', 'postflight']);
  for (const call of result.calls.filter(c => c.args.includes('deploy/validate-state.js'))) assert.ok(call.args.includes('--nodb'));
});
for (const [mode, status, diagnostic] of [
  ['preflight-error', 17, 'MongoServerSelectionError'], ['postflight-error', 17, 'MongoServerSelectionError'],
  ['liquibase-error', 19, 'Authentication'], ['suppressed', 1, 'unexpected suppressed migration error'],
]) test(`${mode} preserves failure and sanitized classification`, () => {
  const result = run(['update'], mode);
  assert.equal(result.status, status);
  assert.ok(result.output.includes(diagnostic));
  if (mode === 'preflight-error') assert.ok(!result.calls.some(c => c.tool.endsWith('liquibase')));
});
test('missing configuration fails safely before any connection', () => {
  const result = run(['update'], 'success', false);
  assert.notEqual(result.status, 0);
  assert.ok(result.output.includes('LIQUIBASE_COMMAND_URL'));
  assert.equal(result.calls.length, 0);
});
for (const args of [['status', '--verbose'], ['history'], ['validate'], ['rollback-count', '--count=10'], ['--help'], ['--version']]) {
  test(`${args[0]} output is sanitized`, () => assert.equal(run(args).status, 0));
}
for (const args of [['update', '--url=override'], ['drop-all'], ['status', '--password=override'], ['rollback-count', '--url=override']]) {
  test(`${args[0]} rejects unsafe arguments before execution`, () => {
    const result = run(args);
    assert.equal(result.status, 2);
    assert.equal(result.calls.length, 0);
  });
}
