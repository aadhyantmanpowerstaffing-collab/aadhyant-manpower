(function initializePasswordRecovery() {
  'use strict';

  const body = document.body;
  const portal = body?.dataset.passwordRecoveryPortal;
  const client = window.aadhyantSupabase?.client;
  const configured = Boolean(window.aadhyantSupabase?.isConfigured && client && portal);
  const markerKey = `aadhyant.password-recovery.${portal || 'unknown'}`;
  const query = new URLSearchParams(window.location.search);
  const fragment = new URLSearchParams(window.location.hash.startsWith('#') ? window.location.hash.slice(1) : '');
  const value = (name) => query.get(name) || fragment.get(name) || '';
  const callbackError = String(value('error')).toLowerCase();
  const callbackCode = String(value('error_code')).toLowerCase();
  const callbackType = String(value('type')).toLowerCase();
  const callbackHasSessionTokens = Boolean(value('access_token') && value('refresh_token'));
  const hasAuthCallback = Boolean(value('code') || callbackType || callbackError || callbackCode);
  const hasExpiredCallback = callbackCode === 'otp_expired' || callbackError === 'access_denied';
  let recoverySession = false;

  const technicalParameters = ['access_token', 'code', 'error', 'error_code', 'error_description', 'error_uri', 'expires_at', 'expires_in', 'provider_refresh_token', 'provider_token', 'refresh_token', 'token_hash', 'type'];
  const visible = (node) => node && !node.hidden && !node.closest('[hidden]');
  const activeMessage = () => Array.from(document.querySelectorAll('[data-page-message], [data-message]')).find(visible)
    || document.querySelector('[data-page-message], [data-message]');
  const showMessage = (text, type = '') => {
    const node = activeMessage();
    if (!node) return;
    node.textContent = text;
    node.classList.remove('success', 'error', 'is-success', 'is-error');
    if (type) {
      node.classList.add(type);
      node.classList.add(`is-${type}`);
    }
  };
  const show = (name) => {
    document.querySelectorAll('[data-recovery-login-content]').forEach((node) => { node.hidden = name !== 'login'; });
    document.querySelectorAll('[data-recovery-set-password]').forEach((node) => { node.hidden = name !== 'set-password'; });
    document.querySelectorAll('[data-recovery-expired]').forEach((node) => { node.hidden = name !== 'expired'; });
    document.querySelectorAll('[data-recovery-success]').forEach((node) => { node.hidden = name !== 'success'; });
  };
  const cleanCallbackUrl = () => {
    technicalParameters.forEach((name) => query.delete(name));
    const remaining = query.toString();
    window.history.replaceState(window.history.state, '', `${window.location.pathname}${remaining ? `?${remaining}` : ''}`);
  };
  const resetRedirect = () => new URL(window.location.pathname, window.location.origin).href;
  const passwordIsValid = (password) => {
    const minimum = Number(body?.dataset.passwordRecoveryMinLength || 8);
    const needsLetterAndNumber = portal !== 'candidate' && body?.dataset.passwordRecoveryRequireLetterNumber !== 'false';
    return password.length >= minimum && (!needsLetterAndNumber || (/[A-Za-z]/.test(password) && /\d/.test(password)));
  };
  const rememberRecovery = () => {
    try { window.sessionStorage.setItem(markerKey, 'active'); } catch (_error) { /* Session storage is optional. */ }
  };
  const rememberedRecovery = () => {
    try { return window.sessionStorage.getItem(markerKey) === 'active'; } catch (_error) { return false; }
  };
  const clearRecovery = () => {
    try { window.sessionStorage.removeItem(markerKey); } catch (_error) { /* Session storage is optional. */ }
  };
  const genericResetMessage = 'If an account exists for this email, password reset instructions have been sent.';
  const requestReset = async (email, button) => {
    if (!email) {
      showMessage('Enter your email address to request a reset link.', 'error');
      return;
    }
    if (button) button.disabled = true;
    try {
      const { error } = await client.auth.resetPasswordForEmail(email, { redirectTo: resetRedirect() });
      showMessage(error ? 'Password reset instructions could not be sent. Please try again.' : genericResetMessage, error ? 'error' : 'success');
    } catch (_error) {
      showMessage('Password reset instructions could not be sent. Please try again.', 'error');
    } finally {
      if (button) button.disabled = false;
    }
  };
  const activateRecovery = (session, confirmedRecovery = false) => {
    // A URL marker alone is never enough: accept a recovery only when Supabase
    // emits PASSWORD_RECOVERY, or when its implicit-flow tokens formed a session.
    // The short-lived marker only survives URL cleanup; it is not authentication.
    const implicitRecoverySession = callbackType === 'recovery' && callbackHasSessionTokens;
    if (!session || !(confirmedRecovery || implicitRecoverySession || rememberedRecovery())) return false;
    recoverySession = true;
    rememberRecovery();
    cleanCallbackUrl();
    show('set-password');
    document.querySelector('[data-recovery-new-password]')?.focus();
    return true;
  };
  const showExpired = () => {
    cleanCallbackUrl();
    show('expired');
    document.querySelector('[data-password-recovery-request-form] input[name="email"]')?.focus();
  };
  const initializeRequests = () => {
    document.querySelectorAll('[data-password-recovery-request]').forEach((button) => {
      button.addEventListener('click', () => {
        const loginForm = button.closest('[data-recovery-login-content]')?.querySelector('[data-login-form]');
        requestReset(String(loginForm?.elements.email?.value || '').trim(), button);
      });
    });
    document.querySelectorAll('[data-password-recovery-request-form]').forEach((form) => {
      form.addEventListener('submit', (event) => {
        event.preventDefault();
        requestReset(String(form.elements.email?.value || '').trim(), form.querySelector('button[type="submit"]'));
      });
    });
  };
  const initializePasswordUpdate = () => {
    const form = document.querySelector('[data-password-recovery-form]');
    if (!form) return;
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const password = String(form.elements.password?.value || '');
      const confirmation = String(form.elements.confirmPassword?.value || '');
      if (!passwordIsValid(password)) {
        const minimum = body?.dataset.passwordRecoveryMinLength || 8;
        const policy = portal === 'candidate' || body?.dataset.passwordRecoveryRequireLetterNumber === 'false'
          ? `Use at least ${minimum} characters.`
          : `Use at least ${minimum} characters including a letter and a number.`;
        showMessage(policy, 'error');
        return;
      }
      if (password !== confirmation) {
        showMessage('New Password and Confirm New Password must match.', 'error');
        return;
      }
      const { data } = await client.auth.getSession();
      if (!data?.session || !(recoverySession || rememberedRecovery())) {
        showExpired();
        return;
      }
      const button = form.querySelector('button[type="submit"]');
      if (button) button.disabled = true;
      try {
        const { error } = await client.auth.updateUser({ password });
        if (error) {
          showMessage('Password could not be updated. Please request a new reset link.', 'error');
          return;
        }
        clearRecovery();
        await client.auth.signOut();
        form.reset();
        show('success');
      } catch (_error) {
        showMessage('Password could not be updated. Please request a new reset link.', 'error');
      } finally {
        if (button) button.disabled = false;
      }
    });
  };
  const start = async () => {
    if (!portal) return;
    initializeRequests();
    initializePasswordUpdate();
    if (!configured) {
      showMessage('Password recovery is temporarily unavailable. Please try again later.', 'error');
      return;
    }
    if (hasExpiredCallback) {
      showExpired();
      return;
    }
    if (!hasAuthCallback) {
      show('login');
      return;
    }
    client.auth.onAuthStateChange((event, session) => {
      if (event === 'PASSWORD_RECOVERY') activateRecovery(session, true);
    });
    const { data, error } = await client.auth.getSession();
    if (error) {
      showExpired();
      return;
    }
    if (activateRecovery(data?.session)) return;
    window.setTimeout(async () => {
      const { data: retry, error: retryError } = await client.auth.getSession();
      if (retryError) {
        showExpired();
        return;
      }
      if (!activateRecovery(retry?.session)) {
        if (retry?.session) window.dispatchEvent(new Event('aadhyant-auth-callback-not-recovery'));
        else showExpired();
      }
    }, 500);
  };

  window.aadhyantPasswordRecovery = Object.freeze({
    isRecoveryCallback: () => hasAuthCallback,
    cleanCallbackUrl,
    passwordIsValid
  });
  start().catch(showExpired);
}());
