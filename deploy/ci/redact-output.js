// CI diagnostics must retain the error while omitting connection credentials.
let output = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { output += chunk; });
process.stdin.on('end', () => {
  for (const password of [process.env.CI_ADMIN_PASSWORD, process.env.CI_SALES_APP_PASSWORD]) {
    if (!password) continue;
    for (const value of [password, encodeURIComponent(password)]) {
      output = output.split(value).join('[REDACTED]');
    }
  }
  output = output.replace(/mongodb(?:\+srv)?:\/\/[^\s"'`]+/gi, '[REDACTED]');
  process.stdout.write(output);
});
