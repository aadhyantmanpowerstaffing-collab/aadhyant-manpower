-- Migration 050 vacancy Candidate terms checkpoint.
-- This is deliberately a rollback-only runtime checkpoint. It creates only
-- M50-prefixed synthetic identities and vacancies and must be run only after
-- the repository's approved-target identity gate has passed.
\set ON_ERROR_STOP on
begin;

do $$
declare v_definition text;
begin
  if to_regclass('private.vacancy_candidate_benefits') is null
     or to_regclass('private.contractor_vacancy_submission_term_requests') is null
     or to_regprocedure('private.apply_vacancy_candidate_terms(uuid,jsonb)') is null
     or to_regprocedure('public.list_candidate_job_opportunities(text,integer,integer)') is null then
    raise exception 'CHECKPOINT_050_REQUIRED_OBJECT_MISSING';
  end if;
  if has_table_privilege('anon','private.vacancy_candidate_benefits','select,insert,update,delete')
     or has_table_privilege('authenticated','private.vacancy_candidate_benefits','select,insert,update,delete')
     or has_table_privilege('anon','private.contractor_vacancy_submission_term_requests','select,insert,update,delete')
     or has_table_privilege('authenticated','private.contractor_vacancy_submission_term_requests','select,insert,update,delete') then
    raise exception 'CHECKPOINT_050_PRIVATE_BROWSER_GRANT';
  end if;
  select pg_get_functiondef('public.list_candidate_job_opportunities(text,integer,integer)'::regprocedure) into v_definition;
  if v_definition not ilike '%security definer%'
     or v_definition not ilike '%set search_path to ''''%'
     or position('private.vacancy_is_application_eligible(r.id)' in v_definition)=0
     or position('private.vacancy_candidate_benefits_projection(r.id)' in v_definition)=0 then
    raise exception 'CHECKPOINT_050_CANDIDATE_PROJECTION_SECURITY';
  end if;
end;
$$;

-- All identities use a unique checkpoint prefix and disappear at ROLLBACK.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
  ('50000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m50-admin@test.invalid','x','{}','{}',clock_timestamp(),clock_timestamp()),
  ('50000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m50-company@test.invalid','x','{}','{}',clock_timestamp(),clock_timestamp()),
  ('50000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m50-contractor@test.invalid','x','{}','{}',clock_timestamp(),clock_timestamp()),
  ('50000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m50-candidate@test.invalid','x','{}','{}',clock_timestamp(),clock_timestamp());
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
  ('50000000-0000-0000-0000-000000000002','company','M50 Company','m50-company@test.invalid','active'),
  ('50000000-0000-0000-0000-000000000003','contractor','M50 Contractor','m50-contractor@test.invalid','active'),
  ('50000000-0000-0000-0000-000000000004','candidate','M50 Candidate','m50-candidate@test.invalid','active');
insert into public.admin_users(user_id) values ('50000000-0000-0000-0000-000000000001');
insert into public.companies(id,legal_name,main_phone,main_email,city,state,verification_status,account_status) values
  ('50000000-0000-0000-0001-000000000001','M50 Company Private Limited','9876550002','m50-company@test.invalid','Ahmedabad','Gujarat','verified','active');
insert into public.company_users(company_id,user_id,role,status) values
  ('50000000-0000-0000-0001-000000000001','50000000-0000-0000-0000-000000000002','owner','active');
insert into public.contractors(id,agency_name,owner_name,main_phone,main_email,city,state,verification_status,account_status) values
  ('50000000-0000-0000-0001-000000000002','M50 Contractor','M50 Owner','9876550003','m50-contractor@test.invalid','Ahmedabad','Gujarat','verified','active');
insert into public.contractor_users(contractor_id,user_id,role,status) values
  ('50000000-0000-0000-0001-000000000002','50000000-0000-0000-0000-000000000003','owner','active');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status,user_id,profile_status,profile_completion_status,availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth,pincode) values
  ('50000000-0000-0000-0001-000000000003','M50 Candidate',25,'Female','9876550004','Ahmedabad','Ahmedabad','Gujarat','ITI','Fitter','Fresher','Yes',true,'new','50000000-0000-0000-0000-000000000004','active','complete','open_to_opportunities',repeat('5',64),'5004','2001-01-01','380001');

-- This helper is the authoritative, full M050 snapshot used by both owner
-- RPC paths. It covers every scalar field and both cash/provided benefits.
create function pg_temp.m50_terms(p_benefits jsonb default '[{"benefit_type":"insurance","benefit_value_type":"provided"},{"benefit_type":"travel_allowance","benefit_value_type":"cash","amount":500,"amount_basis":"per_month"}]'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'compensation_cadence','monthly','paid_leave_days_per_year',12,
    'casual_leave_days_per_year',6,'sick_leave_days_per_year',6,
    'national_holiday_days_per_year',3,'festival_holiday_days_per_year',8,
    'working_days_per_week',6,'weekly_off_count',1,'overtime_rate',120,
    'overtime_rate_basis','per_hour','canteen_status','chargeable',
    'canteen_charge_amount',30,'canteen_charge_basis','per_day',
    'transport_status','chargeable','transport_charge_amount',900,
    'transport_charge_basis','per_month','employment_type','contract',
    'payroll_type','contractor','contract_duration_months',12,
    'probation_period_months',3,'training_period_days',30,'notice_period_days',30,
    'benefits',p_benefits);
$$;

-- A direct synthetic row exercises every CHECK constraint without bypassing
-- it. Legacy NULL values and explicit zero leave values are both valid.
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,consent,status,requirement_code,job_location,filled_positions,source_type,review_status,requirement_visibility,requirement_stage,basic_da,attendance_bonus,monthly_bonus,leave_amount,other_fixed_earning,gross_wages,employee_pf,employee_esic,canteen_deduction,other_deduction,approx_in_hand,employer_pf,employer_esic,gratuity_provision,bonus_provision,leave_provision,other_ctc_component,ctc)
values ('50000000-0000-0000-0002-000000000001','M50 Constraint Co','M50','9876550099','Ahmedabad','M50 Constraint Role',1,'ITI',true,'new','M50-CONSTRAINT','Ahmedabad',0,'admin_manual','draft','private','draft',100,10,20,111,9,250,10,5,5,0,230,10,5,2,3,222,8,500);

do $$
begin
  if not exists(select 1 from public.employer_requirements r where r.id='50000000-0000-0000-0002-000000000001'
    and r.gross_wages=coalesce(r.basic_da,0)+coalesce(r.attendance_bonus,0)+coalesce(r.monthly_bonus,0)+coalesce(r.leave_amount,0)+coalesce(r.other_fixed_earning,0)
    and r.approx_in_hand=r.gross_wages-coalesce(r.employee_pf,0)-coalesce(r.employee_esic,0)-coalesce(r.canteen_deduction,0)-coalesce(r.other_deduction,0)
    and r.ctc=r.gross_wages+coalesce(r.employer_pf,0)+coalesce(r.employer_esic,0)+coalesce(r.gratuity_provision,0)+coalesce(r.bonus_provision,0)+coalesce(r.leave_provision,0)+coalesce(r.other_ctc_component,0)
    and r.leave_amount=111 and r.leave_provision=222) then
    raise exception 'CHECKPOINT_050_FIXTURE_WAGE_TOTALS';
  end if;
end;
$$;

do $$
declare v_bad jsonb; v_field text; v_value integer; v_status text; v_basis text;
begin
  foreach v_field in array array['paid_leave_days_per_year','casual_leave_days_per_year','sick_leave_days_per_year','national_holiday_days_per_year','festival_holiday_days_per_year'] loop
    -- NULL is unknown/not supplied; 0, a positive annual value, and 366 are
    -- explicit valid annual values for every approved entitlement field.
    perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object(v_field,null,'benefits','[]'::jsonb));
    if (select to_jsonb(r)->>v_field from public.employer_requirements r where r.id='50000000-0000-0000-0002-000000000001') is not null then raise exception 'CHECKPOINT_050_LEAVE_NULL_FAILED: %',v_field; end if;
    foreach v_value in array array[0,12,366] loop
      perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object(v_field,v_value,'benefits','[]'::jsonb));
      if (select (to_jsonb(r)->>v_field)::integer from public.employer_requirements r where r.id='50000000-0000-0000-0002-000000000001')<>v_value then raise exception 'CHECKPOINT_050_LEAVE_VALID_FAILED: %=%',v_field,v_value; end if;
    end loop;
    foreach v_value in array array[-1,367] loop
      begin
        perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object(v_field,v_value,'benefits','[]'::jsonb));
        raise exception 'CHECKPOINT_050_LEAVE_BOUND_ACCEPTED: %=%',v_field,v_value;
      exception when check_violation or raise_exception then
        if sqlerrm like 'CHECKPOINT_050_LEAVE_BOUND_ACCEPTED%' then raise; end if;
      end;
    end loop;
  end loop;
  if (select leave_amount from public.employer_requirements where id='50000000-0000-0000-0002-000000000001')<>111
     or (select leave_provision from public.employer_requirements where id='50000000-0000-0000-0002-000000000001')<>222 then
    raise exception 'CHECKPOINT_050_FINANCIAL_LEAVE_FIELDS_REPURPOSED';
  end if;
  -- Complete structured Canteen matrix: NULL preserves legacy fallback;
  -- every non-chargeable state clears charges; every approved charge basis
  -- accepts a positive amount.
  perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('canteen_status',null,'benefits','[]'::jsonb));
  if (select canteen_status from public.employer_requirements where id='50000000-0000-0000-0002-000000000001') is not null then raise exception 'CHECKPOINT_050_CANTEEN_LEGACY_NULL'; end if;
  foreach v_status in array array['free','not_available','not_applicable'] loop
    perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('canteen_status',v_status,'benefits','[]'::jsonb));
    if exists(select 1 from public.employer_requirements where id='50000000-0000-0000-0002-000000000001' and (canteen_status<>v_status or canteen_charge_amount is not null or canteen_charge_basis is not null)) then raise exception 'CHECKPOINT_050_CANTEEN_NONCHARGEABLE: %',v_status; end if;
  end loop;
  foreach v_basis in array array['per_day','per_meal','per_month'] loop
    perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('canteen_status','chargeable','canteen_charge_amount',30,'canteen_charge_basis',v_basis,'benefits','[]'::jsonb));
    if not exists(select 1 from public.employer_requirements where id='50000000-0000-0000-0002-000000000001' and canteen_status='chargeable' and canteen_charge_amount=30 and canteen_charge_basis=v_basis) then raise exception 'CHECKPOINT_050_CANTEEN_CHARGEABLE: %',v_basis; end if;
  end loop;
  -- Complete structured Transport matrix, including both approved charge bases.
  perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('transport_status',null,'benefits','[]'::jsonb));
  if (select transport_status from public.employer_requirements where id='50000000-0000-0000-0002-000000000001') is not null then raise exception 'CHECKPOINT_050_TRANSPORT_LEGACY_NULL'; end if;
  foreach v_status in array array['free','not_available','not_applicable'] loop
    perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('transport_status',v_status,'benefits','[]'::jsonb));
    if exists(select 1 from public.employer_requirements where id='50000000-0000-0000-0002-000000000001' and (transport_status<>v_status or transport_charge_amount is not null or transport_charge_basis is not null)) then raise exception 'CHECKPOINT_050_TRANSPORT_NONCHARGEABLE: %',v_status; end if;
  end loop;
  foreach v_basis in array array['per_day','per_month'] loop
    perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',jsonb_build_object('transport_status','chargeable','transport_charge_amount',900,'transport_charge_basis',v_basis,'benefits','[]'::jsonb));
    if not exists(select 1 from public.employer_requirements where id='50000000-0000-0000-0002-000000000001' and transport_status='chargeable' and transport_charge_amount=900 and transport_charge_basis=v_basis) then raise exception 'CHECKPOINT_050_TRANSPORT_CHARGEABLE: %',v_basis; end if;
  end loop;
  foreach v_bad in array array[
    '{"compensation_cadence":"weekly"}'::jsonb,
    '{"working_days_per_week":6,"weekly_off_count":2}'::jsonb,
    '{"overtime_rate":100}'::jsonb,
    '{"overtime_rate_basis":"per_hour"}'::jsonb,
    '{"overtime_rate":0,"overtime_rate_basis":"per_hour"}'::jsonb,
    '{"canteen_status":"chargeable","canteen_charge_amount":0,"canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"chargeable","canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"chargeable","canteen_charge_amount":30}'::jsonb,
    '{"canteen_status":"chargeable","canteen_charge_amount":-1,"canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"chargeable","canteen_charge_amount":30,"canteen_charge_basis":"invalid"}'::jsonb,
    '{"canteen_status":"free","canteen_charge_amount":30,"canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"not_available","canteen_charge_amount":30,"canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"not_applicable","canteen_charge_amount":30,"canteen_charge_basis":"per_day"}'::jsonb,
    '{"canteen_status":"unsupported"}'::jsonb,
    '{"transport_status":"chargeable","transport_charge_amount":30,"transport_charge_basis":"per_meal"}'::jsonb,
    '{"transport_status":"chargeable","transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"chargeable","transport_charge_amount":900}'::jsonb,
    '{"transport_status":"chargeable","transport_charge_amount":0,"transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"chargeable","transport_charge_amount":-1,"transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"free","transport_charge_amount":900,"transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"not_available","transport_charge_amount":900,"transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"not_applicable","transport_charge_amount":900,"transport_charge_basis":"per_day"}'::jsonb,
    '{"transport_status":"unsupported"}'::jsonb,
    '{"employment_type":"permanent","contract_duration_months":12}'::jsonb,
    '{"employment_type":"contract","contract_duration_months":121}'::jsonb,
    '{"probation_period_months":25}'::jsonb,
    '{"training_period_days":366}'::jsonb,
    '{"notice_period_days":181}'::jsonb,
    '{"benefits":[{"benefit_type":"arbitrary","benefit_value_type":"provided"}]}'::jsonb,
    '{"benefits":[{"benefit_type":"insurance","benefit_value_type":"cash","amount":0,"amount_basis":"per_month"}]}'::jsonb,
    '{"benefits":[{"benefit_type":"insurance","benefit_value_type":"provided","amount":1}]}'::jsonb
  ] loop
    begin
      perform private.apply_vacancy_candidate_terms('50000000-0000-0000-0002-000000000001',v_bad);
      raise exception 'CHECKPOINT_050_INVALID_TERMS_ACCEPTED: %',v_bad;
    exception when check_violation or raise_exception then
      if sqlerrm like 'CHECKPOINT_050_INVALID_TERMS_ACCEPTED%' then raise; end if;
    end;
  end loop;
  -- Existing M044 accommodation constraints remain authoritative.
  begin
    update public.employer_requirements set accommodation_status='free',accommodation_charge_amount=1 where id='50000000-0000-0000-0002-000000000001';
    raise exception 'CHECKPOINT_050_ACCOMMODATION_REGRESSION';
  exception when check_violation then null;
  end;
end;
$$;

-- Browser-role execution must not discover the private benefits table.
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000004',true);
do $$
begin
  begin
    perform 1 from private.vacancy_candidate_benefits;
    raise exception 'CHECKPOINT_050_AUTHENTICATED_PRIVATE_BENEFITS_READ';
  exception when insufficient_privilege then null;
    when undefined_table then null;
    when raise_exception then if sqlerrm='CHECKPOINT_050_AUTHENTICATED_PRIVATE_BENEFITS_READ' then raise; end if;
  end;
end;
$$;
reset role;

-- Company owner uses the M050-aware controlled RPC. No browser table write
-- is used to create or serialize the Company snapshot.
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000002',true);
do $$
declare v_company record;
begin
  select * into v_company from public.manage_company_portal_requirement(
    p_action=>'create',p_requirement_id=>null,p_department=>'M50',p_job_role=>'M50 Company Fitter',p_job_location=>'Ahmedabad',p_required_headcount=>2,p_qualification=>'ITI',p_iti_trade=>'Fitter',p_experience_requirement=>'Fresher',p_gender_preference=>'Any',p_age_min=>18,p_age_max=>45,p_salary_min=>15000,p_salary_max=>16000,p_shift_details=>'Day',p_working_hours=>'8 hours',p_overtime_details=>'Available',p_canteen=>'Available',p_transport=>'Available',p_accommodation=>'Available',p_interview_location=>'Ahmedabad',p_interview_date=>null,p_expected_joining_date=>(clock_timestamp() at time zone 'Asia/Kolkata')::date,p_additional_notes=>'M50 synthetic',p_payable_days=>26,p_basic_da=>12000,p_attendance_bonus=>500,p_monthly_bonus=>250,p_leave_amount=>100,p_other_fixed_earning=>150,p_gross_wages=>13000,p_employee_pf=>100,p_employee_esic=>50,p_canteen_deduction=>0,p_other_deduction=>0,p_employer_pf=>100,p_employer_esic=>50,p_gratuity_provision=>25,p_bonus_provision=>25,p_leave_provision=>25,p_other_ctc_component=>25,p_approx_in_hand=>12850,p_ctc=>13250,p_accommodation_status=>'chargeable',p_accommodation_charge_amount=>1500,p_accommodation_charge_basis=>'per_month',p_candidate_terms=>pg_temp.m50_terms()) limit 1;
  if v_company.id is null or (select count(*) from private.vacancy_candidate_benefits where requirement_id=v_company.id)<>2 then
    raise exception 'CHECKPOINT_050_COMPANY_OWNER_RPC_TERMS';
  end if;
  perform set_config('m50.company_requirement',v_company.id::text,true);
end;
$$;
reset role;

-- Contractor submission exercises M049's base ledger plus the M050 terms
-- ledger in one transaction. Same-key replays must remain one logical row.
create function pg_temp.submit_m50(p_key uuid,p_terms jsonb,p_client_name text default 'M50 Client')
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language sql as $$
  select * from public.manage_contractor_portal_vacancy(
    p_action=>'create_and_submit',p_requirement_id=>null,p_client_name=>p_client_name,p_department=>'M50',p_job_role=>'M50 Contractor Fitter',p_job_location=>'Ahmedabad',p_required_headcount=>2,p_qualification=>'ITI',p_iti_trade=>'Fitter',p_experience_requirement=>'Fresher',p_gender_preference=>'Any',p_age_min=>18,p_age_max=>45,p_salary_min=>15000,p_salary_max=>16000,p_shift_details=>'Day',p_working_hours=>'8 hours',p_overtime_details=>'Available',p_canteen=>'Available',p_transport=>'Available',p_accommodation=>'Available',p_interview_location=>'Ahmedabad',p_expected_joining_date=>(clock_timestamp() at time zone 'Asia/Kolkata')::date,p_additional_notes=>'M50 synthetic',p_payable_days=>26,p_basic_da=>12000,p_attendance_bonus=>500,p_monthly_bonus=>250,p_leave_amount=>100,p_other_fixed_earning=>150,p_gross_wages=>13000,p_employee_pf=>100,p_employee_esic=>50,p_canteen_deduction=>0,p_other_deduction=>0,p_employer_pf=>100,p_employer_esic=>50,p_gratuity_provision=>25,p_bonus_provision=>25,p_leave_provision=>25,p_other_ctc_component=>25,p_approx_in_hand=>12850,p_ctc=>13250,p_accommodation_status=>'chargeable',p_accommodation_charge_amount=>1500,p_accommodation_charge_basis=>'per_month',p_submission_idempotency_key=>p_key,p_candidate_terms=>p_terms
  );
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000003',true);
do $$
declare v_first record; v_replay record; v_terms jsonb:=pg_temp.m50_terms();
begin
  select * into v_first from pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',v_terms);
  select * into v_replay from pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',v_terms);
  if v_first.id is null or v_first.id<>v_replay.id or v_first.submission_status<>'submitted' then
    raise exception 'CHECKPOINT_050_IDEMPOTENT_REPLAY';
  end if;
  if (select count(*) from public.employer_requirements where id=v_first.id)<>1
     or (select count(*) from public.requirement_contractors where requirement_id=v_first.id and contractor_id='50000000-0000-0000-0001-000000000002')<>1
     or (select count(*) from private.contractor_vacancy_submission_requests where requirement_id=v_first.id)<>1
     or (select count(*) from private.contractor_vacancy_submission_term_requests where requirement_id=v_first.id)<>1
     or (select count(*) from private.vacancy_candidate_benefits where requirement_id=v_first.id)<>2 then
    raise exception 'CHECKPOINT_050_IDEMPOTENCY_CARDINALITY';
  end if;
  perform set_config('m50.contractor_requirement',v_first.id::text,true);
  begin
    perform pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',v_terms,'M50 Changed Base Client');
    raise exception 'CHECKPOINT_050_CHANGED_BASE_REPLAY_ACCEPTED';
  exception when raise_exception then if sqlerrm='CHECKPOINT_050_CHANGED_BASE_REPLAY_ACCEPTED' then raise; end if;
  end;
  begin
    perform pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',jsonb_set(v_terms,'{paid_leave_days_per_year}','13'::jsonb));
    raise exception 'CHECKPOINT_050_CHANGED_SCALAR_REPLAY_ACCEPTED';
  exception when raise_exception then if sqlerrm='CHECKPOINT_050_CHANGED_SCALAR_REPLAY_ACCEPTED' then raise; end if;
  end;
  begin
    perform pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',jsonb_set(v_terms,'{benefits}','[{"benefit_type":"uniform","benefit_value_type":"provided"}]'::jsonb));
    raise exception 'CHECKPOINT_050_CHANGED_BENEFIT_REPLAY_ACCEPTED';
  exception when raise_exception then if sqlerrm='CHECKPOINT_050_CHANGED_BENEFIT_REPLAY_ACCEPTED' then raise; end if;
  end;
  begin
    perform pg_temp.submit_m50('50000000-0000-0000-0003-000000000001',jsonb_set(v_terms,'{paid_leave_days_per_year}','13'::jsonb),'M50 Changed Base And Terms');
    raise exception 'CHECKPOINT_050_CHANGED_BASE_AND_TERMS_REPLAY_ACCEPTED';
  exception when raise_exception then if sqlerrm='CHECKPOINT_050_CHANGED_BASE_AND_TERMS_REPLAY_ACCEPTED' then raise; end if;
  end;
  if (select count(*) from public.employer_requirements where id=v_first.id)<>1
     or (select count(*) from private.contractor_vacancy_submission_requests where requirement_id=v_first.id)<>1
     or (select count(*) from private.contractor_vacancy_submission_term_requests where requirement_id=v_first.id)<>1
     or (select count(*) from private.vacancy_candidate_benefits where requirement_id=v_first.id)<>2 then
    raise exception 'CHECKPOINT_050_CONFLICT_RESIDUE';
  end if;
end;
$$;
reset role;

-- Admin approval followed by scalar and benefit-only material changes must
-- remove a vacancy from Candidate eligibility until explicit republication.
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
select public.admin_approve_and_publish_vacancy(current_setting('m50.contractor_requirement')::uuid,null);
do $$
declare v_requirement uuid:=current_setting('m50.contractor_requirement')::uuid;
begin
  if not private.vacancy_is_application_eligible(v_requirement) then raise exception 'CHECKPOINT_050_APPROVAL_PRECONDITION'; end if;
end;
$$;
reset role;
do $$
declare v_requirement uuid:=current_setting('m50.contractor_requirement')::uuid;
begin
  perform private.apply_vacancy_candidate_terms(v_requirement,jsonb_set(pg_temp.m50_terms(),'{canteen_charge_amount}','35'::jsonb));
  if private.vacancy_is_application_eligible(v_requirement) then raise exception 'CHECKPOINT_050_SCALAR_REREVIEW_GATE'; end if;
end;
$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
select public.admin_approve_and_publish_vacancy(current_setting('m50.contractor_requirement')::uuid,null);
reset role;
do $$
declare v_requirement uuid:=current_setting('m50.contractor_requirement')::uuid;
begin
  insert into private.vacancy_candidate_benefits(requirement_id,benefit_type,benefit_value_type) values(v_requirement,'uniform','provided');
  if private.vacancy_is_application_eligible(v_requirement) then raise exception 'CHECKPOINT_050_BENEFIT_REREVIEW_GATE'; end if;
end;
$$;

-- Pending Review stays excluded from the Candidate RPC. After the explicit
-- approval transition, the safe projection includes only approved fields.
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000004',true);
do $$
declare v_requirement uuid:=current_setting('m50.contractor_requirement')::uuid;
begin
  if exists(select 1 from public.list_candidate_job_opportunities('M50 Contractor Fitter',50,0) where requirement_code=(select requirement_code from public.employer_requirements where id=v_requirement)) then
    raise exception 'CHECKPOINT_050_PENDING_REVIEW_EXPOSED';
  end if;
end;
$$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
select public.admin_approve_and_publish_vacancy(current_setting('m50.contractor_requirement')::uuid,null);
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000004',true);
do $$
declare v_row record;
begin
  select * into v_row from public.list_candidate_job_opportunities('M50 Contractor Fitter',50,0) limit 1;
  if v_row.requirement_code is null or v_row.compensation_cadence<>'monthly' or v_row.approx_in_hand<>12850
     or v_row.candidate_benefits::text like any(array['%requirement_id%','%owner_id%','%user_id%','%internal_notes%','%margin%','%invoice%'])
     or v_row.candidate_benefits<>jsonb_build_array(jsonb_build_object('benefit_type','insurance','benefit_value_type','provided'),jsonb_build_object('benefit_type','travel_allowance','benefit_value_type','cash','amount',500,'amount_basis','per_month'),jsonb_build_object('benefit_type','uniform','benefit_value_type','provided')) then
    raise exception 'CHECKPOINT_050_CANDIDATE_SAFE_PROJECTION';
  end if;
end;
$$;
reset role;

-- Legacy compatibility: all M050 optional fields remain NULL and legacy
-- salary/facility values are not converted to zero or fabricated terms.
insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,consent,status,requirement_code,job_location,filled_positions,source_type,review_status,requirement_visibility,requirement_stage,salary_wage,canteen,transport,accommodation)
values ('50000000-0000-0000-0002-000000000002','M50 Legacy Co','M50','9876550098','Ahmedabad','M50 Legacy Role',1,'ITI',true,'in_progress','M50-LEGACY','Ahmedabad',0,'admin_manual','approved','public','open','15000','Available','Not Available','Available');
set local role authenticated;
select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000004',true);
do $$
declare v_row record;
begin
  select * into v_row from public.list_candidate_job_opportunities('M50 Legacy Role',50,0) limit 1;
  if v_row.salary_wage<>'15000' or v_row.canteen_status is not null or v_row.transport_status is not null
     or v_row.candidate_benefits<>'[]'::jsonb then
    raise exception 'CHECKPOINT_050_LEGACY_FALLBACK';
  end if;
end;
$$;
reset role;

-- The transaction boundary is the zero-residue assertion: all M50-prefixed
-- users, requirements, links, audit effects, idempotency rows, and benefits
-- above are rolled back atomically. No cleanup statement targets real data.
rollback;
select 'CHECKPOINT_050_ZERO_RESIDUE_ROLLBACK_COMPLETE' as checkpoint;
