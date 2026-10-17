-- Reuse the same approval gate as the public job list and authenticated Apply.
-- Existing API signature, grants, identity resolution and deduplication remain unchanged.
begin;
create or replace function public.register_candidate_requirement_interest(
  p_requirement_code text,
  p_candidate jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_code text := upper(btrim(coalesce(p_requirement_code, '')));
  normalized_mobile text := regexp_replace(coalesce(p_candidate ->> 'mobile', ''), '[^0-9]', '', 'g');
  normalized_name text := btrim(coalesce(p_candidate ->> 'full_name', ''));
  candidate_age integer;
  identity_match_count integer;
  identity_match_id uuid;
  requirement_record public.employer_requirements%rowtype;
  candidate_record public.candidates%rowtype;
begin
  if normalized_code = '' or length(normalized_code) > 40
     or normalized_code !~ '^AAD-[0-9]{4}-[0-9]{6}$' then
    raise exception 'Opportunity is not available for interest registration';
  end if;
  if p_candidate is null or jsonb_typeof(p_candidate) <> 'object' then
    raise exception 'Candidate details are invalid';
  end if;
  if p_candidate - array[
    'full_name', 'age', 'gender', 'mobile', 'whatsapp_number',
    'current_location', 'district', 'state', 'highest_qualification',
    'specialization', 'candidate_type', 'total_experience',
    'previous_job_role', 'interview_available', 'preferred_job_location',
    'additional_information', 'consent'
  ] <> '{}'::jsonb then
    raise exception 'Candidate details contain unsupported fields';
  end if;

  begin
    candidate_age := (p_candidate ->> 'age')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Candidate age is invalid';
  end;

  if length(normalized_name) not between 1 and 160
     or normalized_mobile !~ '^[6-9][0-9]{9}$'
     or candidate_age not between 16 and 75
     or coalesce((p_candidate ->> 'consent')::boolean, false) is not true then
    raise exception 'Candidate details are invalid';
  end if;

  select r.* into requirement_record
  from public.employer_requirements r
  where r.requirement_code = normalized_code
    and r.requirement_stage = 'open'
    and r.requirement_visibility = 'public'
    and r.required_headcount > r.filled_positions
    and private.vacancy_is_application_eligible(r.id)
  for share;

  if not found then
    raise exception 'Opportunity is not available for interest registration';
  end if;

  -- Serialize all job-linked submissions for this normalized mobile.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('r11-candidate:' || normalized_mobile, 0)
  );

  if exists (
    select 1
    from public.candidate_applications a
    join public.candidates c on c.id = a.candidate_id
    where a.requirement_id = requirement_record.id
      and c.mobile = normalized_mobile
  ) then
    return 'already_registered';
  end if;

  -- Reuse only an unambiguous exact identity match; do not merge on mobile alone.
  select count(*)::integer
  into identity_match_count
  from public.candidates c
  where c.mobile = normalized_mobile
    and lower(btrim(c.full_name)) = lower(normalized_name)
    and c.age = candidate_age;

  if identity_match_count = 1 then
    select c.id into identity_match_id
    from public.candidates c
    where c.mobile = normalized_mobile
      and lower(btrim(c.full_name)) = lower(normalized_name)
      and c.age = candidate_age;
    select c.* into candidate_record from public.candidates c where c.id = identity_match_id;
  elsif identity_match_count > 1 then
    raise exception 'Candidate identity requires manual review';
  else
    insert into public.candidates (
      full_name, age, gender, mobile, whatsapp_number, current_location,
      district, state, highest_qualification, specialization, candidate_type,
      total_experience, previous_job_role, interview_available,
      preferred_job_location, additional_information, consent
    ) values (
      normalized_name, candidate_age, p_candidate ->> 'gender', normalized_mobile,
      nullif(btrim(p_candidate ->> 'whatsapp_number'), ''),
      btrim(p_candidate ->> 'current_location'), btrim(p_candidate ->> 'district'),
      btrim(p_candidate ->> 'state'), p_candidate ->> 'highest_qualification',
      nullif(btrim(p_candidate ->> 'specialization'), ''),
      p_candidate ->> 'candidate_type',
      nullif(btrim(p_candidate ->> 'total_experience'), ''),
      nullif(btrim(p_candidate ->> 'previous_job_role'), ''),
      p_candidate ->> 'interview_available',
      nullif(btrim(p_candidate ->> 'preferred_job_location'), ''),
      nullif(btrim(p_candidate ->> 'additional_information'), ''), true
    ) returning * into candidate_record;
  end if;

  insert into public.candidate_applications (
    candidate_id, requirement_id, source_type, application_status
  ) values (
    candidate_record.id, requirement_record.id, 'direct', 'interested'
  );

  return 'registered';
exception
  when unique_violation then
    return 'already_registered';
  when check_violation or not_null_violation or string_data_right_truncation then
    raise exception 'Candidate details are invalid';
end;
$$;


commit;
