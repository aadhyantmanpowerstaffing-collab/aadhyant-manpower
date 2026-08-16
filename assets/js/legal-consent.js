(() => {
  'use strict';

  const configurations = {
    company: {
      body: '[data-company-page="register"]',
      label: '.consent-field label',
      text: 'I voluntarily submit this Company and contact information for account review and workforce coordination. I understand that registration is subject to review and does not activate access automatically.',
      id: 'company-consent-legal'
    },
    partner: {
      body: '[data-contractor-page="register"]',
      label: 'label.consent',
      text: 'I voluntarily submit this agency and contact information for onboarding review and workforce coordination. I understand that registration is subject to approval and does not guarantee assignments, business or revenue.',
      id: 'partner-consent-legal'
    }
  };

  const initialize = () => {
    const configuration = Object.values(configurations).find(({ body }) => document.querySelector(body));
    if (!configuration) return;
    const label = document.querySelector(configuration.label);
    const checkbox = label?.querySelector('input[name="consent"]');
    const text = label?.querySelector('span');
    if (!label || !checkbox || !text || document.getElementById(configuration.id)) return;

    text.textContent = configuration.text;
    checkbox.setAttribute('aria-describedby', configuration.id);
    const legal = document.createElement('p');
    legal.id = configuration.id;
    legal.className = 'consent-legal';
    legal.style.margin = '.5rem 0 0';
    legal.style.color = '#53627a';
    legal.style.fontSize = '.75rem';
    legal.append('By continuing, I accept the ');
    const privacy = document.createElement('a');
    privacy.href = '../privacy/';
    privacy.textContent = 'Privacy Policy';
    const terms = document.createElement('a');
    terms.href = '../terms/';
    terms.textContent = 'Terms of Use';
    legal.append(privacy, ' and ', terms, '.');
    label.after(legal);
  };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initialize, { once: true });
  else initialize();
})();
