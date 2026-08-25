const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const root = path.join(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'scripts', 'build-staging-artifact.js'), 'utf8');
test('staging builder is isolated and safety bounded', () => {
  assert.match(script, /dist-staging/);
  assert.match(script, /zrluniaccvcdrvfwgrmj/);
  assert.match(script, /aadhyant-web-platform-staging\.pages\.dev/);
  assert.match(script, /STAGING_SUPABASE_PUBLISHABLE_KEY/);
  assert.match(script, /service[_-]?role|postgres/);
  assert.match(script, /localhost|127\\\.0\\\.0\\\.1/);
  assert.match(script, /artifact-manifest\.json/);
  assert.match(script, /aggregatePayloadSha256/);
  assert.doesNotMatch(script, /supabaseProjectRef:\s*['"]wsuctjhbqiedttfnwjvf/);
});
test('production workflow and builder remain unchanged by staging plan', () => {
  assert.match(fs.readFileSync(path.join(root, 'scripts', 'build-production-artifact.js'), 'utf8'), /environment: 'production'/);
  assert.match(fs.readFileSync(path.join(root, '.github', 'workflows', 'pages-production.yml'), 'utf8'), /deploy_production/);
});
