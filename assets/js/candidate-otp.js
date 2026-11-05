/* Staged WhatsApp OTP candidate registration. Controlled by config.js flag. */
(() => {
  if (window.AADHYANT_CONFIG?.candidateOtpEnabled !== true) return;

  const form = document.querySelector('#candidate-registration-form');
  const review = document.querySelector('[data-review="candidate"]');
  const button = review?.querySelector('[data-database-submit="candidate"]');
  const status = review?.querySelector('[data-submission-status="candidate"]');
  const client = window.aadhyantSupabase?.client;
  const config = window.AADHYANT_CONFIG;
  if (!form || !review || !button || !status || !client) return;

  const phoneInput = form.querySelector('[name="mobile"]');
  const control = document.createElement('div');
  control.className = 'candidate-otp-controls';
  control.setAttribute('aria-live', 'polite');
  control.innerHTML = `
    <div class="field">
      <label for="candidate-otp-code">WhatsApp verification code</label>
      <input id="candidate-otp-code" type="text" inputmode="numeric"
        autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6"
        placeholder="6-digit OTP" disabled>
      <p class="field-help">Code expires in 5 minutes. Request up to three times in 24 hours.</p>
    </div>
    <button class="button button-secondary" type="button" data-candidate-otp-send>Send OTP</button>
    <button class="button button-primary" type="button" data-candidate-otp-verify disabled>Verify &amp; Register</button>
    <p role="status" aria-live="polite" data-candidate-otp-status></p>
  `;
  button.hidden = true;
  button.after(control);

  const send = control.querySelector('[data-candidate-otp-send]');
  const verify = control.querySelector('[data-candidate-otp-verify]');
  const input = control.querySelector('#candidate-otp-code');
  const notice = control.querySelector('[data-candidate-otp-status]');
  let sending = false;
  let phoneAtSend = null;
  let completed = false;
  let pendingProof = null;
  let proofExpiresAt = 0;
  const phone = () => '91' + String(phoneInput.value || '').trim();
  const show = (message) => { notice.textContent = message; };
  const api = async (payload) => {
    const response = await fetch(config.supabaseUrl + '/functions/v1/candidate-whatsapp-otp', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'apikey': config.supabasePublishableKey,
      },
      body: JSON.stringify(payload),
    });
    let data;
    try { data = await response.json(); } catch { throw Error('Verification service unavailable'); }
    if (!response.ok) throw Error(data.error || 'Verification service unavailable');
    return data;
  };
  // Blocking the legacy direct insertion is essential when the OTP flag is active.
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);

  send.addEventListener('click', async () => {
    if (sending || completed) return;
    if (!/^91[6-9][0-9]{9}$/.test(phone())) {
      show('Enter a valid 10-digit mobile number in the registration form.');
      return;
    }
    const currentPhone = phone();
    sending = true;
    send.disabled = true;
    verify.disabled = true;
    pendingProof = null;
    proofExpiresAt = 0;
    show('Requesting WhatsApp OTP…');
    try {
      await api({ action: 'request', phone: currentPhone });
      phoneAtSend = currentPhone;
      input.disabled = false;
      input.value = '';
      verify.disabled = false;
      show('OTP requested. Enter the code sent to your WhatsApp number.');
      input.focus();
    } catch (error) {
      show(error.message || 'Could not request OTP.');
    } finally {
      sending = false;
      send.disabled = false;
    }
  });

  verify.addEventListener('click', async () => {
    if (sending || completed || phoneAtSend !== phone()) {
      show('Mobile number changed. Request a fresh OTP.');
      return;
    }
    const otp = input.value.trim();
    if (!/^[0-9]{6}$/.test(otp) && !(pendingProof && proofExpiresAt > Date.now())) {
      show('Enter the 6-digit OTP.');
      return;
    }
    sending = true;
    verify.disabled = true;
    send.disabled = true;
    show('Verifying OTP…');
    try {
      if (!pendingProof || proofExpiresAt <= Date.now()) {
        pendingProof = null;
        const verification = await api({ action: 'verify', phone: phoneAtSend, otp });
        if (!verification.verified || !verification.proof) {
          throw Error('OTP verification failed.');
        }
        pendingProof = verification.proof;
        proofExpiresAt = Date.now() + Math.min(
          Number(verification.proofExpiresInSeconds || 600), 600,
        ) * 1000;
      }
      const data = new FormData(form);
      const nullable = (name) => String(data.get(name) || '').trim() || null;
      const candidate = {
        full_name: nullable('fullName'),
        age: Number(data.get('age')),
        gender: nullable('gender'),
        mobile: nullable('mobile'),
        whatsapp_number: nullable('whatsapp'),
        current_location: nullable('city'),
        district: nullable('district'),
        state: nullable('state'),
        highest_qualification: nullable('qualification'),
        specialization: nullable('trade'),
        candidate_type: nullable('candidateType'),
        total_experience: nullable('totalExperience'),
        previous_job_role: nullable('previousRole'),
        interview_available: nullable('interview'),
        preferred_job_location: nullable('preferredLocation'),
        additional_information: nullable('additional'),
        consent: data.get('consent') === 'on',
      };
      const box = document.querySelector('[data-candidate-opportunity]');
      const requested = new URLSearchParams(location.search).get('requirement');
      const requirementCode = box && !box.hidden ? requested : null;
      show('OTP verified. Completing registration…');
      const result = await api({
        action: 'register',
        phone: phoneAtSend,
        proof: pendingProof,
        candidate,
        requirementCode,
      });
      if (!result.registered) throw Error('Registration was not completed.');
      completed = true;
      pendingProof = null;
      proofExpiresAt = 0;
      input.disabled = true;
      send.hidden = true;
      verify.hidden = true;
      show(result.result === 'already_registered'
        ? 'Your registration or job interest is already recorded.'
        : 'Your verified registration has been submitted successfully.');
      review.querySelector('[data-edit="candidate"]').hidden = true;
    } catch (error) {
      show(error.message || 'Verification or registration failed. You can retry the verification while the OTP is valid.');
      verify.disabled = false;
      // A verified proof can be retried within ten minutes if registration fails.
    } finally {
      sending = false;
      if (!completed) send.disabled = false;
    }
  });
})();
