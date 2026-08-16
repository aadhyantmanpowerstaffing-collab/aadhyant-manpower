-- Run only against an isolated disposable Supabase database with migrations through 012.
-- All fixtures are rolled back.

\set ON_ERROR_STOP on
begin;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('41000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','r11-admin@test.local','x',now(),'{}','{}',now(),now());
insert into public.admin_users(user_id) values ('41000000-0000-0000-0000-000000000001');

insert into public.employer_requirements (
  company_name, contact_person, mobile, company_location, job_role,
  required_headcount, filled_positions, consent, department, job_location,
  requirement_stage, requirement_visibility, published_at
) values
  ('R11 Open', 'Test', '9876511001', 'Ahmedabad', 'R11 Open Fitter', 5, 1, true, 'Production', 'Ahmedabad', 'open', 'public', now()),
  ('R11 Draft', 'Test', '9876511002', 'Ahmedabad', 'R11 Draft Role', 5, 0, true, 'Production', 'Ahmedabad', 'draft', 'public', null),
  ('R11 Private', 'Test', '9876511003', 'Ahmedabad', 'R11 Private Role', 5, 0, true, 'Production', 'Ahmedabad', 'open', 'private', now()),
  ('R11 Closed', 'Test', '9876511004', 'Ahmedabad', 'R11 Closed Role', 5, 0, true, 'Production', 'Ahmedabad', 'closed', 'public', now());

create temporary table r11_codes as
select job_role, requirement_code from public.employer_requirements where job_role like 'R11 %';
grant select on r11_codes to anon;

set local role anon;

do $$
declare
  candidate_payload jsonb := jsonb_build_object(
    'full_name','R11 Candidate','age',24,'gender','Male','mobile','9876511099',
    'whatsapp_number','9876511099','current_location','Kadi','district','Mahesana',
    'state','Gujarat','highest_qualification','ITI','specialization','Fitter',
    'candidate_type','Experienced','total_experience','2 years','previous_job_role','Fitter',
    'interview_available','Yes','preferred_job_location','Ahmedabad',
    'additional_information','R11 local fixture','consent',true
  );
  result text;
  denied boolean := false;
  code text;
begin
  select requirement_code into code from r11_codes where job_role='R11 Open Fitter';
  result := public.register_candidate_requirement_interest(code, candidate_payload);
  if result <> 'registered' then raise exception 'Open/public interest was not registered'; end if;
  result := public.register_candidate_requirement_interest(code, candidate_payload);
  if result <> 'already_registered' then raise exception 'Duplicate interest was not handled'; end if;

  foreach code in array array[
    (select requirement_code from r11_codes where job_role='R11 Draft Role'),
    (select requirement_code from r11_codes where job_role='R11 Private Role'),
    (select requirement_code from r11_codes where job_role='R11 Closed Role'),
    'AAD-2099-999999'
  ] loop
    begin
      perform public.register_candidate_requirement_interest(code, candidate_payload || jsonb_build_object('mobile','9876511088'));
      raise exception 'Ineligible requirement unexpectedly accepted: %', code;
    exception when raise_exception then
      if sqlerrm like 'Ineligible requirement unexpectedly accepted:%' then raise; end if;
    end;
  end loop;

  begin perform 1 from public.candidates limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous Candidate SELECT unexpectedly succeeded'; end if;
  denied := false;
  begin perform 1 from public.candidate_applications limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous application SELECT unexpectedly succeeded'; end if;
  denied := false;
  begin perform 1 from public.employer_requirements limit 1; exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Anonymous requirement base SELECT unexpectedly succeeded'; end if;
end;
$$;

-- Existing general anonymous Candidate registration remains available.
insert into public.candidates(full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent)
values('R11 General Candidate',25,'Female','9876511077','Kadi','Mahesana','Gujarat','Graduate','Fresher','Yes',true);

reset role;

do $$
begin
  if (select count(*) from public.candidates where full_name='R11 Candidate') <> 1 then
    raise exception 'Linked registration created duplicate Candidate profiles';
  end if;
  if (select count(*) from public.candidate_applications a join public.candidates c on c.id=a.candidate_id where c.full_name='R11 Candidate') <> 1 then
    raise exception 'Duplicate Candidate interest was created';
  end if;
  if exists (select 1 from pg_policies where schemaname='public' and tablename='candidate_applications' and 'anon'=any(roles) and cmd='SELECT') then
    raise exception 'Anonymous application SELECT policy unexpectedly exists';
  end if;
  if has_table_privilege('anon','public.candidate_applications','SELECT') then
    raise exception 'Anonymous application SELECT grant unexpectedly exists';
  end if;
  if not has_function_privilege('anon','public.register_candidate_requirement_interest(text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.register_candidate_requirement_interest(text,jsonb)','EXECUTE') then
    raise exception 'R11 function grants are incorrect';
  end if;
  if not exists (select 1 from public.get_public_job_requirements(50,0) where job_role='R11 Open Fitter') then
    raise exception 'R10 public Jobs RPC regression';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000099',true);
do $$
begin
  if exists(select 1 from public.candidate_applications) then raise exception 'Non-admin authenticated user read Candidate interests'; end if;
  if exists(select 1 from public.candidates) then raise exception 'Non-admin authenticated user read Candidates'; end if;
end;
$$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','41000000-0000-0000-0000-000000000001',true);
do $$ begin
  if not exists(select 1 from public.candidate_applications a join public.candidates c on c.id=a.candidate_id where c.full_name='R11 Candidate' and a.application_status='interested') then
    raise exception 'Approved Admin could not review Candidate interest';
  end if;
end $$;
reset role;

rollback;
