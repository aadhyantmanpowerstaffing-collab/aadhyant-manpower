-- W7B: Admin vacancy campaigns, deterministic Candidate matching, frozen audiences, and W7A outbox reuse.

begin;

do $$
begin
  if to_regclass('public.candidates') is null or to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null or to_regclass('public.whatsapp_contacts') is null
     or to_regclass('public.whatsapp_outbound_messages') is null or to_regclass('public.whatsapp_message_events') is null
     or to_regclass('public.audit_logs') is null then
    raise exception 'W7B canonical prerequisites are missing';
  end if;
  if to_regprocedure('public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)') is null
     or to_regprocedure('private.whatsapp_contact_allows_purpose(uuid,text)') is null
     or to_regprocedure('private.has_staff_role(text)') is null then
    raise exception 'W7B W7A or staff authorization contracts are missing';
  end if;
  if to_regclass('public.whatsapp_campaigns') is not null or to_regclass('public.whatsapp_campaign_recipients') is not null then
    raise exception 'W7B objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

create table public.whatsapp_campaigns (
  id uuid primary key default extensions.gen_random_uuid(),
  operation_key uuid not null unique,
  requirement_id uuid not null references public.employer_requirements(id) on delete restrict,
  campaign_name text not null check (length(btrim(campaign_name)) between 1 and 160),
  campaign_status text not null default 'draft'
    check (campaign_status in ('draft','audience_ready','approved','queued','sending','completed','cancelled','failed')),
  purpose text not null check (purpose='vacancy_campaign'),
  consent_class text not null check (consent_class='marketing'),
  template_name text not null check (template_name=lower(template_name) and length(template_name) between 1 and 160),
  template_language text not null check (template_language ~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'),
  template_version text not null check (length(template_version) between 1 and 80),
  criteria jsonb not null default '{}'::jsonb check (jsonb_typeof(criteria)='object' and pg_catalog.octet_length(criteria::text)<=4096),
  created_by uuid not null references auth.users(id) on delete restrict,
  approved_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  audience_frozen_at timestamptz,
  approved_at timestamptz,
  queued_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  constraint whatsapp_campaign_approval_check check ((approved_by is null)=(approved_at is null)),
  constraint whatsapp_campaign_state_dates_check check (
    (campaign_status in ('draft','audience_ready','cancelled') or approved_at is not null)
    and (campaign_status not in ('queued','sending','completed','failed') or queued_at is not null)
    and (campaign_status<>'completed' or completed_at is not null)
    and (campaign_status<>'cancelled' or cancelled_at is not null))
);

create table public.whatsapp_campaign_recipients (
  id uuid primary key default extensions.gen_random_uuid(),
  campaign_id uuid not null references public.whatsapp_campaigns(id) on delete restrict,
  candidate_id uuid not null references public.candidates(id) on delete restrict,
  whatsapp_contact_id uuid references public.whatsapp_contacts(id) on delete restrict,
  inclusion_source text not null check (inclusion_source in ('matched','manual_include','manual_exclude')),
  recipient_status text not null check (recipient_status in ('included','excluded','queued')),
  match_reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(match_reasons)='array' and pg_catalog.octet_length(match_reasons::text)<=4096),
  exclusion_reason text check (exclusion_reason is null or (exclusion_reason in ('manual_exclude','no_contact','suppressed','opted_out','blocked','inactive_candidate','existing_application','duplicate_contact'))),
  outbound_message_id uuid references public.whatsapp_outbound_messages(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(campaign_id,candidate_id),
  unique(campaign_id,whatsapp_contact_id),
  constraint whatsapp_campaign_recipient_state_check check (
    (recipient_status='excluded' and exclusion_reason is not null and outbound_message_id is null)
    or (recipient_status='included' and exclusion_reason is null and whatsapp_contact_id is not null and outbound_message_id is null)
    or (recipient_status='queued' and exclusion_reason is null and whatsapp_contact_id is not null and outbound_message_id is not null))
);

create index whatsapp_campaigns_requirement_idx on public.whatsapp_campaigns(requirement_id,created_at desc);
create index whatsapp_campaigns_status_idx on public.whatsapp_campaigns(campaign_status,created_at desc);
create index whatsapp_campaign_recipients_campaign_idx on public.whatsapp_campaign_recipients(campaign_id,recipient_status);
create unique index whatsapp_campaign_recipients_outbound_idx on public.whatsapp_campaign_recipients(outbound_message_id) where outbound_message_id is not null;

create trigger set_whatsapp_campaigns_updated_at before update on public.whatsapp_campaigns
for each row execute function private.set_updated_at();
create trigger set_whatsapp_campaign_recipients_updated_at before update on public.whatsapp_campaign_recipients
for each row execute function private.set_updated_at();

create function private.can_manage_whatsapp_campaigns()
returns boolean language sql stable security definer set search_path='' as $$
  select ((select private.is_admin()) and (select auth.uid()) is not null
      and not exists(select 1 from public.platform_users where user_id=(select auth.uid())))
    or (select private.has_staff_role('super_admin')) or (select private.has_staff_role('admin'));
$$;

create function private.whatsapp_campaign_criteria_safe(p_criteria jsonb)
returns boolean language sql immutable set search_path='' as $$
  select jsonb_typeof(coalesce(p_criteria,'{}'::jsonb))='object'
    and not exists(select 1 from jsonb_object_keys(coalesce(p_criteria,'{}'::jsonb)) k
      where k not in ('state','district','location','qualification','specialization','candidate_type','interview_available','avoid_existing_application'))
    and not exists(select 1 from jsonb_each(coalesce(p_criteria,'{}'::jsonb)) e
      where (e.key='avoid_existing_application' and (jsonb_typeof(e.value)<>'boolean' or e.value<>'true'::jsonb))
         or (e.key<>'avoid_existing_application' and (jsonb_typeof(e.value)<>'string' or length(e.value #>> '{}')>160)))
    and pg_catalog.octet_length(coalesce(p_criteria,'{}'::jsonb)::text)<=4096;
$$;

create function private.whatsapp_campaign_match_reasons(p_candidate public.candidates,p_requirement public.employer_requirements,p_criteria jsonb)
returns jsonb language sql stable set search_path='' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'qualification',case when nullif(btrim(p_requirement.qualification),'') is null or lower(p_candidate.highest_qualification)=lower(p_requirement.qualification) then 'match' end,
    'specialization',case when nullif(btrim(p_requirement.iti_trade),'') is null or lower(coalesce(p_candidate.specialization,''))=lower(p_requirement.iti_trade) then 'match' end,
    'experience',case when p_requirement.experience_requirement is null or p_requirement.experience_requirement='Both' or p_candidate.candidate_type=p_requirement.experience_requirement then 'match' end,
    'location',case when nullif(btrim(coalesce(p_criteria->>'location',p_requirement.job_location,p_requirement.company_location)),'') is null
      or lower(p_candidate.current_location)=lower(coalesce(p_criteria->>'location',p_requirement.job_location,p_requirement.company_location))
      or lower(p_candidate.district)=lower(coalesce(p_criteria->>'location',p_requirement.job_location,p_requirement.company_location)) then 'match' end,
    'interview_available',case when p_candidate.interview_available='Yes' then 'match' end));
$$;

create function public.admin_preview_whatsapp_campaign_audience(
  p_requirement_id uuid,p_criteria jsonb default '{}'::jsonb,p_limit integer default 50,p_offset integer default 0)
returns table(candidate_id uuid,candidate_name text,highest_qualification text,specialization text,candidate_type text,
  experience_summary text,current_location text,district text,state text,match_reasons jsonb,contact_masked text,
  existing_application boolean,eligible boolean,eligibility_reason text)
language plpgsql stable security definer set search_path='' as $$
declare req public.employer_requirements%rowtype; criteria jsonb:=coalesce(p_criteria,'{}'::jsonb); capped integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  if not (select private.whatsapp_campaign_criteria_safe(criteria)) then raise exception 'Campaign criteria are unsupported'; end if;
  if coalesce(p_offset,0)<0 then raise exception 'Offset must not be negative'; end if;
  select * into req from public.employer_requirements where id=p_requirement_id and requirement_stage='open';
  if not found then raise exception 'Open requirement was not found'; end if;
  if nullif(btrim(req.qualification),'') is null and nullif(btrim(req.iti_trade),'') is null
     and coalesce(req.experience_requirement,'Both')='Both'
     and nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null then
    raise exception 'Open requirement lacks canonical matching criteria';
  end if;
  return query
  select c.id,left(c.full_name,1)||repeat('•',greatest(1,least(length(c.full_name)-1,12))),c.highest_qualification,c.specialization,c.candidate_type,
    c.total_experience,c.current_location,c.district,c.state,
    (select coalesce(jsonb_agg(key order by key),'[]'::jsonb) from jsonb_each_text(private.whatsapp_campaign_match_reasons(c,req,criteria))),
    case when wc.id is null then 'Unavailable' else '+91XXXXXX'||right(wc.indian_mobile_key,4) end,
    (a.id is not null),
    (wc.id is not null and wc.resolution_status='resolved' and wc.candidate_id=c.id and wc.marketing_consent_status='opted_in'
      and private.whatsapp_contact_allows_purpose(wc.id,'marketing') and c.profile_status='active' and c.status<>'inactive' and a.id is null),
    case when c.profile_status<>'active' or c.status='inactive' then 'inactive_candidate'
      when wc.id is null then 'no_contact' when wc.resolution_status='blocked' then 'blocked'
      when wc.resolution_status='ambiguous' then 'duplicate_contact' when wc.resolution_status<>'resolved' then 'no_contact'
      when wc.marketing_consent_status='opted_out' then 'opted_out'
      when wc.marketing_consent_status<>'opted_in' then 'suppressed'
      when a.id is not null and coalesce((criteria->>'avoid_existing_application')::boolean,true) then 'existing_application' else null end
  from public.candidates c
  left join public.whatsapp_contacts wc on wc.candidate_id=c.id and wc.provider='whatsapp'
  left join public.candidate_applications a on a.candidate_id=c.id and a.requirement_id=req.id
  where c.profile_status='active' and c.status<>'inactive'
    and (nullif(btrim(req.qualification),'') is null or lower(c.highest_qualification)=lower(req.qualification))
    and (nullif(btrim(req.iti_trade),'') is null or lower(coalesce(c.specialization,''))=lower(req.iti_trade))
    and (req.experience_requirement is null or req.experience_requirement='Both' or c.candidate_type=req.experience_requirement)
    and (nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null
      or lower(c.current_location)=lower(coalesce(req.job_location,req.company_location))
      or lower(c.district)=lower(coalesce(req.job_location,req.company_location))
      or lower(c.state)=lower(coalesce(req.job_location,req.company_location)))
    and (nullif(criteria->>'state','') is null or lower(c.state)=lower(criteria->>'state'))
    and (nullif(criteria->>'district','') is null or lower(c.district)=lower(criteria->>'district'))
    and (nullif(criteria->>'location','') is null or lower(c.current_location)=lower(criteria->>'location'))
    and (nullif(criteria->>'qualification','') is null or c.highest_qualification=criteria->>'qualification')
    and (nullif(criteria->>'specialization','') is null or lower(coalesce(c.specialization,''))=lower(criteria->>'specialization'))
    and (nullif(criteria->>'candidate_type','') is null or c.candidate_type=criteria->>'candidate_type')
    and (nullif(criteria->>'interview_available','') is null or c.interview_available=criteria->>'interview_available')
  order by c.created_at desc,c.id limit capped offset least(coalesce(p_offset,0),5000);
end;
$$;

create function public.admin_create_whatsapp_campaign(p_requirement_id uuid,p_operation_key uuid,p_campaign_name text,p_template_name text,
  p_template_language text,p_template_version text,p_criteria jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; existing public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; criteria jsonb:=coalesce(p_criteria,'{}'::jsonb); actor uuid:=(select auth.uid());
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  select * into req from public.employer_requirements where id=p_requirement_id and requirement_stage='open';
  if not found then raise exception 'Open requirement was not found'; end if;
  if nullif(btrim(req.qualification),'') is null and nullif(btrim(req.iti_trade),'') is null
     and coalesce(req.experience_requirement,'Both')='Both'
     and nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null then raise exception 'Open requirement lacks canonical matching criteria'; end if;
  if length(btrim(coalesce(p_campaign_name,''))) not between 1 and 160 then raise exception 'Campaign name is invalid'; end if;
  if btrim(coalesce(p_template_name,'')) !~ '^[a-z0-9_]{1,160}$'
     or btrim(coalesce(p_template_language,'')) !~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'
     or length(btrim(coalesce(p_template_version,''))) not between 1 and 80 then raise exception 'Template metadata is invalid'; end if;
  if not (select private.whatsapp_campaign_criteria_safe(criteria)) then raise exception 'Campaign criteria are unsupported'; end if;
  if p_operation_key is null then raise exception 'Campaign operation key is required'; end if;
  select * into existing from public.whatsapp_campaigns where operation_key=p_operation_key;
  if found then
    if existing.created_by is distinct from actor or existing.requirement_id is distinct from p_requirement_id
       or existing.campaign_name is distinct from btrim(p_campaign_name) or existing.template_name is distinct from btrim(p_template_name)
       or existing.template_language is distinct from btrim(p_template_language) or existing.template_version is distinct from btrim(p_template_version)
       or existing.criteria is distinct from criteria then raise exception 'Campaign operation key conflicts with existing campaign'; end if;
    return existing.id;
  end if;
  insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,purpose,consent_class,template_name,template_language,template_version,criteria,created_by)
  values(p_operation_key,p_requirement_id,btrim(p_campaign_name),'vacancy_campaign','marketing',btrim(p_template_name),btrim(p_template_language),btrim(p_template_version),criteria,actor)
  on conflict(operation_key) do nothing returning id into result;
  if result is null then
    select * into existing from public.whatsapp_campaigns where operation_key=p_operation_key;
    if not found or existing.created_by is distinct from actor or existing.requirement_id is distinct from p_requirement_id
       or existing.campaign_name is distinct from btrim(p_campaign_name) or existing.template_name is distinct from btrim(p_template_name)
       or existing.template_language is distinct from btrim(p_template_language) or existing.template_version is distinct from btrim(p_template_version)
       or existing.criteria is distinct from criteria then raise exception 'Campaign operation key conflicts with existing campaign'; end if;
    return existing.id;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.campaign_created','whatsapp_campaign',result,'admin',jsonb_build_object('requirement_id',p_requirement_id));
  return result;
end;
$$;

create function public.admin_freeze_whatsapp_campaign_audience(p_campaign_id uuid,p_included_candidate_ids uuid[],
  p_excluded_candidate_ids uuid[] default '{}'::uuid[],p_expected_included_count integer default null)
returns integer language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; cid uuid; contact public.whatsapp_contacts%rowtype; included_count integer:=0; actor uuid:=(select auth.uid());
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  select * into campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if not found or campaign.campaign_status not in ('draft','audience_ready') then raise exception 'Campaign audience can no longer change'; end if;
  select * into req from public.employer_requirements where id=campaign.requirement_id and requirement_stage='open' for share;
  if not found then raise exception 'Open requirement was not found'; end if;
  if nullif(btrim(req.qualification),'') is null and nullif(btrim(req.iti_trade),'') is null
     and coalesce(req.experience_requirement,'Both')='Both'
     and nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null then raise exception 'Open requirement lacks canonical matching criteria'; end if;
  if cardinality(coalesce(p_included_candidate_ids,'{}'::uuid[]))>500 or cardinality(coalesce(p_excluded_candidate_ids,'{}'::uuid[]))>500 then raise exception 'Campaign audience is too large'; end if;
  if exists(select 1 from unnest(coalesce(p_included_candidate_ids,'{}'::uuid[])) i(candidate_id)
    join unnest(coalesce(p_excluded_candidate_ids,'{}'::uuid[])) e(candidate_id) using(candidate_id)) then raise exception 'Candidate cannot be included and excluded'; end if;
  delete from public.whatsapp_campaign_recipients where campaign_id=campaign.id;
  for cid in select distinct input.candidate_id from unnest(coalesce(p_included_candidate_ids,'{}'::uuid[])) as input(candidate_id) loop
    if not exists(select 1 from public.candidates c where c.id=cid and c.profile_status='active' and c.status<>'inactive'
        and (nullif(btrim(req.qualification),'') is null or lower(c.highest_qualification)=lower(req.qualification))
        and (nullif(btrim(req.iti_trade),'') is null or lower(coalesce(c.specialization,''))=lower(req.iti_trade))
        and (req.experience_requirement is null or req.experience_requirement='Both' or c.candidate_type=req.experience_requirement)
        and (nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null
          or lower(c.current_location)=lower(coalesce(req.job_location,req.company_location))
          or lower(c.district)=lower(coalesce(req.job_location,req.company_location))
          or lower(c.state)=lower(coalesce(req.job_location,req.company_location)))
        and (nullif(campaign.criteria->>'state','') is null or lower(c.state)=lower(campaign.criteria->>'state'))
        and (nullif(campaign.criteria->>'district','') is null or lower(c.district)=lower(campaign.criteria->>'district'))
        and (nullif(campaign.criteria->>'location','') is null or lower(c.current_location)=lower(campaign.criteria->>'location'))
        and (nullif(campaign.criteria->>'qualification','') is null or c.highest_qualification=campaign.criteria->>'qualification')
        and (nullif(campaign.criteria->>'specialization','') is null or lower(coalesce(c.specialization,''))=lower(campaign.criteria->>'specialization'))
        and (nullif(campaign.criteria->>'candidate_type','') is null or c.candidate_type=campaign.criteria->>'candidate_type')
        and (nullif(campaign.criteria->>'interview_available','') is null or c.interview_available=campaign.criteria->>'interview_available')) then
      raise exception 'Included Candidate is not eligible for this requirement';
    end if;
    select * into contact from public.whatsapp_contacts where candidate_id=cid and provider='whatsapp' for share;
    if not found or contact.resolution_status<>'resolved' or contact.candidate_id is distinct from cid or contact.marketing_consent_status<>'opted_in'
       or not (select private.whatsapp_contact_allows_purpose(contact.id,'marketing')) then raise exception 'Included Candidate is not eligible for marketing contact'; end if;
    if exists(select 1 from public.candidate_applications where candidate_id=cid and requirement_id=campaign.requirement_id) then raise exception 'Included Candidate already has an application'; end if;
    insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
    values(campaign.id,cid,contact.id,'manual_include','included','["server_validated"]'::jsonb);
    included_count:=included_count+1;
  end loop;
  for cid in select distinct input.candidate_id from unnest(coalesce(p_excluded_candidate_ids,'{}'::uuid[])) as input(candidate_id) loop
    if not exists(select 1 from public.candidates where id=cid) then raise exception 'Excluded Candidate was not found'; end if;
    insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,inclusion_source,recipient_status,exclusion_reason)
    values(campaign.id,cid,'manual_exclude','excluded','manual_exclude');
  end loop;
  if included_count=0 or (p_expected_included_count is not null and included_count<>p_expected_included_count) then raise exception 'Final audience count does not match'; end if;
  update public.whatsapp_campaigns set campaign_status='audience_ready',audience_frozen_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.audience_frozen','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('included_count',included_count,'excluded_count',cardinality(coalesce(p_excluded_candidate_ids,'{}'::uuid[]))));
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.recipients_included','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',included_count));
  if cardinality(coalesce(p_excluded_candidate_ids,'{}'::uuid[]))>0 then
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'staff','whatsapp.recipients_excluded','whatsapp_campaign',campaign.id,'admin',
      jsonb_build_object('count',cardinality(coalesce(p_excluded_candidate_ids,'{}'::uuid[]))));
  end if;
  return included_count;
end;
$$;

create function public.admin_approve_whatsapp_campaign(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; actor uuid:=(select auth.uid()); count_ready integer; count_included integer;
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  select * into campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if not found or campaign.campaign_status<>'audience_ready' then raise exception 'Audience-ready campaign is required'; end if;
  select * into req from public.employer_requirements where id=campaign.requirement_id and requirement_stage='open' for share;
  if not found then raise exception 'Open requirement was not found'; end if;
  if nullif(btrim(req.qualification),'') is null and nullif(btrim(req.iti_trade),'') is null
     and coalesce(req.experience_requirement,'Both')='Both'
     and nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null then raise exception 'Open requirement lacks canonical matching criteria'; end if;
  if campaign.template_name !~ '^[a-z0-9_]{1,160}$' or campaign.template_language !~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'
     or length(campaign.template_version) not between 1 and 80 then raise exception 'Template metadata is invalid'; end if;
  select count(*) into count_included from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included';
  select count(*) into count_ready
  from public.whatsapp_campaign_recipients cr
  join public.candidates c on c.id=cr.candidate_id
  join public.whatsapp_contacts wc on wc.id=cr.whatsapp_contact_id and wc.candidate_id=cr.candidate_id and wc.provider='whatsapp'
  left join public.candidate_applications a on a.candidate_id=c.id and a.requirement_id=campaign.requirement_id
  where cr.campaign_id=campaign.id and cr.recipient_status='included' and c.profile_status='active' and c.status<>'inactive'
    and wc.resolution_status='resolved' and wc.marketing_consent_status='opted_in'
    and private.whatsapp_contact_allows_purpose(wc.id,'marketing') and a.id is null
    and (nullif(btrim(req.qualification),'') is null or lower(c.highest_qualification)=lower(req.qualification))
    and (nullif(btrim(req.iti_trade),'') is null or lower(coalesce(c.specialization,''))=lower(req.iti_trade))
    and (req.experience_requirement is null or req.experience_requirement='Both' or c.candidate_type=req.experience_requirement)
    and (nullif(btrim(coalesce(req.job_location,req.company_location)),'') is null
      or lower(c.current_location)=lower(coalesce(req.job_location,req.company_location))
      or lower(c.district)=lower(coalesce(req.job_location,req.company_location))
      or lower(c.state)=lower(coalesce(req.job_location,req.company_location)))
    and (nullif(campaign.criteria->>'state','') is null or lower(c.state)=lower(campaign.criteria->>'state'))
    and (nullif(campaign.criteria->>'district','') is null or lower(c.district)=lower(campaign.criteria->>'district'))
    and (nullif(campaign.criteria->>'location','') is null or lower(c.current_location)=lower(campaign.criteria->>'location'))
    and (nullif(campaign.criteria->>'qualification','') is null or c.highest_qualification=campaign.criteria->>'qualification')
    and (nullif(campaign.criteria->>'specialization','') is null or lower(coalesce(c.specialization,''))=lower(campaign.criteria->>'specialization'))
    and (nullif(campaign.criteria->>'candidate_type','') is null or c.candidate_type=campaign.criteria->>'candidate_type')
    and (nullif(campaign.criteria->>'interview_available','') is null or c.interview_available=campaign.criteria->>'interview_available');
  if count_ready=0 or count_ready<>count_included then raise exception 'Campaign audience is empty, mismatched, unresolved, or suppressed'; end if;
  update public.whatsapp_campaigns set campaign_status='approved',approved_by=actor,approved_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.campaign_approved','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('recipient_count',count_ready));
  return true;
end;
$$;

create function public.admin_queue_whatsapp_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; recipient public.whatsapp_campaign_recipients%rowtype; req public.employer_requirements%rowtype; outbound_id uuid; queued_count integer:=0; expected_count integer; actor uuid:=(select auth.uid());
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  select * into campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if not found then raise exception 'Campaign was not found'; end if;
  if campaign.campaign_status in ('queued','sending','completed','failed') then
    select count(*) into queued_count from public.whatsapp_campaign_recipients cr
    join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id and o.contact_id=cr.whatsapp_contact_id
      and o.candidate_id=cr.candidate_id and o.requirement_id=campaign.requirement_id and o.correlation_id=cr.id
    where cr.campaign_id=campaign.id and cr.recipient_status='queued';
    if queued_count=0 or queued_count<>(select count(*) from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='queued')
       or exists(select 1 from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included') then
      raise exception 'Queued campaign linkage is inconsistent';
    end if;
    return queued_count;
  end if;
  if campaign.campaign_status<>'approved' then raise exception 'Approved campaign is required before queueing'; end if;
  select * into req from public.employer_requirements where id=campaign.requirement_id and requirement_stage='open' for share;
  if not found then raise exception 'Open requirement was not found'; end if;
  select count(*) into expected_count from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included';
  if expected_count=0 then raise exception 'Campaign has no included recipients'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.campaign_queue_started','whatsapp_campaign',campaign.id,'admin',
    jsonb_build_object('requirement_id',campaign.requirement_id,'expected_count',expected_count));
  for recipient in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not exists(select 1 from public.whatsapp_contacts wc where wc.id=recipient.whatsapp_contact_id
        and wc.candidate_id=recipient.candidate_id and wc.provider='whatsapp' and wc.resolution_status='resolved'
        and wc.marketing_consent_status='opted_in' and private.whatsapp_contact_allows_purpose(wc.id,'marketing')) then
      raise exception 'Campaign recipient became suppressed or unresolved';
    end if;
    outbound_id:=public.enqueue_whatsapp_outbound_message(recipient.whatsapp_contact_id,recipient.candidate_id,campaign.requirement_id,
      campaign.purpose,campaign.consent_class,campaign.template_name,campaign.template_language,campaign.template_version,
      jsonb_build_object('requirement_code',req.requirement_code,'job_role',req.job_role,'campaign_id',campaign.id::text,
        'recipient_id',recipient.id::text,'action_id','INTERESTED'),
      'campaign:'||campaign.id::text||':recipient:'||recipient.id::text,recipient.id,3);
    update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound_id where id=recipient.id;
    queued_count:=queued_count+1;
  end loop;
  if queued_count<>expected_count then raise exception 'Campaign queue count is inconsistent'; end if;
  update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.campaign_queue_completed','whatsapp_campaign',campaign.id,'admin',
    jsonb_build_object('requirement_id',campaign.requirement_id,'final_count',queued_count));
  return queued_count;
end;
$$;

create function public.admin_reconcile_whatsapp_campaign(p_campaign_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; total_count integer; queued_count integer; sending_count integer;
  sent_count integer; delivered_count integer; read_count integer; failed_count integer; next_status text; actor uuid:=(select auth.uid());
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  select * into campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if not found then raise exception 'Campaign was not found'; end if;
  if campaign.campaign_status not in ('queued','sending','completed','failed') then raise exception 'Queued campaign is required for reconciliation'; end if;
  select count(*),count(*) filter(where o.state='queued'),count(*) filter(where o.state='sending'),
    count(*) filter(where o.state='sent'),count(*) filter(where o.state='delivered'),count(*) filter(where o.state='read'),count(*) filter(where o.state='failed')
  into total_count,queued_count,sending_count,sent_count,delivered_count,read_count,failed_count
  from public.whatsapp_campaign_recipients cr
  join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id and o.contact_id=cr.whatsapp_contact_id
    and o.candidate_id=cr.candidate_id and o.requirement_id=campaign.requirement_id and o.correlation_id=cr.id
  where cr.campaign_id=campaign.id and cr.recipient_status='queued';
  if total_count=0 or total_count<>(select count(*) from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='queued')
     or exists(select 1 from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included') then
    raise exception 'Campaign outbound linkage is incomplete or inconsistent';
  end if;
  if campaign.campaign_status in ('completed','failed') then next_status:=campaign.campaign_status;
  elsif failed_count=total_count then next_status:='failed';
  elsif delivered_count+read_count+failed_count=total_count then next_status:='completed';
  elsif sending_count+sent_count+delivered_count+read_count+failed_count>0 then next_status:='sending';
  else next_status:='queued'; end if;
  if next_status is distinct from campaign.campaign_status then
    update public.whatsapp_campaigns set campaign_status=next_status,
      completed_at=case when next_status='completed' then clock_timestamp() else completed_at end
    where id=campaign.id;
    insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(actor,'staff','whatsapp.campaign_reconciled','whatsapp_campaign',campaign.id,'admin',
      jsonb_build_object('from_status',campaign.campaign_status,'to_status',next_status,'audience_count',total_count,
        'delivered_count',delivered_count,'read_count',read_count,'failed_count',failed_count));
  end if;
  return jsonb_build_object('campaign_status',next_status,'audience_count',total_count,'queued_count',queued_count,
    'sending_count',sending_count,'sent_count',sent_count,'delivered_count',delivered_count,'read_count',read_count,'failed_count',failed_count);
end;
$$;

create function public.admin_cancel_whatsapp_campaign(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); changed uuid;
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  update public.whatsapp_campaigns set campaign_status='cancelled',cancelled_at=clock_timestamp()
  where id=p_campaign_id and campaign_status in ('draft','audience_ready','approved') returning id into changed;
  if changed is null then raise exception 'Campaign can no longer be cancelled'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
  values(actor,'staff','whatsapp.campaign_cancelled','whatsapp_campaign',changed,'admin','{}'::jsonb);
  return true;
end;
$$;

create function public.admin_list_whatsapp_campaigns(p_status text default null,p_limit integer default 25,p_offset integer default 0)
returns table(campaign_id uuid,campaign_name text,requirement_id uuid,requirement_code text,job_role text,campaign_status text,
  created_at timestamptz,audience_count bigint,queued_count bigint,sending_count bigint,sent_count bigint,delivered_count bigint,read_count bigint,failed_count bigint)
language plpgsql stable security definer set search_path='' as $$
declare capped integer:=least(greatest(coalesce(p_limit,25),1),100);
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  if coalesce(p_offset,0)<0 then raise exception 'Offset must not be negative'; end if;
  return query select c.id,c.campaign_name,c.requirement_id,r.requirement_code,r.job_role,c.campaign_status,c.created_at,
    count(cr.id) filter(where cr.recipient_status in ('included','queued')),count(cr.outbound_message_id),
    count(o.id) filter(where o.state='sending'),count(o.id) filter(where o.state='sent'),count(o.id) filter(where o.state='delivered'),count(o.id) filter(where o.state='read'),count(o.id) filter(where o.state='failed')
  from public.whatsapp_campaigns c join public.employer_requirements r on r.id=c.requirement_id
  left join public.whatsapp_campaign_recipients cr on cr.campaign_id=c.id left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id
  where nullif(btrim(p_status),'') is null or c.campaign_status=lower(btrim(p_status))
  group by c.id,r.requirement_code,r.job_role order by c.created_at desc,c.id limit capped offset coalesce(p_offset,0);
end;
$$;

create function public.admin_get_whatsapp_campaign(p_campaign_id uuid,p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; capped integer:=least(greatest(coalesce(p_limit,50),1),100);
begin
  if not (select private.can_manage_whatsapp_campaigns()) then raise exception 'WhatsApp campaign Admin access is required'; end if;
  if coalesce(p_offset,0)<0 then raise exception 'Offset must not be negative'; end if;
  select jsonb_build_object('id',c.id,'campaign_name',c.campaign_name,'campaign_status',c.campaign_status,'requirement_id',r.id,
    'requirement_code',r.requirement_code,'job_role',r.job_role,'job_location',coalesce(r.job_location,r.company_location),
    'template_name',c.template_name,'template_language',c.template_language,'template_version',c.template_version,
    'criteria',c.criteria,'created_at',c.created_at,
    'created_by',coalesce((select sp.display_name from public.staff_profiles sp where sp.user_id=c.created_by),
      (select split_part(u.email,'@',1) from auth.users u where u.id=c.created_by),'Admin'),
    'approved_at',c.approved_at,'approved_by',case when c.approved_by is null then null else
      coalesce((select sp.display_name from public.staff_profiles sp where sp.user_id=c.approved_by),
        (select split_part(u.email,'@',1) from auth.users u where u.id=c.approved_by),'Admin') end,'queued_at',c.queued_at,
    'audience_count',(select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id and cr.recipient_status in ('included','queued')),
    'queued_count',(select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id and cr.outbound_message_id is not null),
    'sending_count',(select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='sending'),
    'sent_count',(select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='sent'),
    'delivered_count',(select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='delivered'),
    'read_count',(select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='read'),
    'failed_count',(select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='failed'),
    'recipients',(select coalesce(jsonb_agg(jsonb_build_object('recipient_id',x.id,'candidate_id',x.candidate_id,
      'candidate_name',left(x.full_name,1)||repeat('•',greatest(1,least(length(x.full_name)-1,12))),
      'contact_masked',case when x.indian_mobile_key is null then 'Unavailable' else '+91XXXXXX'||right(x.indian_mobile_key,4) end,
      'recipient_status',x.recipient_status,'delivery_status',coalesce(x.outbound_state,x.recipient_status),
      'failure_category',x.last_error_category) order by x.created_at,x.id),'[]'::jsonb)
      from (select cr.*,cand.full_name,wc.indian_mobile_key,o.state outbound_state,o.last_error_category
        from public.whatsapp_campaign_recipients cr join public.candidates cand on cand.id=cr.candidate_id
        left join public.whatsapp_contacts wc on wc.id=cr.whatsapp_contact_id left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id
        where cr.campaign_id=c.id order by cr.created_at,cr.id limit capped offset coalesce(p_offset,0)) x))
  into result from public.whatsapp_campaigns c join public.employer_requirements r on r.id=c.requirement_id where c.id=p_campaign_id;
  if result is null then raise exception 'Campaign was not found'; end if;
  return result;
end;
$$;

alter table public.whatsapp_campaigns enable row level security;
alter table public.whatsapp_campaign_recipients enable row level security;
revoke all on public.whatsapp_campaigns,public.whatsapp_campaign_recipients from public,anon,authenticated;
revoke all on function private.can_manage_whatsapp_campaigns(),private.whatsapp_campaign_criteria_safe(jsonb),
  private.whatsapp_campaign_match_reasons(public.candidates,public.employer_requirements,jsonb) from public,anon,authenticated;
revoke all on function public.admin_preview_whatsapp_campaign_audience(uuid,jsonb,integer,integer),
  public.admin_create_whatsapp_campaign(uuid,uuid,text,text,text,text,jsonb),
  public.admin_freeze_whatsapp_campaign_audience(uuid,uuid[],uuid[],integer),public.admin_approve_whatsapp_campaign(uuid),
  public.admin_queue_whatsapp_campaign(uuid),public.admin_reconcile_whatsapp_campaign(uuid),public.admin_cancel_whatsapp_campaign(uuid),
  public.admin_list_whatsapp_campaigns(text,integer,integer),public.admin_get_whatsapp_campaign(uuid,integer,integer)
  from public,anon,authenticated;
grant execute on function public.admin_preview_whatsapp_campaign_audience(uuid,jsonb,integer,integer),
  public.admin_create_whatsapp_campaign(uuid,uuid,text,text,text,text,jsonb),
  public.admin_freeze_whatsapp_campaign_audience(uuid,uuid[],uuid[],integer),public.admin_approve_whatsapp_campaign(uuid),
  public.admin_queue_whatsapp_campaign(uuid),public.admin_reconcile_whatsapp_campaign(uuid),public.admin_cancel_whatsapp_campaign(uuid),
  public.admin_list_whatsapp_campaigns(text,integer,integer),public.admin_get_whatsapp_campaign(uuid,integer,integer)
  to authenticated;

commit;
