-- Contractor submission idempotency and operational expected-joining-date enforcement.
-- This is additive and preserves all existing vacancy, review, and Candidate contracts.
begin;

do $$
begin
  if to_regprocedure('public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)') is null
     or to_regclass('public.employer_requirements') is null
     or to_regclass('public.requirement_contractors') is null then
    raise exception 'Migration 049 requires the reviewed Contractor vacancy contract through Migration 048';
  end if;
end;
$$;

create table private.contractor_vacancy_submission_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  idempotency_key uuid not null unique,
  contractor_id uuid not null references public.contractors(id),
  actor_user_id uuid not null references auth.users(id),
  payload_fingerprint text not null check (payload_fingerprint ~ '^[0-9a-f]{64}$'),
  requirement_id uuid unique references public.employer_requirements(id),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  check ((completed_at is null) or requirement_id is not null)
);

alter table private.contractor_vacancy_submission_requests enable row level security;
revoke all on table private.contractor_vacancy_submission_requests from public,anon,authenticated;

create or replace function private.assert_contractor_expected_joining_date(p_expected_joining_date date)
returns void language plpgsql volatile security definer set search_path='' as $$
declare v_india_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  if p_expected_joining_date is not null and p_expected_joining_date<v_india_today then
    raise exception 'Expected joining date must be today or a future date';
  end if;
end;
$$;
revoke all on function private.assert_contractor_expected_joining_date(date) from public,anon,authenticated;

create or replace function private.enforce_contractor_expected_joining_date()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.source_type='contractor_portal' then
    if tg_op='INSERT' then
      perform private.assert_contractor_expected_joining_date(new.expected_joining_date);
    elsif new.expected_joining_date is distinct from old.expected_joining_date then
      perform private.assert_contractor_expected_joining_date(new.expected_joining_date);
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_contractor_expected_joining_date() from public,anon,authenticated;

create trigger contractor_expected_joining_date_guard
before insert or update of expected_joining_date on public.employer_requirements
for each row execute function private.enforce_contractor_expected_joining_date();

-- Keep the established extended Contractor management signature, while making
-- the approved optional joining-date rule authoritative for its write actions.
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
  if action in ('create','create_draft','create_and_submit','update','update_draft') then
    perform private.assert_contractor_expected_joining_date(p_expected_joining_date);
  end if;

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

-- A distinct overload is required so the reviewed M048 signature remains
-- callable for existing saved drafts while new Submit Vacancy calls carry an
-- explicit opaque key and receive replay-safe behavior.
create function public.manage_contractor_portal_vacancy(
  p_action text,p_requirement_id uuid,p_client_name text,p_department text,p_job_role text,p_job_location text,p_required_headcount integer,
  p_qualification text,p_iti_trade text,p_experience_requirement text,p_gender_preference text,p_age_min integer,p_age_max integer,
  p_salary_min numeric,p_salary_max numeric,p_shift_details text,p_working_hours text,p_overtime_details text,p_canteen text,p_transport text,
  p_accommodation text,p_interview_location text,p_expected_joining_date date,p_additional_notes text,
  p_payable_days integer,p_basic_da numeric,p_attendance_bonus numeric,p_monthly_bonus numeric,p_leave_amount numeric,p_other_fixed_earning numeric,
  p_gross_wages numeric,p_employee_pf numeric,p_employee_esic numeric,p_canteen_deduction numeric,p_other_deduction numeric,p_employer_pf numeric,
  p_employer_esic numeric,p_gratuity_provision numeric,p_bonus_provision numeric,p_leave_provision numeric,p_other_ctc_component numeric,
  p_approx_in_hand numeric,p_ctc numeric,p_accommodation_status text,p_accommodation_charge_amount numeric,p_accommodation_charge_basis text,
  p_submission_idempotency_key uuid)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare
  v_actor uuid := (select auth.uid());
  v_contractor_id uuid;
  v_action text := lower(btrim(coalesce(p_action,'')));
  v_payload jsonb;
  v_payload_fingerprint text;
  v_request private.contractor_vacancy_submission_requests%rowtype;
  v_result record;
begin
  if v_actor is null or not (select private.can_manage_contractor_vacancies()) then
    raise exception 'Contractor vacancy management access is required';
  end if;
  if v_action<>'create_and_submit' or p_requirement_id is not null then
    raise exception 'Submission idempotency is available only for a new vacancy submission';
  end if;
  if p_submission_idempotency_key is null then
    raise exception 'A vacancy submission key is required';
  end if;
  perform private.assert_contractor_expected_joining_date(p_expected_joining_date);
  v_contractor_id := (select private.current_contractor_portal_id(true));
  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'action',v_action,'client_name',p_client_name,'department',p_department,'job_role',p_job_role,'job_location',p_job_location,
    'required_headcount',p_required_headcount,'qualification',p_qualification,'iti_trade',p_iti_trade,'experience_requirement',p_experience_requirement,
    'gender_preference',p_gender_preference,'age_min',p_age_min,'age_max',p_age_max,'salary_min',p_salary_min,'salary_max',p_salary_max,
    'shift_details',p_shift_details,'working_hours',p_working_hours,'overtime_details',p_overtime_details,'canteen',p_canteen,'transport',p_transport,
    'accommodation',p_accommodation,'interview_location',p_interview_location,'expected_joining_date',p_expected_joining_date,'additional_notes',p_additional_notes,
    'payable_days',p_payable_days,'basic_da',p_basic_da,'attendance_bonus',p_attendance_bonus,'monthly_bonus',p_monthly_bonus,'leave_amount',p_leave_amount,
    'other_fixed_earning',p_other_fixed_earning,'gross_wages',p_gross_wages,'employee_pf',p_employee_pf,'employee_esic',p_employee_esic,
    'canteen_deduction',p_canteen_deduction,'other_deduction',p_other_deduction,'employer_pf',p_employer_pf,'employer_esic',p_employer_esic,
    'gratuity_provision',p_gratuity_provision,'bonus_provision',p_bonus_provision,'leave_provision',p_leave_provision,
    'other_ctc_component',p_other_ctc_component,'approx_in_hand',p_approx_in_hand,'ctc',p_ctc,'accommodation_status',p_accommodation_status,
    'accommodation_charge_amount',p_accommodation_charge_amount,'accommodation_charge_basis',p_accommodation_charge_basis));
  v_payload_fingerprint := encode(extensions.digest(v_payload::text,'sha256'),'hex');

  insert into private.contractor_vacancy_submission_requests(idempotency_key,contractor_id,actor_user_id,payload_fingerprint)
  values(p_submission_idempotency_key,v_contractor_id,v_actor,v_payload_fingerprint)
  on conflict (idempotency_key) do nothing returning * into v_request;

  if found then
    select * into v_result from public.manage_contractor_portal_vacancy(
      p_action,p_requirement_id,p_client_name,p_department,p_job_role,p_job_location,p_required_headcount,p_qualification,p_iti_trade,
      p_experience_requirement,p_gender_preference,p_age_min,p_age_max,p_salary_min,p_salary_max,p_shift_details,p_working_hours,p_overtime_details,
      p_canteen,p_transport,p_accommodation,p_interview_location,p_expected_joining_date,p_additional_notes,p_payable_days,p_basic_da,
      p_attendance_bonus,p_monthly_bonus,p_leave_amount,p_other_fixed_earning,p_gross_wages,p_employee_pf,p_employee_esic,p_canteen_deduction,
      p_other_deduction,p_employer_pf,p_employer_esic,p_gratuity_provision,p_bonus_provision,p_leave_provision,p_other_ctc_component,
      p_approx_in_hand,p_ctc,p_accommodation_status,p_accommodation_charge_amount,p_accommodation_charge_basis);
    update private.contractor_vacancy_submission_requests as request
       set requirement_id=v_result.id,completed_at=clock_timestamp()
     where request.id=v_request.id;
    return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,v_result.updated_at;
    return;
  end if;

  select * into v_request from private.contractor_vacancy_submission_requests
   where idempotency_key=p_submission_idempotency_key for update;
  if v_request.id is null then raise exception 'Vacancy submission could not be reconciled'; end if;
  if v_request.contractor_id<>v_contractor_id or v_request.actor_user_id<>v_actor then
    raise exception 'This vacancy submission key is not available for this Contractor';
  end if;
  if v_request.payload_fingerprint<>v_payload_fingerprint then
    raise exception 'This vacancy submission key conflicts with different vacancy details';
  end if;
  if v_request.requirement_id is null then raise exception 'Vacancy submission could not be reconciled'; end if;

  select r.id,r.requirement_code,rc.submission_status,r.requirement_stage,r.updated_at into v_result
  from public.employer_requirements r
  join public.requirement_contractors rc on rc.requirement_id=r.id and rc.contractor_id=v_contractor_id and rc.origin_type='contractor_submission'
  where r.id=v_request.requirement_id;
  if v_result.id is null then raise exception 'Vacancy submission could not be reconciled'; end if;
  return query select v_result.id,v_result.requirement_code,v_result.submission_status,v_result.requirement_stage,v_result.updated_at;
end;
$$;

revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid) to authenticated;

do $$
declare
  v_signature text := 'public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid)';
  v_oid oid := to_regprocedure(v_signature);
  v_definition text;
  v_config text[];
begin
  select pg_get_functiondef(v_oid),proconfig into v_definition,v_config from pg_proc where oid=v_oid;
  if v_oid is null
     or not (select prosecdef from pg_proc where oid=v_oid)
     or coalesce(array_to_string(v_config,','),'') not like '%search_path=%'
     or not has_function_privilege('authenticated',v_oid,'execute')
     or has_function_privilege('anon',v_oid,'execute')
     or position('on conflict (idempotency_key) do nothing' in lower(v_definition))=0
     or position('for update' in lower(v_definition))=0
     or position('payload_fingerprint' in lower(v_definition))=0
     or position('private.assert_contractor_expected_joining_date' in v_definition)=0 then
    raise exception 'Migration 049 Contractor idempotency security postcondition failed';
  end if;
end;
$$;

commit;
