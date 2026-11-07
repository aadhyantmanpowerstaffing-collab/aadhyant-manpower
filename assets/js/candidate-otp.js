/* Candidate WhatsApp OTP registration. Disabled unless explicitly enabled in config.js. */
(() => {
  const otpConfig = window.AADHYANT_CONFIG;
  if (otpConfig?.candidateOtpEnabled !== true) return;

  const form = document.querySelector('#candidate-registration-form');
  const review = document.querySelector('[data-review="candidate"]');
  const legacySubmit = review?.querySelector('[data-database-submit="candidate"]');
  const client = window.aadhyantSupabase?.client;
  const phoneInput = form?.querySelector('[name="mobile"]');
  const whatsappInput = form?.querySelector('[name="whatsapp"]');
  if (!form || !review || !legacySubmit || !client || !phoneInput) return;

  const control = document.createElement('div');
  control.className = 'candidate-otp-controls';
  control.setAttribute('aria-live', 'polite');
  control.innerHTML = `
    <div class="field">
      <label for="candidate-otp-code">WhatsApp verification code</label>
      <input id="candidate-otp-code" type="text" inputmode="numeric"
        autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6"
        placeholder="6-digit OTP" disabled>
      <p class="field-help">We will send the code to this mobile number on WhatsApp. It expires in 5 minutes.</p>
    </div>
    <div data-candidate-otp-captcha></div>
    <button class="button button-secondary" type="button" data-candidate-otp-send>Send OTP</button>
    <button class="button button-primary" type="button" data-candidate-otp-verify disabled>Verify &amp; Register</button>
    <p role="status" aria-live="polite" data-candidate-otp-status></p>
  `;
  legacySubmit.hidden = true;
  legacySubmit.after(control);

  // OTP registration is the only database path while this feature is enabled.
  review.querySelector('.fallback-heading')?.setAttribute('hidden', '');
  review.querySelector('[data-whatsapp="candidate"]')?.setAttribute('hidden', '');
  review.querySelector('[data-email="candidate"]')?.setAttribute('hidden', '');
  review.querySelector('.review-fallback')?.setAttribute('hidden', '');

  const send = control.querySelector('[data-candidate-otp-send]');
  const verify = control.querySelector('[data-candidate-otp-verify]');
  const input = control.querySelector('#candidate-otp-code');
  const notice = control.querySelector('[data-candidate-otp-status]');
  let busy = false;
  let phoneAtSend = null;
  let verifiedSession = false;
  let completed = false;
  let captchaToken = '';
  let captchaWidgetId = null;
  const captchaHost = control.querySelector('[data-candidate-otp-captcha]');
  const captchaSiteKey = String(otpConfig.candidateOtpCaptchaSiteKey || '').trim();

  const digits = (value) => String(value || '').replace(/\D/g, '');
  const mobile = () => digits(phoneInput.value);
  const phone = () => `91${mobile()}`;
  const show = (message) => { notice.textContent = message; };

  const resetVerification = (message) => {
    phoneAtSend = null;
    verifiedSession = false;
    input.value = '';
    input.disabled = true;
    verify.disabled = true;
    if (message) show(message);
  };

  const requestedPhone = () => {
    const candidateMobile = mobile();
    if (!/^[6-9][0-9]{9}$/.test(candidateMobile)) {
      show('Enter a valid 10-digit mobile number in the registration form.');
      return null;
    }
    const declaredWhatsapp = digits(whatsappInput?.value);
    if (declaredWhatsapp && declaredWhatsapp !== candidateMobile) {
      show('For secure verification, use the WhatsApp number as the mobile number.');
      return null;
    }
    return `91${candidateMobile}`;
  };

  const resetCaptcha = () => {
    captchaToken = '';
    if (captchaWidgetId !== null && window.turnstile?.reset) {
      window.turnstile.reset(captchaWidgetId);
    }
  };

  const prepareCaptcha = () => {
    if (!captchaSiteKey || !captchaHost) {
      send.disabled = true;
      show('Registration is temporarily unavailable while its security check is configured.');
      return false;
    }

    const render = () => {
      if (!window.turnstile?.render || captchaWidgetId !== null) return;
      captchaWidgetId = window.turnstile.render(captchaHost, {
        sitekey: captchaSiteKey,
        callback: (token) => { captchaToken = token; },
        'expired-callback': () => { captchaToken = ''; },
        'error-callback': () => {
          captchaToken = '';
          show('Security check could not load. Please refresh and try again.');
        },
        'response-field': false,
      });
    };

    if (window.turnstile?.render) {
      render();
      return true;
    }
    const attachTurnstileListeners = (script) => {
      script.addEventListener('load', render, { once: true });
      script.addEventListener('error', () => {
        show('Security check could not load. Please refresh and try again.');
      }, { once: true });
    };
    let script = document.querySelector('script[data-aadhyant-turnstile]');
    if (!script) {
      script = document.createElement('script');
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      script.async = true;
      script.defer = true;
      script.dataset.aadhyantTurnstile = 'true';
      attachTurnstileListeners(script);
      document.head.append(script);
    } else {
      attachTurnstileListeners(script);
    }
    return true;
  };

  const requestOtp = async (targetPhone, verificationToken) => {
    const { error } = await client.auth.signInWithOtp({
      phone: `+${targetPhone}`,
      options: { shouldCreateUser: true, captchaToken: verificationToken },
    });
    if (error) throw Error('WhatsApp OTP request failed. Please try again.');
  };

  const verifyOtp = async (targetPhone, otp) => {
    const { data, error } = await client.auth.verifyOtp({
      phone: `+${targetPhone}`,
      token: otp,
      type: 'sms',
    });
    if (error || !data?.session || !data?.user?.phone_confirmed_at) {
      throw Error('Incorrect or expired OTP.');
    }
  };

  const registerCandidate = async (candidate, requirementCode) => {
    const { data, error } = await client.rpc('register_authenticated_candidate', {
      p_candidate: candidate,
      p_requirement_code: requirementCode || null,
    });
    if (error) throw Error('Verified registration failed. Please retry.');
    return data;
  };

  // The older anonymous submission handler must never receive this click.
  legacySubmit.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);

  phoneInput.addEventListener('input', () => {
    if (phoneAtSend && phoneAtSend !== phone()) {
      resetVerification('Mobile number changed. Request a fresh OTP.');
    }
  });

  if (!prepareCaptcha()) return;

  send.addEventListener('click', async () => {
    if (busy || completed) return;
    const targetPhone = requestedPhone();
    if (!targetPhone) return;
    if (!captchaToken) {
      show('Complete the security check before requesting the WhatsApp OTP.');
      return;
    }

    busy = true;
    send.disabled = true;
    verify.disabled = true;
    resetVerification();
    show('Requesting WhatsApp OTP…');
    try {
      await requestOtp(targetPhone, captchaToken);
      phoneAtSend = targetPhone;
      input.disabled = false;
      verify.disabled = false;
      input.focus();
      show('OTP requested. Enter the code sent to your WhatsApp number.');
    } catch (error) {
      show(error.message || 'Could not request OTP.');
    } finally {
      resetCaptcha();
      busy = false;
      if (!completed) send.disabled = false;
    }
  });

  verify.addEventListener('click', async () => {
    if (busy || completed) return;
    if (!phoneAtSend || phoneAtSend !== phone()) {
      resetVerification('Mobile number changed. Request a fresh OTP.');
      return;
    }

    const otp = input.value.trim();
    if (!verifiedSession && !/^[0-9]{6}$/.test(otp)) {
      show('Enter the 6-digit OTP.');
      return;
    }

    busy = true;
    verify.disabled = true;
    send.disabled = true;
    try {
      if (!verifiedSession) {
        show('Verifying OTP…');
        await verifyOtp(phoneAtSend, otp);
        verifiedSession = true;
        input.disabled = true;
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
      const opportunity = document.querySelector('[data-candidate-opportunity]');
      const requirementCode = opportunity && !opportunity.hidden
        ? new URLSearchParams(location.search).get('requirement')
        : null;

      show('OTP verified. Completing registration…');
      const result = await registerCandidate(candidate, requirementCode);
      completed = true;
      send.hidden = true;
      verify.hidden = true;
      show(result === 'already_registered'
        ? 'Your registration or job interest is already recorded.'
        : 'Your verified registration and Candidate account are ready.');
      review.querySelector('[data-edit="candidate"]')?.setAttribute('hidden', '');
    } catch (error) {
      show(verifiedSession
        ? 'Phone is verified. Registration was not completed; please retry.'
        : (error.message || 'Verification failed. Please try again.'));
      verify.disabled = false;
    } finally {
      busy = false;
      if (!completed) send.disabled = false;
    }
  });
})();
