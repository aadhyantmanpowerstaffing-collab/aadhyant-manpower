-- Run only against an isolated disposable Supabase database after the Candidate
-- OTP migrations, including the final rollout enforcement migration. All
-- fixtures and dispatch records are rolled back.

\set ON_ERROR_STOP on
begin;

do $$
begin
  if to_regclass('private.candidate_whatsapp_otp_dispatches') is null
     or to_regprocedure('public.candidate_otp_dispatch_reserve(text,text)') is null
     or to_regprocedure('public.register_authenticated_candidate(jsonb,text)') is null then
    raise exception 'Candidate OTP prerequisites are missing';
  end if;
  if has_table_privilege('anon', 'private.candidate_whatsapp_otp_dispatches', 'SELECT,INSERT,UPDATE,DELETE')
     or has_table_privilege('authenticated', 'private.candidate_whatsapp_otp_dispatches', 'SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'Browser role can access private OTP dispatch state';
  end if;
  if has_schema_privilege('anon', 'private', 'USAGE')
     or has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'Browser role can use private OTP schema';
  end if;
  if has_function_privilege('anon', 'public.candidate_otp_dispatch_reserve(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.candidate_otp_dispatch_reserve(text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.candidate_otp_dispatch_complete(text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.candidate_otp_dispatch_complete(text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.candidate_otp_dispatch_fail(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.candidate_otp_dispatch_fail(text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.candidate_otp_dispatch_reserve(text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.candidate_otp_dispatch_complete(text,text)', 'EXECUTE')
     or not has_function_privilege('service_role', 'public.candidate_otp_dispatch_fail(text)', 'EXECUTE') then
    raise exception 'OTP dispatch function grants are incorrect';
  end if;
  if has_table_privilege('anon', 'public.candidates', 'INSERT')
     or has_table_privilege('authenticated', 'public.candidates', 'INSERT')
     or has_function_privilege('anon', 'public.register_candidate_requirement_interest(text,jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.register_candidate_requirement_interest(text,jsonb)', 'EXECUTE') then
    raise exception 'Legacy anonymous Candidate registration bypass remains open';
  end if;
end;
$$;

set local role service_role;
do $$
declare
  phone_hash text := repeat('a', 64);
  code_one text := repeat('b', 64);
  code_two text := repeat('c', 64);
  code_three text := repeat('d', 64);
  code_four text := repeat('e', 64);
  result text;
begin
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_one);
  if result <> 'reserved' then raise exception 'First dispatch was not reserved'; end if;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_one);
  if result <> 'in_progress' then raise exception 'Pending OTP was not idempotent'; end if;
  result := public.candidate_otp_dispatch_complete(code_one, 'wamid.test-delivery-1');
  if result <> 'sent' then raise exception 'Dispatch completion failed'; end if;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_one);
  if result <> 'sent' then raise exception 'Delivered OTP was not idempotent'; end if;
  update private.candidate_whatsapp_otp_dispatches
    set reserved_at = now() - interval '11 minutes'
    where code_hash = code_one;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_one);
  if result <> 'reserved' then raise exception 'Expired idempotency window blocked a new Auth OTP'; end if;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_two);
  if result <> 'reserved' then raise exception 'Second dispatch was not reserved'; end if;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_three);
  if result <> 'reserved' then raise exception 'Third dispatch was not reserved'; end if;
  result := public.candidate_otp_dispatch_reserve(phone_hash, code_four);
  if result <> 'limited' then raise exception '24-hour dispatch cap was not enforced'; end if;
end;
$$;
reset role;

insert into auth.users (
  id, instance_id, aud, role, phone, phone_confirmed_at, encrypted_password,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '51000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', '+919876543210', now(), 'x', '{}', '{}', now(), now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '51000000-0000-0000-0000-000000000001', true);
do $$
declare
  candidate_payload jsonb := jsonb_build_object(
    'full_name','OTP Test Candidate','age',24,'gender','Female','mobile','9876543210',
    'whatsapp_number','9876543210','current_location','Kadi','district','Mahesana',
    'state','Gujarat','highest_qualification','ITI','specialization','Fitter',
    'candidate_type','Fresher','total_experience',null,'previous_job_role',null,
    'interview_available','Yes','preferred_job_location','Sanand',
    'additional_information',null,'consent',true
  );
  result text;
  mobile_mismatch_denied boolean := false;
  whatsapp_mismatch_denied boolean := false;
  identity_mismatch_denied boolean := false;
begin
  result := public.register_authenticated_candidate(candidate_payload, null);
  if result <> 'registered' then raise exception 'Verified Candidate registration failed'; end if;
  begin
    perform public.register_authenticated_candidate(
      candidate_payload || jsonb_build_object('mobile', '9876543211'), null
    );
  exception when raise_exception then
    mobile_mismatch_denied := true;
  end;
  if not mobile_mismatch_denied then raise exception 'Verified session registered a different mobile'; end if;
  begin
    perform public.register_authenticated_candidate(
      candidate_payload || jsonb_build_object('whatsapp_number', '9876543211'), null
    );
  exception when raise_exception then
    whatsapp_mismatch_denied := true;
  end;
  if not whatsapp_mismatch_denied then raise exception 'Verified session registered a different WhatsApp number'; end if;
  begin
    perform public.register_authenticated_candidate(
      candidate_payload || jsonb_build_object('full_name', 'Different Candidate'), null
    );
  exception when raise_exception then
    identity_mismatch_denied := true;
  end;
  if not identity_mismatch_denied then raise exception 'Verified phone could overwrite a different Candidate identity'; end if;
end;
$$;
reset role;

do $$
begin
  if not exists (
    select 1 from public.candidates
    where mobile = '9876543210'
      and user_id = '51000000-0000-0000-0000-000000000001'
      and mobile_verified = true
      and verified_at is not null
  ) then
    raise exception 'Verified Candidate account was not linked';
  end if;
end;
$$;

rollback;
