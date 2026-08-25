'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');

test('staging guard requires production API denylist and verified production hosts are documented', () => {
  const guard = fs.readFileSync(path.join(root, 'scripts/staging/verify-staging-target.ps1'), 'utf8');
  const env = fs.readFileSync(path.join(root, 'STAGING_SAFETY_GUARD.md'), 'utf8');
  assert.match(guard, /AADHYANT_PRODUCTION_DENYLIST_API_HOSTS/);
  assert.match(guard, /Production API\/Edge host detected/);
  assert.match(env, /AADHYANT_PRODUCTION_DENYLIST_API_HOSTS/);
});

test('Admin detail mutation is RPC-only and fails closed for unsupported requirement notes', () => {
  const admin = fs.readFileSync(path.join(root, 'admin/admin.js'), 'utf8');
  assert.doesNotMatch(admin, /client\.from\(table\)\.update/);
  assert.match(admin, /update_recruitment_candidate/);
  assert.match(admin, /set_company_requirement_stage/);
  assert.match(admin, /Internal notes are unavailable in the safe requirement workflow/);
});

test('production browser dependency and config binding are explicit', () => {
  const builder = fs.readFileSync(path.join(root, 'scripts/build-production-artifact.js'), 'utf8');
  const client = fs.readFileSync(path.join(root, 'supabase-client.js'), 'utf8');
  assert.match(builder, /2\.112\.4/);
  assert.match(builder, /productionCspMeta/);
  assert.match(client, /supabaseProjectRef/);
  assert.match(client, /parsedUrl\.hostname/);
});
