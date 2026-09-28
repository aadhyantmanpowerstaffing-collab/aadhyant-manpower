(function () {
  'use strict';
  const reads = new WeakMap();
  const policy = 'candidate-job-alerts-v1';
  const getRpc = 'get_candidate_whatsapp_alert_preference';
  const setRpc = 'set_candidate_whatsapp_alert_preference';
  function element(tag, text) {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    return node;
  }
  function validate(data) {
    if (!data || !['unknown', 'opted_in', 'opted_out'].includes(data.marketing_status)
        || !/^\+91 \*{6}\d{4}$/.test(data.phone_masked)
        || !/^[a-f0-9]{32}$/.test(data.profile_token)
        || data.policy_version !== policy || typeof data.enrollment_available !== 'boolean'
        || typeof data.effective_opt_in !== 'boolean'
        || (data.updated_at !== null && (typeof data.updated_at !== 'string' || !Number.isFinite(Date.parse(data.updated_at))))
        || (data.effective_opt_in && data.marketing_status !== 'opted_in')) {
      throw new Error('Invalid WhatsApp preference response');
    }
    return data;
  }
  async function mount(root, client) {
    if (!root || !client) return;
    const current = {};
    reads.set(root, current);
    const active = () => reads.get(root) === current && root.isConnected;
    const rpc = async (name, args = {}) => {
      const result = await client.rpc(name, args);
      if (result.error) throw result.error;
      return validate(result.data);
    };
    root.replaceChildren(element('p', 'Loading WhatsApp job-alert preference…'));
    function render(state, notice = '') {
      if (!active()) return;
      const title = element('h2', 'WhatsApp job alerts');
      const explanation = element('p', `Optional job alerts from Aadhyant Manpower & Staffing to your saved mobile ${state.phone_masked}. This choice is separate from your application and document sharing.`);
      const form = element('form');
      const label = element('label');
      label.className = 'consent-line';
      const choice = element('input');
      choice.type = 'checkbox';
      choice.name = 'whatsapp_job_alerts';
      choice.checked = state.effective_opt_in;
      choice.disabled = !state.enrollment_available && !state.effective_opt_in;
      label.append(choice, document.createTextNode(' I use this mobile number on WhatsApp and want to receive job alerts.'));
      const help = element('p', 'You can turn job alerts off here or reply STOP on WhatsApp. Saving this preference does not send a message.');
      const button = element('button', 'Save WhatsApp preference');
      button.className = 'button';
      button.type = 'submit';
      button.disabled = choice.disabled;
      const status = element('p', notice || (state.effective_opt_in ? 'Job alerts are enabled.' : 'Job alerts are off.'));
      status.className = 'message';
      status.setAttribute('role', 'status');
      if (!state.enrollment_available) {
        status.textContent = 'Your saved WhatsApp number needs account review before alerts can be enabled.';
      }
      form.append(label, help, button, status);
      root.replaceChildren(title, explanation, form);
      let busy = false;
      form.addEventListener('submit', async event => {
        event.preventDefault();
        if (busy || button.disabled || !active()) return;
        const desired = choice.checked;
        busy = true;
        button.disabled = choice.disabled = true;
        status.textContent = 'Saving WhatsApp preference…';
        try {
          const saved = await rpc(setRpc, {
            p_opt_in: desired,
            p_expected_updated_at: state.updated_at,
            p_policy_version: state.policy_version,
            p_profile_token: state.profile_token,
          });
          if (saved.effective_opt_in !== desired) throw new Error('Preference was not confirmed');
          render(saved, desired ? 'Job-alert preference saved.' : 'Job alerts are off.');
        } catch (_) {
          // Re-read after a conflict or uncertain response; never retry a write.
          try { render(await rpc(getRpc), 'The save was not confirmed. Your current preference is shown; review it before saving again.'); }
          catch (_) {
            if (active()) root.replaceChildren(element('p', 'WhatsApp preferences are temporarily unavailable. Reload this page to check your current setting.'));
          }
        }
      });
    }
    try { render(await rpc(getRpc)); }
    catch (_) {
      if (active()) root.replaceChildren(element('p', 'WhatsApp job alerts are not available yet. Your profile and applications are unaffected.'));
    }
  }
  window.AadhyantWhatsAppPreferences = Object.freeze({ mount });
})();
