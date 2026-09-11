-- Correct the M044 Contractor compensation wrapper record-shape regression.
-- The legacy management RPC returns submission_status, while employer_requirements does not.
-- Keep those two record shapes separate when M044 fields are persisted.
begin;

do $$
begin
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)') is null then
    raise exception 'Migration 048 requires the Migration 044 extended Contractor vacancy RPC';
  end if;
end;
$$;

create or replace function public.manage_contractor_portal_vacancy(
  p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,
  p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,
  p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text,
  p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,
  p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,
  p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,
  p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
  managed record;
  updated_requirement public.employer_requirements%rowtype;
  action text:=lower(btrim(coalesce(p_action,'')));
begin
  select * into managed from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,
    p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,
    p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes);

  if action in ('create','create_draft','create_and_submit','update','update_draft') then
    update public.employer_requirements as r set payable_days=p_payable_days,basic_da=p_basic_da,attendance_bonus=p_attendance_bonus,
      monthly_bonus=p_monthly_bonus,leave_amount=p_leave_amount,other_fixed_earning=p_other_fixed_earning,gross_wages=p_gross_wages,
      employee_pf=p_employee_pf,employee_esic=p_employee_esic,canteen_deduction=p_canteen_deduction,other_deduction=p_other_deduction,
      employer_pf=p_employer_pf,employer_esic=p_employer_esic,gratuity_provision=p_gratuity_provision,bonus_provision=p_bonus_provision,
      leave_provision=p_leave_provision,other_ctc_component=p_other_ctc_component,approx_in_hand=p_approx_in_hand,ctc=p_ctc,
      accommodation_status=p_accommodation_status,accommodation_charge_amount=p_accommodation_charge_amount,accommodation_charge_basis=p_accommodation_charge_basis
    where r.id=managed.id returning r.* into updated_requirement;
  end if;

  return query select managed.id,managed.requirement_code,managed.submission_status,managed.requirement_stage,
    coalesce(updated_requirement.updated_at,managed.updated_at);
end;
$$;

revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) to authenticated;

do $$
declare
  fn_oid oid:=to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)');
  fn_def text;
  fn_config text[];
begin
  select pg_get_functiondef(fn_oid),proconfig into fn_def,fn_config from pg_proc where oid=fn_oid;
  if fn_oid is null
     or not (select prosecdef from pg_proc where oid=fn_oid)
     or coalesce(array_to_string(fn_config,','),'') not like '%search_path=%'
     or not has_function_privilege('authenticated',fn_oid,'execute')
     or has_function_privilege('anon',fn_oid,'execute')
     or position('updated_requirement public.employer_requirements%rowtype' in fn_def)=0
     or position('returning r.* into updated_requirement' in fn_def)=0
     or position('managed.submission_status' in fn_def)=0
     or position('returning r.* into managed' in fn_def)>0 then
    raise exception 'Migration 048 Contractor management RPC security or record-shape postcondition failed';
  end if;
end;
$$;

commit;
