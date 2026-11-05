-- Atomic OTP challenges, verification proof and registration handoff.
-- These functions are SERVICE ROLE ONLY, never callable by public clients.
alter table public.candidate_phone_otp
  add column if not exists proof_hash text,
  add column if not exists proof_expires_at timestamptz,
  add column if not exists consumed_at timestamptz;

create or replace function public.candidate_otp_issue(
  p_phone text, p_hash text
) returns text language plpgsql
set search_path = ''
as $$
declare
  v_row public.candidate_phone_otp%rowtype;
  v_now timestamptz := now();
  v_same_window boolean;
begin
  if current_user <> 'service_role' then raise exception 'Not authorized'; end if;
  if p_phone !~ '^91[6-9][0-9]{9}$' or length(p_hash) <> 64
      or p_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid OTP input';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('candidate-otp:' || p_phone, 0));
  select * into v_row from public.candidate_phone_otp where phone = p_phone for update;
  if found and v_now < v_row.last_sent_at + interval '60 seconds' then
    return 'cooldown';
  end if;
  v_same_window := found and v_now < v_row.window_started_at + interval '24 hours';
  if v_same_window and v_row.sends_in_window >= 3 then
    return 'limited';
  end if;
  insert into public.candidate_phone_otp (
    phone, otp_hash, expires_at, last_sent_at, window_started_at,
    sends_in_window, verify_attempts, verified_at, proof_hash, proof_expires_at, consumed_at
  ) values (
    p_phone, p_hash, v_now + interval '5 minutes', v_now,
    case when v_same_window then v_row.window_started_at else v_now end,
    case when v_same_window then v_row.sends_in_window + 1 else 1 end,
    0, null, null, null, null
  )
  on conflict (phone) do update set
    otp_hash = excluded.otp_hash,
    expires_at = excluded.expires_at,
    last_sent_at = excluded.last_sent_at,
    window_started_at = excluded.window_started_at,
    sends_in_window = excluded.sends_in_window,
    verify_attempts = 0,
    verified_at = null,
    proof_hash = null,
    proof_expires_at = null,
    consumed_at = null;
  return 'issued';
end;
$$;

create or replace function public.candidate_otp_verify(
  p_phone text, p_hash text, p_proof_hash text
) returns boolean language plpgsql
set search_path = ''
as $$
declare v_row public.candidate_phone_otp%rowtype;
begin
  if current_user <> 'service_role' then raise exception 'Not authorized'; end if;
  if p_phone !~ '^91[6-9][0-9]{9}$'
    or p_hash !~ '^[0-9a-f]{64}$' or p_proof_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  select * into v_row from public.candidate_phone_otp
    where phone = p_phone for update;
  if not found or v_row.verified_at is not null or v_row.expires_at <= now()
    or v_row.verify_attempts >= 5 then
    return false;
  end if;
  update public.candidate_phone_otp
    set verify_attempts = verify_attempts + 1
    where phone = p_phone;
  if v_row.otp_hash <> p_hash then return false; end if;
  update public.candidate_phone_otp
    set verified_at = now(),
        proof_hash = p_proof_hash,
        proof_expires_at = now() + interval '10 minutes'
    where phone = p_phone;
  return true;
end;
$$;

create or replace function public.candidate_otp_cancel(
  p_phone text, p_hash text
) returns void language plpgsql set search_path = ''
as $$
begin
  if current_user <> 'service_role' then raise exception 'Not authorized'; end if;
  update public.candidate_phone_otp
    set expires_at = now(), proof_hash = null,
        proof_expires_at = null, verified_at = null
    where phone = p_phone and otp_hash = p_hash;
end;
$$;

create or replace function public.candidate_otp_register(
  p_phone text, p_proof_hash text, p_candidate jsonb, p_requirement_code text default null
) returns text language plpgsql set search_path = ''
as $$
declare
  v_row public.candidate_phone_otp%rowtype;
  v_phone text;
  v_age integer;
  v_candidate_id uuid;
  v_match_count integer;
  v_result text;
  v_name text;
begin
  if current_user <> 'service_role' then raise exception 'Not authorized'; end if;
  if p_candidate is null or jsonb_typeof(p_candidate) <> 'object'
      or p_proof_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Invalid registration';
  end if;
  if p_candidate - array[
    'full_name','age','gender','mobile','whatsapp_number',
    'current_location','district','state','highest_qualification',
    'specialization','candidate_type','total_experience','previous_job_role',
    'interview_available','preferred_job_location','additional_information','consent'
  ] <> '{}'::jsonb then
    raise exception 'Invalid candidate attributes';
  end if;
  v_phone := regexp_replace(coalesce(p_candidate ->> 'mobile',''), '[^0-9]', '', 'g');
  v_name := btrim(coalesce(p_candidate ->> 'full_name',''));
  begin
    v_age := (p_candidate ->> 'age')::integer;
  exception when others then
    raise exception 'Invalid candidate age';
  end;
  if p_phone <> '91' || v_phone or v_phone !~ '^[6-9][0-9]{9}$'
    or length(v_name) not between 1 and 160 or v_age not between 16 and 75
    or coalesce((p_candidate ->> 'consent')::boolean,false) <> true
    or coalesce(btrim(p_candidate ->> 'gender'),'') = ''
    or coalesce(btrim(p_candidate ->> 'current_location'),'') = ''
    or coalesce(btrim(p_candidate ->> 'district'),'') = ''
    or coalesce(btrim(p_candidate ->> 'state'),'') = ''
    or coalesce(btrim(p_candidate ->> 'highest_qualification'),'') = ''
    or coalesce(btrim(p_candidate ->> 'candidate_type'),'') = ''
    or coalesce(btrim(p_candidate ->> 'interview_available'),'') = '' then
      raise exception 'Invalid candidate details';
  end if;
  select * into v_row from public.candidate_phone_otp
    where phone = p_phone for update;
  if not found or v_row.verified_at is null or v_row.consumed_at is not null
    or v_row.proof_hash is distinct from p_proof_hash
    or v_row.proof_expires_at <= now() then
    raise exception 'Verified OTP proof required';
  end if;
  if nullif(btrim(coalesce(p_requirement_code,'')), '') is not null then
    v_result := public.register_candidate_requirement_interest(p_requirement_code, p_candidate);
    if v_result = 'registered' or v_result = 'already_registered' then
      update public.candidates
        set mobile_verified = true, verified_at = coalesce(verified_at, now())
        where mobile = v_phone and lower(btrim(full_name)) = lower(v_name) and age = v_age;
    end if;
  else
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('r11-candidate:' || v_phone, 0));
    select count(*) into v_match_count from public.candidates
      where mobile = v_phone and lower(btrim(full_name)) = lower(v_name) and age = v_age;
    if v_match_count > 1 then raise exception 'Candidate identity requires review'; end if;
    if v_match_count = 1 then
      update public.candidates
        set mobile_verified = true, verified_at = coalesce(verified_at, now())
        where mobile = v_phone and lower(btrim(full_name)) = lower(v_name) and age = v_age;
      v_result := 'already_registered';
    else
      insert into public.candidates (
        full_name,age,gender,mobile,whatsapp_number,current_location,district,state,
        highest_qualification,specialization,candidate_type,total_experience,
        previous_job_role,interview_available,preferred_job_location,
        additional_information,consent,mobile_verified,verified_at
      ) values (
        v_name,v_age,p_candidate ->> 'gender',v_phone,
        nullif(btrim(p_candidate ->> 'whatsapp_number'),''),
        btrim(p_candidate ->> 'current_location'),btrim(p_candidate ->> 'district'),
        btrim(p_candidate ->> 'state'),p_candidate ->> 'highest_qualification',
        nullif(btrim(p_candidate ->> 'specialization'),''),
        p_candidate ->> 'candidate_type',
        nullif(btrim(p_candidate ->> 'total_experience'),''),
        nullif(btrim(p_candidate ->> 'previous_job_role'),''),
        p_candidate ->> 'interview_available',
        nullif(btrim(p_candidate ->> 'preferred_job_location'),''),
        nullif(btrim(p_candidate ->> 'additional_information'),''),
        true,true,now()
      ) returning id into v_candidate_id;
      v_result := 'registered';
    end if;
  end if;
  update public.candidate_phone_otp
    set consumed_at = now(), proof_hash = null, proof_expires_at = null
    where phone = p_phone;
  return v_result;
end;
$$;

revoke all on function public.candidate_otp_issue(text,text) from public, anon, authenticated;
revoke all on function public.candidate_otp_verify(text,text,text) from public, anon, authenticated;
revoke all on function public.candidate_otp_cancel(text,text) from public, anon, authenticated;
revoke all on function public.candidate_otp_register(text,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.candidate_otp_issue(text,text) to service_role;
grant execute on function public.candidate_otp_verify(text,text,text) to service_role;
grant execute on function public.candidate_otp_cancel(text,text) to service_role;
grant execute on function public.candidate_otp_register(text,text,jsonb,text) to service_role;
