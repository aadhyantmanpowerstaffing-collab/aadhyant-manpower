(() => {
  'use strict';
  window.AadhyantRegistrationNextSteps = ({email, loginUrl, reviewRequired = false, hasSession = false}) => {
    document.querySelector('[data-account-next-steps]')?.remove();
    const dialog = document.createElement('dialog');
    dialog.dataset.accountNextSteps = '';
    dialog.setAttribute('aria-labelledby', 'account-next-steps-title');
    dialog.setAttribute('aria-describedby', 'account-next-steps-description');
    const heading = document.createElement('h2');
    heading.id = 'account-next-steps-title';
    heading.textContent = hasSession ? 'Registration submitted' : 'Check your email to continue';
    const description = document.createElement('p');
    description.id = 'account-next-steps-description';
    description.textContent = hasSession ? 'Sign in to check your account approval status.' : `Check ${email} for the Aadhyant confirmation email. If you already have an account, sign in instead.`;
    dialog.append(heading, description);
    if (!hasSession) {
      const steps = document.createElement('ol');
      ['Open your email Inbox. Check Spam or Junk if needed.', 'Open the Aadhyant email and select the email confirmation link.', 'After confirming your email, return here and sign in with your email and password.'].forEach(text => { const item = document.createElement('li'); item.textContent = text; steps.append(item); });
      dialog.append(steps);
    }
    const next = document.createElement('p');
    next.textContent = reviewRequired ? 'Email confirmation and Aadhyant account approval are separate steps. Sign in to view your approval status.' : 'After signing in, complete your Candidate profile to continue.';
    const link = document.createElement('a');
    link.href = loginUrl;
    link.textContent = 'Go to Sign In';
    const close = document.createElement('button');
    close.type = 'button';
    close.textContent = hasSession ? 'OK' : 'OK, I will check my email';
    close.autofocus = true;
    close.addEventListener('click', () => dialog.close());
    dialog.append(next, link, close);
    document.body.append(dialog);
    dialog.showModal();
  };
})();
