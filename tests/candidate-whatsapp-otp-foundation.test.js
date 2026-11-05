// Regression guard for staged candidate WhatsApp OTP integration.
// Run with: node --test tests/candidate-whatsapp-otp-foundation.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');

test('OTP remains disabled until explicit production readiness', () => {
  const config = read('config.js');
  assert.match(config, /candidateOtpEnabled:\s*false/);
  const page = read('candidate/register/index.html');
  assert.match(page, /assets\/js\/candidate-otp\.js/);
  const client = read('assets/js/candidate-otp.js');
  assert.match(client, /candidateOtpEnabled !== true/);
});

test('candidate OTP proof is consumed in a server-side transaction', () => {
  const sql = read('supabase/migrations/20261105094500_candidate_otp_atomic_registration.sql');
  assert.match(sql, /create or replace function public\.candidate_otp_register/);
  assert.match(sql, /where phone = p_phone for update/);
  assert.match(sql, /proof_hash is distinct from p_proof_hash/);
  assert.match(sql, /consumed_at = now\(\)/);
  assert.match(sql, /grant execute on function public\.candidate_otp_register.*to service_role/);
  assert.match(sql, /revoke all on function public\.candidate_otp_register.*from public, anon, authenticated/);
});

test('client register action does not call the anonymous direct insert', () => {
  const js = read('assets/js/candidate-otp.js');
  assert.match(js, /action: 'verify'/);
  assert.match(js, /action: 'register'/);
  assert.match(js, /stopImmediatePropagation\(\)/);
  assert.doesNotMatch(js, /\.from\(['"]candidates['"]\)\.insert/);
});

test('server never returns OTP and does not operate without approved provider config', () => {
  const edge = read('supabase/functions/candidate-whatsapp-otp/index.ts');
  assert.match(edge, /CANDIDATE_OTP_HASH_SECRET/);
  assert.match(edge, /META_WA_OTP_TEMPLATE_NAME/);
  assert.match(edge, /await db\.rpc\("candidate_otp_issue"/);
  assert.match(edge, /await db\.rpc\("candidate_otp_verify"/);
  assert.match(edge, /await db\.rpc\("candidate_otp_register"/);
  assert.doesNotMatch(edge, /json\(\{[^\n]*otp\s*[,}]/);
});

test('OTP database is inaccessible to public and authenticated users', () => {
  const sql = read('supabase/migrations/20261105090000_candidate_phone_otp_foundation.sql');
  assert.match(sql, /enable row level security/);
  assert.match(sql, /revoke all on public\.candidate_phone_otp from public, anon, authenticated/);
  assert.match(sql, /grant select, insert, update, delete on public\.candidate_phone_otp to service_role/);
});
