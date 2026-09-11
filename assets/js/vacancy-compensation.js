(function () {
  'use strict';

  const earnings = ['basicDa','attendanceBonus','monthlyBonus','leaveAmount','otherFixedEarning'];
  const deductions = ['employeePf','employeeEsic','canteenDeduction','otherDeduction'];
  const employer = ['employerPf','employerEsic','gratuityProvision','bonusProvision','leaveProvision','otherCtcComponent'];
  const allInputs = ['payableDays', ...earnings, ...deductions, ...employer];
  const columns = Object.freeze({
    payableDays: 'payable_days', basicDa: 'basic_da', attendanceBonus: 'attendance_bonus', monthlyBonus: 'monthly_bonus',
    leaveAmount: 'leave_amount', otherFixedEarning: 'other_fixed_earning', grossWages: 'gross_wages', employeePf: 'employee_pf',
    employeeEsic: 'employee_esic', canteenDeduction: 'canteen_deduction', otherDeduction: 'other_deduction', employerPf: 'employer_pf',
    employerEsic: 'employer_esic', gratuityProvision: 'gratuity_provision', bonusProvision: 'bonus_provision', leaveProvision: 'leave_provision',
    otherCtcComponent: 'other_ctc_component', approxInHand: 'approx_in_hand', ctc: 'ctc', accommodationStatus: 'accommodation_status',
    accommodationChargeAmount: 'accommodation_charge_amount', accommodationChargeBasis: 'accommodation_charge_basis'
  });
  const labels = Object.freeze({
    payable_days: 'Payable Days', basic_da: 'Basic + DA', attendance_bonus: 'Attendance Bonus', monthly_bonus: 'Monthly Bonus',
    leave_amount: 'EL / Leave Amount', other_fixed_earning: 'Other Fixed Earning', employee_pf: 'Employee PF', employee_esic: 'Employee ESIC',
    canteen_deduction: 'Canteen Deduction', other_deduction: 'Other Deduction', employer_pf: 'Employer PF', employer_esic: 'Employer ESIC',
    gratuity_provision: 'Gratuity Provision', bonus_provision: 'Bonus Provision', leave_provision: 'Leave Provision', other_ctc_component: 'Other CTC Component'
  });
  const number = (value) => value === '' || value === null || value === undefined ? null : Number(value);
  const finite = (value) => Number.isFinite(value) ? value : null;
  const sum = (record, names) => names.reduce((total, name) => total + (finite(number(record[name])) || 0), 0);
  const money = (value, fallback = 'Not specified') => {
    const numeric = finite(number(value));
    return numeric === null ? fallback : `₹${numeric.toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
  };
  const sentence = (value) => String(value || '').replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase());

  function calculate(record = {}) {
    const grossWages = sum(record, earnings);
    const approxInHand = grossWages - sum(record, deductions);
    const ctc = grossWages + sum(record, employer);
    return { grossWages, approxInHand, ctc };
  }

  function hasStructuredSalary(record = {}) {
    return [...allInputs, 'grossWages', 'approxInHand', 'ctc'].some((name) => {
      const column = columns[name] || name;
      return record[name] !== null && record[name] !== undefined && record[name] !== '' || record[column] !== null && record[column] !== undefined && record[column] !== '';
    });
  }

  function valueFor(record, name) {
    const column = columns[name];
    const source = name.startsWith('accommodation') ? record?.accommodation_detail : record?.compensation;
    const nested = { accommodationStatus: 'status', accommodationChargeAmount: 'charge_amount', accommodationChargeBasis: 'charge_basis' }[name];
    return record?.[name] ?? record?.[column] ?? source?.[name] ?? source?.[column] ?? source?.[nested] ?? null;
  }

  function facility(value) {
    const normalized = String(value || '').trim().toLowerCase();
    if (!normalized || normalized === 'not applicable') return 'Not Applicable';
    if (normalized === 'yes' || normalized === 'available') return 'Available';
    if (normalized === 'no' || normalized === 'not available') return 'Not Available';
    return sentence(value);
  }

  function accommodation(record = {}) {
    const status = valueFor(record, 'accommodationStatus');
    if (status === 'free') return 'Free';
    if (status === 'chargeable') {
      const amount = money(valueFor(record, 'accommodationChargeAmount'), 'Chargeable');
      const basis = valueFor(record, 'accommodationChargeBasis') === 'per_day' ? 'per day' : 'per month';
      return `${amount} ${basis}`;
    }
    if (status === 'not_available') return 'Not Available';
    return facility(record.accommodation);
  }

  function legacySalary(record = {}) {
    const minimum = record.salaryMin ?? record.salary_min;
    const maximum = record.salaryMax ?? record.salary_max;
    if (minimum === null || minimum === undefined) return maximum === null || maximum === undefined ? 'Not specified' : `Up to ${money(maximum)}`;
    if (maximum === null || maximum === undefined) return `From ${money(minimum)}`;
    return `${money(minimum)} – ${money(maximum)}`;
  }

  function setChargeableState(form) {
    const status = form?.elements?.accommodationStatus;
    const charge = form?.querySelector?.('[data-accommodation-charge]');
    if (!status || !charge) return;
    const chargeable = status.value === 'chargeable';
    charge.hidden = !chargeable;
    charge.querySelectorAll('input,select').forEach((control) => {
      control.disabled = !chargeable;
      if (!chargeable) control.value = '';
    });
  }

  function writeTotals(form) {
    const record = Object.fromEntries(allInputs.map((name) => [name, form.elements[name]?.value ?? '']));
    const present = allInputs.some((name) => form.elements[name]?.value !== '');
    const totals = calculate(record);
    ['grossWages', 'approxInHand', 'ctc'].forEach((name) => { if (form.elements[name]) form.elements[name].value = present ? String(totals[name]) : ''; });
  }

  function wireForm(form) {
    if (!form) return;
    allInputs.forEach((name) => form.elements[name]?.addEventListener('input', () => writeTotals(form)));
    form.elements.accommodationStatus?.addEventListener('change', () => setChargeableState(form));
    setChargeableState(form);
  }

  function validate(form) {
    const payable = number(form.elements.payableDays?.value);
    if (payable !== null && (!Number.isInteger(payable) || payable < 1 || payable > 31)) return 'Payable Days must be a whole number from 1 to 31.';
    for (const name of allInputs.filter((name) => name !== 'payableDays')) {
      const current = number(form.elements[name]?.value);
      if (current !== null && (!Number.isFinite(current) || current < 0)) return 'Salary and wage amounts cannot be negative.';
    }
    if (form.elements.accommodationStatus?.value === 'chargeable') {
      const amount = number(form.elements.accommodationChargeAmount?.value);
      if (!Number.isFinite(amount) || amount <= 0 || !form.elements.accommodationChargeBasis?.value) return 'Enter a positive accommodation charge and choose its basis.';
    }
    return '';
  }

  function rpcParams(form) {
    const values = {};
    allInputs.forEach((name) => { values[`p_${columns[name]}`] = number(form.elements[name]?.value); });
    ['grossWages', 'approxInHand', 'ctc'].forEach((name) => { values[`p_${columns[name]}`] = number(form.elements[name]?.value); });
    values.p_accommodation_status = form.elements.accommodationStatus?.value || null;
    values.p_accommodation_charge_amount = number(form.elements.accommodationChargeAmount?.value);
    values.p_accommodation_charge_basis = form.elements.accommodationChargeBasis?.value || null;
    return values;
  }

  function hydrate(form, record = {}) {
    [...allInputs, 'grossWages', 'approxInHand', 'ctc', 'accommodationStatus', 'accommodationChargeAmount', 'accommodationChargeBasis'].forEach((name) => {
      const control = form.elements[name]; if (control) control.value = valueFor(record, name) ?? '';
    });
    setChargeableState(form); writeTotals(form);
  }

  window.AadhyantVacancyCompensation = Object.freeze({ columns, labels, calculate, hasStructuredSalary, money, facility, accommodation, legacySalary, wireForm, validate, rpcParams, hydrate, writeTotals });
}());
