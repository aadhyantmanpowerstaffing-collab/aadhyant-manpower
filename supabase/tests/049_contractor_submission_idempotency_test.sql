-- Migration 049 Contractor submission idempotency checkpoint.
-- Run against a disposable local baseline through Migration 049 only.
\set ON_ERROR_STOP on
begin;

do $$
declare
  legacy_signature text := 'public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)';
  idempotent_signature text := 'public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text,uuid)';
  definition text;
begin
  if to_regclass('private.contractor_vacancy_submission_requests') is null
     or to_regprocedure(legacy_signature) is null
     or to_regprocedure(idempotent_signature) is null then
    raise exception 'M049 Contractor idempotency objects are missing';
  end if;
  if has_table_privilege('authenticated','private.contractor_vacancy_submission_requests','select,insert,update,delete')
     or has_table_privilege('anon','private.contractor_vacancy_submission_requests','select,insert,update,delete') then
    raise exception 'M049 idempotency ledger browser-table boundary failed';
  end if;
  select pg_get_functiondef(to_regprocedure(idempotent_signature)) into definition;
  if definition not ilike '%security definer%'
     or definition not ilike '%set search_path to ''''%'
     or position('on conflict (idempotency_key) do nothing' in lower(definition))=0
     or position('for update' in lower(definition))=0
     or position('payload_fingerprint' in lower(definition))=0 then
    raise exception 'M049 idempotent Contractor function is not concurrency-safe';
  end if;
end;
$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
  ('49000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m49-contractor-a@test.local','x','{}','{}',now(),now()),
  ('49000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m49-contractor-b@test.local','x','{}','{}',now(),now());
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
  ('49000000-0000-0000-0000-000000000001','contractor','M49 Contractor A','m49-contractor-a@test.local','active'),
  ('49000000-0000-0000-0000-000000000002','contractor','M49 Contractor B','m49-contractor-b@test.local','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,city,state,verification_status,account_status) values
  ('49000000-0000-0000-0001-000000000001','M49 Contractor A','Synthetic A','9876549001','m49-a@test.local','Chennai','Tamil Nadu','verified','active'),
  ('49000000-0000-0000-0001-000000000002','M49 Contractor B','Synthetic B','9876549002','m49-b@test.local','Pune','Maharashtra','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
  ('49000000-0000-0000-0001-000000000001','49000000-0000-0000-0000-000000000001','owner','active'),
  ('49000000-0000-0000-0001-000000000002','49000000-0000-0000-0000-000000000002','owner','active');

create function pg_temp.submit_m49(p_key uuid,p_client_name text,p_joining_date date)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language sql as $$
  select * from public.manage_contractor_portal_vacancy(
    p_action=>'create_and_submit',p_requirement_id=>null,p_client_name=>p_client_name,p_department=>null,p_job_role=>'Fitter',
    p_job_location=>'Sanand',p_required_headcount=>1,p_qualification=>'ITI',p_iti_trade=>null,p_experience_requirement=>null,
    p_gender_preference=>null,p_age_min=>null,p_age_max=>null,p_salary_min=>12000,p_salary_max=>13000,p_shift_details=>null,
    p_working_hours=>null,p_overtime_details=>null,p_canteen=>'No',p_transport=>'No',p_accommodation=>'No',p_interview_location=>null,
    p_expected_joining_date=>p_joining_date,p_additional_notes=>null,p_payable_days=>null,p_basic_da=>null,p_attendance_bonus=>null,
    p_monthly_bonus=>null,p_leave_amount=>null,p_other_fixed_earning=>null,p_gross_wages=>null,p_employee_pf=>null,p_employee_esic=>null,
    p_canteen_deduction=>null,p_other_deduction=>null,p_employer_pf=>null,p_employer_esic=>null,p_gratuity_provision=>null,
    p_bonus_provision=>null,p_leave_provision=>null,p_other_ctc_component=>null,p_approx_in_hand=>null,p_ctc=>null,
    p_accommodation_status=>'not_available',p_accommodation_charge_amount=>null,p_accommodation_charge_basis=>null,
    p_submission_idempotency_key=>p_key
  );
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','49000000-0000-0000-0000-000000000001',true);
do $$
declare
  v_first record;
  v_replay record;
  v_second record;
  v_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  select * into v_first from pg_temp.submit_m49('49000000-0000-0000-0002-000000000001','M49 Primary',v_today);
  select * into v_replay from pg_temp.submit_m49('49000000-0000-0000-0002-000000000001','M49 Primary',v_today);
  if v_first.id is null or v_first.id<>v_replay.id or v_first.submission_status<>'submitted' then
    raise exception 'CHECKPOINT_049_SAME_KEY_REPLAY_SAME_RESULT_FAILED';
  end if;
  perform set_config('m49.primary_requirement_id',v_first.id::text,true);
  select * into v_second from pg_temp.submit_m49('49000000-0000-0000-0002-000000000002','M49 Primary',v_today);
  if v_second.id=v_first.id then
    raise exception 'CHECKPOINT_049_DIFFERENT_KEY_IDENTICAL_PAYLOAD_FAILED';
  end if;
  perform pg_temp.submit_m49('49000000-0000-0000-0002-000000000003','M49 Null',null);
  perform pg_temp.submit_m49('49000000-0000-0000-0002-000000000004','M49 Future',v_today+1);
  begin
    perform pg_temp.submit_m49('49000000-0000-0000-0002-000000000001','M49 Conflict',v_today);
    raise exception 'CHECKPOINT_049_CONFLICTING_SAME_KEY_ACCEPTED';
  exception when raise_exception then
    if sqlerrm='CHECKPOINT_049_CONFLICTING_SAME_KEY_ACCEPTED' then raise; end if;
  end;
  begin
    perform pg_temp.submit_m49('49000000-0000-0000-0002-000000000005','M49 Past',v_today-1);
    raise exception 'CHECKPOINT_049_PAST_EXPECTED_JOINING_ACCEPTED';
  exception when raise_exception then
    if sqlerrm='CHECKPOINT_049_PAST_EXPECTED_JOINING_ACCEPTED' then raise; end if;
  end;
end;
$$;

reset role;
do $$
declare v_primary_requirement_id uuid := current_setting('m49.primary_requirement_id')::uuid;
begin
  if (select count(*) from public.employer_requirements where created_by_user_id='49000000-0000-0000-0000-000000000001')<>4
     or (select count(*) from public.requirement_contractors where contractor_id='49000000-0000-0000-0001-000000000001')<>4
     or (select count(*) from private.contractor_vacancy_submission_requests where actor_user_id='49000000-0000-0000-0000-000000000001')<>4 then
    raise exception 'CHECKPOINT_049_IDEMPOTENCY_COUNTS_FAILED';
  end if;
  if (select count(*) from public.audit_logs where entity_type='employer_requirement' and entity_id=v_primary_requirement_id
      and action='contractor_vacancy_create_and_submit')<>1 then
    raise exception 'CHECKPOINT_049_REPLAY_AUDIT_DETERMINISM_FAILED';
  end if;
  if private.vacancy_is_application_eligible(v_primary_requirement_id) then
    raise exception 'CHECKPOINT_049_PENDING_PRIVATE_CANDIDATE_INELIGIBLE_FAILED';
  end if;
end;
$$;

select set_config('request.jwt.claim.sub','49000000-0000-0000-0000-000000000002',true);
do $$
declare v_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  begin
    perform pg_temp.submit_m49('49000000-0000-0000-0002-000000000001','M49 Cross Contractor',v_today);
    raise exception 'CHECKPOINT_049_CROSS_CONTRACTOR_KEY_ACCEPTED';
  exception when raise_exception then
    if sqlerrm='CHECKPOINT_049_CROSS_CONTRACTOR_KEY_ACCEPTED' then raise; end if;
  end;
end;
$$;
reset role;

-- The operational date derives from Asia/Kolkata, not UTC. The server-side
-- helper is evaluated at execution, and the past case above proves rejection.
do $$
declare v_today date := (clock_timestamp() at time zone 'Asia/Kolkata')::date;
begin
  perform private.assert_contractor_expected_joining_date(null);
  perform private.assert_contractor_expected_joining_date(v_today);
  perform private.assert_contractor_expected_joining_date(v_today+1);
  begin
    perform private.assert_contractor_expected_joining_date(v_today-1);
    raise exception 'CHECKPOINT_049_IST_ROLLOVER_BOUNDARY_FAILED';
  exception when raise_exception then
    if sqlerrm='CHECKPOINT_049_IST_ROLLOVER_BOUNDARY_FAILED' then raise; end if;
  end;
end;
$$;
rollback;
