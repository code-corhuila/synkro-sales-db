try {
  const text = require('fs').readFileSync(process.env.SALES_DIAGNOSTIC_FILE, 'utf8');
  print(require(process.cwd() + '/deploy/secret-output.js').sanitize(text));
} catch {
  quit(1);
}
