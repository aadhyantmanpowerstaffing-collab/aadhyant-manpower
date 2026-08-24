-- W7C: correlate inbound INTERESTED replies to W7B recipients and canonical Candidate Applications.

begin;

do $$
begin
  if to_regclass('public.whatsapp_inbound_messages') is null
     or to_regclass('public.whatsapp_outbound_messages') is null
     or to_regclass('public.whatsapp_contacts') is null
     or to_regclass('public.whatsapp_campaigns') is null
     or to_regclass('public.whatsapp_campaign_recipients') is null
     or to_regclass('public.candidates') is null
     or to_regclass('public.employer_requirements') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.audit_logs') is null then
    raise exception 'W7C canonical W7A/W7B/recruitment prerequisites are missing';
  end if;
  if to_regprocedure('public.record_whatsapp_inbound_message(uuid,uuid,text,timestamp with time zone,text,text,text,text,jsonb)') is null
     or to_regprocedure('private.whatsapp_contact_allows_purpose(uuid,text)') is null then
    raise exception 'W7C W7A processing contracts are missing';
  end if;
  if to_regprocedure('public.process_whatsapp_interested_response(uuid)') is not null
     or exists(select 1 from information_schema.columns where table_schema='public' and table_name='whatsapp_inbound_messages'
       and column_name in ('campaign_recipient_id','application_id')) then
    raise exception 'W7C objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

alter table public.whatsapp_inbound_messages
  drop constraint whatsapp_inbound_messages_processing_status_check;

alter table public.whatsapp_inbound_messages
  add constraint whatsapp_inbound_messages_processing_status_check
    check (processing_status in ('received','normalized','processed','ignored','failed')),
  add column campaign_recipient_id uuid references public.whatsapp_campaign_recipients(id) on delete restrict,
  add column application_id uuid references public.candidate_applications(id) on delete restrict,
  add constraint whatsapp_inbound_interested_link_check check (
    (campaign_recipient_id is null and application_id is null)
    or (campaign_recipient_id is not null and application_id is not null and processing_status='processed'));

create index whatsapp_inbound_campaign_recipient_idx
  on public.whatsapp_inbound_messages(campaign_recipient_id,created_at desc)
  where campaign_recipient_id is not null;
create index whatsapp_inbound_application_idx
  on public.whatsapp_inbound_messages(application_id,created_at desc)
  where application_id is not null;

create function public.process_whatsapp_interested_response(p_inbound_message_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  inbound public.whatsapp_inbound_messages%rowtype;
  outbound public.whatsapp_outbound_messages%rowtype;
  recipient public.whatsapp_campaign_recipients%rowtype;
  campaign public.whatsapp_campaigns%rowtype;
  contact public.whatsapp_contacts%rowtype;
  requirement public.employer_requirements%rowtype;
  application_id_result uuid;
  application_created boolean:=false;
begin
  select * into inbound from public.whatsapp_inbound_messages
  where id=p_inbound_message_id for update;
  if not found then raise exception 'WhatsApp inbound message was not found'; end if;

  if inbound.processing_status='processed' then
    if inbound.campaign_recipient_id is null or inbound.application_id is null then
      raise exception 'Processed INTERESTED linkage is inconsistent';
    end if;
    select cr.* into recipient from public.whatsapp_campaign_recipients cr
      where cr.id=inbound.campaign_recipient_id;
    select c.* into campaign from public.whatsapp_campaigns c
      where c.id=recipient.campaign_id;
    return pg_catalog.jsonb_build_object('status','already_processed','inbound_message_id',inbound.id,
      'campaign_id',campaign.id,'requirement_id',campaign.requirement_id,'recipient_id',recipient.id,
      'candidate_id',recipient.candidate_id,'contact_id',recipient.whatsapp_contact_id,'application_id',inbound.application_id);
  end if;

  if pg_catalog.upper(pg_catalog.btrim(coalesce(inbound.action_id,'')))<>'INTERESTED' then
    raise exception 'INTERESTED action is required';
  end if;
  if nullif(pg_catalog.btrim(coalesce(inbound.correlation_key,'')),'') is null then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='correlation_unavailable',last_error_code='missing_reply_context'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','missing_reply_context','inbound_message_id',inbound.id);
  end if;

  select o.* into outbound from public.whatsapp_outbound_messages o
    where o.provider_message_id=pg_catalog.btrim(inbound.correlation_key) and o.contact_id=inbound.contact_id for share;
  if not found then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='correlation_unavailable',last_error_code='outbound_not_found'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','outbound_not_found','inbound_message_id',inbound.id);
  end if;

  select cr.* into recipient from public.whatsapp_campaign_recipients cr
    where cr.outbound_message_id=outbound.id and cr.whatsapp_contact_id=inbound.contact_id
      and cr.candidate_id=outbound.candidate_id and cr.recipient_status='queued'
      and outbound.requirement_id is not null and outbound.correlation_id=cr.id
    for update;
  if not found then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='correlation_unavailable',last_error_code='recipient_not_found'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','recipient_not_found','inbound_message_id',inbound.id);
  end if;

  select c.* into campaign from public.whatsapp_campaigns c
    where c.id=recipient.campaign_id and c.requirement_id=outbound.requirement_id for share;
  if not found or campaign.campaign_status not in ('queued','sending','completed')
     or outbound.purpose<>'vacancy_campaign' or outbound.consent_class<>'marketing'
     or outbound.state not in ('sent','delivered','read') then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='correlation_unavailable',last_error_code='campaign_delivery_ineligible'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','campaign_delivery_ineligible','inbound_message_id',inbound.id);
  end if;

  select wc.* into contact from public.whatsapp_contacts wc
    where wc.id=inbound.contact_id and wc.id=recipient.whatsapp_contact_id
      and wc.candidate_id=recipient.candidate_id and wc.provider='whatsapp' and wc.resolution_status='resolved'
    for share;
  if not found or not exists(select 1 from public.candidates c where c.id=recipient.candidate_id
      and c.profile_status='active' and c.status<>'inactive') then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='candidate_unavailable',last_error_code='candidate_contact_mismatch'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','candidate_contact_mismatch','inbound_message_id',inbound.id);
  end if;

  select r.* into requirement from public.employer_requirements r
    where r.id=campaign.requirement_id and r.requirement_stage='open' for share;
  if not found then
    update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=pg_catalog.clock_timestamp(),
      last_error_category='requirement_unavailable',last_error_code='requirement_not_open'
      where id=inbound.id;
    return pg_catalog.jsonb_build_object('status','ignored','reason','requirement_not_open','inbound_message_id',inbound.id);
  end if;

  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,
    source_reference,correlation_id)
  values(recipient.candidate_id,campaign.requirement_id,'whatsapp','interested',
    'whatsapp_campaign:'||campaign.id::text||':recipient:'||recipient.id::text,inbound.id)
  on conflict(candidate_id,requirement_id) do nothing
  returning id into application_id_result;

  if application_id_result is null then
    select a.id into application_id_result from public.candidate_applications a
      where a.candidate_id=recipient.candidate_id and a.requirement_id=campaign.requirement_id for share;
    if not found then raise exception 'Canonical Candidate Application linkage failed'; end if;
  else
    application_created:=true;
  end if;

  update public.whatsapp_inbound_messages set processing_status='processed',processed_at=pg_catalog.clock_timestamp(),
    last_error_category=null,last_error_code=null,campaign_recipient_id=recipient.id,application_id=application_id_result
    where id=inbound.id;

  insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values('service',case when application_created then 'whatsapp.interested_application_created'
      else 'whatsapp.interested_application_linked' end,
    'candidate_application',application_id_result,'whatsapp',inbound.id,
    pg_catalog.jsonb_build_object('campaign_id',campaign.id,'requirement_id',campaign.requirement_id,
      'recipient_id',recipient.id,'candidate_id',recipient.candidate_id,'contact_id',recipient.whatsapp_contact_id));

  return pg_catalog.jsonb_build_object('status',case when application_created then 'application_created' else 'application_exists' end,
    'inbound_message_id',inbound.id,'campaign_id',campaign.id,'requirement_id',campaign.requirement_id,
    'recipient_id',recipient.id,'candidate_id',recipient.candidate_id,'contact_id',recipient.whatsapp_contact_id,
    'application_id',application_id_result);
end;
$$;

revoke all on function public.process_whatsapp_interested_response(uuid) from public,anon,authenticated;
grant execute on function public.process_whatsapp_interested_response(uuid) to service_role;

commit;
