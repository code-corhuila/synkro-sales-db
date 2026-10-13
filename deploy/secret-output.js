// Shared by the supported runner and CI. Secrets are data, never executable source.
function sanitize(text, env = process.env) {
  const secrets = new Set();
  const add = value => {
    if (!value) return;
    secrets.add(value);
    secrets.add(encodeURIComponent(value));
  };
  for (const name of ['LIQUIBASE_COMMAND_PASSWORD', 'MONGO_ADMIN_PASSWORD', 'CI_ADMIN_PASSWORD', 'CI_SALES_APP_PASSWORD']) add(env[name]);
  for (const name of ['LIQUIBASE_COMMAND_URL', 'MONGODB_URI']) {
    const uri = env[name];
    if (!uri) continue;
    secrets.add(uri);
    const match = uri.match(/^mongodb(?:\+srv)?:\/\/([^@/]*?)@/i);
    if (match) {
      const password = match[1].slice(match[1].indexOf(':') + 1);
      add(password);
      try { add(decodeURIComponent(password)); } catch { /* malformed URI is still masked */ }
    }
  }
  let output = String(text);
  // Escape casing is insensitive; surrounding literal password casing is exact.
  for (const secret of [...secrets].sort((a, b) => b.length - a.length)) {
    const pattern = secret.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%([0-9a-f]{2})/gi,
      (_, hex) => '%' + [...hex].map(c => /[a-f]/i.test(c) ? `[${c.toLowerCase()}${c.toUpperCase()}]` : c).join(''));
    output = output.replace(new RegExp(pattern, 'g'), '[REDACTED]');
  }
  return output.replace(/mongodb(?:\+srv)?:\/\/[^\s"'`<>]+/gi, '[REDACTED]');
}
module.exports = {sanitize};
