-- R12: Admin-only Candidate application status and internal-note management.

begin;

do $$
begin
  if to_regclass('public.candidate_applications') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.employer_requirements') is null then
    raise exception 'R12 prerequisite tables are missing';
  end if;
  if to_regprocedure('private.is_admin()') is null
     or to_regprocedure('public.get_public_job_requirements(integer,integer)') is null
     or to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') is null then
    raise exception 'R12 prerequisite Admin, R10, or R11 function is missing';
  end if;
  if to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') is not null
     or exists (
       select 1 from information_schema.columns
       where table_schema='public' and table_name='candidate_applications' and column_name='admin_notes'
     ) then
    raise exception 'R12 objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

alter table public.candidate_applications
  add column admin_notes text
  constraint candidate_applications_admin_notes_length_check
  check (admin_notes is null or length(admin_notes) <= 4000);

create index candidate_applications_applied_at_idx
  on public.candidate_applications (applied_at desc);

create function public.admin_update_candidate_application(
  p_application_id uuid,
  p_application_status text,
  p_admin_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_status text := lower(btrim(coalesce(p_application_status, '')));
  normalized_notes text := nullif(btrim(p_admin_notes), '');
begin
  if (select auth.uid()) is null or not (select private.is_admin()) then
    raise exception 'Approved administrator access is required';
  end if;
  if p_application_id is null then
    raise exception 'Candidate application identifier is required';
  end if;
  if normalized_status <> all(array[
    'interested','applied','screening','shortlisted','interview','selected',
    'rejected','joining_pending','joined','left','cancelled'
  ]) then
    raise exception 'Unsupported Candidate application status';
  end if;
  if normalized_notes is not null and length(normalized_notes) > 4000 then
    raise exception 'Internal Admin note must be 4000 characters or fewer';
  end if;

  update public.candidate_applications
  set application_status = normalized_status,
      admin_notes = normalized_notes
  where id = p_application_id;

  if not found then
    raise exception 'Candidate application was not found';
  end if;
  return true;
end;
$$;

revoke all on function public.admin_update_candidate_application(uuid,text,text) from public;
revoke all on function public.admin_update_candidate_application(uuid,text,text) from anon;
grant execute on function public.admin_update_candidate_application(uuid,text,text) to authenticated;

-- Existing RLS and M7 Admin policies remain authoritative. No tenant/public policy is added.

commit;
