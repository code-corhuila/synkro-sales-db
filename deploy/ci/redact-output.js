// CI diagnostics must retain the error while omitting connection credentials.
let output = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { output += chunk; });
process.stdin.on('end', () => {
  process.stdout.write(require('../secret-output.js').sanitize(output));
});
