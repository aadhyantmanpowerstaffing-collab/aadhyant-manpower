-- Auth-based candidate registration. The Supabase Auth Send SMS hook routes
-- Supabase-generated codes through approved Meta WhatsApp Authentication templates.
-- This RPC requires a valid, phone-confirmed Supabase Auth session.
create or replace function public.register_authenticated_candidate(
  p_candidate jsonb,
  p_requirement_code text default null
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_phone text;
  v_mobile text;
  v_name text;
  v_age int;
  v_record public.candidates%rowtype;
  v_matches int;
  v_result text;
begin
  if v_user_id is null then raise exception 'Sign in with OTP before registering'; end if;
  if p_candidate is null or jsonb_typeof(p_candidate) <> 'object' then
    raise exception 'Invalid candidate';
  end if;
  if p_candidate - array[
    'full_name','age','gender','mobile','whatsapp_number','current_location',
    'district','state','highest_qualification','specialization','candidate_type',
    'total_experience','previous_job_role','interview_available',
    'preferred_job_location','additional_information','consent'
  ] <> '{}'::jsonb then
    raise exception 'Unsupported candidate fields';
  end if;
  select regexp_replace(u.phone,'[^0-9]','','g')
    into v_phone
    from auth.users u
    where u.id = v_user_id and u.phone_confirmed_at is not null;
  v_mobile := regexp_replace(coalesce(p_candidate ->> 'mobile',''),'[^0-9]','','g');
  v_name := btrim(coalesce(p_candidate ->> 'full_name',''));
  begin
    v_age := (p_candidate ->> 'age')::int;
  exception when others then
    raise exception 'Invalid age';
  end;
  if v_phone is null or v_phone <> '91' || v_mobile
    or v_mobile !~ '^[6-9][0-9]{9}$'
    or length(v_name) not between 1 and 160
    or v_age not between 16 and 75
    or coalesce((p_candidate ->> 'consent')::boolean, false) <> true
    or coalesce(btrim(p_candidate ->> 'gender'),'') = ''
    or coalesce(btrim(p_candidate ->> 'current_location'),'') = ''
    or coalesce(btrim(p_candidate ->> 'district'),'') = ''
    or coalesce(btrim(p_candidate ->> 'state'),'') = ''
    or coalesce(btrim(p_candidate ->> 'highest_qualification'),'') = ''
    or coalesce(btrim(p_candidate ->> 'candidate_type'),'') = ''
    or coalesce(btrim(p_candidate ->> 'interview_available'),'') = '' then
    raise exception 'Invalid candidate details or unverified phone';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r11-candidate:' || v_mobile, 0)
  );
  select count(*) into v_matches
    from public.candidates c
    where c.mobile = v_mobile
      and lower(btrim(c.full_name)) = lower(v_name)
      and c.age = v_age;
  if v_matches > 1 then raise exception 'Candidate identity requires review'; end if;
  if v_matches = 1 then
    select * into v_record from public.candidates c
      where c.mobile = v_mobile
        and lower(btrim(c.full_name)) = lower(v_name)
        and c.age = v_age for update;
    if v_record.user_id is not null and v_record.user_id <> v_user_id then
      raise exception 'Candidate account requires manual review';
    end if;
  end if;

  if nullif(btrim(coalesce(p_requirement_code,'')), '') is not null then
    v_result := public.register_candidate_requirement_interest(p_requirement_code,p_candidate);
    if v_result not in ('registered','already_registered') then
      raise exception 'Candidate interest could not be registered';
    end if;
    select * into v_record from public.candidates c
      where c.mobile = v_mobile
        and lower(btrim(c.full_name)) = lower(v_name)
        and c.age = v_age for update;
    if not found or (v_record.user_id is not null and v_record.user_id <> v_user_id) then
      raise exception 'Candidate account requires manual review';
    end if;
  elsif v_matches = 1 then
    v_result := 'already_registered';
  else
    insert into public.candidates (
      full_name,age,gender,mobile,whatsapp_number,current_location,district,state,
      highest_qualification,specialization,candidate_type,total_experience,
      previous_job_role,interview_available,preferred_job_location,
      additional_information,consent,user_id,mobile_verified,verified_at
    ) values (
      v_name,v_age,p_candidate ->> 'gender',v_mobile,
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
      true,v_user_id,true,now()
    ) returning * into v_record;
    v_result := 'registered';
  end if;
  update public.candidates
    set user_id = v_user_id, mobile_verified = true,
        verified_at = coalesce(verified_at,now())
    where id = v_record.id and (user_id is null or user_id = v_user_id);
  if not found then raise exception 'Candidate account was not linked'; end if;
  return v_result;
end;
$$;

revoke all on function public.register_authenticated_candidate(jsonb,text)
  from public, anon;
grant execute on function public.register_authenticated_candidate(jsonb,text)
  to authenticated;
