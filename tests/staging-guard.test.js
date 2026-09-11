'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const guard = fs.readFileSync(path.join(root, 'scripts', 'staging', 'verify-staging-target.ps1'), 'utf8');
const identity = fs.readFileSync(path.join(root, 'scripts', 'staging', 'verify-staging-identity.ps1'), 'utf8');
const readme = fs.readFileSync(path.join(root, 'scripts', 'staging', 'README.md'), 'utf8');
const migration036 = fs.readFileSync(path.join(root, 'supabase', 'migrations', '036_revoke_public_execute_recruitment_rpcs.sql'), 'utf8').replace(/^\uFEFF/, '');

const migration036Signatures = [
  'public.admin_assign_requirement_owner(uuid,uuid)',
  'public.admin_assign_candidate_owner(uuid,uuid)',
  'public.admin_assign_contractor_owner(uuid,uuid)',
  'public.admin_set_requirement_follow_up(uuid,text,timestamp with time zone)',
  'public.admin_set_candidate_follow_up(uuid,text,timestamp with time zone)',
  'public.admin_set_contractor_follow_up(uuid,text,timestamp with time zone)',
  'public.admin_list_recruitment_attention(integer,integer)',
  'public.admin_correct_requirement_source(uuid,text,text,text,text)',
  'public.admin_correct_candidate_source(uuid,text,text,text,text)',
  'public.admin_correct_contractor_source(uuid,text,text,text,text)',
  'public.admin_list_recruitment_source_options()'
];

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');

function canonicalManifest() {
  const migrationRoot = path.join(root, 'supabase', 'migrations');
  const migrations = fs.readdirSync(migrationRoot)
    .filter((name) => /^(00[7-9]|01[0-9]|02[0-9]|03[0-9]|04[0-8])_.*\.sql$/.test(name))
    .sort();
  const numbers = migrations.map((name) => Number(name.slice(0, 3)));
  assert.deepEqual(numbers, Array.from({ length: 42 }, (_, index) => index + 7));
  const files = [path.join(root, 'supabase', 'schema.sql'), ...migrations.map((name) => path.join(migrationRoot, name))];
  const lines = files.map((file) => `${path.relative(root, file).replaceAll(path.sep, '/')}=${sha256(fs.readFileSync(file))}`);
  return { files, lines, digest: sha256(lines.join('\n')) };
}

test('guard manifest is exact through migration 048 and excludes migration 049+', () => {
  assert.match(guard, /04\[0-8\]/);
  assert.match(guard, /\$expectedNumbers = @\(7\.\.48\)/);
  assert.match(guard, /\$files\.Count -ne 43/);
  assert.match(guard, /schema\.sql plus exactly migrations 007-048/);
  assert.doesNotMatch(guard, /\$expectedNumbers = @\(7\.\.49\)|007-049/);
  assert.match(readme, /migrations 007.048 \(43 files total/);
  assert.match(readme, /Migration 049 and later files are excluded/);
});

test('canonical manifest ordering and aggregate are deterministic', () => {
  const first = canonicalManifest();
  const second = canonicalManifest();
  assert.equal(first.files.length, 43);
  assert.equal(first.lines[0].split('=')[0], 'supabase/schema.sql');
  assert.equal(first.lines.at(-1).split('=')[0], 'supabase/migrations/048_fix_vacancy_submit_managed_record_shape.sql');
  assert.equal(first.digest, 'a80005a2e789d368eec431ae15d0450b211bace43be6f6a150ae156be686502a');
  assert.equal(second.digest, first.digest);
});

test('guard self-tests cover missing, duplicate, future migration, and exact HEAD refusal', () => {
  assert.match(guard, /048_fixture\.sql/);
  assert.match(guard, /048_duplicate\.sql/);
  assert.match(guard, /049_future\.sql/);
  assert.match(guard, /Migration manifest hash is not deterministic/);
  assert.match(guard, /Git HEAD does not equal the approved staging-test commit/);
  assert.match(guard, /\$ApprovedCommit -cne \$Head/);
});

test('production and privileged identity refusal assertions remain explicit', () => {
  for (const name of [
    'AADHYANT_PRODUCTION_DENYLIST_PROJECT_REFS',
    'AADHYANT_PRODUCTION_DENYLIST_DB_HOSTS',
    'AADHYANT_PRODUCTION_DENYLIST_API_HOSTS'
  ]) assert.match(guard, new RegExp(name));
  assert.match(identity, /production denylist conflict/);
  assert.match(identity, /production host denylist conflict/);
  assert.match(identity, /service-role connection identity/);
  assert.match(identity, /ConfiguredUser = 'service_role'/);
  assert.match(identity, /configured host outside allowlist/);
  assert.match(identity, /transaction_read_only/);
});

test('migration 036 is privilege-only and revokes every approved RPC from PUBLIC and anon', () => {
  for (const signature of migration036Signatures) {
    const expression = new RegExp(`revoke\\s+execute\\s+on\\s+function\\s+${escapeRegExp(signature)}\\s+from\\s+public,\\s*anon\\s*;`, 'gi');
    assert.equal((migration036.match(expression) || []).length, 1, signature);
  }
  assert.doesNotMatch(migration036, /\bauthenticated\b/i);
  assert.doesNotMatch(migration036, /\b(insert|update|delete|upsert|merge|truncate|copy|create|alter|drop|grant)\b/i);
  assert.doesNotMatch(migration036, /\b(row level security|policy|security definer|set role)\b/i);
  assert.match(migration036, /^begin;/i);
  assert.match(migration036, /commit;\s*$/i);
});
