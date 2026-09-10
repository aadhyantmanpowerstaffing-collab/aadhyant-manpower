-- Batch 2: canonical structured compensation, accommodation, and safe owner lifecycle.
-- This migration is additive. Legacy salary_wage/salary_min/salary_max and Yes/No facilities remain authoritative for legacy records.

do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.requirement_contractors') is null
     or to_regprocedure('public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text)') is null
     or to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text)') is null then
    raise exception 'Migration 044 requires the reviewed vacancy workflow through Migration 043';
  end if;
end;
$$;

alter table public.employer_requirements
  add column if not exists payable_days integer,
  add column if not exists basic_da numeric,
  add column if not exists attendance_bonus numeric,
  add column if not exists monthly_bonus numeric,
  add column if not exists leave_amount numeric,
  add column if not exists other_fixed_earning numeric,
  add column if not exists gross_wages numeric,
  add column if not exists employee_pf numeric,
  add column if not exists employee_esic numeric,
  add column if not exists canteen_deduction numeric,
  add column if not exists other_deduction numeric,
  add column if not exists employer_pf numeric,
  add column if not exists employer_esic numeric,
  add column if not exists gratuity_provision numeric,
  add column if not exists bonus_provision numeric,
  add column if not exists leave_provision numeric,
  add column if not exists other_ctc_component numeric,
  add column if not exists approx_in_hand numeric,
  add column if not exists ctc numeric,
  add column if not exists accommodation_status text,
  add column if not exists accommodation_charge_amount numeric,
  add column if not exists accommodation_charge_basis text;

alter table public.employer_requirements
  drop constraint if exists employer_requirements_payable_days_check,
  add constraint employer_requirements_payable_days_check check (payable_days is null or payable_days between 1 and 31),
  drop constraint if exists employer_requirements_wage_amounts_nonnegative_check,
  add constraint employer_requirements_wage_amounts_nonnegative_check check (
    coalesce(basic_da,0)>=0 and coalesce(attendance_bonus,0)>=0 and coalesce(monthly_bonus,0)>=0 and coalesce(leave_amount,0)>=0
    and coalesce(other_fixed_earning,0)>=0 and coalesce(gross_wages,0)>=0 and coalesce(employee_pf,0)>=0 and coalesce(employee_esic,0)>=0
    and coalesce(canteen_deduction,0)>=0 and coalesce(other_deduction,0)>=0 and coalesce(employer_pf,0)>=0 and coalesce(employer_esic,0)>=0
    and coalesce(gratuity_provision,0)>=0 and coalesce(bonus_provision,0)>=0 and coalesce(leave_provision,0)>=0
    and coalesce(other_ctc_component,0)>=0 and coalesce(approx_in_hand,0)>=0 and coalesce(ctc,0)>=0
  ),
  drop constraint if exists employer_requirements_wage_totals_check,
  add constraint employer_requirements_wage_totals_check check (
    (
      basic_da is null and attendance_bonus is null and monthly_bonus is null and leave_amount is null and other_fixed_earning is null
      and gross_wages is null and employee_pf is null and employee_esic is null and canteen_deduction is null and other_deduction is null
      and employer_pf is null and employer_esic is null and gratuity_provision is null and bonus_provision is null and leave_provision is null
      and other_ctc_component is null and approx_in_hand is null and ctc is null
    ) or (
      gross_wages is not null and approx_in_hand is not null and ctc is not null
      and gross_wages = coalesce(basic_da,0)+coalesce(attendance_bonus,0)+coalesce(monthly_bonus,0)+coalesce(leave_amount,0)+coalesce(other_fixed_earning,0)
      and approx_in_hand = gross_wages-coalesce(employee_pf,0)-coalesce(employee_esic,0)-coalesce(canteen_deduction,0)-coalesce(other_deduction,0)
      and ctc = gross_wages+coalesce(employer_pf,0)+coalesce(employer_esic,0)+coalesce(gratuity_provision,0)+coalesce(bonus_provision,0)+coalesce(leave_provision,0)+coalesce(other_ctc_component,0)
    )
  ),
  drop constraint if exists employer_requirements_accommodation_status_check,
  add constraint employer_requirements_accommodation_status_check check (accommodation_status is null or accommodation_status in ('not_available','free','chargeable')),
  drop constraint if exists employer_requirements_accommodation_basis_check,
  add constraint employer_requirements_accommodation_basis_check check (accommodation_charge_basis is null or accommodation_charge_basis in ('per_day','per_month')),
  drop constraint if exists employer_requirements_accommodation_charge_check,
  add constraint employer_requirements_accommodation_charge_check check (
    (accommodation_status is null and accommodation_charge_amount is null and accommodation_charge_basis is null)
    or (accommodation_status='chargeable' and accommodation_charge_amount is not null and accommodation_charge_amount>0 and accommodation_charge_basis is not null)
    or (accommodation_status in ('not_available','free') and accommodation_charge_amount is null and accommodation_charge_basis is null)
  );

create or replace function private.vacancy_compensation_projection(p_requirement public.employer_requirements)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'payable_days',p_requirement.payable_days,'basic_da',p_requirement.basic_da,'attendance_bonus',p_requirement.attendance_bonus,
    'monthly_bonus',p_requirement.monthly_bonus,'leave_amount',p_requirement.leave_amount,'other_fixed_earning',p_requirement.other_fixed_earning,
    'gross_wages',p_requirement.gross_wages,'employee_pf',p_requirement.employee_pf,'employee_esic',p_requirement.employee_esic,
    'canteen_deduction',p_requirement.canteen_deduction,'other_deduction',p_requirement.other_deduction,'employer_pf',p_requirement.employer_pf,
    'employer_esic',p_requirement.employer_esic,'gratuity_provision',p_requirement.gratuity_provision,'bonus_provision',p_requirement.bonus_provision,
    'leave_provision',p_requirement.leave_provision,'other_ctc_component',p_requirement.other_ctc_component,
    'approx_in_hand',p_requirement.approx_in_hand,'ctc',p_requirement.ctc
  ));
$$;

create or replace function private.vacancy_accommodation_projection(p_requirement public.employer_requirements)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_strip_nulls(jsonb_build_object('status',p_requirement.accommodation_status,
    'charge_amount',p_requirement.accommodation_charge_amount,'charge_basis',p_requirement.accommodation_charge_basis));
$$;

create or replace function private.vacancy_has_recruitment_dependencies(p_requirement_id uuid,p_ignored_contractor_link_id uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.candidate_applications a where a.requirement_id=p_requirement_id)
      or exists(select 1 from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=p_requirement_id)
      or exists(select 1 from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=p_requirement_id)
      or exists(select 1 from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.id is distinct from p_ignored_contractor_link_id);
$$;

revoke all on function private.vacancy_compensation_projection(public.employer_requirements),private.vacancy_accommodation_projection(public.employer_requirements),private.vacancy_has_recruitment_dependencies(uuid,uuid) from public,anon,authenticated;

-- Explicit extended overloads avoid changing or ambiguously resolving the reviewed legacy RPC signatures.
create function public.manage_company_portal_vacancy(
  p_action text,p_requirement_id uuid,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,
  p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,
  p_accommodation text,p_interview_location text,p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text,
  p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,
  p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,
  p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,
  p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare managed record; action text:=lower(btrim(coalesce(p_action,'')));
begin
  select * into managed from public.manage_company_portal_vacancy(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,
    p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,
    p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,p_expected_joining_date,p_additional_notes);
  if action in ('create','create_and_submit','update') then
    update public.employer_requirements set payable_days=p_payable_days,basic_da=p_basic_da,attendance_bonus=p_attendance_bonus,
      monthly_bonus=p_monthly_bonus,leave_amount=p_leave_amount,other_fixed_earning=p_other_fixed_earning,gross_wages=p_gross_wages,
      employee_pf=p_employee_pf,employee_esic=p_employee_esic,canteen_deduction=p_canteen_deduction,other_deduction=p_other_deduction,
      employer_pf=p_employer_pf,employer_esic=p_employer_esic,gratuity_provision=p_gratuity_provision,bonus_provision=p_bonus_provision,
      leave_provision=p_leave_provision,other_ctc_component=p_other_ctc_component,approx_in_hand=p_approx_in_hand,ctc=p_ctc,
      accommodation_status=p_accommodation_status,accommodation_charge_amount=p_accommodation_charge_amount,accommodation_charge_basis=p_accommodation_charge_basis
    where employer_requirements.id=managed.id returning * into managed;
  end if;
  return query select managed.id,managed.requirement_code,managed.requirement_stage,managed.requirement_visibility,managed.updated_at;
end;
$$;

create function public.manage_company_portal_requirement(
  p_action text,p_requirement_id uuid,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,
  p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,
  p_accommodation text,p_interview_location text,p_interview_date timestamptz,p_expected_joining_date date,p_additional_notes text,
  p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,
  p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,
  p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,
  p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text)
returns table(id uuid,requirement_code text,requirement_stage text,requirement_visibility text,updated_at timestamptz)
language sql security definer set search_path='' as $$
  select * from public.manage_company_portal_vacancy(p_action,p_requirement_id,p_department,p_job_role,p_job_location,p_required_headcount,
    p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,
    p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_interview_date,p_expected_joining_date,p_additional_notes,
    p_payable_days,p_basic_da,p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,
    p_canteen_deduction,p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,
    p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis);
$$;

create function public.manage_contractor_portal_vacancy(
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
declare managed record; action text:=lower(btrim(coalesce(p_action,'')));
begin
  select * into managed from public.manage_contractor_portal_vacancy(p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,
    p_required_headcount,p_qualification,p_iti_trade,p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,
    p_shift_details,p_working_hours,p_overtime_details,p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes);
  if action in ('create','create_draft','create_and_submit','update','update_draft') then
    update public.employer_requirements set payable_days=p_payable_days,basic_da=p_basic_da,attendance_bonus=p_attendance_bonus,
      monthly_bonus=p_monthly_bonus,leave_amount=p_leave_amount,other_fixed_earning=p_other_fixed_earning,gross_wages=p_gross_wages,
      employee_pf=p_employee_pf,employee_esic=p_employee_esic,canteen_deduction=p_canteen_deduction,other_deduction=p_other_deduction,
      employer_pf=p_employer_pf,employer_esic=p_employer_esic,gratuity_provision=p_gratuity_provision,bonus_provision=p_bonus_provision,
      leave_provision=p_leave_provision,other_ctc_component=p_other_ctc_component,approx_in_hand=p_approx_in_hand,ctc=p_ctc,
      accommodation_status=p_accommodation_status,accommodation_charge_amount=p_accommodation_charge_amount,accommodation_charge_basis=p_accommodation_charge_basis
    where employer_requirements.id=managed.id returning * into managed;
  end if;
  return query select managed.id,managed.requirement_code,managed.submission_status,managed.requirement_stage,managed.updated_at;
end;
$$;

revoke all on function public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text),
  public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text),
  public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) from public,anon;
grant execute on function public.manage_company_portal_vacancy(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text),
  public.manage_company_portal_requirement(text,uuid,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,timestamp with time zone,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text),
  public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('manage_company_portal_vacancy','manage_company_portal_requirement','manage_contractor_portal_vacancy')
      and p.proargnames @> array['p_payable_days','p_accommodation_status']
      and (not p.prosecdef or not has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))
  ) then
    raise exception 'Migration 044 extended vacancy management RPC security postcondition failed';
  end if;
end;
$$;

create function public.delete_company_portal_draft_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); company_id uuid; requirement public.employer_requirements%rowtype;
begin
  if actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  company_id:=(select private.current_company_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=company_id and r.source_type='employer_portal' for update;
  if requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if requirement.review_status<>'draft' or requirement.requirement_stage<>'draft' then raise exception 'Only a draft vacancy can be deleted'; end if;
  if private.vacancy_has_recruitment_dependencies(requirement.id,null) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
  delete from public.employer_requirements where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'company','company_vacancy_draft_deleted','employer_requirement',requirement.id,'company',jsonb_build_object('requirement_code',requirement.requirement_code));
  return true;
end;
$$;

create function public.withdraw_company_portal_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); company_id uuid; requirement public.employer_requirements%rowtype;
begin
  if actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  company_id:=(select private.current_company_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=company_id and r.source_type='employer_portal' for update;
  if requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if requirement.review_status<>'pending_review' then raise exception 'Only a pending-review vacancy can be withdrawn'; end if;
  update public.employer_requirements set review_status='closed',requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
    where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'company','company_vacancy_withdrawn','employer_requirement',requirement.id,'company',jsonb_build_object('prior_review_status','pending_review'));
  return true;
end;
$$;

create function public.close_company_portal_open_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); company_id uuid; requirement public.employer_requirements%rowtype;
begin
  if actor is null or not (select private.can_manage_company_portal()) then raise exception 'Company requirement management access is required'; end if;
  company_id:=(select private.current_company_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.company_id=company_id and r.source_type='employer_portal' for update;
  if requirement.id is null then raise exception 'Company vacancy was not found'; end if;
  if requirement.review_status<>'approved' or requirement.requirement_stage<>'open' or requirement.requirement_visibility<>'public' then raise exception 'Only a published open vacancy can be closed'; end if;
  update public.employer_requirements set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp()
    where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'company','company_vacancy_closed','employer_requirement',requirement.id,'company',jsonb_build_object('prior_stage','open'));
  return true;
end;
$$;

create function public.delete_contractor_portal_draft_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); contractor_id uuid; requirement public.employer_requirements%rowtype; link public.requirement_contractors%rowtype;
begin
  if actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  contractor_id:=(select private.current_contractor_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' for update;
  if requirement.id is null or link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if link.submission_status<>'draft' or requirement.requirement_stage<>'draft' then raise exception 'Only a draft vacancy can be deleted'; end if;
  if private.vacancy_has_recruitment_dependencies(requirement.id,link.id) then raise exception 'Vacancies with recruitment dependencies cannot be deleted'; end if;
  delete from public.requirement_contractors where id=link.id;
  delete from public.employer_requirements where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'contractor','contractor_vacancy_draft_deleted','employer_requirement',requirement.id,'contractor',jsonb_build_object('requirement_code',requirement.requirement_code));
  return true;
end;
$$;

create function public.withdraw_contractor_portal_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); contractor_id uuid; requirement public.employer_requirements%rowtype; link public.requirement_contractors%rowtype;
begin
  if actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  contractor_id:=(select private.current_contractor_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' for update;
  if requirement.id is null or link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if link.submission_status not in ('submitted','under_review') then raise exception 'Only a pending-review vacancy can be withdrawn'; end if;
  update public.requirement_contractors set submission_status='cancelled',closed_at=clock_timestamp() where id=link.id;
  update public.employer_requirements set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'contractor','contractor_vacancy_withdrawn','employer_requirement',requirement.id,'contractor',jsonb_build_object('prior_submission_status',link.submission_status));
  return true;
end;
$$;

create function public.close_contractor_portal_open_vacancy(p_requirement_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); contractor_id uuid; requirement public.employer_requirements%rowtype; link public.requirement_contractors%rowtype;
begin
  if actor is null or not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  contractor_id:=(select private.current_contractor_portal_id(true));
  select r.* into requirement from public.employer_requirements r where r.id=p_requirement_id and r.source_type='contractor_portal' for update;
  select rc.* into link from public.requirement_contractors rc where rc.requirement_id=p_requirement_id and rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' for update;
  if requirement.id is null or link.id is null then raise exception 'Contractor vacancy was not found'; end if;
  if link.submission_status<>'approved' or requirement.requirement_stage<>'open' or requirement.requirement_visibility<>'public' then raise exception 'Only a published open vacancy can be closed'; end if;
  update public.requirement_contractors set submission_status='closed',assignment_status='completed',closed_at=clock_timestamp() where id=link.id;
  update public.employer_requirements set review_status='closed',requirement_stage='closed',requirement_visibility='private',status='closed',closed_at=clock_timestamp() where id=requirement.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'contractor','contractor_vacancy_closed','employer_requirement',requirement.id,'contractor',jsonb_build_object('prior_stage','open'));
  return true;
end;
$$;

revoke all on function public.delete_company_portal_draft_vacancy(uuid),public.withdraw_company_portal_vacancy(uuid),public.close_company_portal_open_vacancy(uuid),
  public.delete_contractor_portal_draft_vacancy(uuid),public.withdraw_contractor_portal_vacancy(uuid),public.close_contractor_portal_open_vacancy(uuid) from public,anon;
grant execute on function public.delete_company_portal_draft_vacancy(uuid),public.withdraw_company_portal_vacancy(uuid),public.close_company_portal_open_vacancy(uuid),
  public.delete_contractor_portal_draft_vacancy(uuid),public.withdraw_contractor_portal_vacancy(uuid),public.close_contractor_portal_open_vacancy(uuid) to authenticated;

do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in ('delete_company_portal_draft_vacancy','withdraw_company_portal_vacancy','close_company_portal_open_vacancy',
      'delete_contractor_portal_draft_vacancy','withdraw_contractor_portal_vacancy','close_contractor_portal_open_vacancy')
      and (not p.prosecdef or not has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute'))
  ) then
    raise exception 'Migration 044 vacancy lifecycle RPC security postcondition failed';
  end if;
end;
$$;

-- Owner lists retain their existing rows and add only the submitted compensation/accommodation
-- values.  They remain owner-scoped security-definer projections, not browser table access.
drop function if exists public.list_company_portal_requirements(text,text,integer,integer);
create function public.list_company_portal_requirements(p_search text default null,p_stage text default null,
  p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,department text,job_role text,job_location text,required_headcount integer,
  filled_positions integer,qualification text,experience_requirement text,gender_preference text,age_min integer,age_max integer,
  salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,
  leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,
  other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,
  other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,
  accommodation_charge_basis text,shift_details text,working_hours text,overtime_details text,canteen text,transport text,
  accommodation text,interview_location text,interview_date timestamptz,additional_notes text,requirement_stage text,
  requirement_visibility text,application_count bigint,interview_count bigint,selected_count bigint,joined_count bigint,
  created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare company_id uuid:=(select private.current_company_portal_id(true)); needle text:=nullif(btrim(p_search),''); stage text:=nullif(lower(btrim(p_stage)), '');
begin
  if company_id is null then raise exception 'Active Company access is required'; end if;
  if stage is not null and stage not in ('draft','open','on_hold','filled','closed','cancelled') then raise exception 'Unsupported requirement stage'; end if;
  return query select r.id,r.requirement_code,r.department,r.job_role,r.job_location,r.required_headcount,r.filled_positions,
    r.qualification,r.experience_requirement,r.gender_preference,r.age_min,r.age_max,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,
    r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,
    r.accommodation_charge_amount,r.accommodation_charge_basis,r.shift_details,r.working_hours,r.overtime_details,
    r.canteen,r.transport,r.accommodation,r.interview_location,r.interview_date,r.additional_notes,r.requirement_stage,
    r.requirement_visibility,count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),
    count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.employer_requirements r left join public.candidate_applications a on a.requirement_id=r.id
    left join public.interviews i on i.application_id=a.id
  where r.company_id=company_id and (stage is null or r.requirement_stage=stage)
    and (needle is null or r.requirement_code ilike '%'||needle||'%' or r.job_role ilike '%'||needle||'%' or r.job_location ilike '%'||needle||'%')
  group by r.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

drop function if exists public.list_contractor_portal_vacancies(text,text,integer,integer);
create function public.list_contractor_portal_vacancies(p_search text default null,p_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(id uuid,requirement_code text,client_name text,job_role text,job_location text,required_headcount integer,
  salary_min numeric,salary_max numeric,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,
  leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,
  other_deduction numeric,employer_pf numeric,employer_esic numeric,gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,
  other_ctc_component numeric,approx_in_hand numeric,ctc numeric,accommodation_status text,accommodation_charge_amount numeric,
  accommodation_charge_basis text,submission_status text,requirement_stage text,review_feedback text,application_count bigint,interview_count bigint,
  selected_count bigint,joined_count bigint,created_at timestamptz,updated_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare contractor_id uuid:=(select private.current_contractor_portal_id(true)); needle text:=nullif(btrim(p_search),''); filter_status text:=nullif(lower(btrim(p_status)), '');
begin
  if contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  if filter_status is not null and filter_status not in ('draft','submitted','under_review','correction_required','approved','rejected','closed','cancelled') then raise exception 'Unsupported submission status'; end if;
  return query select r.id,r.requirement_code,r.company_name,r.job_role,r.job_location,r.required_headcount,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,
    r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.accommodation_status,
    r.accommodation_charge_amount,r.accommodation_charge_basis,rc.submission_status,r.requirement_stage,rc.review_feedback,
    count(distinct a.id),count(distinct i.id),count(distinct a.id) filter(where a.application_status='selected'),
    count(distinct a.id) filter(where a.application_status='joined'),r.created_at,r.updated_at
  from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
  where rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' and (filter_status is null or rc.submission_status=filter_status)
    and (needle is null or r.requirement_code ilike '%'||needle||'%' or r.job_role ilike '%'||needle||'%' or r.job_location ilike '%'||needle||'%')
  group by r.id,rc.id order by r.created_at desc,r.id limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0);
end;
$$;

revoke all on function public.list_company_portal_requirements(text,text,integer,integer),public.list_contractor_portal_vacancies(text,text,integer,integer) from public,anon;
grant execute on function public.list_company_portal_requirements(text,text,integer,integer),public.list_contractor_portal_vacancies(text,text,integer,integer) to authenticated;

-- Candidate and public job projections remain narrow, approved/open/public, and omit all contact, billing, and internal fields.
drop function if exists public.list_candidate_job_opportunities(text,integer,integer);
create function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,company_worksite_name text,department text,job_location text,open_positions integer,
  qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,
  payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,gross_wages numeric,
  employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,
  gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,
  shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,accommodation_status text,
  accommodation_charge_amount numeric,accommodation_charge_basis text,interview_location text,interview_date timestamptz,expected_joining_date date,
  safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path='' as $$
declare candidate_id uuid:=(select private.current_candidate_portal_id()); term text:=nullif(btrim(p_search),'');
begin
  if candidate_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,r.company_name,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.qualification,r.iti_trade,r.experience_requirement,r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,
    r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,r.gross_wages,
    r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,r.bonus_provision,
    r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,
    r.accommodation,r.accommodation_status,r.accommodation_charge_amount,r.accommodation_charge_basis,r.interview_location,r.interview_date,
    r.expected_joining_date,r.additional_notes,
    exists(select 1 from public.candidate_applications a where a.candidate_id=candidate_id and a.requirement_id=r.id)
  from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
    and (term is null or r.requirement_code ilike '%'||term||'%' or r.job_role ilike '%'||term||'%' or coalesce(r.job_location,'') ilike '%'||term||'%')
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

drop function if exists public.get_public_job_requirements(integer,integer);
create function public.get_public_job_requirements(p_limit integer default 20,p_offset integer default 0)
returns table(requirement_code text,job_role text,company_worksite_name text,department text,job_location text,open_positions integer,salary_min numeric,salary_max numeric,
  salary_text text,payable_days integer,basic_da numeric,attendance_bonus numeric,monthly_bonus numeric,leave_amount numeric,other_fixed_earning numeric,
  gross_wages numeric,employee_pf numeric,employee_esic numeric,canteen_deduction numeric,other_deduction numeric,employer_pf numeric,employer_esic numeric,
  gratuity_provision numeric,bonus_provision numeric,leave_provision numeric,other_ctc_component numeric,approx_in_hand numeric,ctc numeric,
  qualification text,iti_trade text,experience_requirement text,shift_details text,working_hours text,overtime_details text,canteen text,transport text,
  accommodation text,accommodation_status text,accommodation_charge_amount numeric,accommodation_charge_basis text,interview_date timestamptz,
  interview_location text,expected_joining_date date,published_at timestamptz)
language sql stable security definer set search_path='' as $$
  select r.requirement_code,r.job_role,r.company_name,r.department,r.job_location,greatest(r.required_headcount-r.filled_positions,0)::integer,
    r.salary_min,r.salary_max,r.salary_wage,r.payable_days,r.basic_da,r.attendance_bonus,r.monthly_bonus,r.leave_amount,r.other_fixed_earning,
    r.gross_wages,r.employee_pf,r.employee_esic,r.canteen_deduction,r.other_deduction,r.employer_pf,r.employer_esic,r.gratuity_provision,
    r.bonus_provision,r.leave_provision,r.other_ctc_component,r.approx_in_hand,r.ctc,r.qualification,r.iti_trade,r.experience_requirement,
    r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,r.accommodation_status,
    r.accommodation_charge_amount,r.accommodation_charge_basis,r.interview_date,r.interview_location,r.expected_joining_date,coalesce(r.published_at,r.created_at)
  from public.employer_requirements r where private.vacancy_is_application_eligible(r.id) and r.requirement_code is not null
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,20),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
$$;

create or replace function public.get_company_portal_requirement(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare company_id uuid:=(select private.current_company_portal_id(true)); result jsonb;
begin
  if company_id is null then raise exception 'Active Company access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,
    'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,
    'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,
    'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,
    'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),
    'interview_location',r.interview_location,'interview_date',r.interview_date,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,
    'review_status',r.review_status,'review_feedback',r.review_feedback,'submitted_at',r.submitted_at,'reviewed_at',r.reviewed_at,
    'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),
      'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined'))
  ) into result from public.employer_requirements r
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
    left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and r.company_id=company_id group by r.id;
  if result is null then raise exception 'Company requirement was not found'; end if;
  return result;
end;
$$;

create or replace function public.get_contractor_portal_vacancy(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare contractor_id uuid:=(select private.current_contractor_portal_id(true)); result jsonb;
begin
  if contractor_id is null then raise exception 'Active Contractor access is required'; end if;
  select jsonb_build_object(
    'requirement_code',r.requirement_code,'client_name',r.company_name,'department',r.department,'job_role',r.job_role,'job_location',r.job_location,
    'required_headcount',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,'experience_requirement',r.experience_requirement,
    'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,'salary_min',r.salary_min,'salary_max',r.salary_max,
    'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,'canteen',r.canteen,'transport',r.transport,
    'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),'compensation',private.vacancy_compensation_projection(r),
    'interview_location',r.interview_location,'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,
    'submission_status',rc.submission_status,'normalized_review_status',private.normalized_vacancy_review_status(r.id),
    'requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'review_feedback',rc.review_feedback,
    'submitted_at',rc.submitted_at,'reviewed_at',rc.reviewed_at,'created_at',r.created_at,'updated_at',r.updated_at,
    'pipeline',jsonb_build_object('applications',count(distinct a.id),'screening',count(distinct a.id) filter(where a.application_status='screening'),
      'shortlisted',count(distinct a.id) filter(where a.application_status='shortlisted'),'interviews',count(distinct i.id),
      'selected',count(distinct a.id) filter(where a.application_status='selected'),'joined',count(distinct j.id) filter(where j.joining_status='joined'))
  ) into result from public.requirement_contractors rc join public.employer_requirements r on r.id=rc.requirement_id
    left join public.candidate_applications a on a.requirement_id=r.id left join public.interviews i on i.application_id=a.id
    left join public.candidate_joinings j on j.application_id=a.id
  where r.id=p_requirement_id and rc.contractor_id=contractor_id and rc.origin_type='contractor_submission' group by r.id,rc.id;
  if result is null then raise exception 'Contractor vacancy was not found'; end if;
  return result;
end;
$$;

create or replace function public.admin_get_vacancy_review_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not (select private.can_review_vacancies()) then raise exception 'Approved administrator access is required'; end if;
  select jsonb_build_object(
    'source',jsonb_strip_nulls(jsonb_build_object('source_type',r.source_type,'submitted_by',u.display_name,'company',r.company_name,'contractor',coalesce(c.agency_name,c.owner_name))),
    'vacancy',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,'department',r.department,
      'location',coalesce(r.job_location,r.company_location),'openings',r.required_headcount,'qualification',r.qualification,'iti_trade',r.iti_trade,
      'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,
      'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,
      'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),
      'compensation',private.vacancy_compensation_projection(r),'interview_location',r.interview_location,'interview_date',r.interview_date,
      'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes)),
    'review',jsonb_strip_nulls(jsonb_build_object('normalized_status',private.normalized_vacancy_review_status(r.id),'contractor_submission_status',rc.submission_status,
      'feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),
      'reviewer',reviewer.display_name)),
    'lifecycle',jsonb_build_object('requirement_stage',r.requirement_stage,'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,
      'closed_at',r.closed_at,'required_headcount',r.required_headcount,'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions),
    'progress',jsonb_build_object('applications',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),
      'interviews',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),
      'selected',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),
      'joined',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=r.id and j.joining_status='joined'))
  ) into result from public.employer_requirements r
    left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
    left join public.contractors c on c.id=rc.contractor_id left join public.platform_users u on u.user_id=r.created_by_user_id
    left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by) where r.id=p_requirement_id;
  if result is null then raise exception 'Vacancy was not found'; end if;
  return result;
end;
$$;

create or replace function public.admin_get_job_lead_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  if not (select private.can_manage_recruitment_operations()) then raise exception 'Recruitment access is required'; end if;
  select jsonb_build_object(
    'requirement',jsonb_strip_nulls(jsonb_build_object('requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,
      'department',r.department,'location',coalesce(r.job_location,r.company_location),'company',r.company_name,'contractor',coalesce(c.agency_name,c.owner_name),
      'submitted_by',submitter.display_name,'source_type',r.source_type,'qualification',r.qualification,'iti_trade',r.iti_trade,
      'experience_requirement',r.experience_requirement,'gender_preference',r.gender_preference,'age_min',r.age_min,'age_max',r.age_max,
      'salary_min',r.salary_min,'salary_max',r.salary_max,'shift_details',r.shift_details,'working_hours',r.working_hours,'overtime_details',r.overtime_details,
      'canteen',r.canteen,'transport',r.transport,'accommodation',r.accommodation,'accommodation_detail',private.vacancy_accommodation_projection(r),
      'compensation',private.vacancy_compensation_projection(r),'interview_location',r.interview_location,'interview_date',r.interview_date,
      'expected_joining_date',r.expected_joining_date,'additional_notes',r.additional_notes,'normalized_review_status',private.normalized_vacancy_review_status(r.id),
      'review_feedback',coalesce(rc.review_feedback,r.review_feedback),'submitted_at',coalesce(rc.submitted_at,r.submitted_at),'reviewed_at',coalesce(rc.reviewed_at,r.reviewed_at),
      'reviewed_by',reviewer.display_name,'contractor_submission_status',rc.submission_status,'requirement_stage',r.requirement_stage,
      'requirement_visibility',r.requirement_visibility,'published_at',r.published_at,'closed_at',r.closed_at,'required_headcount',r.required_headcount,
      'filled_positions',r.filled_positions,'remaining_positions',r.required_headcount-r.filled_positions,
      'application_count',(select count(*) from public.candidate_applications a where a.requirement_id=r.id),
      'interview_count',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id),
      'selected_count',(select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status='selected'),
      'joined_count',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=r.id and j.joining_status='joined'))),
    'history',coalesce((select jsonb_agg(jsonb_build_object('action',h.action,'actor_type',h.actor_type,'created_at',h.created_at,'summary','Operational activity') order by h.created_at desc,h.id desc)
      from (select l.id,l.action,l.actor_type,l.created_at from public.audit_logs l where l.entity_id=r.id and l.entity_type='employer_requirement' order by l.created_at desc,l.id desc limit 50) h),'[]'::jsonb)
  ) into result from public.employer_requirements r
    left join lateral (select x.* from public.requirement_contractors x where x.requirement_id=r.id and x.origin_type='contractor_submission' order by x.created_at desc,x.id desc limit 1) rc on true
    left join public.contractors c on c.id=rc.contractor_id left join public.platform_users submitter on submitter.user_id=r.created_by_user_id
    left join public.platform_users reviewer on reviewer.user_id=coalesce(rc.reviewed_by,r.reviewed_by) where r.id=p_requirement_id;
  if result is null then raise exception 'Job Lead was not found'; end if;
  return result;
end;
$$;

revoke all on function public.list_candidate_job_opportunities(text,integer,integer),public.get_public_job_requirements(integer,integer),
  public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid),public.admin_get_vacancy_review_detail(uuid),public.admin_get_job_lead_detail(uuid) from public,anon;
grant execute on function public.list_candidate_job_opportunities(text,integer,integer),public.get_public_job_requirements(integer,integer),
  public.get_company_portal_requirement(uuid),public.get_contractor_portal_vacancy(uuid),public.admin_get_vacancy_review_detail(uuid),public.admin_get_job_lead_detail(uuid) to authenticated;

-- The public marketing projection remains anonymous only through its existing narrow RPC grant.
grant execute on function public.get_public_job_requirements(integer,integer) to anon;
