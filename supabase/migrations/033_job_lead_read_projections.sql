-- Recruitment Operations Core Phase B: bounded Job Lead read projections.
do $$
begin
  if to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.interviews') is null
     or to_regclass('public.candidate_joinings') is null
     or to_regprocedure('private.can_manage_recruitment_operations()') is null
     or to_regprocedure('public.admin_list_recruitment_attention(integer,integer)') is null then
    raise exception 'Phase A prerequisites for Job Lead projections are missing';
  end if;
  if to_regprocedure('public.admin_list_job_leads(text,text,text,text,uuid,boolean,uuid,boolean,date,date,integer,integer)') is not null
     or to_regprocedure('public.admin_get_job_lead_detail(uuid)') is not null then
    raise exception 'Job Lead projection objects already exist; refusing partial install';
  end if;
end $$;

create function public.admin_list_job_leads(
  p_search text default null, p_stage text default null, p_source_type text default null,
  p_owner_staff_user_id uuid default null, p_unassigned boolean default false,
  p_company_id uuid default null, p_contractor_origin boolean default null,
  p_attention_only boolean default false, p_from_date date default null, p_to_date date default null,
  p_limit integer default 25, p_offset integer default 0
)
returns table(
  requirement_id uuid, requirement_code text, company_id uuid, company_name text,
  contractor_origin boolean, contractor_count bigint, source_type text, source_detail text,
  source_reference text, attributed_at timestamptz, owner_staff_user_id uuid,
  owner_assigned_at timestamptz, next_action text, follow_up_due_at timestamptz,
  qualified_at timestamptz, lost_reason text, operational_updated_at timestamptz,
  requirement_stage text, requirement_visibility text, created_at timestamptz, updated_at timestamptz,
  required_headcount integer, filled_positions integer, remaining_positions integer,
  fulfillment_percent numeric, application_count bigint, interview_count bigint,
  selected_count bigint, joined_count bigint, age_days integer, overdue boolean,
  operational_state text
)
language sql stable security definer set search_path = '' as $$
  with authz as (select private.can_manage_recruitment_operations() allowed), args as (
    select nullif(btrim(p_search),'') search_term,
      nullif(lower(btrim(p_stage)),'') stage_term,
      nullif(lower(btrim(p_source_type)),'') source_term,
      least(greatest(coalesce(p_limit,25),1),100) lim,
      greatest(coalesce(p_offset,0),0) off
  ), base as (
    select r.*, coalesce(c.trade_name,c.legal_name) as resolved_company_name,
      exists(select 1 from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' and rc.submission_status in ('submitted','under_review','approved')) as has_contractor_origin,
      (select count(*) from public.requirement_contractors rc where rc.requirement_id=r.id) as contractor_total,
      (select count(*) from public.candidate_applications a where a.requirement_id=r.id) as apps,
      (select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.requirement_id=r.id) as interviews,
      (select count(*) from public.candidate_applications a where a.requirement_id=r.id and a.application_status in ('selected','joining_pending','joined')) as selected,
      (select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.requirement_id=r.id and j.joining_status in ('joined','left')) as joined
    from public.employer_requirements r left join public.companies c on c.id=r.company_id
  )
  select b.id,b.requirement_code,b.company_id,coalesce(b.resolved_company_name,b.company_name),b.has_contractor_origin,b.contractor_total,
    b.source_type,b.source_detail,b.source_reference,b.attributed_at,b.owner_staff_user_id,b.owner_assigned_at,b.next_action,b.follow_up_due_at,
    b.qualified_at,b.lost_reason,b.operational_updated_at,b.requirement_stage,b.requirement_visibility,b.created_at,b.updated_at,
    b.required_headcount,b.filled_positions,greatest(coalesce(b.required_headcount,0)-coalesce(b.filled_positions,0),0),
    case when coalesce(b.required_headcount,0)>0 then least(100::numeric,round((coalesce(b.filled_positions,0)::numeric*100)/b.required_headcount,2)) else 0 end,
    b.apps,b.interviews,b.selected,b.joined,greatest(0,(extract(epoch from (clock_timestamp()-b.created_at))/86400)::integer),
    (b.follow_up_due_at is not null and b.follow_up_due_at<clock_timestamp()),
    case when b.requirement_stage='draft' then 'qualification' when b.requirement_stage='open' and b.joined>0 then 'fulfillment' when b.requirement_stage='open' then 'active_vacancy' when b.requirement_stage='filled' then 'fulfilled' when b.requirement_stage='cancelled' then 'cancelled_lost' else b.requirement_stage end
  from base b cross join args a cross join authz z
  where z.allowed
    and (a.search_term is null or b.requirement_code ilike '%'||a.search_term||'%' or b.company_name ilike '%'||a.search_term||'%' or b.job_role ilike '%'||a.search_term||'%' or coalesce(b.job_location,b.company_location) ilike '%'||a.search_term||'%')
    and (a.stage_term is null or lower(b.requirement_stage)=a.stage_term)
    and (a.source_term is null or lower(b.source_type)=a.source_term)
    and (p_owner_staff_user_id is null or b.owner_staff_user_id=p_owner_staff_user_id)
    and (not coalesce(p_unassigned,false) or b.owner_staff_user_id is null)
    and (p_company_id is null or b.company_id=p_company_id)
    and (p_contractor_origin is null or b.has_contractor_origin=p_contractor_origin)
    and (p_from_date is null or b.created_at::date>=p_from_date)
    and (p_to_date is null or b.created_at::date<=p_to_date)
    and (not coalesce(p_attention_only,false) or (b.follow_up_due_at is not null and b.follow_up_due_at<clock_timestamp()) or b.owner_staff_user_id is null or b.requirement_stage='draft')
  order by b.created_at desc,b.id limit (select lim from args) offset (select off from args);
$$;

create function public.admin_get_job_lead_detail(p_requirement_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not (select private.can_manage_recruitment_operations()) then raise exception 'Recruitment access is required'; end if;
  select jsonb_build_object('requirement',to_jsonb(x), 'history', coalesce((select jsonb_agg(jsonb_build_object('action',h.action,'actor_type',h.actor_type,'created_at',h.created_at,'summary',h.summary) order by h.created_at desc,h.audit_id desc) from (select l.id audit_id,l.action,l.actor_type,l.created_at,case when l.action like 'recruitment.source_%' then 'Source attribution corrected' when l.action='recruitment.owner_changed' then 'Owner changed' when l.action like 'recruitment.%follow%' then 'Follow-up updated' else 'Operational activity' end summary from public.audit_logs l where l.entity_id=p_requirement_id and l.entity_type='employer_requirement' and l.action like 'recruitment.%' order by l.created_at desc,l.id desc limit 50) h),'[]'::jsonb)) into result
  from public.admin_list_job_leads(null,null,null,null,false,null,null,false,null,null,1,0) x where x.requirement_id=p_requirement_id;
  if result is null then raise exception 'Job Lead was not found'; end if;
  return result;
end; $$;

revoke all on function public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer) from public, anon, authenticated;
revoke all on function public.admin_get_job_lead_detail(uuid) from public, anon, authenticated;
grant execute on function public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer) to authenticated;
grant execute on function public.admin_get_job_lead_detail(uuid) to authenticated;
