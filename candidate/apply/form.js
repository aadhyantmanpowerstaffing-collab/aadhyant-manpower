(function () {
  'use strict';
  const form = document.querySelector('[data-application-form]');
  const status = document.querySelector('[data-status]');
  const receipt = document.querySelector('[data-receipt]');
  const options = window.AadhyantRegistrationOptions;
  const client = window.aadhyantSupabase?.client;
  // Fragment capabilities never go to the static host, referrers or analytics.
  const token = new URLSearchParams(location.hash.slice(1)).get('token') || '';
  let busy = false;
  const message = (text, error = false) => { status.textContent = text; status.className = error ? 'status error' : 'status'; };
  const call = async (name, args) => {
    const {data, error} = await client.rpc(name, args);
    if (error) throw new Error('Registration unavailable');
    return data;
  };
  function submitted(alerts, sameDay = false) {
    form.reset(); form.hidden = true; message(''); receipt.hidden = false;
    document.querySelector('[data-alert-receipt]').textContent = alerts
      ? 'You selected all future WhatsApp job alerts. Reply STOP anytime to stop alerts.'
      : 'General WhatsApp job alerts: No.';
    document.querySelector('[data-alert-receipt]').textContent += sameDay ? ' Same-Day Pay alerts: Yes (Sanand location rules apply).' : ' Same-Day Pay alerts: No.';
    receipt.focus();
  }
  async function start() {
    if (!/^[a-f0-9]{64}$/.test(token) || !client || !options) {
      message('Open the private registration link from your latest Aadhyant WhatsApp message. No details have been submitted.', true); return;
    }
    try {
      const context = await call('get_whatsapp_registration_form', {p_token:token});
      if (!context || !['ready','completed'].includes(context.status)) throw new Error('unavailable');
      document.querySelector('[data-job-code]').textContent = context.requirement_code;
      document.querySelector('[data-job-role]').textContent = context.job_role;
      document.querySelector('[data-job-location]').textContent = context.job_location || '';
      document.querySelector('[data-bound-phone]').value = context.phone_masked;
      if (context.status === 'completed') {
        message('This registration has already been submitted. You do not need to fill it again.'); return;
      }
      options.setupCandidateForm(form); options.setupStateDistrict(form);
      form.hidden = false; message('');
    } catch (_) {
      message('This private link is unavailable, expired or needs staff review. Return to WhatsApp and contact Aadhyant. No details have been submitted.', true);
    }
  }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy || !form.reportValidity()) return;
    const d = new FormData(form), get = name => String(d.get(name) || '').trim();
    if (!['yes','no'].includes(get('job_alert_consent')) || !['yes','no'].includes(get('same_day_alert_consent'))) { message('Choose Yes or No for both WhatsApp alert types.', true); return; }
    const state = get('state'), district = get('district');
    if (!options.sets.states.includes(state) || !options.districtsByState[state]?.includes(district)) {
      message('Select your State and District from the dropdowns.', true); return;
    }
    const p_profile = {
      form_kind:'aadhyant_registration_v1',consent_policy_version:'wa-web-registration-alerts-v1',
      full_name:get('full_name'),age:get('age'),gender:get('gender'),state,district,
      current_village_city:get('current_village_city'),highest_qualification:get('highest_qualification'),
      course_trade_specialization:options.candidateSpecialization(form) || 'General',
      experience_status:get('candidate_type'),interview_available:get('interview_available'),
      registration_consent:form.elements.registration_consent.checked,
      job_alert_consent:get('job_alert_consent') === 'yes'
    };
    const p_optional = {same_day_alert_consent:get('same_day_alert_consent') === 'yes',current_job_location:get('current_job_location'),pincode:get('pincode'),total_experience:options.candidateExperience(form) || '',
      previous_job_role:get('previous_job_role'),preferred_job_location:get('preferred_job_location')};
    busy = true; const button = form.querySelector('button[type="submit"]'); button.disabled = true;
    message('Submitting your registration…');
    try {
      const result = await call('submit_whatsapp_registration_form',{p_token:token,p_profile,p_optional});
      if (result?.status !== 'registered' || typeof result.job_alerts_selected !== 'boolean') throw new Error('receipt');
      submitted(result.job_alerts_selected, result.same_day_alerts_selected);
    } catch (_) {
      // Keep entered details only in this form; never store them in browser storage or logs.
      message('Submission could not be confirmed. Your details remain in this form. Try Submit again; the same private link cannot create a duplicate application. If it continues, contact Aadhyant for review.', true);
    } finally { busy = false; button.disabled = false; }
  });
  addEventListener('pagehide', () => form.reset());
  start();
}());
