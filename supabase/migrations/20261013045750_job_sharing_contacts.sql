-- Sharing audiences use canonical WhatsApp contacts/campaigns/outbox.
-- Import never creates Candidates, records marketing consent or queues a message.
begin;
do $$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname='whatsapp_vacancy_send_eligible') is distinct from 'aa855103a4239ea9c453a343fd2e7175'
    then raise exception 'Send guard baseline changed; reconcile before migration'; end if;
  if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname='whatsapp_contacts' and c.relrowsecurity)
    then raise exception 'Canonical contact RLS must be enabled'; end if;
end;
$$;
alter table public.whatsapp_contacts add column imported_profile jsonb not null default '{}'::jsonb,
  add column sharing_subscription jsonb not null default '{}'::jsonb;
alter table public.whatsapp_contacts add constraint sharing_contact_profiles_check check (
  jsonb_typeof(imported_profile)='object' and octet_length(imported_profile::text)<=4096
  and jsonb_typeof(sharing_subscription)='object' and octet_length(sharing_subscription::text)<=4096);
alter table public.whatsapp_campaigns add column audience_mode text not null default 'candidate_matching'
  check(audience_mode in ('candidate_matching','sharing_contacts'));
alter table public.whatsapp_campaign_recipients alter column candidate_id drop not null;
-- Existing UNIQUE(campaign_id,whatsapp_contact_id) prevents duplicate recipients.

create function private.sharing_contact_eligible(p_contact_id uuid,p_requirement_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.whatsapp_contacts w join public.employer_requirements r on r.id=p_requirement_id
    where w.id=p_contact_id and w.resolution_status in ('resolved','unresolved')
      and private.whatsapp_contact_allows_purpose(w.id,'marketing')
      and w.sharing_subscription->>'policy'='job-sharing-updates-v1'
      and w.sharing_subscription->>'scope' in ('all','filtered')
      and r.requirement_stage='open' and r.requirement_visibility='public'
      and private.vacancy_is_application_eligible(r.id)
      and (w.candidate_id is null or not exists(select 1 from public.candidate_applications a
        where a.candidate_id=w.candidate_id and a.requirement_id=r.id))
      and (w.sharing_subscription->>'scope'='all' or (
        (jsonb_array_length(coalesce(w.sharing_subscription->'locations','[]'::jsonb))=0 or exists(
          select 1 from jsonb_array_elements_text(w.sharing_subscription->'locations') x(v)
          where lower(btrim(x.v))=lower(btrim(coalesce(nullif(r.job_location,''),r.company_location)))))
        and (jsonb_array_length(coalesce(w.sharing_subscription->'trades','[]'::jsonb))=0 or exists(
          select 1 from jsonb_array_elements_text(w.sharing_subscription->'trades') x(v)
          where lower(btrim(x.v))=lower(btrim(r.iti_trade)))))));
$$;
revoke all on function private.sharing_contact_eligible(uuid,uuid) from public,anon,authenticated;

create function public.admin_import_sharing_contacts(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb; phone text; target uuid; candidate uuid; matches integer; added integer:=0; reused integer:=0; seen text[]:='{}';
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows) not between 1 and 500
    or octet_length(p_rows::text)>1048576 then raise exception 'Import requires 1 to 500 rows'; end if;
  for item in select value from jsonb_array_elements(p_rows) loop
    phone:=item->>'Mobile';
    if phone is null or phone !~ '^[6-9][0-9]{9}$' or coalesce(length(btrim(item->>'Name')),0) not between 1 and 160
      or (item->>'Age') is null or (item->>'Age') !~ '^[0-9]{1,2}$' or (item->>'Age')::integer not between 18 and 75
      or item->>'Gender' is null or item->>'Gender' not in ('Male','Female','Other / Prefer not to say')
      or coalesce(length(btrim(item->>'State')),0) not between 1 and 160
      or coalesce(length(btrim(item->>'District')),0) not between 1 and 160
      or length(coalesce(item->>'Email',''))>254 or jsonb_typeof(item) is distinct from 'object'
      or exists(select 1 from jsonb_object_keys(item) k where k not in ('Name','Email','Mobile','Gender','Age','State','District'))
      then raise exception 'Invalid import row'; end if;
    if phone=any(seen) then reused:=reused+1; continue; end if;
    seen:=array_append(seen,phone);
    select count(distinct c.id),min(c.id::text)::uuid into matches,candidate from public.candidates c
      where c.profile_status='active' and c.status<>'inactive' and (c.mobile=phone or c.whatsapp_number=phone);
    insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,imported_profile)
      values('+91'||phone,phone,case when matches=1 then candidate else null end,
        case when matches=1 then 'resolved' when matches>1 then 'ambiguous' else 'unresolved' end,item-'Mobile')
      on conflict(provider,provider_address) do nothing returning id into target;
    if target is null then
      reused:=reused+1;
      -- Preserve original identity, STOP, existing consent and subscriber choices.
      update public.whatsapp_contacts set imported_profile=item-'Mobile'
        where provider='whatsapp' and indian_mobile_key=phone and imported_profile='{}'::jsonb;
    else added:=added+1; end if;
    target:=null;
  end loop;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
    values(auth.uid(),'staff','whatsapp.sharing_contacts_imported','whatsapp_contact','admin',jsonb_build_object('added',added,'reused',reused));
  return jsonb_build_object('added',added,'reused',reused,'consent_changed',false,'queued',0);
end;
$$;

-- Only the signature-verified webhook calls this RPC, with a persisted inbound ID.
-- Replaying an earlier subscription never reverses a later STOP.
create function public.subscribe_whatsapp_sharing_updates(p_inbound_message_id uuid,p_preferences jsonb)
returns boolean language plpgsql security definer set search_path='' as $$
declare msg public.whatsapp_inbound_messages%rowtype; contact public.whatsapp_contacts%rowtype; v_scope text; kind text; item jsonb;
begin
  select * into msg from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
  if not found or msg.message_type<>'text' or msg.action_id is distinct from 'SUBSCRIBE_JOB_UPDATES' then raise exception 'Verified subscription event required'; end if;
  if exists(select 1 from public.audit_logs where action='whatsapp.sharing_subscription_recorded' and entity_id=msg.id) then return true; end if;
  select * into contact from public.whatsapp_contacts where id=msg.contact_id for update;
  if not found or contact.resolution_status in ('blocked','ambiguous') then raise exception 'Contact needs review'; end if;
  if msg.provider_timestamp is null or msg.provider_timestamp>clock_timestamp()+interval '5 minutes'
    or (contact.opted_out_at is not null and msg.provider_timestamp<=contact.opted_out_at) then return false; end if;
  if contact.consent_policy_version='job-sharing-updates-v1' and contact.consent_recorded_at is not null
    and msg.provider_timestamp<=contact.consent_recorded_at then return false; end if;
  v_scope:=p_preferences->>'scope';
  if jsonb_typeof(p_preferences) is distinct from 'object' or v_scope is null or v_scope not in ('all','filtered')
    or exists(select 1 from jsonb_object_keys(p_preferences) k where k not in ('scope','locations','trades'))
    or octet_length(p_preferences::text)>2000 then raise exception 'Invalid subscription preferences'; end if;
  foreach kind in array array['locations','trades'] loop
    if jsonb_typeof(p_preferences->kind) is distinct from 'array' or jsonb_array_length(p_preferences->kind)>20 then raise exception 'Invalid subscription filters'; end if;
    for item in select value from jsonb_array_elements(p_preferences->kind) loop
      if jsonb_typeof(item)<>'string' or length(btrim(item #>> '{}')) not between 1 and 160 then raise exception 'Invalid subscription filter'; end if;
    end loop;
  end loop;
  if v_scope='filtered' and jsonb_array_length(p_preferences->'locations')+jsonb_array_length(p_preferences->'trades')=0 then raise exception 'Select a subscription filter'; end if;
  if v_scope='all' and jsonb_array_length(p_preferences->'locations')+jsonb_array_length(p_preferences->'trades')<>0 then raise exception 'All Jobs has no narrowing filters'; end if;
  update public.whatsapp_contacts set sharing_subscription=p_preferences||jsonb_build_object('policy','job-sharing-updates-v1'),
    marketing_consent_status='opted_in',consent_source='whatsapp_inbound',consent_scope='job_updates_and_sharing',
    consent_recorded_at=msg.provider_timestamp,consent_policy_version='job-sharing-updates-v1',
    opted_out_at=null,opt_out_source=null,opt_out_reason_category=null where id=contact.id;
  insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,metadata)
    values('service','whatsapp.sharing_subscription_recorded','whatsapp_inbound_message',msg.id,'whatsapp',jsonb_build_object('scope',v_scope));
  return true;
end;
$$;

create function public.admin_list_sharing_contacts(p_requirement_id uuid default null,p_filters jsonb default '{}'::jsonb,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  if p_offset not between 0 and 5000 or jsonb_typeof(p_filters) is distinct from 'object'
    or exists(select 1 from jsonb_object_keys(p_filters) k where k not in ('state','district','gender','age_min','age_max'))
    or exists(select 1 from jsonb_each_text(p_filters) e where length(e.value)>160)
    or (p_filters ? 'age_min' and (p_filters->>'age_min') !~ '^[0-9]{1,2}$')
    or (p_filters ? 'age_max' and (p_filters->>'age_max') !~ '^[0-9]{1,2}$') then raise exception 'Invalid contact filters'; end if;
  return (select coalesce(jsonb_agg(t),'[]'::jsonb) from (
    select w.id as contact_id,coalesce(left(w.imported_profile->>'Name',1)||'•••','Subscriber') as name_masked,
      '+91XXXXXX'||right(w.indian_mobile_key,4) as mobile_masked,w.imported_profile->>'Gender' as gender,
      w.imported_profile->>'Age' as age,w.imported_profile->>'State' as state,w.imported_profile->>'District' as district,
      w.marketing_consent_status as consent,w.sharing_subscription->>'scope' as alert_scope,
      w.resolution_status,case when p_requirement_id is null then false else private.sharing_contact_eligible(w.id,p_requirement_id) end as eligible
    from public.whatsapp_contacts w where (w.imported_profile<>'{}'::jsonb or w.sharing_subscription<>'{}'::jsonb)
      and (not(p_filters ? 'state') or lower(w.imported_profile->>'State')=lower(p_filters->>'state'))
      and (not(p_filters ? 'district') or lower(w.imported_profile->>'District')=lower(p_filters->>'district'))
      and (not(p_filters ? 'gender') or w.imported_profile->>'Gender'=p_filters->>'gender')
      and (not(p_filters ? 'age_min') or (w.imported_profile->>'Age')::integer >=(p_filters->>'age_min')::integer)
      and (not(p_filters ? 'age_max') or (w.imported_profile->>'Age')::integer <=(p_filters->>'age_max')::integer)
    order by w.created_at desc,w.id limit 100 offset p_offset)t);
end;
$$;

create function public.admin_prepare_sharing_campaign(p_requirement_id uuid,p_operation_key uuid,p_contact_ids uuid[],
  p_campaign_name text,p_template_name text,p_template_language text,p_template_version text)
returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; campaign public.whatsapp_campaigns%rowtype; cid uuid; wc public.whatsapp_contacts%rowtype; v_count integer;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  if p_operation_key is null or cardinality(p_contact_ids) is null or cardinality(p_contact_ids) not between 1 and 500
    or array_position(p_contact_ids,null) is not null
    or coalesce(length(btrim(p_campaign_name)),0) not between 1 and 160
    or coalesce(p_template_name,'') !~ '^[a-z0-9_]{1,160}$'
    or coalesce(p_template_language,'') !~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'
    or coalesce(length(btrim(p_template_version)),0) not between 1 and 80 then raise exception 'Invalid campaign request'; end if;
  perform 1 from public.employer_requirements r where r.id=p_requirement_id and r.requirement_stage='open' and r.requirement_visibility='public' for share;
  if not found then raise exception 'Published open vacancy required'; end if;
  insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,purpose,consent_class,template_name,template_language,template_version,criteria,created_by,audience_mode)
    values(p_operation_key,p_requirement_id,btrim(p_campaign_name),'vacancy_campaign','marketing',p_template_name,p_template_language,p_template_version,'{}',auth.uid(),'sharing_contacts')
    on conflict(operation_key) do nothing returning id into result;
  select * into strict campaign from public.whatsapp_campaigns where operation_key=p_operation_key for update;
  if result is null then
    if campaign.created_by is distinct from auth.uid() or campaign.audience_mode<>'sharing_contacts' or campaign.requirement_id<>p_requirement_id
      or campaign.campaign_name<>btrim(p_campaign_name) or campaign.template_name<>p_template_name
      or campaign.template_language<>p_template_language or campaign.template_version<>p_template_version
      or (select array_agg(distinct x order by x) from unnest(p_contact_ids) x) is distinct from
        (select array_agg(cr.whatsapp_contact_id order by cr.whatsapp_contact_id) from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id)
      then raise exception 'Campaign operation conflicts'; end if;
    return campaign.id;
  end if;
  for cid in select distinct x from unnest(p_contact_ids)x loop
    select * into strict wc from public.whatsapp_contacts where id=cid for share;
    if not private.sharing_contact_eligible(cid,p_requirement_id) then raise exception 'Selected contact is not eligible'; end if;
    insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
      values(campaign.id,wc.candidate_id,wc.id,'manual_include','included','["subscriber_preferences","manual_selection","candidate_matching_not_verified"]');
  end loop;
  select count(*) into v_count from public.whatsapp_campaign_recipients where campaign_id=campaign.id;
  update public.whatsapp_campaigns set campaign_status='audience_ready',audience_frozen_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.sharing_audience_prepared','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',v_count));
  return campaign.id;
end;
$$;

create function public.admin_approve_sharing_campaign(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into strict campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if campaign.audience_mode<>'sharing_contacts' or campaign.campaign_status<>'audience_ready' then raise exception 'Sharing audience-ready campaign required'; end if;
  if not exists(select 1 from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id and cr.recipient_status='included')
    or exists(select 1 from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id
      and (cr.recipient_status<>'included' or not private.sharing_contact_eligible(cr.whatsapp_contact_id,campaign.requirement_id)))
    then raise exception 'Audience changed or suppressed'; end if;
  update public.whatsapp_campaigns set campaign_status='approved',approved_by=auth.uid(),approved_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.sharing_campaign_approved','whatsapp_campaign',campaign.id,'admin','{}');
  return true;
end;
$$;

create function public.admin_queue_sharing_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; cr public.whatsapp_campaign_recipients%rowtype; outbound uuid; total integer:=0;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into strict campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if campaign.audience_mode<>'sharing_contacts' then raise exception 'Sharing campaign required'; end if;
  if campaign.campaign_status in ('queued','sending','completed') then
    return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=campaign.id and outbound_message_id is not null);
  end if;
  if campaign.campaign_status<>'approved' then raise exception 'Approved campaign required'; end if;
  select * into strict req from public.employer_requirements where id=campaign.requirement_id for share;
  for cr in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not private.sharing_contact_eligible(cr.whatsapp_contact_id,req.id) then raise exception 'Audience changed or suppressed'; end if;
    outbound:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,req.id,'vacancy_campaign','marketing',
      campaign.template_name,campaign.template_language,campaign.template_version,
      jsonb_build_object('requirement_code',req.requirement_code,'job_role',req.job_role,'campaign_id',campaign.id::text,'recipient_id',cr.id::text,'action_id','INTERESTED'),
      'campaign:'||campaign.id::text||':recipient:'||cr.id::text,cr.id,3);
    update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound where id=cr.id;
    total:=total+1;
  end loop;
  if total=0 then raise exception 'Empty audience'; end if;
  update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.sharing_campaign_queued','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',total));
  return total;
end;
$$;

create or replace function private.whatsapp_vacancy_send_eligible(p_message_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o
   join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id
   join public.whatsapp_campaigns wc on wc.id=cr.campaign_id
   where o.id=p_message_id and o.purpose='vacancy_campaign' and o.consent_class='marketing'
     and cr.recipient_status='queued' and cr.id=o.correlation_id and cr.whatsapp_contact_id=o.contact_id
     and wc.requirement_id=o.requirement_id and wc.campaign_status in ('queued','sending')
     and wc.approved_at is not null and wc.queued_at is not null and wc.cancelled_at is null
     and private.vacancy_is_application_eligible(o.requirement_id)
     and ((wc.audience_mode='candidate_matching' and cr.candidate_id=o.candidate_id and not exists(
       select 1 from public.candidate_applications a where a.candidate_id=o.candidate_id and a.requirement_id=o.requirement_id))
       or (wc.audience_mode='sharing_contacts' and cr.candidate_id is not distinct from o.candidate_id
         and private.sharing_contact_eligible(o.contact_id,o.requirement_id))));
$$;

create function public.admin_list_sharing_campaigns()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(t),'[]'::jsonb) from (
    select wc.id,wc.campaign_name,wc.campaign_status,r.requirement_code,r.job_role,
      (select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=wc.id) as audience_count
    from public.whatsapp_campaigns wc join public.employer_requirements r on r.id=wc.requirement_id
    where wc.audience_mode='sharing_contacts' order by wc.created_at desc,wc.id limit 100)t);
end;
$$;
revoke all on function public.admin_list_sharing_campaigns() from public,anon,authenticated;
grant execute on function public.admin_list_sharing_campaigns() to authenticated;
revoke all on function public.admin_import_sharing_contacts(jsonb),public.admin_list_sharing_contacts(uuid,jsonb,integer),
  public.admin_prepare_sharing_campaign(uuid,uuid,uuid[],text,text,text,text),public.admin_approve_sharing_campaign(uuid),
  public.admin_queue_sharing_campaign(uuid),public.subscribe_whatsapp_sharing_updates(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.admin_import_sharing_contacts(jsonb),public.admin_list_sharing_contacts(uuid,jsonb,integer),
  public.admin_prepare_sharing_campaign(uuid,uuid,uuid[],text,text,text,text),public.admin_approve_sharing_campaign(uuid),
  public.admin_queue_sharing_campaign(uuid) to authenticated;
grant execute on function public.subscribe_whatsapp_sharing_updates(uuid,jsonb) to service_role;
commit;
