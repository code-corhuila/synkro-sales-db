// Executed inside the real pinned runner image. Never publish captured arguments.
const fs = require('fs');
const secret = process.env.CI_ADMIN_PASSWORD;
const encoded = encodeURIComponent(secret);
const found = new Set();
let failures = 0, privateFiles = 0;
const sample = () => {
  for (const pid of fs.readdirSync('/proc').filter(n => /^\d+$/.test(n))) {
    try {
      const args = fs.readFileSync(`/proc/${pid}/cmdline`, 'utf8');
      if (!args) continue;
      const executable = args.split('\0')[0].split('/').pop();
      if (['bash', 'java', 'mongosh'].includes(executable)) found.add(executable);
      if ([secret, encoded, process.env.LIQUIBASE_COMMAND_URL].filter(Boolean).some(value => args.includes(value))) failures++;
    } catch (error) { if (!['ENOENT', 'ESRCH', 'EACCES'].includes(error.code)) throw error; }
  }
  for (const dir of fs.readdirSync('/tmp').filter(n => n.startsWith('tmp.'))) {
    try {
      const base = '/tmp/'+dir;
      if (!fs.statSync(base).isDirectory()) continue;
      for (const file of ['output', 'liquibase']) {
        if (!fs.existsSync(base+'/'+file)) continue;
        privateFiles++;
        if ((fs.statSync(base).mode & 0o777) !== 0o700 || (fs.statSync(base+'/'+file).mode & 0o777) !== 0o600) failures++;
      }
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
};
print('OBSERVER READY');
// Return a promise so mongosh waits for the observer rather than exiting after
// scheduling a timer (unlike Node, its script lifecycle does not retain timers).
new Promise(resolve => {
const timer = setInterval(() => {
  sample();
  if (fs.existsSync(process.env.OBSERVATION_STOP)) {
    clearInterval(timer);
    const required = process.env.OBSERVATION_COMMAND === 'update' ? ['bash', 'mongosh', 'java'] : ['bash', 'java'];
    if (failures || !privateFiles || required.some(name => !found.has(name))) {
      print('FAIL real process arguments or private diagnostics'); quit(1);
    }
    print('PASS real process arguments: '+required.join(', ')+'; private diagnostics 0700/0600');
    resolve();
  }
}, 10);
});
