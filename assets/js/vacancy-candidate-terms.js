(function () {
  'use strict';
  const status = ['free', 'chargeable', 'not_available', 'not_applicable'];
  const basis = { canteen: ['per_day', 'per_meal', 'per_month'], transport: ['per_day', 'per_month'] };
  const annualLeave = ['paidLeaveDaysPerYear','casualLeaveDaysPerYear','sickLeaveDaysPerYear','nationalHolidayDaysPerYear','festivalHolidayDaysPerYear'];
  const scalar = ['compensationCadence','paidLeaveDaysPerYear','casualLeaveDaysPerYear','sickLeaveDaysPerYear','nationalHolidayDaysPerYear','festivalHolidayDaysPerYear','workingDaysPerWeek','weeklyOffCount','overtimeRate','overtimeRateBasis','canteenStatus','canteenChargeAmount','canteenChargeBasis','transportStatus','transportChargeAmount','transportChargeBasis','employmentType','payrollType','contractDurationMonths','probationPeriodMonths','trainingPeriodDays','noticePeriodDays'];
  const column = Object.fromEntries(scalar.map((key) => [key, key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)]));
  const number = (value) => value === '' || value == null ? null : Number(value);
  const normalizeFacility = (form, facility) => {
    const chargeable = form.elements[`${facility}Status`]?.value === 'chargeable';
    ['Amount', 'Basis'].forEach((suffix) => {
      const control = form.elements[`${facility}Charge${suffix}`];
      if (!control) return;
      if (!chargeable) control.value = '';
      control.disabled = !chargeable;
    });
    const container = form.querySelector(`[data-${facility}-charge]`);
    if (container) container.hidden = !chargeable;
    return chargeable;
  };
  const terms = (form) => {
    ['canteen', 'transport'].forEach((facility) => normalizeFacility(form, facility));
    const values = {};
    scalar.forEach((key) => { const control = form.elements[key]; if (!control) return; const value = [...annualLeave,'workingDaysPerWeek','weeklyOffCount','overtimeRate','canteenChargeAmount','transportChargeAmount','contractDurationMonths','probationPeriodMonths','trainingPeriodDays','noticePeriodDays'].includes(key) ? number(control.value) : String(control.value || '').trim() || null; values[column[key]] = value; });
    values.benefits = [];
    form.querySelectorAll('[data-candidate-benefit]').forEach((row) => { const type=row.querySelector('[name=benefitType]')?.value; const kind=row.querySelector('[name=benefitValueType]')?.value; if (!type || !kind) return; values.benefits.push({ benefit_type:type, benefit_value_type:kind, amount:number(row.querySelector('[name=benefitAmount]')?.value), amount_basis:row.querySelector('[name=benefitAmountBasis]')?.value || null }); });
    return values;
  };
  const validate = (form) => {
    const t=terms(form), err=(text)=>text;
    if ((t.compensation_cadence && !['monthly','annual'].includes(t.compensation_cadence))) return err('Choose a valid compensation cadence.');
    for (const field of annualLeave) { const value=t[column[field]]; if (value!=null && (!Number.isInteger(value) || value<0 || value>366)) return err('Annual leave and holiday values must be whole days from 0 through 366.'); }
    if (t.working_days_per_week!=null && t.weekly_off_count!=null && t.working_days_per_week+t.weekly_off_count!==7) return err('Working days plus weekly off must equal 7.');
    if ((t.overtime_rate==null)!==(t.overtime_rate_basis==null) || (t.overtime_rate!=null && t.overtime_rate<=0)) return err('Overtime rate and basis must be supplied together, with a positive rate.');
    for (const facility of ['canteen','transport']) { const s=t[`${facility}_status`], amount=t[`${facility}_charge_amount`], unit=t[`${facility}_charge_basis`]; if (s && !status.includes(s)) return err(`Choose a valid ${facility} status.`); if (s==='chargeable' && (!(amount>0) || !basis[facility].includes(unit))) return err(`Enter a positive ${facility} charge and valid basis.`); if (s && s!=='chargeable' && (amount!=null || unit!=null)) return err(`Clear ${facility} charge terms unless it is Chargeable.`); }
    if (t.employment_type!=='contract' && t.contract_duration_months!=null) return err('Contract duration applies only to Contract employment.');
    for (const benefit of t.benefits) { if (benefit.benefit_value_type==='cash' && (!(benefit.amount>0)||!benefit.amount_basis)) return err('Cash benefits require a positive amount and basis.'); if (benefit.benefit_value_type==='provided' && (benefit.amount!=null||benefit.amount_basis)) return err('Provided benefits cannot include a cash amount.'); }
    return null;
  };
  const hydrate = (form, current={}) => { const source=current.candidate_terms||current; scalar.forEach((key)=>{const c=form.elements[key];if(c&&source[column[key]]!=null)c.value=source[column[key]];}); const host=form.querySelector('[data-candidate-benefits]'), template=form.querySelector('template[data-candidate-benefit-template]'); if(host&&template){host.replaceChildren();(current.candidate_benefits||[]).forEach((benefit)=>{const fragment=template.content.cloneNode(true);const row=fragment.querySelector('[data-candidate-benefit]');row.querySelector('[name=benefitType]').value=benefit.benefit_type||'';row.querySelector('[name=benefitValueType]').value=benefit.benefit_value_type||'provided';row.querySelector('[name=benefitAmount]').value=benefit.amount??'';row.querySelector('[name=benefitAmountBasis]').value=benefit.amount_basis||'';row.querySelectorAll('[data-benefit-cash]').forEach((node)=>{node.hidden=benefit.benefit_value_type!=='cash';});host.append(fragment);});} };
  const wire = (form) => {
    const toggle=(facility)=>normalizeFacility(form, facility);
    ['canteen','transport'].forEach((facility)=>{form.elements[`${facility}Status`]?.addEventListener('change',()=>toggle(facility));toggle(facility);});
    form.elements.employmentType?.addEventListener('change',()=>{const row=form.querySelector('[data-contract-duration]');if(row)row.hidden=form.elements.employmentType.value!=='contract';});
    form.querySelector('[data-add-candidate-benefit]')?.addEventListener('click', () => { const template=form.querySelector('template[data-candidate-benefit-template]'); const host=form.querySelector('[data-candidate-benefits]'); if (template && host) host.append(template.content.cloneNode(true)); });
    form.addEventListener('change', (event) => { if (event.target?.name==='benefitValueType') { const row=event.target.closest('[data-candidate-benefit]'); const cash=event.target.value==='cash'; row?.querySelectorAll('[data-benefit-cash]').forEach((node)=>{node.hidden=!cash;}); } });
  };
  window.AadhyantVacancyCandidateTerms=Object.freeze({ terms, validate, hydrate, wire, normalizeFacility, column });
}());
