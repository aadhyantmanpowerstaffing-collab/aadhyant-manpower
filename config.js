// Public browser configuration only. Never add a service-role key or database password here.
window.AADHYANT_CONFIG = Object.freeze({
  supabaseUrl: 'https://wsuctjhbqiedttfnwjvf.supabase.co',
  candidateOtpEnabled: false, // Only enable after Meta approval, audited backend deployment, and end-to-end tests.
  // Must match the CAPTCHA provider selected in Supabase Auth. Public site key only; never put a CAPTCHA secret here.
  candidateOtpCaptchaProvider: 'turnstile', // Supported values: 'turnstile' or 'hcaptcha'.
  candidateOtpCaptchaSiteKey: '', // Required before enabling OTP; use a free provider site key.
  supabasePublishableKey: 'sb_publishable_CEoBm5kONv5LgL8XaIBaFw_6T1_LPGH'
});
