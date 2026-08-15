const menuToggle = document.querySelector('[data-menu-toggle]');
const navigation = document.querySelector('[data-navigation]');

if (menuToggle && navigation) {
  const closeMenu = () => {
    menuToggle.setAttribute('aria-expanded', 'false');
    navigation.classList.remove('is-open');
    document.body.classList.remove('menu-open');
  };

  menuToggle.addEventListener('click', () => {
    const isOpen = menuToggle.getAttribute('aria-expanded') === 'true';
    menuToggle.setAttribute('aria-expanded', String(!isOpen));
    navigation.classList.toggle('is-open', !isOpen);
    document.body.classList.toggle('menu-open', !isOpen);
  });

  navigation.addEventListener('click', (event) => {
    if (event.target.closest('a')) closeMenu();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && navigation.classList.contains('is-open')) {
      closeMenu();
      menuToggle.focus();
    }
  });

  window.addEventListener('resize', () => {
    if (window.innerWidth > 900) closeMenu();
  });
}

const phoneLink = document.querySelector('a[href^="tel:"]');
const emailLink = document.querySelector('a[href^="mailto:"]');
const phoneDigits = phoneLink ? phoneLink.getAttribute('href').replace(/\D/g, '') : '';
const businessPhone = phoneDigits.length === 10 ? `91${phoneDigits}` : phoneDigits;
const businessEmail = emailLink ? emailLink.getAttribute('href').replace(/^mailto:/, '').split('?')[0] : '';

const flowConfig = {
  employer: {
    title: 'Employer Manpower Requirement',
    subject: 'Manpower Requirement - Aadhyant',
    fields: [
      ['Company', 'company'], ['Contact Person', 'contactPerson'], ['Mobile', 'mobile'],
      ['Email', 'email'], ['Location', 'location'], ['Job Role', 'jobRole'],
      ['Headcount', 'headcount'], ['Qualification', 'qualification'],
      ['ITI Trade / Specialization', 'trade'], ['Experience', 'experience'],
      ['Gender Preference', 'genderPreference'], ['Salary', 'salary'], ['Shift', 'shift'],
      ['Working Hours', 'workingHours'], ['Joining', 'joining'],
      ['Accommodation', 'accommodation'], ['Canteen', 'canteen'],
      ['Transport', 'transport'], ['Notes', 'notes']
    ]
  },
  candidate: {
    title: 'Candidate Registration',
    subject: 'Candidate Registration - Aadhyant',
    fields: [
      ['Name', 'fullName'], ['Age', 'age'], ['Gender', 'gender'], ['Mobile', 'mobile'],
      ['WhatsApp', 'whatsapp'], ['Village / City', 'city'], ['District', 'district'],
      ['State', 'state'], ['Qualification', 'qualification'],
      ['Trade / Specialization', 'trade'], ['Candidate Type', 'candidateType'],
      ['Experience', 'totalExperience'], ['Previous Job Role', 'previousRole'],
      ['Can Attend Interview', 'interview'], ['Preferred Location', 'preferredLocation'],
      ['Additional Information', 'additional']
    ]
  }
};

const databaseConfig = {
  employer: {
    table: 'employer_requirements',
    successTitle: 'Requirement Submitted Successfully',
    success: 'Your manpower requirement has been submitted successfully. Our team can review the details and contact you.',
    error: 'We could not submit your requirement online. Your details are still available on this page. Please try again or contact us by WhatsApp, phone, or email.',
    buttonLabel: 'Submit Requirement',
    payload: (data) => ({
      company_name: data.get('company').trim(),
      contact_person: data.get('contactPerson').trim(),
      mobile: data.get('mobile').trim(),
      email: data.get('email').trim() || null,
      company_location: data.get('location').trim(),
      job_role: data.get('jobRole').trim(),
      required_headcount: Number(data.get('headcount')),
      qualification: data.get('qualification') || null,
      iti_trade: data.get('trade').trim() || null,
      experience_requirement: data.get('experience') || null,
      gender_preference: data.get('genderPreference') || null,
      salary_wage: data.get('salary').trim() || null,
      shift_details: data.get('shift').trim() || null,
      working_hours: data.get('workingHours').trim() || null,
      expected_joining_date: data.get('joining') || null,
      accommodation: data.get('accommodation') || null,
      canteen: data.get('canteen') || null,
      transport: data.get('transport') || null,
      additional_notes: data.get('notes').trim() || null,
      consent: data.get('consent') === 'on'
    })
  },
  candidate: {
    table: 'candidates',
    successTitle: 'Registration Submitted Successfully',
    success: 'Your registration has been submitted successfully. Your details can now be considered for suitable job opportunities.',
    error: 'We could not submit your registration online. Your details are still available on this page. Please try again or contact us by WhatsApp, phone, or email.',
    buttonLabel: 'Submit Registration',
    payload: (data) => ({
      full_name: data.get('fullName').trim(),
      age: Number(data.get('age')),
      gender: data.get('gender'),
      mobile: data.get('mobile').trim(),
      whatsapp_number: data.get('whatsapp').trim() || null,
      current_location: data.get('city').trim(),
      district: data.get('district').trim(),
      state: data.get('state').trim(),
      highest_qualification: data.get('qualification'),
      specialization: data.get('trade').trim() || null,
      candidate_type: data.get('candidateType'),
      total_experience: data.get('totalExperience')?.trim() || null,
      previous_job_role: data.get('previousRole')?.trim() || null,
      interview_available: data.get('interview'),
      preferred_job_location: data.get('preferredLocation').trim() || null,
      additional_information: data.get('additional').trim() || null,
      consent: data.get('consent') === 'on'
    })
  }
};

const setSubmissionStatus = (element, message, type = '', title = '') => {
  element.replaceChildren();
  element.classList.toggle('is-success', type === 'success');
  if (title) {
    const heading = document.createElement('strong');
    heading.textContent = title;
    element.append(heading);
  }
  if (message) {
    const copy = document.createElement('span');
    copy.textContent = message;
    element.append(copy);
  }
};

const getFieldError = (field) => {
  if (field.type === 'checkbox' && field.required && !field.checked) {
    return 'Please confirm your consent before continuing.';
  }
  if (field.required && !String(field.value).trim()) return 'This field is required.';
  if (field.validity.typeMismatch) return 'Enter a valid email address.';
  if (field.validity.patternMismatch) return 'Enter a valid 10-digit Indian mobile number starting with 6, 7, 8 or 9.';
  if (field.validity.rangeUnderflow || field.validity.rangeOverflow) {
    if (field.name === 'age') return 'Enter an age between 16 and 75.';
    return `Enter a value of at least ${field.min}.`;
  }
  if (field.validity.stepMismatch || field.validity.badInput) return 'Enter a valid whole number.';
  return '';
};

const errorElementFor = (field) => {
  if (field.type === 'checkbox' && field.name === 'consent') {
    return document.getElementById(`${field.id}-error`);
  }
  return field.closest('.field')?.querySelector('.field-error') || null;
};

const showFieldError = (field, message) => {
  const error = errorElementFor(field);
  field.setAttribute('aria-invalid', message ? 'true' : 'false');
  if (error) {
    error.textContent = message;
    if (message) field.setAttribute('aria-describedby', error.id);
    else if (field.getAttribute('aria-describedby') === error.id) field.removeAttribute('aria-describedby');
  }
  if (field.type === 'checkbox' && field.name === 'consent') {
    field.closest('.consent-field')?.classList.toggle('has-error', Boolean(message));
  }
};

const validateField = (field) => {
  if (field.disabled || !field.willValidate) return true;
  const message = getFieldError(field);
  showFieldError(field, message);
  return !message;
};

const validateForm = (form) => {
  const fields = [...form.elements].filter((field) => field.matches('input, select, textarea'));
  let firstInvalid = null;
  fields.forEach((field) => {
    if (!validateField(field) && !firstInvalid) firstInvalid = field;
  });
  if (firstInvalid) {
    form.querySelector('.form-status').textContent = 'Please check the highlighted fields before reviewing your details.';
    firstInvalid.focus();
    return false;
  }
  form.querySelector('.form-status').textContent = '';
  return true;
};

const collectDetails = (form, config) => {
  const data = new FormData(form);
  return config.fields
    .map(([label, name]) => [label, String(data.get(name) || '').trim()])
    .filter(([, value]) => value);
};

const createMessage = (title, details) => [title, '', ...details.map(([label, value]) => `${label}: ${value}`)].join('\n');

const showReview = (type, form) => {
  const config = flowConfig[type];
  const review = document.querySelector(`[data-review="${type}"]`);
  const list = review.querySelector('[data-review-list]');
  const details = collectDetails(form, config);
  const message = createMessage(config.title, details);

  list.replaceChildren();
  details.forEach(([label, value]) => {
    const item = document.createElement('div');
    item.className = 'review-item';
    const term = document.createElement('dt');
    const description = document.createElement('dd');
    term.textContent = label;
    description.textContent = value;
    item.append(term, description);
    list.append(item);
  });

  review.querySelector(`[data-whatsapp="${type}"]`).href = `https://wa.me/${businessPhone}?text=${encodeURIComponent(message)}`;
  review.querySelector(`[data-email="${type}"]`).href = `mailto:${businessEmail}?subject=${encodeURIComponent(config.subject)}&body=${encodeURIComponent(message)}`;

  const submissionButton = review.querySelector(`[data-database-submit="${type}"]`);
  const submissionStatus = review.querySelector(`[data-submission-status="${type}"]`);
  if (window.aadhyantSupabase?.isConfigured) {
    setSubmissionStatus(submissionStatus, '');
    submissionButton.disabled = false;
    submissionButton.textContent = databaseConfig[type].buttonLabel;
  } else {
    setSubmissionStatus(submissionStatus, window.aadhyantSupabase?.configurationMessage || 'Online submission is temporarily unavailable. Please use WhatsApp or email instead.');
    submissionButton.disabled = true;
  }

  form.hidden = true;
  review.hidden = false;
  const heading = review.querySelector('h3');
  heading.tabIndex = -1;
  review.scrollIntoView({ behavior: 'smooth', block: 'start' });
  heading.focus({ preventScroll: true });
};

document.querySelectorAll('[data-lead-form]').forEach((form) => {
  const type = form.dataset.leadForm;

  form.addEventListener('submit', (event) => {
    event.preventDefault();
    if (validateForm(form)) showReview(type, form);
  });

  form.addEventListener('input', (event) => {
    if (event.target.matches('input, select, textarea') && event.target.getAttribute('aria-invalid') === 'true') {
      validateField(event.target);
    }
  });

  form.addEventListener('change', (event) => {
    if (event.target.matches('input, select, textarea')) validateField(event.target);
  });
});

document.querySelectorAll('[data-edit]').forEach((button) => {
  button.addEventListener('click', () => {
    const type = button.dataset.edit;
    const form = document.querySelector(`[data-lead-form="${type}"]`);
    const review = document.querySelector(`[data-review="${type}"]`);
    review.hidden = true;
    form.hidden = false;
    form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    form.querySelector('input, select, textarea')?.focus({ preventScroll: true });
  });
});

document.querySelectorAll('[data-database-submit]').forEach((button) => {
  button.addEventListener('click', async () => {
    const type = button.dataset.databaseSubmit;
    const settings = databaseConfig[type];
    const form = document.querySelector(`[data-lead-form="${type}"]`);
    const review = document.querySelector(`[data-review="${type}"]`);
    const status = review.querySelector(`[data-submission-status="${type}"]`);
    const connection = window.aadhyantSupabase;
    if (!connection?.isConfigured || !connection.client) {
      setSubmissionStatus(status, connection?.configurationMessage || 'Online submission is temporarily unavailable. Please use WhatsApp or email instead.');
      return;
    }

    button.disabled = true;
    button.textContent = 'Submitting…';
    setSubmissionStatus(status, '');
    try {
      const payload = settings.payload(new FormData(form));
      const { error } = await connection.client.from(settings.table).insert(payload);
      if (error) throw new Error('submission_failed');
      setSubmissionStatus(status, settings.success, 'success', settings.successTitle);
      button.textContent = 'Submitted';
      review.querySelector(`[data-edit="${type}"]`).hidden = true;
    } catch (_error) {
      setSubmissionStatus(status, settings.error);
      button.disabled = false;
      button.textContent = 'Retry Submission';
    }
  });
});

const candidateType = document.querySelector('[data-candidate-type]');
const experienceFields = document.querySelector('[data-experience-fields]');
if (candidateType && experienceFields) {
  const updateExperienceFields = () => {
    const show = candidateType.value === 'Experienced';
    experienceFields.hidden = !show;
    experienceFields.querySelectorAll('input').forEach((input) => {
      input.disabled = !show;
      if (!show) input.value = '';
    });
  };
  candidateType.addEventListener('change', updateExperienceFields);
  updateExperienceFields();
}

const sameAsMobile = document.querySelector('[data-same-mobile]');
const candidateMobile = document.getElementById('candidate-mobile');
const candidateWhatsApp = document.getElementById('candidate-whatsapp');
if (sameAsMobile && candidateMobile && candidateWhatsApp) {
  const copyMobile = () => {
    if (sameAsMobile.checked) {
      candidateWhatsApp.value = candidateMobile.value;
      candidateWhatsApp.readOnly = true;
      validateField(candidateWhatsApp);
    } else {
      candidateWhatsApp.readOnly = false;
    }
  };
  sameAsMobile.addEventListener('change', copyMobile);
  candidateMobile.addEventListener('input', copyMobile);
}
