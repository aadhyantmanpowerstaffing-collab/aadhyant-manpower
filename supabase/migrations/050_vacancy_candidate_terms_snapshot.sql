-- Candidate-safe, per-vacancy employment-terms snapshots.  This migration is
-- additive: legacy salary and facility fields remain authoritative fallbacks.
begin;

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null then
    raise exception 'Migration 050 requires the reviewed M044-M049 vacancy contract';
  end if;
end $$;

alter table public.employer_requirements
  add column if not exists compensation_cadence text,
  add column if not exists paid_leave_days_per_year integer,
  add column if not exists casual_leave_days_per_year integer,
  add column if not exists sick_leave_days_per_year integer,
  add column if not exists national_holiday_days_per_year integer,
  add column if not exists festival_holiday_days_per_year integer,
  add column if not exists working_days_per_week integer,
  add column if not exists weekly_off_count integer,
  add column if not exists overtime_rate numeric,
  add column if not exists overtime_rate_basis text,
  add column if not exists canteen_status text,
  add column if not exists canteen_charge_amount numeric,
  add column if not exists canteen_charge_basis text,
  add column if not exists transport_status text,
  add column if not exists transport_charge_amount numeric,
  add column if not exists transport_charge_basis text,
  add column if not exists employment_type text,
  add column if not exists payroll_type text,
  add column if not exists contract_duration_months integer,
  add column if not exists probation_period_months integer,
  add column if not exists training_period_days integer,
  add column if not exists notice_period_days integer;

alter table public.employer_requirements
  drop constraint if exists employer_requirements_compensation_cadence_m050_check,
  add constraint employer_requirements_compensation_cadence_m050_check check (compensation_cadence is null or compensation_cadence in ('monthly','annual')),
  drop constraint if exists employer_requirements_leave_days_m050_check,
  add constraint employer_requirements_leave_days_m050_check check (
    (paid_leave_days_per_year is null or paid_leave_days_per_year between 0 and 366) and (casual_leave_days_per_year is null or casual_leave_days_per_year between 0 and 366)
    and (sick_leave_days_per_year is null or sick_leave_days_per_year between 0 and 366) and (national_holiday_days_per_year is null or national_holiday_days_per_year between 0 and 366)
    and (festival_holiday_days_per_year is null or festival_holiday_days_per_year between 0 and 366)),
  drop constraint if exists employer_requirements_work_week_m050_check,
  add constraint employer_requirements_work_week_m050_check check (
    (working_days_per_week is null or working_days_per_week between 1 and 7) and (weekly_off_count is null or weekly_off_count between 0 and 6)
    and (working_days_per_week is null or weekly_off_count is null or working_days_per_week+weekly_off_count=7)),
  drop constraint if exists employer_requirements_overtime_rate_m050_check,
  add constraint employer_requirements_overtime_rate_m050_check check (
    case
      when overtime_rate is null then overtime_rate_basis is null
      when overtime_rate_basis is null then false
      when overtime_rate<=0 then false
      else overtime_rate_basis in ('per_hour','per_day','multiplier')
    end),
  drop constraint if exists employer_requirements_canteen_terms_m050_check,
  add constraint employer_requirements_canteen_terms_m050_check check (
    case
      when canteen_status is null then canteen_charge_amount is null and canteen_charge_basis is null
      when canteen_status='chargeable' then canteen_charge_amount is not null and canteen_charge_amount>0 and canteen_charge_basis is not null and canteen_charge_basis in ('per_day','per_meal','per_month')
      when canteen_status in ('free','not_available','not_applicable') then canteen_charge_amount is null and canteen_charge_basis is null
      else false
    end),
  drop constraint if exists employer_requirements_transport_terms_m050_check,
  add constraint employer_requirements_transport_terms_m050_check check (
    case
      when transport_status is null then transport_charge_amount is null and transport_charge_basis is null
      when transport_status='chargeable' then transport_charge_amount is not null and transport_charge_amount>0 and transport_charge_basis is not null and transport_charge_basis in ('per_day','per_month')
      when transport_status in ('free','not_available','not_applicable') then transport_charge_amount is null and transport_charge_basis is null
      else false
    end),
  drop constraint if exists employer_requirements_employment_terms_m050_check,
  add constraint employer_requirements_employment_terms_m050_check check (
    (employment_type is null or employment_type in ('permanent','contract','temporary','trainee','apprentice'))
    and (payroll_type is null or payroll_type in ('company','contractor','third_party'))
    and (contract_duration_months is null or contract_duration_months between 1 and 120)
    and (probation_period_months is null or probation_period_months between 1 and 24)
    and (training_period_days is null or training_period_days between 1 and 365)
    and (notice_period_days is null or notice_period_days between 1 and 180)
    and (contract_duration_months is null or (employment_type is not null and employment_type='contract')));

create table private.vacancy_candidate_benefits (
  requirement_id uuid not null references public.employer_requirements(id) on delete cascade,
  benefit_type text not null check (benefit_type in ('production_incentive','performance_incentive','night_shift_allowance','travel_allowance','conveyance_allowance','joining_bonus','retention_bonus','insurance','medical_benefit','uniform','safety_shoes','ppe')),
  benefit_value_type text not null check (benefit_value_type in ('cash','provided')),
  amount numeric,
  amount_basis text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(requirement_id,benefit_type),
  check (
    case
      when benefit_value_type='cash' then amount is not null and amount>0 and amount_basis is not null and amount_basis in ('per_day','per_month','one_time','annual')
      when benefit_value_type='provided' then amount is null and amount_basis is null
      else false
    end
  )
);
alter table private.vacancy_candidate_benefits enable row level security;
revoke all on table private.vacancy_candidate_benefits from public,anon,authenticated;

create or replace function private.vacancy_candidate_terms_projection(p_requirement public.employer_requirements)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'compensation_cadence',p_requirement.compensation_cadence,'paid_leave_days_per_year',p_requirement.paid_leave_days_per_year,
    'casual_leave_days_per_year',p_requirement.casual_leave_days_per_year,'sick_leave_days_per_year',p_requirement.sick_leave_days_per_year,
    'national_holiday_days_per_year',p_requirement.national_holiday_days_per_year,'festival_holiday_days_per_year',p_requirement.festival_holiday_days_per_year,
    'working_days_per_week',p_requirement.working_days_per_week,'weekly_off_count',p_requirement.weekly_off_count,
    'overtime_rate',p_requirement.overtime_rate,'overtime_rate_basis',p_requirement.overtime_rate_basis,
    'canteen_status',p_requirement.canteen_status,'canteen_charge_amount',p_requirement.canteen_charge_amount,'canteen_charge_basis',p_requirement.canteen_charge_basis,
    'transport_status',p_requirement.transport_status,'transport_charge_amount',p_requirement.transport_charge_amount,'transport_charge_basis',p_requirement.transport_charge_basis,
    'employment_type',p_requirement.employment_type,'payroll_type',p_requirement.payroll_type,'contract_duration_months',p_requirement.contract_duration_months,
    'probation_period_months',p_requirement.probation_period_months,'training_period_days',p_requirement.training_period_days,'notice_period_days',p_requirement.notice_period_days));
$$;
revoke all on function private.vacancy_candidate_terms_projection(public.employer_requirements) from public,anon,authenticated;

create or replace function private.vacancy_candidate_benefits_projection(p_requirement_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('benefit_type',b.benefit_type,'benefit_value_type',b.benefit_value_type,'amount',b.amount,'amount_basis',b.amount_basis)) order by b.benefit_type),'[]'::jsonb)
  from private.vacancy_candidate_benefits b where b.requirement_id=p_requirement_id;
$$;
revoke all on function private.vacancy_candidate_benefits_projection(uuid) from public,anon,authenticated;

-- Benefit order is not a Candidate-term semantic.  The M050 idempotency
-- fingerprint therefore uses this canonical snapshot while M049 remains the
-- sole authority for the base-vacancy payload fingerprint.
create or replace function private.canonical_vacancy_candidate_terms(p_terms jsonb)
returns jsonb language sql immutable security definer set search_path='' as $$
  select (jsonb_strip_nulls(coalesce(p_terms,'{}'::jsonb))-'benefits') || jsonb_build_object(
    'benefits',coalesce((select jsonb_agg(jsonb_strip_nulls(value) order by value->>'benefit_type',value::text)
      from jsonb_array_elements(coalesce(p_terms->'benefits','[]'::jsonb)) value),'[]'::jsonb));
$$;
revoke all on function private.canonical_vacancy_candidate_terms(jsonb) from public,anon,authenticated;

create or replace function private.apply_vacancy_candidate_terms(p_requirement_id uuid,p_terms jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_terms jsonb:=coalesce(p_terms,'{}'::jsonb); v_key text; v_benefit jsonb;
begin
  if jsonb_typeof(v_terms)<>'object' then raise exception 'Candidate vacancy terms must be an object'; end if;
  if exists(select 1 from jsonb_object_keys(v_terms) k where k not in ('compensation_cadence','paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year','working_days_per_week','weekly_off_count','overtime_rate','overtime_rate_basis','canteen_status','canteen_charge_amount','canteen_charge_basis','transport_status','transport_charge_amount','transport_charge_basis','employment_type','payroll_type','contract_duration_months','probation_period_months','training_period_days','notice_period_days','benefits')) then
    raise exception 'Unsupported Candidate vacancy term';
  end if;
  update public.employer_requirements r set
    compensation_cadence=nullif(v_terms->>'compensation_cadence',''), paid_leave_days_per_year=nullif(v_terms->>'paid_leave_days_per_year','')::integer,
    casual_leave_days_per_year=nullif(v_terms->>'casual_leave_days_per_year','')::integer, sick_leave_days_per_year=nullif(v_terms->>'sick_leave_days_per_year','')::integer,
    national_holiday_days_per_year=nullif(v_terms->>'national_holiday_days_per_year','')::integer, festival_holiday_days_per_year=nullif(v_terms->>'festival_holiday_days_per_year','')::integer,
    working_days_per_week=nullif(v_terms->>'working_days_per_week','')::integer, weekly_off_count=nullif(v_terms->>'weekly_off_count','')::integer,
    overtime_rate=nullif(v_terms->>'overtime_rate','')::numeric, overtime_rate_basis=nullif(v_terms->>'overtime_rate_basis',''),
    canteen_status=nullif(v_terms->>'canteen_status',''), canteen_charge_amount=nullif(v_terms->>'canteen_charge_amount','')::numeric, canteen_charge_basis=nullif(v_terms->>'canteen_charge_basis',''),
    transport_status=nullif(v_terms->>'transport_status',''), transport_charge_amount=nullif(v_terms->>'transport_charge_amount','')::numeric, transport_charge_basis=nullif(v_terms->>'transport_charge_basis',''),
    employment_type=nullif(v_terms->>'employment_type',''), payroll_type=nullif(v_terms->>'payroll_type',''), contract_duration_months=nullif(v_terms->>'contract_duration_months','')::integer,
    probation_period_months=nullif(v_terms->>'probation_period_months','')::integer, training_period_days=nullif(v_terms->>'training_period_days','')::integer, notice_period_days=nullif(v_terms->>'notice_period_days','')::integer
  where r.id=p_requirement_id;
  if not found then raise exception 'Vacancy was not found'; end if;
  if exists(select 1 from public.employer_requirements r where r.id=p_requirement_id and r.ctc is not null and r.compensation_cadence is null) then
    raise exception 'Compensation cadence is required when structured CTC is supplied';
  end if;
  delete from private.vacancy_candidate_benefits where requirement_id=p_requirement_id;
  if v_terms ? 'benefits' then
    if jsonb_typeof(v_terms->'benefits')<>'array' then raise exception 'Candidate benefits must be an array'; end if;
    for v_benefit in select value from jsonb_array_elements(v_terms->'benefits') loop
      insert into private.vacancy_candidate_benefits(requirement_id,benefit_type,benefit_value_type,amount,amount_basis)
      values(p_requirement_id,nullif(v_benefit->>'benefit_type',''),nullif(v_benefit->>'benefit_value_type',''),nullif(v_benefit->>'amount','')::numeric,nullif(v_benefit->>'amount_basis',''));
    end loop;
  end if;
end;
$$;
revoke all on function private.apply_vacancy_candidate_terms(uuid,jsonb) from public,anon,authenticated;

-- An approved/public vacancy is immediately removed from Candidate eligibility
-- when an approved Candidate-facing snapshot changes.  The existing source
-- workflow supplies the later explicit approval/publication transition.
create or replace function private.require_vacancy_candidate_terms_rereview(p_requirement_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_source text;
begin
  select source_type into v_source from public.employer_requirements where id=p_requirement_id for update;
  if not found or not private.vacancy_is_application_eligible(p_requirement_id) then return; end if;
  update public.employer_requirements set requirement_stage='draft',requirement_visibility='private',published_at=null,review_status=case when v_source='contractor_portal' then review_status else 'pending_review' end,submitted_at=clock_timestamp(),reviewed_at=null where id=p_requirement_id;
  if v_source='contractor_portal' then update public.requirement_contractors set submission_status='submitted',submitted_at=clock_timestamp(),reviewed_at=null where requirement_id=p_requirement_id and origin_type='contractor_submission'; end if;
end;
$$;
revoke all on function private.require_vacancy_candidate_terms_rereview(uuid) from public,anon,authenticated;

create or replace function private.vacancy_candidate_terms_material_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if row(old.salary_min,old.salary_max,old.salary_wage,old.payable_days,old.basic_da,old.attendance_bonus,old.monthly_bonus,old.leave_amount,old.other_fixed_earning,old.gross_wages,old.employee_pf,old.employee_esic,old.canteen_deduction,old.other_deduction,old.employer_pf,old.employer_esic,old.gratuity_provision,old.bonus_provision,old.leave_provision,old.other_ctc_component,old.approx_in_hand,old.ctc,old.compensation_cadence,old.paid_leave_days_per_year,old.casual_leave_days_per_year,old.sick_leave_days_per_year,old.national_holiday_days_per_year,old.festival_holiday_days_per_year,old.working_days_per_week,old.weekly_off_count,old.overtime_rate,old.overtime_rate_basis,old.canteen_status,old.canteen_charge_amount,old.canteen_charge_basis,old.transport_status,old.transport_charge_amount,old.transport_charge_basis,old.accommodation_status,old.accommodation_charge_amount,old.accommodation_charge_basis,old.employment_type,old.payroll_type,old.contract_duration_months,old.probation_period_months,old.training_period_days,old.notice_period_days) is distinct from row(new.salary_min,new.salary_max,new.salary_wage,new.payable_days,new.basic_da,new.attendance_bonus,new.monthly_bonus,new.leave_amount,new.other_fixed_earning,new.gross_wages,new.employee_pf,new.employee_esic,new.canteen_deduction,new.other_deduction,new.employer_pf,new.employer_esic,new.gratuity_provision,new.bonus_provision,new.leave_provision,new.other_ctc_component,new.approx_in_hand,new.ctc,new.compensation_cadence,new.paid_leave_days_per_year,new.casual_leave_days_per_year,new.sick_leave_days_per_year,new.national_holiday_days_per_year,new.festival_holiday_days_per_year,new.working_days_per_week,new.weekly_off_count,new.overtime_rate,new.overtime_rate_basis,new.canteen_status,new.canteen_charge_amount,new.canteen_charge_basis,new.transport_status,new.transport_charge_amount,new.transport_charge_basis,new.accommodation_status,new.accommodation_charge_amount,new.accommodation_charge_basis,new.employment_type,new.payroll_type,new.contract_duration_months,new.probation_period_months,new.training_period_days,new.notice_period_days) and private.vacancy_is_application_eligible(old.id) then
    new.requirement_stage:='draft'; new.requirement_visibility:='private'; new.published_at:=null; new.submitted_at:=clock_timestamp(); new.reviewed_at:=null;
    if old.source_type='contractor_portal' then
      update public.requirement_contractors set submission_status='submitted',submitted_at=clock_timestamp(),reviewed_at=null where requirement_id=old.id and origin_type='contractor_submission';
    else
      new.review_status:='pending_review';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.vacancy_candidate_terms_material_change() from public,anon,authenticated;
create trigger vacancy_candidate_terms_material_change_guard before update on public.employer_requirements for each row execute function private.vacancy_candidate_terms_material_change();

create or replace function private.vacancy_candidate_benefit_material_change()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform private.require_vacancy_candidate_terms_rereview(coalesce(new.requirement_id,old.requirement_id));
  return coalesce(new,old);
end;
$$;
revoke all on function private.vacancy_candidate_benefit_material_change() from public,anon,authenticated;
create trigger vacancy_candidate_benefit_material_change_guard after insert or update or delete on private.vacancy_candidate_benefits for each row execute function private.vacancy_candidate_benefit_material_change();

-- New overloads append the snapshot payload, preserving reviewed M044-M049
-- callers and keeping all browser writes inside established owner RPCs.
create function public.manage_company_portal_requirement(
  p_action text,p_requirement_id uuid,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text,p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text,p_candidate_terms jsonb)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_result record; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
 select * into v_result from public.manage_company_portal_requirement(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,p_expected_joining_date,p_additional_notes,p_payable_days,p_basic_da,p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,p_canteen_deduction,p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis);
 if v_action in ('create','create_draft','create_and_submit','update','update_draft') then perform private.apply_vacancy_candidate_terms(v_result.id,p_candidate_terms); end if;
 return query select v_result.id,v_result.requirement_code,v_result.requirement_stage,v_result.requirement_visibility,v_result.updated_at;
end;
$$;

create function public.manage_contractor_portal_vacancy(
  p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text,p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text,p_candidate_terms jsonb)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_result record; v_action text:=lower(btrim(coalesce(p_action,'')));
begin
 select * into v_result from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes,p_payable_days,p_basic_da,p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,p_canteen_deduction,p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis);
 if v_action in ('create','create_draft','create_and_submit','update','update_draft') then perform private.apply_vacancy_candidate_terms(v_result.id,p_candidate_terms); end if;
 return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,v_result.updated_at;
end;
$$;

revoke all on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,jsonb),public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,jsonb) from public,anon;
grant execute on function public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,jsonb),public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,jsonb) to authenticated;

create table private.contractor_vacancy_submission_term_requests (
  idempotency_key uuid primary key,
  contractor_id uuid not null references public.contractors(id),
  actor_user_id uuid not null references auth.users(id),
  terms_fingerprint text not null check (terms_fingerprint ~ '^[0-9a-f]{64}$'),
  requirement_id uuid unique references public.employer_requirements(id),
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check ((completed_at is null) or requirement_id is not null)
);
alter table private.contractor_vacancy_submission_term_requests enable row level security;
revoke all on table private.contractor_vacancy_submission_term_requests from public,anon,authenticated;

create function public.manage_contractor_portal_vacancy(
  p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text,p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text,p_submission_idempotency_key uuid,p_candidate_terms jsonb)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=(select auth.uid()); v_contractor uuid:=(select private.current_contractor_portal_id(true)); v_request private.contractor_vacancy_submission_term_requests%rowtype; v_result record; v_fingerprint text:=encode(extensions.digest(private.canonical_vacancy_candidate_terms(p_candidate_terms)::text,'sha256'),'hex');
begin
 if lower(btrim(coalesce(p_action,'')))<>'create_and_submit' or p_requirement_id is not null or p_submission_idempotency_key is null or v_actor is null or v_contractor is null then raise exception 'Candidate-term idempotency is available only for a new authorized Contractor submission'; end if;
 insert into private.contractor_vacancy_submission_term_requests(idempotency_key,contractor_id,actor_user_id,terms_fingerprint) values(p_submission_idempotency_key,v_contractor,v_actor,v_fingerprint) on conflict do nothing returning * into v_request;
 if found then
   select * into v_result from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes,p_payable_days,p_basic_da,p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,p_canteen_deduction,p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis,p_submission_idempotency_key);
   perform private.apply_vacancy_candidate_terms(v_result.id,p_candidate_terms);
   update private.contractor_vacancy_submission_term_requests set requirement_id=v_result.id,completed_at=clock_timestamp() where idempotency_key=p_submission_idempotency_key;
   return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,v_result.updated_at; return;
 end if;
 select * into v_request from private.contractor_vacancy_submission_term_requests where idempotency_key=p_submission_idempotency_key for update;
 if v_request.contractor_id<>v_contractor or v_request.actor_user_id<>v_actor then raise exception 'This vacancy submission key is not available for this Contractor'; end if;
 -- Always route a replay through M049 before validating the additive terms
 -- ledger.  This preserves M049's authoritative base-payload conflict check.
 select * into v_result from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes,p_payable_days,p_basic_da,p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,p_canteen_deduction,p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis,p_submission_idempotency_key);
 if v_request.terms_fingerprint<>v_fingerprint then raise exception 'This vacancy submission key conflicts with different Candidate terms'; end if;
 if v_request.requirement_id is null or v_request.requirement_id<>v_result.id then raise exception 'Vacancy submission could not be reconciled'; end if;
 return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,v_result.updated_at;
end;
$$;
revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid,jsonb) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid,jsonb) to authenticated;

-- Candidate-safe projection; only additive, approved fields and an ordered,
-- closed-catalog benefit aggregate are returned to authenticated Candidates.
drop function public.list_candidate_job_opportunities(text,integer,integer);
create function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,company_worksite_name text,department text,job_location text,open_positions integer,qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,salary_wage text,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,compensation_cadence text,paid_leave_days_per_year integer,casual_leave_days_per_year integer,sick_leave_days_per_year integer,national_holiday_days_per_year integer,festival_holiday_days_per_year integer,working_days_per_week integer,weekly_off_count integer,overtime_rate numeric,overtime_rate_basis text,canteen_status text,canteen_charge_amount numeric,canteen_charge_basis text,transport_status text,transport_charge_amount numeric,transport_charge_basis text,employment_type text,payroll_type text,contract_duration_months integer,probation_period_months integer,training_period_days integer,notice_period_days integer,candidate_benefits jsonb,shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,accommodation_status text,accommodation_charge_amount numeric,accommodation_charge_basis text,interview_location text,interview_date timestamptz,expected_joining_date date,safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_candidate_id uuid:=(select private.current_candidate_portal_id()); v_term text:=nullif(btrim(p_search),'');
begin
 if v_candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
 return query select r.requirement_code,r.job_role,r.company_name,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,r.salary_wage,r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.compensation_cadence,r.paid_leave_days_per_year,r.casual_leave_days_per_year,r.sick_leave_days_per_year,r.national_holiday_days_per_year,r.festival_holiday_days_per_year,r.working_days_per_week,r.weekly_off_count,r.overtime_rate,r.overtime_rate_basis,r.canteen_status,r.canteen_charge_amount,r.canteen_charge_basis,r.transport_status,r.transport_charge_amount,r.transport_charge_basis,r.employment_type,r.payroll_type,r.contract_duration_months,r.probation_period_months,r.training_period_days,r.notice_period_days,private.vacancy_candidate_benefits_projection(r.id),r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,r.interview_location,r.interview_date,r.expected_joining_date,r.additional_notes,exists(select 1 from public.candidate_applications a where a.candidate_id=v_candidate_id and a.requirement_id=r.id)
 from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null and (v_term is null or r.requirement_code ilike '%'||v_term||'%' or r.job_role ilike '%'||v_term||'%' or coalesce(r.company_name,'') ilike '%'||v_term||'%' or coalesce(r.job_location,'') ilike '%'||v_term||'%') order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;
revoke all on function public.list_candidate_job_opportunities(text,integer,integer) from public,anon;
grant execute on function public.list_candidate_job_opportunities(text,integer,integer) to authenticated;

-- The existing Admin review surface receives the same candidate-facing snapshot
-- for informed approval, without exposing ledger, ownership, or audit data.
create or replace function public.admin_get_vacancy_review_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
 select jsonb_build_object(
   'source',jsonb_strip_nulls(jsonb_build_object('source_type',r.source_type,'submitted_by',u.display_name,'company',r.company_name,'contractor',coalesce(c.agency_name,c.owner_name))),
   'vacancy',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,'department',r.department,'location',coalesce(r.job_location,r.company_location),'openings',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),'candidate_terms',private.vacancy_candidate_terms_projection(r),'candidate_benefits',private.vacancy_candidate_benefits_projection(r.id),'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes)),
   'review',jsonb_strip_nulls(jsonb_build_object('normalized_status',private.normalized_vacancy_review_status(r.id),'contractor_submission_status',rc.submission_status,'feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),'reviewer',reviewer.display_name)),
   'lifecycle',jsonb_build_object('requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,'closed_at',r.closed_at,'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions),
   'progress',jsonb_build_object('applications',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),'interviews',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),'selected',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),'joined',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id and j.joining_status='joined'))
 ) into result from public.employer_requirements r left join lateral(select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true left join public.contractors c on c.id=rc.contractor_id left join public.platform_users u on u.user_id=r.created_by_user_id left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by) where r.id=p_requirement_id;
 if result is null then raise exception 'Vacancy was not found'; end if; return result;
end;
$$;
revoke all on function public.admin_get_vacancy_review_detail(uuid) from public,anon;
grant execute on function public.admin_get_vacancy_review_detail(uuid) to authenticated;

create or replace function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_company_id uuid:=(select private.current_company_portal_id(true)); v_result jsonb;
begin
 if v_company_id is null then raise exception 'Active Company access is required'; end if;
 select jsonb_build_object('requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),'candidate_terms',private.vacancy_candidate_terms_projection(r),'candidate_benefits',private.vacancy_candidate_benefits_projection(r.id),'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'review_status',r.review_status,'review_feedback',r.review_feedback,'submitted_at',r.submitted_at,'reviewed_at',r.reviewed_at,'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'created_at',r.created_at,'updated_at',r.updated_at) into v_result from public.employer_requirements r where r.id=p_requirement_id and r.company_id=v_company_id;
 if v_result is null then raise exception 'Company requirement was not found'; end if; return v_result;
end;
$$;

create or replace function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_contractor_id uuid:=(select private.current_contractor_portal_id(true)); v_result jsonb;
begin
 if v_contractor_id is null then raise exception 'Active Contractor access is required'; end if;
 select jsonb_build_object('requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),'candidate_terms',private.vacancy_candidate_terms_projection(r),'candidate_benefits',private.vacancy_candidate_benefits_projection(r.id),'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'submission_status',rc.submission_status,'normalized_review_status',private.normalized_vacancy_review_status(r.id),'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'review_feedback',rc.review_feedback,'submitted_at',rc.submitted_at,'reviewed_at',rc.reviewed_at,'created_at',r.created_at,'updated_at',r.updated_at) into v_result from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id where r.id=p_requirement_id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission';
 if v_result is null then raise exception 'Contractor vacancy was not found'; end if; return v_result;
end;
$$;
revoke all on function public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) from public,anon;
grant execute on function public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid) to authenticated;

do $$
declare v_oid oid:='public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure;
begin
 if not (select prosecdef from pg_proc where oid=v_oid) or coalesce(array_to_string((select proconfig from pg_proc where oid=v_oid),','),'') not like '%search_path=%' or not has_function_privilege('authenticated',v_oid,'execute') or has_function_privilege('anon',v_oid,'execute') then raise exception 'Migration 050 Candidate projection security postcondition failed'; end if;
end $$;

commit;
