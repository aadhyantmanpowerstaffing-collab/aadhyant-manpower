const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const recovery = fs.readFileSync(path.join(root, 'assets', 'js', 'password-recovery.js'), 'utf8');
const portals = Object.freeze({
  company: fs.readFileSync(path.join(root, 'company', 'login.html'), 'utf8'),
  contractor: fs.readFileSync(path.join(root, 'contractor', 'login.html'), 'utf8'),
  candidate: fs.readFileSync(path.join(root, 'candidate', 'portal', 'login.html'), 'utf8')
});

function classList() { return { add() {}, remove() {} }; }
function executeRecovery({ search = '', hash = '', session = null, portal = 'company', minimum = '8' } = {}) {
  const views = {
    login: { hidden: false },
    set: { hidden: true },
    expired: { hidden: true },
    success: { hidden: true }
  };
  const focused = { value: false };
  const historyCalls = [];
  const updateCalls = [];
  const signOutCalls = [];
  const storage = new Map();
  const timers = [];
  const message = { hidden: false, textContent: '', classList: classList(), closest() { return null; } };
  const recoveryForm = {
    elements: { password: { value: '' }, confirmPassword: { value: '' } },
    reset() { this.elements.password.value = ''; this.elements.confirmPassword.value = ''; },
    addEventListener(type, handler) { if (type === 'submit') this.submit = handler; },
    querySelector(selector) { return selector === 'button[type="submit"]' ? { disabled: false } : null; }
  };
  const document = {
    body: { dataset: { passwordRecoveryPortal: portal, passwordRecoveryMinLength: minimum } },
    querySelectorAll(selector) {
      if (selector === '[data-recovery-login-content]') return [views.login];
      if (selector === '[data-recovery-set-password]') return [views.set];
      if (selector === '[data-recovery-expired]') return [views.expired];
      if (selector === '[data-recovery-success]') return [views.success];
      if (selector === '[data-page-message], [data-message]') return [message];
      return [];
    },
    querySelector(selector) {
      if (selector === '[data-recovery-new-password]') return { focus() { focused.value = true; } };
      if (selector === '[data-password-recovery-form]') return recoveryForm;
      if (selector === '[data-page-message], [data-message]') return message;
      return null;
    }
  };
  const client = {
    auth: {
      onAuthStateChange(handler) { client.handler = handler; return { data: { subscription: { unsubscribe() {} } } }; },
      getSession: async () => ({ data: { session } }),
      resetPasswordForEmail: async () => ({ error: null }),
      updateUser: async (attributes) => { updateCalls.push(attributes); return { error: null }; },
      signOut: async () => { signOutCalls.push(true); return { error: null }; }
    }
  };
  const location = { search, hash, pathname: `/${portal === 'candidate' ? 'candidate/portal' : portal}/login.html`, origin: 'https://staging.example.test' };
  const window = {
    aadhyantSupabase: { client, isConfigured: true },
    location,
    history: { state: {}, replaceState(_state, _title, url) { historyCalls.push(url); } },
    sessionStorage: { setItem(key, value) { storage.set(key, value); }, getItem(key) { return storage.get(key) || null; }, removeItem(key) { storage.delete(key); } },
    setTimeout(callback) { timers.push(callback); },
    dispatchEvent() {}
  };
  const context = { window, document, URL, URLSearchParams, setTimeout: window.setTimeout, console };
  vm.runInNewContext(recovery, context);
  return new Promise((resolve) => setImmediate(() => resolve({ views, focused, historyCalls, api: window.aadhyantPasswordRecovery, client, timers, recoveryForm, message, updateCalls, signOutCalls })));
}

test('all three portal logins provide a complete portal-scoped recovery surface', () => {
  for (const [portal, html] of Object.entries(portals)) {
    assert.match(html, new RegExp(`data-password-recovery-portal="${portal}"`));
    assert.match(html, /data-password-recovery-request/);
    assert.match(html, /data-recovery-set-password/);
    assert.match(html, /New Password/);
    assert.match(html, /Confirm New Password/);
    assert.match(html, /Update Password/);
    assert.match(html, /This password reset link has expired or was already used\./);
    assert.match(html, /Request New Reset Link/);
    assert.match(html, /Password updated successfully\. You can now sign in with your new password\./);
    assert.match(html, /assets\/js\/password-recovery\.js/);
  }
  assert.match(portals.company, /Return to Employer Login/);
  assert.match(portals.contractor, /Return to Contractor Login/);
  assert.match(portals.candidate, /Return to Candidate Login/);
  assert.match(portals.candidate, /data-password-recovery-min-length="10"/);
});

test('an implicit valid recovery callback opens Set New Password only after Supabase formed its session', async () => {
  const result = await executeRecovery({ hash: '#type=recovery&access_token=fresh-access-token&refresh_token=fresh-refresh-token', session: { user: { id: 'recovery-user' } } });
  assert.equal(result.views.login.hidden, true);
  assert.equal(result.views.set.hidden, false);
  assert.equal(result.views.expired.hidden, true);
  assert.equal(result.focused.value, true);
  assert.deepEqual(result.historyCalls, ['/company/login.html']);
});

test('a fresh external recovery callback is accepted only on Supabase PASSWORD_RECOVERY', async () => {
  const result = await executeRecovery({ search: '?code=fresh-recovery-code' });
  assert.equal(result.views.login.hidden, false);
  result.client.handler('PASSWORD_RECOVERY', { user: { id: 'external-recovery-user' } });
  assert.equal(result.views.login.hidden, true);
  assert.equal(result.views.set.hidden, false);
  assert.deepEqual(result.historyCalls, ['/company/login.html']);
});

test('a URL type marker plus an ordinary session cannot open the password-update form', async () => {
  const result = await executeRecovery({ search: '?type=recovery', session: { user: { id: 'ordinary-session-user' } } });
  assert.equal(result.views.login.hidden, false);
  assert.equal(result.views.set.hidden, true);
  assert.equal(result.views.expired.hidden, true);
});

test('a recovery session blocks mismatched passwords and updates only through Supabase Auth before showing portal-safe success', async () => {
  const result = await executeRecovery({ hash: '#type=recovery&access_token=fresh-access-token&refresh_token=fresh-refresh-token', session: { user: { id: 'recovery-user' } }, portal: 'contractor' });
  result.recoveryForm.elements.password.value = 'Password123';
  result.recoveryForm.elements.confirmPassword.value = 'Different123';
  await result.recoveryForm.submit({ preventDefault() {} });
  assert.deepEqual(result.updateCalls, []);
  assert.match(result.message.textContent, /must match/);
  result.recoveryForm.elements.confirmPassword.value = 'Password123';
  await result.recoveryForm.submit({ preventDefault() {} });
  assert.equal(result.updateCalls.length, 1);
  assert.equal(result.updateCalls[0].password, 'Password123');
  assert.equal(result.signOutCalls.length, 1);
  assert.equal(result.views.success.hidden, false);
  assert.equal(result.views.set.hidden, true);
});

test('expired or denied recovery callbacks show only the safe expiry UX and remove technical query and hash parameters', async () => {
  const result = await executeRecovery({ search: '?error=access_denied&error_code=otp_expired&error_description=raw-auth-detail', hash: '#access_token=raw-token&refresh_token=raw-refresh-token', portal: 'candidate', minimum: '10' });
  assert.equal(result.views.login.hidden, true);
  assert.equal(result.views.expired.hidden, false);
  assert.equal(result.views.set.hidden, true);
  assert.deepEqual(result.historyCalls, ['/candidate/portal/login.html']);
});

test('shared recovery logic uses Supabase Auth only and preserves anti-enumeration and password rules', () => {
  assert.match(recovery, /auth\.resetPasswordForEmail\(email, \{ redirectTo: resetRedirect\(\) \}\)/);
  assert.match(recovery, /event === 'PASSWORD_RECOVERY'/);
  assert.match(recovery, /auth\.updateUser\(\{ password \}\)/);
  assert.match(recovery, /event === 'PASSWORD_RECOVERY'/);
  assert.match(recovery, /callbackType === 'recovery' && callbackHasSessionTokens/);
  assert.match(recovery, /!session \|\| !\(confirmedRecovery \|\| implicitRecoverySession \|\| rememberedRecovery\(\)\)/);
  assert.match(recovery, /If an account exists for this email, password reset instructions have been sent\./);
  assert.match(recovery, /technicalParameters = \['access_token'.*'token_hash'.*'type'\]/s);
  assert.match(recovery, /password\.length >= minimum/);
  assert.doesNotMatch(recovery, /service[_-]?role|client\.from\s*\(/i);
  assert.doesNotMatch(recovery, /rememberRequest|recoveryRequestIsPending/);
  assert.doesNotMatch(recovery, /error_description\s*\)/);
});

test('recovery redirects stay on the current portal origin and do not hard-code staging or production', () => {
  assert.match(recovery, /new URL\(window\.location\.pathname, window\.location\.origin\)\.href/);
  assert.doesNotMatch(recovery, /pages\.dev|aadhyantmanpower\.in|supabase\.co/i);
});
