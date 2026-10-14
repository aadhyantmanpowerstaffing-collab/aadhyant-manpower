begin;
-- Session replies stay in the existing outbox; metadata is internal, not a Meta template.
alter table public.whatsapp_outbound_messages drop constraint whatsapp_outbound_messages_message_type_check;
alter table public.whatsapp_outbound_messages add constraint whatsapp_outbound_messages_message_type_check
 check (message_type='template' or (message_type='session_text' and purpose='interested_registration' and consent_class='transactional'
 and template_name='aadhyant_interested_registration' and template_version='1' and max_attempts=1));

create function private.registration_reply_eligible(p_message_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages reply
 join public.whatsapp_inbound_messages m on m.id=reply.correlation_id and m.contact_id=reply.contact_id
 join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 join public.whatsapp_outbound_messages original on original.provider_message_id=m.correlation_key and original.contact_id=m.contact_id
 join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=original.id and cr.id=original.correlation_id and cr.whatsapp_contact_id=m.contact_id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id and c.requirement_id=original.requirement_id
 join public.employer_requirements r on r.id=c.requirement_id
 join public.whatsapp_contacts w on w.id=m.contact_id
 where reply.id=p_message_id and reply.message_type='session_text' and reply.purpose='interested_registration'
 and reply.consent_class='transactional' and reply.requirement_id=c.requirement_id and reply.candidate_id is null
 and reply.destination=w.provider_address and reply.template_variables=jsonb_build_object('requirement_code',r.requirement_code)
 and m.action_id='INTERESTED' and m.last_error_category='registration_required'
 and m.provider_timestamp>clock_timestamp()-interval '24 hours' and m.provider_timestamp<=clock_timestamp()
 and original.state in ('sent','delivered','read') and original.candidate_id is null and c.console_template_id is not null
 and private.vacancy_is_application_eligible(r.id)
 and w.resolution_status in ('unresolved','resolved') and w.marketing_consent_status<>'opted_out' and w.transactional_contact_status<>'suppressed');
$$;

create function public.console_claim_registration_reply(p_inbound_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb)
language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; original public.whatsapp_outbound_messages%rowtype; rid uuid; code text;
begin
 if p_worker_id is null or length(btrim(p_worker_id)) not between 1 and 160 then raise exception 'Worker required'; end if;
 if not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then return;end if;
 select * into m from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
 if not found or m.action_id<>'INTERESTED' or m.last_error_category is distinct from 'registration_required' then return;end if;
 select o.* into original from public.whatsapp_outbound_messages o where o.provider_message_id=m.correlation_key and o.contact_id=m.contact_id;
 if not found or original.candidate_id is not null then return;end if;
 select r.requirement_code into code from public.employer_requirements r where r.id=original.requirement_id;
 if code is null or code !~ '^[A-Z0-9_-]{1,64}$' then return;end if;
 insert into public.whatsapp_outbound_messages(contact_id,requirement_id,purpose,consent_class,message_type,template_name,template_language,template_version,template_variables,destination,idempotency_key,correlation_id,max_attempts)
 values(m.contact_id,original.requirement_id,'interested_registration','transactional','session_text','aadhyant_interested_registration','gu','1',jsonb_build_object('requirement_code',code),original.destination,'interested-registration:'||original.id,m.id,1)
 on conflict(idempotency_key) do nothing returning id into rid;
 if rid is not null then
  insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
  values('service','whatsapp.registration_reply_queued','whatsapp_outbound_message',rid,'whatsapp',m.id,jsonb_build_object('inbound_message_id',m.id,'requirement_id',original.requirement_id));
 end if;
 select o.id into rid from public.whatsapp_outbound_messages o where o.idempotency_key='interested-registration:'||original.id for update;
 update public.whatsapp_outbound_messages set state='failed',send_phase=case when send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,last_error_category='reply_lease_expired',last_error_code='no_automatic_retry',updated_at=clock_timestamp()
 where id=rid and state='sending' and lease_expires_at<=clock_timestamp();
 -- A replay can only claim the original ready row. It can never send twice.
 if not private.registration_reply_eligible(rid) then
  update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=clock_timestamp(),last_error_category='reply_ineligible',last_error_code='window_or_contact_or_job',updated_at=clock_timestamp()
  where id=rid and state='queued' and send_phase='ready';return;
 end if;
 return query update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=1,lease_owner=btrim(p_worker_id),lease_expires_at=clock_timestamp()+interval '120 seconds',updated_at=clock_timestamp()
 where o.id=rid and o.state='queued' and o.send_phase='ready' and o.attempt_count=0
 returning o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables;
end;$$;

create function public.console_registration_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 select contact_id into contact from public.whatsapp_outbound_messages where id=p_message_id and state='sending' and send_phase='claimed' and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() for update;
 if not found then raise exception 'Reply lease unavailable';end if;
 perform 1 from public.whatsapp_contacts where id=contact for share;
 perform 1 from public.employer_requirements r join public.whatsapp_outbound_messages o on o.requirement_id=r.id where o.id=p_message_id for share of r;
 perform 1 from private.whatsapp_console_config where singleton and sender_ready and phone_number_id=p_phone_id and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found or not private.registration_reply_eligible(p_message_id) then raise exception 'Reply eligibility changed';end if;
 update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=clock_timestamp() where id=p_message_id and lease_expires_at>clock_timestamp();
 if not found then raise exception 'Reply lease expired';end if;
 return true;
end;$$;

revoke all on function private.registration_reply_eligible(uuid),public.console_claim_registration_reply(uuid,text),public.console_registration_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_registration_reply(uuid,text),public.console_registration_boundary(uuid,text,text,text) to service_role;

create or replace function public.admin_console_replies(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select m.id,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,m.action_id,m.processing_status,m.last_error_category,m.application_id,m.provider_timestamp,
 reply.state registration_reply_status,reply.last_error_category registration_reply_error
 from public.whatsapp_inbound_messages m join public.whatsapp_contacts w on w.id=m.contact_id
 join public.whatsapp_outbound_messages o on o.provider_message_id=m.correlation_key and o.contact_id=m.contact_id
 join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id
 left join public.whatsapp_outbound_messages reply on reply.idempotency_key='interested-registration:'||o.id
 where c.id=p_campaign_id and c.console_template_id is not null
 order by m.created_at desc,m.id limit 100 offset p_offset)t);
end;$$;
commit;
