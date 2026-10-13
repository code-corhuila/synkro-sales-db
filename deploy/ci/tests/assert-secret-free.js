const fs = require('fs');
const output = fs.readFileSync(0, 'utf8');
const secrets = [process.env.CI_ADMIN_PASSWORD, process.env.CI_SALES_APP_PASSWORD].filter(Boolean);
if (secrets.some(value => [value, encodeURIComponent(value)].some(secret => output.includes(secret))) ||
    /mongodb(?:\+srv)?:\/\/[^\s]*@/i.test(output)) {
  console.error('FAIL captured output contains test credentials');
  process.exit(1);
}
