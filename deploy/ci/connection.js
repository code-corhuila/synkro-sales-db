// Test-only URI construction; credentials are read as data from the environment.
const user = process.env.CI_CONNECTION_USER || 'admin';
const password = user === 'admin' ? process.env.CI_ADMIN_PASSWORD : process.env.CI_SALES_APP_PASSWORD;
const host = process.env.CI_CONNECTION_HOST || process.env.CI_MONGO_CONTAINER;
process.stdout.write(`mongodb://${user}:${encodeURIComponent(password)}@${host}:27017`);
