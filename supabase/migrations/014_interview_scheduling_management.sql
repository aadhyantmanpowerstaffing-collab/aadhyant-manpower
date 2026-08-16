-- R13: Admin-only Candidate interview scheduling and management.

begin;

do $$
begin
  if to_regclass('public.interviews') is null
     or to_regclass('public.candidate_applications') is null then
    raise exception 'R13 prerequisite interview/application tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('private.set_updated_at()') is null
     or to_regprocedure('public.get_public_job_requirements(integer,integer)') is null
     or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null
     or to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') is null then
    raise exception 'R13 prerequisite helper or R10-R12 function is missing';
  end if;
  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.interviews'::regclass
      and tgname = 'interviews_set_updated_at' and tgenabled <> 'D'
  ) then
    raise exception 'R13 prerequisite interviews updated_at trigger is missing or disabled';
  end if;
  if to_regprocedure('public.admin_schedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') is not null
     or to_regprocedure('public.admin_reschedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') is not null
     or to_regprocedure('public.admin_update_candidate_interview(uuid,text,text,text)') is not null
     or exists (
       select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'interviews'
         and column_name in ('interview_round','supersedes_interview_id','meeting_link','contact_person','contact_phone','instructions','result_notes')
     ) then
    raise exception 'R13 objects already exist; inspect database state instead of re-running';
  end if;
  if exists (
    select 1 from public.interviews
    where status = 'scheduled'
    group by application_id
    having count(*) > 1
  ) then
    raise exception 'R13 requires at most one currently scheduled interview per application';
  end if;
end;
$$;

alter table public.interviews
  add column interview_round smallint,
  add column supersedes_interview_id uuid references public.interviews(id) on delete restrict,
  add column meeting_link text,
  add column contact_person text,
  add column contact_phone text,
  add column instructions text,
  add column result_notes text,
  add constraint interviews_meeting_link_length_check check (meeting_link is null or length(meeting_link) <= 1000),
  add constraint interviews_contact_person_length_check check (contact_person is null or length(contact_person) <= 200),
  add constraint interviews_contact_phone_length_check check (contact_phone is null or length(contact_phone) <= 30),
  add constraint interviews_instructions_length_check check (instructions is null or length(instructions) <= 4000),
  add constraint interviews_result_notes_length_check check (result_notes is null or length(result_notes) <= 4000),
  add constraint interviews_location_length_check check (location is null or length(location) <= 500),
  add constraint interviews_supersedes_not_self_check check (supersedes_interview_id is null or supersedes_interview_id <> id),
  add constraint interviews_supersedes_key unique (supersedes_interview_id);

alter table public.interviews disable trigger interviews_set_updated_at;
with ranked as (
  select id, row_number() over (partition by application_id order by scheduled_at nulls last, created_at, id)::smallint as round_number
  from public.interviews
)
update public.interviews as interview
set interview_round = ranked.round_number
from ranked
where ranked.id = interview.id;
alter table public.interviews enable trigger interviews_set_updated_at;

alter table public.interviews
  alter column interview_round set not null,
  add constraint interviews_round_positive_check check (interview_round > 0);

create unique index interviews_one_scheduled_per_application_idx
  on public.interviews (application_id)
  where status = 'scheduled';

create index interviews_status_scheduled_idx
  on public.interviews (status, scheduled_at desc);

revoke insert, update on public.interviews from authenticated;

create function public.admin_schedule_candidate_interview(
  p_application_id uuid,
  p_scheduled_at timestamptz,
  p_mode text,
  p_location text default null,
  p_meeting_link text default null,
  p_contact_person text default null,
  p_contact_phone text default null,
  p_instructions text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  application_status text;
  next_round smallint;
  interview_id uuid;
  normalized_mode text := lower(btrim(coalesce(p_mode, '')));
  normalized_location text := nullif(btrim(p_location), '');
  normalized_link text := nullif(btrim(p_meeting_link), '');
  normalized_person text := nullif(btrim(p_contact_person), '');
  normalized_phone text := nullif(btrim(p_contact_phone), '');
  normalized_instructions text := nullif(btrim(p_instructions), '');
begin
  if caller_id is null or not (select private.is_admin()) then
    raise exception 'Approved administrator access is required';
  end if;
  if p_application_id is null or p_scheduled_at is null or p_scheduled_at <= now() then
    raise exception 'A future interview date and valid application are required';
  end if;
  if normalized_mode <> all(array['onsite','phone','video','other']) then
    raise exception 'Unsupported interview mode';
  end if;
  if length(coalesce(normalized_location, '')) > 500
     or length(coalesce(normalized_link, '')) > 1000
     or length(coalesce(normalized_person, '')) > 200
     or length(coalesce(normalized_phone, '')) > 30
     or length(coalesce(normalized_instructions, '')) > 4000 then
    raise exception 'Interview details exceed allowed lengths';
  end if;

  select a.application_status into application_status
  from public.candidate_applications a
  where a.id = p_application_id
  for update;
  if not found then raise exception 'Candidate application was not found'; end if;
  if application_status not in ('interested','applied','screening','shortlisted','interview') then
    raise exception 'Candidate application is not eligible for interview scheduling';
  end if;
  if exists (select 1 from public.interviews where application_id = p_application_id and status = 'scheduled') then
    raise exception 'A current interview is already scheduled';
  end if;

  select (coalesce(max(interview_round), 0) + 1)::smallint into next_round
  from public.interviews where application_id = p_application_id;

  insert into public.interviews (
    application_id, interview_round, scheduled_at, location, mode, status,
    meeting_link, contact_person, contact_phone, instructions, created_by
  ) values (
    p_application_id, next_round, p_scheduled_at, normalized_location, normalized_mode, 'scheduled',
    normalized_link, normalized_person, normalized_phone, normalized_instructions, caller_id
  ) returning id into interview_id;

  if application_status in ('interested','applied','screening','shortlisted') then
    update public.candidate_applications set application_status = 'interview' where id = p_application_id;
  end if;
  return interview_id;
exception when unique_violation then
  raise exception 'A current interview is already scheduled';
end;
$$;

create function public.admin_reschedule_candidate_interview(
  p_interview_id uuid,
  p_scheduled_at timestamptz,
  p_mode text,
  p_location text default null,
  p_meeting_link text default null,
  p_contact_person text default null,
  p_contact_phone text default null,
  p_instructions text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  previous public.interviews%rowtype;
  application_status text;
  new_interview_id uuid;
  normalized_mode text := lower(btrim(coalesce(p_mode, '')));
begin
  if caller_id is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if p_interview_id is null or p_scheduled_at is null or p_scheduled_at <= now() then raise exception 'A future interview date and valid interview are required'; end if;
  if normalized_mode <> all(array['onsite','phone','video','other']) then raise exception 'Unsupported interview mode'; end if;
  if length(coalesce(nullif(btrim(p_location), ''), '')) > 500
     or length(coalesce(nullif(btrim(p_meeting_link), ''), '')) > 1000
     or length(coalesce(nullif(btrim(p_contact_person), ''), '')) > 200
     or length(coalesce(nullif(btrim(p_contact_phone), ''), '')) > 30
     or length(coalesce(nullif(btrim(p_instructions), ''), '')) > 4000 then
    raise exception 'Interview details exceed allowed lengths';
  end if;

  select * into previous from public.interviews where id = p_interview_id for update;
  if not found or previous.status <> 'scheduled' then raise exception 'Only a currently scheduled interview can be rescheduled'; end if;
  select a.application_status into application_status from public.candidate_applications a where a.id = previous.application_id for update;
  if application_status not in ('interested','applied','screening','shortlisted','interview') then raise exception 'Candidate application is not eligible for interview rescheduling'; end if;

  update public.interviews set status = 'rescheduled' where id = previous.id;
  insert into public.interviews (
    application_id, interview_round, supersedes_interview_id, scheduled_at, location, mode, status,
    meeting_link, contact_person, contact_phone, instructions, created_by
  ) values (
    previous.application_id, previous.interview_round, previous.id, p_scheduled_at,
    nullif(btrim(p_location), ''), normalized_mode, 'scheduled', nullif(btrim(p_meeting_link), ''),
    nullif(btrim(p_contact_person), ''), nullif(btrim(p_contact_phone), ''), nullif(btrim(p_instructions), ''), caller_id
  ) returning id into new_interview_id;
  return new_interview_id;
exception when unique_violation then
  raise exception 'Interview rescheduling conflicted with another update';
end;
$$;

create function public.admin_update_candidate_interview(
  p_interview_id uuid,
  p_status text,
  p_result text default null,
  p_result_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  current_status text;
  normalized_status text := lower(btrim(coalesce(p_status, '')));
  normalized_result text := nullif(lower(btrim(p_result)), '');
  normalized_notes text := nullif(btrim(p_result_notes), '');
begin
  if caller_id is null or not (select private.is_admin()) then raise exception 'Approved administrator access is required'; end if;
  if normalized_status <> all(array['attended','completed','absent','cancelled']) then raise exception 'Unsupported interview status'; end if;
  if normalized_result is not null and normalized_result <> all(array['pending','selected','rejected','on_hold']) then raise exception 'Unsupported interview result'; end if;
  if length(coalesce(normalized_notes, '')) > 4000 then raise exception 'Interview result notes must be 4000 characters or fewer'; end if;

  select status into current_status from public.interviews where id = p_interview_id for update;
  if not found then raise exception 'Interview was not found'; end if;
  if not ((current_status = 'scheduled' and normalized_status in ('attended','completed','absent','cancelled'))
       or (current_status = 'attended' and normalized_status = 'completed')) then
    raise exception 'Unsupported interview status transition';
  end if;
  update public.interviews
  set status = normalized_status, result = normalized_result, result_notes = normalized_notes
  where id = p_interview_id;
  return true;
end;
$$;

revoke all on function public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) from public, anon;
revoke all on function public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) from public, anon;
revoke all on function public.admin_update_candidate_interview(uuid,text,text,text) from public, anon;
grant execute on function public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_update_candidate_interview(uuid,text,text,text) to authenticated;

commit;
