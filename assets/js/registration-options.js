(function () {
  'use strict';

  const sets = Object.freeze({
    states: Object.freeze([
      'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh',
      'Chhattisgarh', 'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat', 'Haryana',
      'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand', 'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep',
      'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry',
      'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
      'West Bengal'
    ]),
    genders: Object.freeze(['Male', 'Female', 'Other / Prefer not to say']),
    qualifications: Object.freeze(['Below 10th', '10th', '12th', 'ITI', 'Diploma', 'Graduate', 'Post Graduate', 'Other']),
    candidateTypes: Object.freeze(['Fresher', 'Experienced']),
    interviewAvailability: Object.freeze(['Yes', 'No']),
    experienceDurations: Object.freeze(['Less than 1 year', '1 year', '2 years', '3 years', '4 years', '5 years', '6-10 years', '10+ years', 'Other']),
    workforceSizes: Object.freeze(['1-10', '11-50', '51-200', '201-500', '501-1000', '1000+']),
    industries: Object.freeze([
      'Automotive', 'Engineering', 'FMCG', 'Manufacturing', 'Warehouse & Logistics', 'Industrial Operations',
      'Construction & Infrastructure', 'Healthcare', 'Hospitality', 'Retail & E-commerce',
      'IT & Business Services', 'Other'
    ])
  });

  const tradesByQualification = Object.freeze({
    ITI: Object.freeze(['Fitter', 'Electrician', 'Welder', 'Machinist', 'Turner', 'Mechanic Diesel', 'COPA', 'Electronics Mechanic', 'Wireman', 'Other']),
    Diploma: Object.freeze(['Mechanical', 'Electrical', 'Electronics', 'Civil', 'Automobile', 'Production', 'Chemical', 'Other']),
    Graduate: Object.freeze(['Arts', 'Commerce', 'Science', 'Engineering', 'Business Administration', 'Computer Applications', 'Other']),
    'Post Graduate': Object.freeze(['Arts', 'Commerce', 'Science', 'Engineering', 'Business Administration', 'Computer Applications', 'Other']),
    Other: Object.freeze(['Other'])
  });

  function populate(select, values, placeholder) {
    if (!select) return;
    const current = select.value;
    select.replaceChildren();
    if (placeholder !== null) {
      const empty = document.createElement('option');
      empty.value = '';
      empty.textContent = placeholder || select.dataset.placeholder || 'Select an option';
      select.append(empty);
    }
    values.forEach((value) => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      select.append(option);
    });
    if (current) setValue(select, current);
  }

  function setValue(select, value) {
    if (!select) return;
    const normalized = String(value ?? '').trim();
    if (!normalized) {
      select.value = '';
      return;
    }
    if (![...select.options].some((option) => option.value === normalized)) {
      const option = document.createElement('option');
      option.value = normalized;
      option.textContent = `${normalized} (saved value)`;
      option.dataset.savedValue = 'true';
      select.append(option);
    }
    select.value = normalized;
  }

  function initialize(root = document) {
    root.querySelectorAll('select[data-option-set]').forEach((select) => {
      const values = sets[select.dataset.optionSet];
      if (!values) return;
      populate(select, values, select.dataset.placeholder ?? 'Select an option');
    });
  }

  function toggleOther(select, wrapper, input) {
    const show = select?.value === 'Other';
    if (wrapper) wrapper.hidden = !show;
    if (input) {
      input.disabled = !show;
      input.required = show;
      if (!show) input.value = '';
    }
  }

  function setupCandidateForm(form, initial = {}) {
    if (!form) return;
    initialize(form);
    const qualification = form.elements.highest_qualification;
    const specialization = form.elements.specialization;
    const specializationOther = form.elements.specialization_other;
    const specializationOtherWrap = form.querySelector('[data-specialization-other]');
    const candidateType = form.elements.candidate_type;
    const experienceWrap = form.querySelector('[data-experience-fields]');
    const duration = form.elements.total_experience;
    const durationOther = form.elements.total_experience_other;
    const durationOtherWrap = form.querySelector('[data-experience-other]');
    const previousRole = form.elements.previous_job_role;

    const syncSpecialization = (saved = '') => {
      const values = tradesByQualification[qualification?.value] || [];
      const hasChoices = values.length > 0;
      if (specialization) {
        populate(specialization, values, hasChoices ? 'Select trade / specialization' : 'Not applicable');
        specialization.disabled = !hasChoices;
      }
      if (!hasChoices) {
        if (specializationOtherWrap) specializationOtherWrap.hidden = true;
        if (specializationOther) {
          specializationOther.disabled = true;
          specializationOther.required = false;
          specializationOther.value = '';
        }
        return;
      }
      if (saved) {
        if (values.includes(saved)) setValue(specialization, saved);
        else {
          setValue(specialization, 'Other');
          specializationOther.value = saved;
        }
      }
      toggleOther(specialization, specializationOtherWrap, specializationOther);
    };

    const syncExperience = (saved = '') => {
      const experienced = candidateType?.value === 'Experienced';
      if (experienceWrap) experienceWrap.hidden = !experienced;
      [duration, previousRole].forEach((control) => {
        if (!control) return;
        control.disabled = !experienced;
        control.required = experienced;
      });
      if (experienced && saved) {
        if (sets.experienceDurations.includes(saved)) setValue(duration, saved);
        else {
          setValue(duration, 'Other');
          durationOther.value = saved;
        }
      }
      toggleOther(duration, durationOtherWrap, durationOther);
      if (!experienced) {
        if (duration) duration.value = '';
        if (durationOther) durationOther.value = '';
        if (previousRole) previousRole.value = '';
      }
    };

    qualification?.addEventListener('change', () => syncSpecialization(''));
    specialization?.addEventListener('change', () => toggleOther(specialization, specializationOtherWrap, specializationOther));
    candidateType?.addEventListener('change', () => syncExperience(''));
    duration?.addEventListener('change', () => toggleOther(duration, durationOtherWrap, durationOther));
    syncSpecialization(initial.specialization || '');
    syncExperience(initial.totalExperience || '');
  }

  function candidateSpecialization(form) {
    const selected = String(form.elements.specialization?.value || '').trim();
    return selected === 'Other' ? String(form.elements.specialization_other?.value || '').trim() : selected;
  }

  function candidateExperience(form) {
    if (form.elements.candidate_type?.value !== 'Experienced') return '';
    const selected = String(form.elements.total_experience?.value || '').trim();
    return selected === 'Other' ? String(form.elements.total_experience_other?.value || '').trim() : selected;
  }

  window.AadhyantRegistrationOptions = Object.freeze({
    sets,
    tradesByQualification,
    populate,
    setValue,
    initialize,
    setupCandidateForm,
    candidateSpecialization,
    candidateExperience
  });

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => initialize());
  else initialize();
}());
