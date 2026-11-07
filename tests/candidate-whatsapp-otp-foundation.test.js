// Regression guard for staged candidate WhatsApp OTP integration.
// Run with: node --test tests/candidate-whatsapp-otp-foundation.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (name) => fs.readFileSync(path.join(root, name), 'utf8');
const exists = (name) => fs.existsSync(path.join(root, name));

test('OTP stays disabled and CAPTCHA-gated until an approved rollout', () => {
  const config = read('config.js');
  assert.match(config, /candidateOtpEnabled:\s*false/);
  assert.match(config, /candidateOtpCaptchaSiteKey:\s*''/);

  const page = read('candidate/register/index.html');
  assert.match(page, /assets\/js\/candidate-otp\.js/);
  assert.match(page, /WhatsApp verification code/);

  const client = read('assets/js/candidate-otp.js');
  assert.match(client, /candidateOtpEnabled !== true/);
  assert.match(client, /candidateOtpCaptchaSiteKey/);
  assert.match(client, /captchaToken/);
  assert.match(client, /challenges\.cloudflare\.com\/turnstile/);
});

test('browser registration requires Supabase phone verification, not anonymous inserts', () => {
  const js = read('assets/js/candidate-otp.js');
  assert.match(js, /auth\.signInWithOtp/);
  assert.match(js, /auth\.verifyOtp/);
  assert.match(js, /captchaToken: verificationToken/);
  assert.match(js, /register_authenticated_candidate/);
  assert.match(js, /stopImmediatePropagation\(\)/);
  assert.match(js, /declaredWhatsapp !== candidateMobile/);
  assert.doesNotMatch(js, /\.from\(['"]candidates['"]\)\.insert/);
  assert.doesNotMatch(js, /candidate-whatsapp-otp/);
});

test('Meta hook verifies a signed Auth request and keeps within the hook budget', () => {
  const hook = read('supabase/functions/candidate-auth-whatsapp-hook/index.ts');
  assert.match(hook, /standardwebhooks/);
  assert.match(hook, /\.verify\(payload, Object\.fromEntries\(req\.headers\)\)/);
  assert.match(hook, /WHATSAPP_ACCESS_TOKEN/);
  assert.match(hook, /WHATSAPP_PHONE_NUMBER_ID/);
  assert.match(hook, /META_WA_OTP_TEMPLATE_NAME/);
  assert.match(hook, /candidate_otp_dispatch_reserve/);
  assert.match(hook, /candidate_otp_dispatch_complete/);
  assert.match(hook, /AbortSignal\.timeout\(2_500\)/);
  assert.match(hook, /phoneHash/);
  assert.match(hook, /codeHash/);
  assert.doesNotMatch(hook, /console\.(log|error|warn)/);
  assert.doesNotMatch(hook, /META_WA_ACCESS_TOKEN/);
});

test('dispatch guard keeps only hashes private and is callable only by service role', () => {
  const sql = read('supabase/migrations/20261105120000_candidate_otp_dispatch_guard.sql');
  assert.match(sql, /create table if not exists private\.candidate_whatsapp_otp_dispatches/);
  assert.match(sql, /revoke all on schema private from public, anon, authenticated/);
  assert.match(sql, /enable row level security/);
  assert.match(sql, /code_hash text primary key/);
  assert.match(sql, /phone_hash text not null/);
  assert.match(sql, /candidate_otp_dispatch_reserve/);
  assert.match(sql, /candidate_otp_dispatch_complete/);
  assert.match(sql, /candidate_otp_dispatch_fail/);
  assert.match(sql, /return 'limited'/);
  assert.match(sql, /v_existing_reserved_at >= now\(\) - interval '10 minutes'/);
  assert.match(sql, /p_phone_hash is null or p_code_hash is null/);
  assert.match(sql, /p_code_hash is null or p_provider_message_id is null/);
  assert.match(sql, /grant execute on function public\.candidate_otp_dispatch_reserve\(text, text\) to service_role/);
  assert.match(sql, /revoke all on table private\.candidate_whatsapp_otp_dispatches/);
  assert.doesNotMatch(sql, /otp_hash/);
  assert.doesNotMatch(sql, /phone text primary key/);
});

test('verified phone session authorizes Candidate account registration and final cutover closes bypasses', () => {
  const registration = read('supabase/migrations/20261105111500_authenticated_candidate_registration.sql');
  assert.match(registration, /auth\.uid\(\)/);
  assert.match(registration, /phone_confirmed_at is not null/);
  assert.match(registration, /v_phone <> '91' \|\| v_mobile/);
  assert.match(registration, /v_whatsapp <> '' and v_whatsapp <> v_mobile/);
  assert.match(registration, /where c\.mobile = v_mobile;/);
  assert.match(registration, /Candidate account requires manual review/);
  assert.match(registration, /grant execute on function public\.register_authenticated_candidate.*?\n\s*to authenticated/);
  assert.match(registration, /user_id = v_user_id/);

  const cutover = read('supabase/migrations/20261105121500_candidate_otp_rollout_enforcement.sql');
  assert.match(cutover, /drop policy if exists "Public can submit candidate registrations"/);
  assert.match(cutover, /revoke insert on table public\.candidates from public, anon, authenticated/);
  assert.match(cutover, /revoke execute on function public\.register_candidate_requirement_interest/);
});

test('obsolete custom OTP transport and migrations are not left deployable', () => {
  assert.equal(exists('supabase/functions/candidate-whatsapp-otp/index.ts'), false);
  assert.equal(exists('supabase/migrations/20261105090000_candidate_phone_otp_foundation.sql'), false);
  assert.equal(exists('supabase/migrations/20261105094500_candidate_otp_atomic_registration.sql'), false);
  assert.match(read('docs/otp/CANDIDATE_WHATSAPP_OTP_READINESS.md'), /does \*\*not\*\* use\nWANotifier/);
});

test('disposable-environment security test covers grants, dispatch cap, and account link', () => {
  const sql = read('supabase/tests/20261105_candidate_otp_security_test.sql');
  assert.match(sql, /set local role service_role/);
  assert.match(sql, /set local role authenticated/);
  assert.match(sql, /24-hour dispatch cap was not enforced/);
  assert.match(sql, /Expired idempotency window blocked a new Auth OTP/);
  assert.match(sql, /candidate_otp_dispatch_complete\(text,text\)/);
  assert.match(sql, /candidate_otp_dispatch_fail\(text\)/);
  assert.match(sql, /Legacy anonymous Candidate registration bypass remains open/);
  assert.match(sql, /Verified Candidate account was not linked/);
  assert.match(sql, /Verified session registered a different WhatsApp number/);
  assert.match(sql, /Verified phone could overwrite a different Candidate identity/);
  assert.match(sql, /rollback;/);
});
