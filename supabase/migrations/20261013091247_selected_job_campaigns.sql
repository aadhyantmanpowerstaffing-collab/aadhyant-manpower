-- Explicit manual job audiences. Reuses canonical contacts, campaigns and outbox.
-- Matching is advisory; opt-in, STOP, explicit subscriber preferences and vacancy checks remain authoritative.
begin;
do $$ begin
 if md5(pg_get_functiondef('private.whatsapp_vacancy_send_eligible(uuid)'::regprocedure)) is distinct from '00e4d287ed62fd10a114eb39b515cb7f' then raise exception 'Send guard baseline changed'; end if;
 if exists(select 1 from public.whatsapp_outbound_messages where state in ('queued','sending')) then raise exception 'Pending outbound messages require reconciliation'; end if;
end; $$;
alter table public.whatsapp_campaigns drop constraint whatsapp_campaigns_audience_mode_check;
alter table public.whatsapp_campaigns add constraint whatsapp_campaigns_audience_mode_check check(audience_mode in ('candidate_matching','sharing_contacts','selected_contacts'));
create function private.selected_job_contact_eligible(p_contact_id uuid,p_requirement_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_contacts w join public.employer_requirements r on r.id=p_requirement_id
 where w.id=p_contact_id and w.provider='whatsapp' and w.resolution_status in ('resolved','unresolved')
 and w.marketing_consent_status='opted_in' and private.whatsapp_contact_allows_purpose(w.id,'marketing')
 and r.requirement_stage='open' and r.requirement_visibility='public' and private.vacancy_is_application_eligible(r.id)
 and (w.sharing_subscription='{}'::jsonb or private.sharing_contact_eligible(w.id,r.id))
 and (w.candidate_id is null or (w.resolution_status='resolved' and exists(select 1 from public.candidates c
   where c.id=w.candidate_id and c.profile_status='active' and c.status<>'inactive')
   and not exists(select 1 from public.candidate_applications a where a.candidate_id=w.candidate_id and a.requirement_id=r.id))));
$$;
revoke all on function private.selected_job_contact_eligible(uuid,uuid) from public,anon,authenticated;

create function public.admin_preview_selected_job_contacts(p_requirement_id uuid,p_source text default 'registered',p_view text default 'suggested',p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare req public.employer_requirements%rowtype; result jsonb;
begin
 if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_source is null or p_source not in ('registered','contacts') or p_view is null or p_view not in ('suggested','all') or p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid audience query'; end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id and requirement_stage='open' and requirement_visibility='public';
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
  select w.id contact_id,w.candidate_id,
    left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
    case when w.id is null then 'Unavailable' else '+91XXXXXX'||right(w.indian_mobile_key,4) end mobile_masked,
    c.highest_qualification qualification,c.specialization trade,
    coalesce(c.current_location,w.imported_profile->>'District') location,
    w.marketing_consent_status consent,w.sharing_subscription->>'scope' alert_scope,
    private.selected_job_contact_eligible(w.id,req.id) eligible,
    case when w.id is null then 'WhatsApp contact unavailable' when w.resolution_status in ('blocked','ambiguous') then 'Contact blocked or ambiguous'
      when w.marketing_consent_status<>'opted_in' then 'Consent required'
      when w.candidate_id is not null and (c.profile_status<>'active' or c.status='inactive') then 'Inactive candidate'
      when exists(select 1 from public.candidate_applications a where a.candidate_id=w.candidate_id and a.requirement_id=req.id) then 'Already applied'
      when w.sharing_subscription<>'{}'::jsonb and not private.sharing_contact_eligible(w.id,req.id) then 'Subscriber preference does not match'
      when private.selected_job_contact_eligible(w.id,req.id) then 'Can select' else 'Contact needs review' end status,
    coalesce(m.suggested,false) suggested,m.reasons match_reasons
  from public.whatsapp_contacts w full join public.candidates c on c.id=w.candidate_id
  cross join lateral (select array_remove(array[
    case when nullif(btrim(req.qualification),'') is not null and lower(coalesce(c.highest_qualification,''))<>lower(req.qualification) then 'Qualification differs' end,
    case when nullif(btrim(req.iti_trade),'') is not null and lower(coalesce(c.specialization,''))<>lower(req.iti_trade) then 'Trade differs' end,
    case when req.experience_requirement is not null and req.experience_requirement<>'Both' and c.candidate_type is distinct from req.experience_requirement then 'Experience differs' end,
    case when nullif(btrim(coalesce(req.job_location,req.company_location)),'') is not null and
      lower(coalesce(c.current_location,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.district,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.state,''))<>lower(coalesce(req.job_location,req.company_location)) then 'Location differs' end
  ],null) reasons) reasons
  cross join lateral (select reasons.reasons, c.id is not null and cardinality(reasons.reasons)=0 suggested) m
  where (w.provider='whatsapp' or w.id is null) and ((p_source='registered' and c.id is not null) or (p_source='contacts' and w.imported_profile<>'{}'::jsonb))
    and (p_view='all' or p_source='contacts' or m.suggested)
  order by m.suggested desc,w.created_at desc nulls last,w.id,c.id limit 100 offset p_offset
 ) t;
 return result;
end; $$;
revoke all on function public.admin_preview_selected_job_contacts(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.admin_preview_selected_job_contacts(uuid,text,text,integer) to authenticated;

create function public.admin_prepare_selected_job_campaign(p_requirement_id uuid,p_operation_key uuid,p_contact_ids uuid[],
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
    values(p_operation_key,p_requirement_id,btrim(p_campaign_name),'vacancy_campaign','marketing',p_template_name,p_template_language,p_template_version,'{}',auth.uid(),'selected_contacts')
    on conflict(operation_key) do nothing returning id into result;
  select * into strict campaign from public.whatsapp_campaigns where operation_key=p_operation_key for update;
  if result is null then
    if campaign.created_by is distinct from auth.uid() or campaign.audience_mode<>'selected_contacts' or campaign.requirement_id<>p_requirement_id
      or campaign.campaign_name<>btrim(p_campaign_name) or campaign.template_name<>p_template_name
      or campaign.template_language<>p_template_language or campaign.template_version<>p_template_version
      or (select array_agg(distinct x order by x) from unnest(p_contact_ids) x) is distinct from
        (select array_agg(cr.whatsapp_contact_id order by cr.whatsapp_contact_id) from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id)
      then raise exception 'Campaign operation conflicts'; end if;
    return campaign.id;
  end if;
  for cid in select distinct x from unnest(p_contact_ids)x loop
    select * into strict wc from public.whatsapp_contacts where id=cid for share;
    if not private.selected_job_contact_eligible(cid,p_requirement_id) then raise exception 'Selected contact is not eligible'; end if;
    insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
      values(campaign.id,wc.candidate_id,wc.id,'manual_include','included','["manual_selection","matching_advisory","consent_rechecked"]');
  end loop;
  select count(*) into v_count from public.whatsapp_campaign_recipients where campaign_id=campaign.id;
  update public.whatsapp_campaigns set campaign_status='audience_ready',audience_frozen_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.selected_job_audience_prepared','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',v_count));
  return campaign.id;
end;
$$;

create function public.admin_approve_selected_job_campaign(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into strict campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if campaign.audience_mode<>'selected_contacts' or campaign.campaign_status<>'audience_ready' then raise exception 'Sharing audience-ready campaign required'; end if;
  if not exists(select 1 from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id and cr.recipient_status='included')
    or exists(select 1 from public.whatsapp_campaign_recipients cr where cr.campaign_id=campaign.id
      and (cr.recipient_status<>'included' or not private.selected_job_contact_eligible(cr.whatsapp_contact_id,campaign.requirement_id)))
    then raise exception 'Audience changed or suppressed'; end if;
  update public.whatsapp_campaigns set campaign_status='approved',approved_by=auth.uid(),approved_at=clock_timestamp() where id=campaign.id;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(auth.uid(),'staff','whatsapp.selected_job_campaign_approved','whatsapp_campaign',campaign.id,'admin','{}');
  return true;
end;
$$;

create function public.admin_queue_selected_job_campaign(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare campaign public.whatsapp_campaigns%rowtype; req public.employer_requirements%rowtype; cr public.whatsapp_campaign_recipients%rowtype; outbound uuid; total integer:=0;
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  select * into strict campaign from public.whatsapp_campaigns where id=p_campaign_id for update;
  if campaign.audience_mode<>'selected_contacts' then raise exception 'Sharing campaign required'; end if;
  if campaign.campaign_status in ('queued','sending','completed') then
    return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=campaign.id and outbound_message_id is not null);
  end if;
  if campaign.campaign_status<>'approved' then raise exception 'Approved campaign required'; end if;
  select * into strict req from public.employer_requirements where id=campaign.requirement_id for share;
  for cr in select * from public.whatsapp_campaign_recipients where campaign_id=campaign.id and recipient_status='included' order by id for update loop
    if not private.selected_job_contact_eligible(cr.whatsapp_contact_id,req.id) then raise exception 'Audience changed or suppressed'; end if;
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
    values(auth.uid(),'staff','whatsapp.selected_job_campaign_queued','whatsapp_campaign',campaign.id,'admin',jsonb_build_object('count',total));
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
         and private.sharing_contact_eligible(o.contact_id,o.requirement_id))
       or (wc.audience_mode='selected_contacts' and cr.candidate_id is not distinct from o.candidate_id
         and private.selected_job_contact_eligible(o.contact_id,o.requirement_id))));
$$;

create function public.admin_list_selected_job_campaigns()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(t),'[]'::jsonb) from (
    select wc.id,wc.campaign_name,wc.campaign_status,r.requirement_code,r.job_role,
      (select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=wc.id) as audience_count
    from public.whatsapp_campaigns wc join public.employer_requirements r on r.id=wc.requirement_id
    where wc.audience_mode='selected_contacts' order by wc.created_at desc,wc.id limit 100)t);
end;
$$;
revoke all on function public.admin_prepare_selected_job_campaign(uuid,uuid,uuid[],text,text,text,text),public.admin_approve_selected_job_campaign(uuid),public.admin_queue_selected_job_campaign(uuid),public.admin_list_selected_job_campaigns() from public,anon,authenticated;
grant execute on function public.admin_prepare_selected_job_campaign(uuid,uuid,uuid[],text,text,text,text),public.admin_approve_selected_job_campaign(uuid),public.admin_queue_selected_job_campaign(uuid),public.admin_list_selected_job_campaigns() to authenticated;
commit;
