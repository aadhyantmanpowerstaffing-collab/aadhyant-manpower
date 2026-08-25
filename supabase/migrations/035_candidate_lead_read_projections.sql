-- Phase C: bounded Candidate Lead read projections over canonical Candidate/Application data.
do $$
begin
  if to_regprocedure('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)') is null
     or to_regprocedure('public.admin_get_job_lead_detail(uuid)') is null
     or to_regprocedure('private.can_manage_recruitment_operations()') is null
     or to_regprocedure('public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer)') is not null
     or to_regprocedure('public.admin_get_candidate_lead_detail(uuid)') is not null then
    raise exception 'Migration 034 prerequisites or migration 035 partial state invalid';
  end if;
end $$;

create or replace function public.admin_list_candidate_leads(
  p_search text default null,
  p_source_type text default null,
  p_owner_staff_user_id uuid default null,
  p_unassigned boolean default false,
  p_profile_readiness text default null,
  p_operational_state text default null,
  p_application_stage text default null,
  p_attention_only boolean default false,
  p_from_date date default null,
  p_to_date date default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table(
  candidate_id uuid, full_name text, current_location text, district text, state text,
  highest_qualification text, specialization text, candidate_type text, total_experience text,
  availability_status text, profile_completion_status text, acquisition_source_type text,
  acquisition_source_detail text, acquisition_source_reference text, acquisition_attributed_at timestamptz,
  owner_staff_user_id uuid, owner_assigned_at timestamptz, next_action text, follow_up_due_at timestamptz,
  application_count bigint, active_application_count bigint, interview_count bigint, selected_count bigint,
  joining_pending_count bigint, joined_count bigint, operational_state text, attention boolean,
  created_at timestamptz, updated_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
declare
  term text := nullif(btrim(p_search),'');
  source_term text := nullif(lower(btrim(p_source_type)),'');
  readiness_term text := nullif(lower(btrim(p_profile_readiness)),'');
  state_term text := nullif(lower(btrim(p_operational_state)),'');
  stage_term text := nullif(lower(btrim(p_application_stage)),'');
  capped integer := least(greatest(coalesce(p_limit,50),1),100);
begin
  if not (select private.can_manage_recruitment_operations()) then raise exception 'Recruitment access is required'; end if;
  if coalesce(p_offset,0) < 0 then raise exception 'Offset must not be negative'; end if;
  if source_term is not null and source_term not in ('public_website','candidate_portal','employer_portal','contractor_portal','whatsapp_campaign','admin_manual','referral','campus','iti','csc_vle','field_sourcing','external_job_lead') then raise exception 'Unsupported candidate source'; end if;
  if readiness_term is not null and readiness_term not in ('complete','incomplete','review_required') then raise exception 'Unsupported profile readiness'; end if;
  return query
  with base as (
    select c.id,c.full_name,c.current_location,c.district,c.state,c.highest_qualification,c.specialization,
      c.candidate_type,c.total_experience,c.availability_status,c.profile_completion_status,c.status,
      c.acquisition_source_type,c.acquisition_source_detail,c.acquisition_source_reference,c.acquisition_attributed_at,
      c.owner_staff_user_id,c.owner_assigned_at,c.next_action,c.follow_up_due_at,c.created_at,c.updated_at,
      (select count(*) from public.candidate_applications a where a.candidate_id=c.id) applications,
      (select count(*) from public.candidate_applications a where a.candidate_id=c.id and a.application_status in ('interested','applied','screening','shortlisted','interview','selected','joining_pending')) active_apps,
      (select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.candidate_id=c.id) interviews,
      (select count(*) from public.candidate_applications a where a.candidate_id=c.id and a.application_status='selected') selected_apps,
      (select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.candidate_id=c.id and j.joining_status in ('pending','confirmed','deferred')) pending_joinings,
      (select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.candidate_id=c.id and j.joining_status='joined') joined_rows
    from public.candidates c
  ), derived as (
    select b.*, case
      when b.status = 'inactive' then 'inactive'
      when b.pending_joinings > 0 then 'joining_pending'
      when b.joined_rows > 0 then 'joined'
      when b.active_apps > 0 and b.interviews > 0 then 'interview'
      when b.active_apps > 0 then 'applied'
      when b.profile_completion_status <> 'complete' then 'profile_incomplete'
      when b.applications = 0 then 'awaiting_match'
      else 'profile_ready' end state_name,
      (b.status <> 'inactive' and (b.owner_staff_user_id is null or b.profile_completion_status <> 'complete' or (b.follow_up_due_at is not null and b.follow_up_due_at <= clock_timestamp()) or b.pending_joinings > 0 or (b.profile_completion_status='complete' and b.active_apps=0) or exists(select 1 from public.candidate_applications aa cross join private.phase_a_sla() sla where aa.candidate_id=b.id and aa.application_status in ('interested','applied','screening','shortlisted','interview','selected','joining_pending') and aa.updated_at < clock_timestamp() - (sla.application_age_days * interval '1 day')) or exists(select 1 from public.interviews ii join public.candidate_applications ia on ia.id=ii.application_id cross join private.phase_a_sla() sla where ia.candidate_id=b.id and ii.status='scheduled' and (ii.scheduled_at <= clock_timestamp() + (sla.upcoming_interview_hours * interval '1 hour') or ii.scheduled_at < clock_timestamp())))) needs_attention
    from base b
  )
  select d.id,d.full_name,d.current_location,d.district,d.state,d.highest_qualification,d.specialization,d.candidate_type,d.total_experience,
    d.availability_status,d.profile_completion_status,d.acquisition_source_type,d.acquisition_source_detail,d.acquisition_source_reference,d.acquisition_attributed_at,
    d.owner_staff_user_id,d.owner_assigned_at,d.next_action,d.follow_up_due_at,d.applications,d.active_apps,d.interviews,d.selected_apps,d.pending_joinings,d.joined_rows,d.state_name,d.needs_attention,d.created_at,d.updated_at
  from derived d
  where (term is null or d.full_name ilike '%'||term||'%' or d.current_location ilike '%'||term||'%' or d.district ilike '%'||term||'%' or d.specialization ilike '%'||term||'%')
    and (source_term is null or lower(d.acquisition_source_type)=source_term)
    and (p_owner_staff_user_id is null or d.owner_staff_user_id=p_owner_staff_user_id)
    and (not coalesce(p_unassigned,false) or d.owner_staff_user_id is null)
    and (readiness_term is null or lower(d.profile_completion_status)=readiness_term)
    and (state_term is null or d.state_name=state_term)
    and (stage_term is null or exists(select 1 from public.candidate_applications a where a.candidate_id=d.id and lower(a.application_status)=stage_term))
    and (not coalesce(p_attention_only,false) or d.needs_attention)
    and (p_from_date is null or d.created_at::date >= p_from_date)
    and (p_to_date is null or d.created_at::date <= p_to_date)
  order by d.created_at desc,d.id
  limit capped offset coalesce(p_offset,0);
end $$;

create or replace function public.admin_get_candidate_lead_detail(p_candidate_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare result jsonb;
begin
  if not (select private.can_manage_recruitment_operations()) then raise exception 'Recruitment access is required'; end if;
  select jsonb_build_object(
    'candidate',jsonb_build_object('candidate_id',c.id,'full_name',c.full_name,'current_location',c.current_location,'district',c.district,'state',c.state,'highest_qualification',c.highest_qualification,'specialization',c.specialization,'candidate_type',c.candidate_type,'total_experience',c.total_experience,'availability_status',c.availability_status,'profile_completion_status',c.profile_completion_status,'status',c.status,'created_at',c.created_at,'updated_at',c.updated_at),
    'operations',jsonb_build_object('acquisition_source_type',c.acquisition_source_type,'acquisition_source_detail',c.acquisition_source_detail,'acquisition_source_reference',c.acquisition_source_reference,'acquisition_attributed_at',c.acquisition_attributed_at,'owner_staff_user_id',c.owner_staff_user_id,'owner_assigned_at',c.owner_assigned_at,'next_action',c.next_action,'follow_up_due_at',c.follow_up_due_at),
    'applications',(select coalesce(jsonb_agg(jsonb_build_object('application_id',a.id,'requirement_id',a.requirement_id,'requirement_code',r.requirement_code,'application_source',a.source_type,'application_status',a.application_status,'applied_at',a.applied_at,'updated_at',a.updated_at) order by a.updated_at desc,a.id),'[]'::jsonb) from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=c.id),
    'interviews',(select coalesce(jsonb_agg(jsonb_build_object('interview_id',i.id,'application_id',i.application_id,'scheduled_at',i.scheduled_at,'mode',i.mode,'status',i.status,'result',i.result) order by i.scheduled_at desc nulls last,i.id),'[]'::jsonb) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.candidate_id=c.id),
    'joinings',(select coalesce(jsonb_agg(jsonb_build_object('joining_id',j.id,'application_id',j.application_id,'expected_joining_date',j.expected_joining_date,'actual_joining_date',j.actual_joining_date,'joining_status',j.joining_status) order by j.updated_at desc,j.id),'[]'::jsonb) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.candidate_id=c.id),
    'attention',(select coalesce(jsonb_agg(jsonb_build_object('reason',x.reason,'severity',x.severity,'due_at',x.due_at) order by x.severity desc,x.due_at) filter (where x.reason is not null),'[]'::jsonb) from (select 'Unassigned candidate' reason,'normal' severity,c.follow_up_due_at due_at where c.status<>'inactive' and c.owner_staff_user_id is null union all select 'Profile incomplete','normal',null where c.status<>'inactive' and c.profile_completion_status<>'complete' union all select 'Candidate follow-up due','high',c.follow_up_due_at where c.status<>'inactive' and c.follow_up_due_at is not null and c.follow_up_due_at<=clock_timestamp() union all select 'Awaiting match review','normal',null where c.status<>'inactive' and c.profile_completion_status='complete' and not exists(select 1 from public.candidate_applications ma where ma.candidate_id=c.id and ma.application_status in ('interested','applied','screening','shortlisted','interview','selected','joining_pending')) union all select 'Application aging','normal',max(aa.updated_at) from public.candidate_applications aa cross join private.phase_a_sla() sla where aa.candidate_id=c.id and aa.application_status in ('interested','applied','screening','shortlisted','interview','selected','joining_pending') and aa.updated_at < clock_timestamp() - (sla.application_age_days * interval '1 day') union all select 'Interview attention','high',min(ii.scheduled_at) from public.interviews ii join public.candidate_applications ia on ia.id=ii.application_id cross join private.phase_a_sla() sla where ia.candidate_id=c.id and ii.status='scheduled' and (ii.scheduled_at <= clock_timestamp() + (sla.upcoming_interview_hours * interval '1 hour') or ii.scheduled_at < clock_timestamp()) union all select 'Joining pending','high',null where c.status<>'inactive' and exists(select 1 from public.candidate_joinings jj join public.candidate_applications ja on ja.id=jj.application_id where ja.candidate_id=c.id and jj.joining_status in ('pending','confirmed','deferred'))) x),
    'history',(select coalesce(jsonb_agg(jsonb_build_object('event_at',e.created_at,'event_type',e.action,'entity_type',e.entity_type,'source',e.source) order by e.created_at desc,e.id desc),'[]'::jsonb) from (select al.id,al.created_at,al.action,al.entity_type,al.source from public.audit_logs al where al.entity_type in ('candidate','candidate_application') and (al.entity_id=c.id or al.metadata->>'candidate_id'=c.id::text) order by al.created_at desc,al.id desc limit 50) e)
  ) into result from public.candidates c where c.id=p_candidate_id;
  if result is null then raise exception 'Candidate was not found'; end if;
  return result;
end $$;

revoke all on function public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer) from public, anon, authenticated;
grant execute on function public.admin_list_candidate_leads(text,text,uuid,boolean,text,text,text,boolean,date,date,integer,integer) to authenticated;
revoke all on function public.admin_get_candidate_lead_detail(uuid) from public, anon, authenticated;
grant execute on function public.admin_get_candidate_lead_detail(uuid) to authenticated;
