begin;
alter table private.whatsapp_console_config add column phone_number_id text,add column business_account_id text,add column verified_at timestamptz,add column scheduler_ready boolean not null default false;
CREATE OR REPLACE FUNCTION public.console_claim_campaign(p_campaign_id uuid, p_worker_id text)
 RETURNS TABLE(message_id uuid, destination text, template_name text, template_language text, template_version text, template_variables jsonb, purpose text, consent_class text, attempt_count integer, correlation_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_worker text:=pg_catalog.btrim(coalesce(p_worker_id,'')); v_batch integer:=least(greatest(10,1),100);
  v_lease integer:=least(greatest(120,15),900);
begin
  if not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then return; end if;
  if pg_catalog.length(v_worker) not between 1 and 160 then raise exception 'A valid worker identifier is required'; end if;
  with expired as (
    update public.whatsapp_outbound_messages o set state='failed',
      send_phase=case when o.send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
      failed_at=pg_catalog.clock_timestamp(),lease_owner=null,lease_expires_at=null,
      last_error_category=case when o.send_phase='provider_call_started' then 'ambiguous_provider_outcome' else 'attempts_exhausted' end,
      last_error_code=case when o.send_phase='provider_call_started' then 'lease_expired_after_provider_call' else 'lease_expired_at_attempt_limit' end,
      updated_at=pg_catalog.clock_timestamp()
    where exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id where cr.outbound_message_id=o.id and c.console_template_id is not null and (p_campaign_id is null or c.id=p_campaign_id)) and o.state='sending' and o.lease_expires_at<=pg_catalog.clock_timestamp()
      and (o.send_phase='provider_call_started' or (o.send_phase='claimed' and o.attempt_count>=o.max_attempts))
    returning o.id,o.correlation_id,o.last_error_category,o.last_error_code
  ) insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',e.id,'whatsapp',e.correlation_id,
      pg_catalog.jsonb_build_object('failure_kind',case when e.last_error_category='ambiguous_provider_outcome' then 'ambiguous' else 'exhausted' end,
        'error_category',e.last_error_category,'error_code',e.last_error_code) from expired e;
  return query with claimable as (
    select o.id from public.whatsapp_outbound_messages o
    where exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id where cr.outbound_message_id=o.id and c.console_template_id is not null and (p_campaign_id is null or c.id=p_campaign_id) and private.console_template_valid(c.id)) and ((o.state='queued' and o.next_attempt_at<=pg_catalog.clock_timestamp())
      or (o.state='sending' and o.send_phase='claimed' and o.lease_expires_at<=pg_catalog.clock_timestamp()
        and o.provider_message_id is null))
      and (o.purpose <> 'vacancy_campaign' OR private.whatsapp_vacancy_send_eligible(o.id))
      and o.attempt_count<o.max_attempts and (select private.whatsapp_contact_allows_purpose(o.contact_id,o.consent_class))
    order by o.next_attempt_at,o.created_at,o.id for update skip locked limit v_batch
  ), claimed as (
    update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=o.attempt_count+1,lease_owner=v_worker,
      lease_expires_at=pg_catalog.clock_timestamp()+pg_catalog.make_interval(secs=>v_lease),updated_at=pg_catalog.clock_timestamp()
    from claimable c where o.id=c.id returning o.*
  ) select c.id,c.destination,c.template_name,c.template_language,c.template_version,c.template_variables,
    c.purpose,c.consent_class,c.attempt_count,c.correlation_id from claimed c;
end;
$function$;
create function public.console_sender_connection(p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if p_phone_id !~ '^[0-9]{8,40}$' or p_account_id !~ '^[0-9]{8,40}$' or p_phone_id is null or p_account_id is null then raise exception 'Verified Meta identifiers required'; end if;
 update private.whatsapp_console_config set phone_number_id=p_phone_id,business_account_id=p_account_id,verified_at=clock_timestamp(),sender_ready=true where singleton;
 return true;
end; $$;
create function public.console_sender_configuration()
returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('ready',sender_ready and verified_at>clock_timestamp()-interval '24 hours','phone_id',phone_number_id,'account_id',business_account_id) from private.whatsapp_console_config where singleton;
$$;
create function public.console_provider_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 perform 1 from public.whatsapp_outbound_messages where id=p_message_id for update;
 select c.id into cid from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns c on c.id=cr.campaign_id
 where cr.outbound_message_id=p_message_id and c.console_template_id is not null for share of c;
 if cid is null then raise exception 'Console campaign required'; end if;
 perform 1 from public.whatsapp_template_catalog t join public.whatsapp_campaigns c on c.console_template_id=t.id where c.id=cid for share of t;
 perform 1 from private.whatsapp_console_config where singleton and sender_ready and phone_number_id=p_phone_id and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found or not private.console_template_valid(cid) then raise exception 'Sender or template approval expired'; end if;
 return public.mark_whatsapp_provider_call_started(p_message_id,p_worker_id);
end; $$;
create function public.console_process_interested(p_inbound_message_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; o public.whatsapp_outbound_messages%rowtype; c public.whatsapp_campaigns%rowtype;
begin
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
 if m.action_id<>'INTERESTED' then raise exception 'Interested action required';end if;
 select om.* into o from public.whatsapp_outbound_messages om where om.provider_message_id=m.correlation_key and om.contact_id=m.contact_id and om.state in ('sent','delivered','read');
 if not found then return jsonb_build_object('status','ignored','reason','outbound_not_found');end if;
 select wc.* into c from public.whatsapp_campaigns wc join public.whatsapp_campaign_recipients cr on cr.campaign_id=wc.id
 where cr.outbound_message_id=o.id and cr.whatsapp_contact_id=m.contact_id and cr.id=o.correlation_id and wc.requirement_id=o.requirement_id and wc.console_template_id is not null;
 if not found then return jsonb_build_object('status','ignored','reason','console_campaign_not_found');end if;
 if o.candidate_id is not null then return public.process_whatsapp_interested_response(m.id);end if;
 if m.last_error_category='registration_required' then return jsonb_build_object('status','registration_required','requirement_id',c.requirement_id);end if;
 update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=clock_timestamp(),last_error_category='registration_required',last_error_code='candidate_not_registered',
 redacted_response=jsonb_build_object('requirement_id',c.requirement_id,'campaign_id',c.id) where id=m.id;
 insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,metadata)
 values('service','whatsapp.interested_registration_required','whatsapp_inbound_message',m.id,'whatsapp',jsonb_build_object('campaign_id',c.id,'requirement_id',c.requirement_id));
 return jsonb_build_object('status','registration_required','requirement_id',c.requirement_id);
end; $$;
create function public.admin_console_replies(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select m.id,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,m.action_id,m.processing_status,m.last_error_category,m.application_id,m.provider_timestamp
 from public.whatsapp_inbound_messages m join public.whatsapp_contacts w on w.id=m.contact_id
 join public.whatsapp_outbound_messages o on o.provider_message_id=m.correlation_key and o.contact_id=m.contact_id
 join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id where c.id=p_campaign_id and c.console_template_id is not null
 order by m.created_at desc,m.id limit 100 offset p_offset)t);
end; $$;
-- Grant only the canonical service contracts consumed by the signed webhook and worker.
-- Legacy public/admin entrypoints remain revoked.
grant execute on function public.accept_whatsapp_webhook_event(text,text,text,jsonb),public.upsert_whatsapp_inbound_contact(text),
 public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb),public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text),
 public.set_whatsapp_contact_suppression(uuid,boolean,text,text),public.subscribe_whatsapp_sharing_updates(uuid,jsonb),
 public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz),public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz) to service_role;
-- Only the signed webhook's provider-message lookup needs table SELECT. Never browser grants.
grant select(id,provider_message_id) on public.whatsapp_outbound_messages to service_role;
revoke all on function public.console_claim_campaign(uuid,text),public.console_sender_connection(text,text),public.console_sender_configuration(),public.console_provider_boundary(uuid,text,text,text),public.console_process_interested(uuid),public.admin_console_replies(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_campaign(uuid,text),public.console_sender_connection(text,text),public.console_sender_configuration(),public.console_provider_boundary(uuid,text,text,text),public.console_process_interested(uuid) to service_role;
grant execute on function public.admin_console_replies(uuid,integer) to authenticated;
create or replace function public.admin_console_queue(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype; n integer;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if not (select sender_ready and verified_at>clock_timestamp()-interval '24 hours' from private.whatsapp_console_config where singleton) then raise exception 'Sender connection is not verified'; end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null for update;
 if c.scheduled_for>clock_timestamp() and not (select scheduler_ready from private.whatsapp_console_config where singleton) then raise exception 'Automatic scheduler setup is pending';end if;
 if not private.console_template_valid(c.id) then raise exception 'Template changed or approval expired'; end if;
 n:=public.admin_queue_selected_job_campaign(c.id);
 update public.whatsapp_outbound_messages o set next_attempt_at=greatest(o.next_attempt_at,coalesce(c.scheduled_for,clock_timestamp()))
 where o.id in(select cr.outbound_message_id from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id)
  and o.state='queued' and o.send_phase='ready';
 return n;
end; $$;

create or replace function public.admin_console_templates()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return jsonb_build_object('sender_ready',(select sender_ready and verified_at>clock_timestamp()-interval '24 hours' from private.whatsapp_console_config where singleton),'scheduler_ready',(select scheduler_ready from private.whatsapp_console_config where singleton),
 'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name,t.language),'[]'::jsonb) from public.whatsapp_template_catalog t));
end; $$;

commit;
