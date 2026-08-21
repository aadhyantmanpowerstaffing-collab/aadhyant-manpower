-- W4 corrective migration: remove PL/pgSQL stage-name ambiguity from the
-- company-safe application listing without changing its tenant or privacy contract.

create or replace function public.list_company_portal_applications(
  p_requirement_id uuid default null,
  p_stage text default null,
  p_limit integer default 25,
  p_offset integer default 0
)
returns table(
  application_id uuid,
  requirement_code text,
  job_role text,
  candidate_name text,
  qualification text,
  specialization text,
  experience_summary text,
  current_location text,
  district text,
  state text,
  application_stage text,
  interview_status text,
  joining_status text,
  applied_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_company_id uuid;
  v_stage text := nullif(lower(btrim(p_stage)), '');
begin
  v_company_id := (select private.current_company_portal_id(true));
  if v_company_id is null then
    raise exception 'Active Company access is required';
  end if;

  if p_requirement_id is not null and not exists (
    select 1
    from public.employer_requirements r
    where r.id = p_requirement_id
      and r.company_id = v_company_id
  ) then
    raise exception 'Company requirement was not found';
  end if;

  if v_stage is not null and not exists (
    select 1
    from public.application_stages s
    where s.stage = v_stage
  ) then
    raise exception 'Unsupported application stage';
  end if;

  return query
  select
    a.id,
    r.requirement_code,
    r.job_role,
    c.full_name,
    c.highest_qualification,
    c.specialization,
    coalesce(c.total_experience, c.previous_job_role),
    c.current_location,
    c.district,
    c.state,
    a.application_status,
    (
      select i.status
      from public.interviews i
      where i.application_id = a.id
      order by i.created_at desc, i.id desc
      limit 1
    ),
    (
      select j.joining_status
      from public.candidate_joinings j
      where j.application_id = a.id
    ),
    a.applied_at,
    a.updated_at
  from public.candidate_applications a
  join public.employer_requirements r on r.id = a.requirement_id
  join public.candidates c on c.id = a.candidate_id
  where r.company_id = v_company_id
    and (p_requirement_id is null or r.id = p_requirement_id)
    and (v_stage is null or a.application_status = v_stage)
  order by a.updated_at desc, a.id
  limit least(greatest(coalesce(p_limit, 25), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.list_company_portal_applications(uuid, text, integer, integer) from public;
revoke all on function public.list_company_portal_applications(uuid, text, integer, integer) from anon;
grant execute on function public.list_company_portal_applications(uuid, text, integer, integer) to authenticated;
