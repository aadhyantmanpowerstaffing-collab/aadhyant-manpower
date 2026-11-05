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

test('client register action does not call the anonymous direct insert', () => {
  const js = read('assets/js/candidate-otp.js');
  assert.match(js, /action: 'verify'/);
  assert.match(js, /action: 'register'/);
  assert.match(js, /stopImmediatePropagation\(\)/);
  assert.doesNotMatch(js, /\.from\(['"]candidates['"]\)\.insert/);
});


test('Meta WhatsApp hook verifies signed Supabase Auth request', () => {
  const hook = read('supabase/functions/candidate-auth-whatsapp-hook/index.ts');
  assert.match(hook, /standardwebhooks/);
  assert.match(hook, /\.verify\(payload, Object\.fromEntries\(req\.headers\)\)/);
  assert.match(hook, /META_WA_OTP_TEMPLATE_NAME/);
  assert.match(hook, /graph\.facebook\.com/);
  assert.doesNotMatch(hook, /console\.log\(.*otp/);
});

test('verified phone session authorizes candidate profile registration', () => {
  const sql = read('supabase/migrations/20261105111500_authenticated_candidate_registration.sql');
  assert.match(sql, /auth\.uid\(\)/);
  assert.match(sql, /phone_confirmed_at is not null/);
  assert.match(sql, /v_phone <> '91' \|\| v_mobile/);
  assert.match(sql, /grant execute on function public\.register_authenticated_candidate.*?\n\s*to authenticated/);
  assert.match(sql, /user_id = v_user_id/);
});

test('public candidate page performs Supabase OTP verify and authorized RPC', () => {
  const page = read('assets/js/candidate-otp.js');
  assert.match(page, /auth\.signInWithOtp/);
  assert.match(page, /auth\.verifyOtp/);
  assert.match(page, /register_authenticated_candidate/);
  assert.match(read('supabase-client.js'), /candidateOtpEnabled === true/);
});
