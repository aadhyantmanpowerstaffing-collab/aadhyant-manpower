-- Manual service replies: canonical single-attempt outbox, Admin author and signed 24-hour inbound boundary.
begin;
alter table public.whatsapp_outbound_messages add column operator_user_id uuid references auth.users(id),add column operator_reply_body text;
alter table public.whatsapp_outbound_messages add constraint whatsapp_operator_reply_shape check (
 (purpose<>'operator_reply' and operator_user_id is null and operator_reply_body is null) or
 (purpose='operator_reply' and operator_user_id is not null and operator_reply_body is not null and operator_reply_body ~ '[^[:space:]]' and char_length(btrim(operator_reply_body)) between 1 and 2000
 and operator_reply_body !~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' and template_variables='{"entry_point":"operator_reply_v1"}'::jsonb
 and template_name='aadhyant_operator_reply' and template_language='en' and template_version='1' and consent_class='transactional'
 and message_type='session_text' and max_attempts=1 and candidate_id is null and requirement_id is null));
alter table public.whatsapp_outbound_messages drop constraint whatsapp_outbound_messages_message_type_check;
alter table public.whatsapp_outbound_messages add constraint whatsapp_outbound_messages_message_type_check check (
 message_type='template' or (message_type='session_text' and consent_class='transactional' and template_version='1' and max_attempts=1
 and ((purpose='interested_registration' and template_name='aadhyant_interested_registration')
 or (purpose='registration_chat' and template_name='aadhyant_chat_registration' and registration_chat_id is not null)
 or (purpose='employer_post_job' and template_name='aadhyant_employer_post_job' and candidate_id is null and requirement_id is null)
 or (purpose='operator_reply' and template_name='aadhyant_operator_reply' and operator_user_id is not null))));
create index whatsapp_operator_rate_idx on public.whatsapp_outbound_messages(operator_user_id,created_at) where purpose='operator_reply';

create function private.operator_reply_window(p_contact_id uuid) returns timestamptz language sql stable security definer set search_path='' as $$
 select max(m.provider_timestamp)+interval '24 hours' from public.whatsapp_inbound_messages m
 join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 where m.contact_id=p_contact_id and m.provider_timestamp<=clock_timestamp()
 and m.provider_timestamp>clock_timestamp()-interval '24 hours';
$$;
create function private.operator_reply_eligible(p_message_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o join public.whatsapp_contacts w on w.id=o.contact_id
 join public.whatsapp_inbound_messages m on m.id=o.correlation_id and m.contact_id=o.contact_id
 join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 where o.id=p_message_id and o.purpose='operator_reply' and o.destination=w.provider_address
 and m.provider_timestamp<=clock_timestamp() and m.provider_timestamp>clock_timestamp()-interval '24 hours'
 and w.resolution_status not in ('blocked','ambiguous') and w.marketing_consent_status<>'opted_out' and w.transactional_contact_status<>'suppressed'
 and not exists(select 1 from public.whatsapp_outbound_messages x where x.contact_id=o.contact_id and x.purpose='operator_reply' and x.id<>o.id
 and (x.send_phase='reconciliation_required' or x.state='sending')));
$$;
create function public.admin_console_reply_window(p_contact_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w public.whatsapp_contacts%rowtype; expiry timestamptz; reason text; pending public.whatsapp_outbound_messages%rowtype;
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict w from public.whatsapp_contacts where id=p_contact_id;
 expiry:=private.operator_reply_window(p_contact_id);
 reason:=case when w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed' then 'Contact is suppressed or needs identity review'
 when expiry is null then 'Reply window closed. Use an approved campaign template or wait for a new incoming message.'
 when exists(select 1 from public.whatsapp_outbound_messages o where o.contact_id=w.id and o.purpose='operator_reply' and (o.send_phase='reconciliation_required' or (o.send_phase='provider_call_started' and o.lease_expires_at<=clock_timestamp()))) then 'A previous reply needs delivery reconciliation before another reply'
 when exists(select 1 from public.whatsapp_outbound_messages o where o.contact_id=w.id and o.purpose='operator_reply' and o.state='sending') then 'A reply is being processed. Check its status before preparing another reply'
 when not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then 'Verify sender connection in Templates before replying'
 else null end;
 select * into pending from public.whatsapp_outbound_messages o where o.contact_id=w.id and o.purpose='operator_reply' and o.operator_user_id=auth.uid() and (o.state in ('queued','sending') or o.send_phase='reconciliation_required') order by o.created_at desc,o.id desc limit 1;
 return jsonb_build_object('pending',case when pending.id is null then null else jsonb_build_object('id',pending.id,'state',pending.state,'phase',pending.send_phase,'body',pending.operator_reply_body,'reconciliation_required',pending.send_phase='reconciliation_required' or (pending.send_phase='provider_call_started' and pending.lease_expires_at<=clock_timestamp())) end,'can_reply',reason is null,'expires_at',expiry,'reason',reason,'maximum_length',2000);
end;$$;
create function public.admin_console_prepare_reply(p_contact_id uuid,p_body text,p_operation uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare result uuid; original public.whatsapp_outbound_messages%rowtype; inbound uuid; window_state jsonb; body text:=btrim(p_body);
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 if p_operation is null or body is null or body !~ '[^[:space:]]' or char_length(body) not between 1 and 2000 or body ~ '[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' then raise exception 'Enter a reply of 1 to 2000 characters';end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-operator:'||auth.uid(),0));
 perform pg_advisory_xact_lock(hashtextextended('wa-operator-contact:'||p_contact_id,0));
 select * into original from public.whatsapp_outbound_messages where idempotency_key='operator-reply:'||auth.uid()||':'||p_operation;
 if found then
  if original.contact_id is distinct from p_contact_id or original.operator_reply_body is distinct from body then raise exception 'Reply operation already used for different content';end if;
  return original.id;
 end if;
 perform 1 from public.whatsapp_contacts where id=p_contact_id for update;if not found then raise exception 'Contact unavailable';end if;
 window_state:=public.admin_console_reply_window(p_contact_id);if (window_state->>'can_reply')::boolean is not true then raise exception '%',window_state->>'reason';end if;
 if (select count(*) from public.whatsapp_outbound_messages where purpose='operator_reply' and contact_id=p_contact_id and created_at>clock_timestamp()-interval '10 minutes')>=10
 or (select count(*) from public.whatsapp_outbound_messages where purpose='operator_reply' and operator_user_id=auth.uid() and created_at>clock_timestamp()-interval '1 hour')>=100 then raise exception 'Reply rate limit reached; wait before sending another reply';end if;
 select m.id into strict inbound from public.whatsapp_inbound_messages m join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 where m.contact_id=p_contact_id and m.provider_timestamp<=clock_timestamp() and m.provider_timestamp>clock_timestamp()-interval '24 hours'
 order by m.provider_timestamp desc,m.id desc limit 1;
 insert into public.whatsapp_outbound_messages(contact_id,purpose,consent_class,message_type,template_name,template_language,template_version,template_variables,
 destination,idempotency_key,correlation_id,max_attempts,operator_user_id,operator_reply_body)
 select id,'operator_reply','transactional','session_text','aadhyant_operator_reply','en','1','{"entry_point":"operator_reply_v1"}',provider_address,
 'operator-reply:'||auth.uid()||':'||p_operation,inbound,1,auth.uid(),body from public.whatsapp_contacts where id=p_contact_id returning id into result;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.operator_reply_prepared','whatsapp_outbound_message',result,'admin','{}');
 return result;
end;$$;
create function public.admin_console_reply_status(p_message_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict o from public.whatsapp_outbound_messages where id=p_message_id and purpose='operator_reply' and operator_user_id=auth.uid();
 return jsonb_build_object('id',o.id,'state',o.state,'phase',o.send_phase,'reconciliation_required',o.send_phase='reconciliation_required' or (o.send_phase='provider_call_started' and o.lease_expires_at<=clock_timestamp()));
end;$$;
create function public.console_claim_operator_reply(p_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb,operator_reply_body text)
language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 if p_worker_id is null or length(btrim(p_worker_id)) not between 1 and 160 then raise exception 'Worker required';end if;
 select o.contact_id into contact from public.whatsapp_outbound_messages o where o.id=p_message_id and o.purpose='operator_reply';if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-operator-contact:'||contact,0));
 update public.whatsapp_outbound_messages o set state='failed',send_phase=case when o.send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,last_error_category='reply_lease_expired',last_error_code='no_automatic_retry',updated_at=clock_timestamp()
 where o.id=p_message_id and o.state='sending' and o.lease_expires_at<=clock_timestamp();
 if not private.operator_reply_eligible(p_message_id) or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then return;end if;
 return query update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=1,lease_owner=btrim(p_worker_id),lease_expires_at=clock_timestamp()+interval '120 seconds',updated_at=clock_timestamp()
 where o.id=p_message_id and o.state='queued' and o.send_phase='ready' and o.attempt_count=0
 returning o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables,o.operator_reply_body;
end;$$;
-- This final boundary is deliberately authenticated: role revocation and authorship are rechecked with the real user JWT, not a service-role identity simulation.
create function public.admin_console_operator_reply_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text) returns boolean language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 select contact_id into contact from public.whatsapp_outbound_messages where id=p_message_id and purpose='operator_reply' and operator_user_id=auth.uid();if not found then raise exception 'Reply unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-operator-contact:'||contact,0));
 perform 1 from public.whatsapp_outbound_messages where id=p_message_id and state='sending' and send_phase='claimed' and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() for update;
 if not found then raise exception 'Reply lease unavailable';end if;
 perform 1 from public.whatsapp_contacts where id=contact for share;
 perform 1 from private.whatsapp_console_config where singleton and sender_ready and phone_number_id=p_phone_id and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found or not private.operator_reply_eligible(p_message_id) then raise exception 'Reply eligibility changed';end if;
 update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=clock_timestamp() where id=p_message_id and lease_expires_at>clock_timestamp();if not found then raise exception 'Reply lease expired';end if;
 return true;
end;$$;
create or replace function public.claim_whatsapp_outbound_batch(p_worker_id text,p_batch_size integer default 25,p_lease_seconds integer default 60)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,
  purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path = '' as $$
declare v_worker text:=pg_catalog.btrim(coalesce(p_worker_id,'')); v_batch integer:=least(greatest(coalesce(p_batch_size,25),1),100);
  v_lease integer:=least(greatest(coalesce(p_lease_seconds,60),15),900);
begin
  if pg_catalog.length(v_worker) not between 1 and 160 then raise exception 'A valid worker identifier is required'; end if;
  with expired as (
    update public.whatsapp_outbound_messages o set state='failed',
      send_phase=case when o.send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
      failed_at=pg_catalog.clock_timestamp(),lease_owner=null,lease_expires_at=null,
      last_error_category=case when o.send_phase='provider_call_started' then 'ambiguous_provider_outcome' else 'attempts_exhausted' end,
      last_error_code=case when o.send_phase='provider_call_started' then 'lease_expired_after_provider_call' else 'lease_expired_at_attempt_limit' end,
      updated_at=pg_catalog.clock_timestamp()
    where o.purpose not in ('employer_post_job','operator_reply') and o.state='sending' and o.lease_expires_at<=pg_catalog.clock_timestamp()
      and (o.send_phase='provider_call_started' or (o.send_phase='claimed' and o.attempt_count>=o.max_attempts))
    returning o.id,o.correlation_id,o.last_error_category,o.last_error_code
  ) insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',e.id,'whatsapp',e.correlation_id,
      pg_catalog.jsonb_build_object('failure_kind',case when e.last_error_category='ambiguous_provider_outcome' then 'ambiguous' else 'exhausted' end,
        'error_category',e.last_error_category,'error_code',e.last_error_code) from expired e;
  return query with claimable as (
    select o.id from public.whatsapp_outbound_messages o
    where o.purpose not in ('employer_post_job','operator_reply') and ((o.state='queued' and o.next_attempt_at<=pg_catalog.clock_timestamp())
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
$$;


create or replace function public.admin_console_conversation(p_contact_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 if p_contact_id is null or not exists(select 1 from public.whatsapp_contacts where id=p_contact_id) then raise exception 'Contact unavailable';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at,t.id,t.direction),'[]'::jsonb) from (
 select * from (
 select m.id,'incoming'::text direction,m.created_at,m.provider_timestamp event_at,m.processing_status status,
 case when m.action_id='POST_JOB' then 'POST JOB — vacancy form requested'
 when m.action_id='INTERESTED' then 'Interested in a vacancy'
 when m.action_id in ('STOP','STOP_ALERTS') then 'Stop alerts requested'
 when m.action_id='SUBSCRIBE_JOB_UPDATES' then 'Job-alert subscription response'
 when m.action_id like 'REGCHAT|%' then 'Registration option selected'
 else 'Message received — original text is not retained in this view' end summary,
 null::text template_name,null::text purpose,null::text job_code,
 null::timestamptz sent_at,null::timestamptz delivered_at,null::timestamptz read_at,
 m.processing_status='failed' or m.last_error_category is not null attention,
 not exists(select 1 from private.whatsapp_inbox_reads r where r.user_id=auth.uid() and r.inbound_id=m.id) unread,
 null::text failure
 from public.whatsapp_inbound_messages m where m.contact_id=p_contact_id
 union all
 select o.id,'outgoing',o.created_at,coalesce(o.sent_at,o.created_at),o.state,
 case when o.purpose='operator_reply' then o.operator_reply_body when o.purpose='employer_post_job' then 'Vacancy posting reply: open https://aadhyantmanpower.in/post-job/ and sign in with your Company or Contractor account to submit for review.'
 when o.purpose='interested_registration' then 'Registration form invitation'
 when o.purpose='registration_chat' then 'WhatsApp registration step'
 when o.purpose='vacancy_campaign' then 'Job opportunity notification'
 else 'Outgoing WhatsApp message' end,
 case when o.purpose='operator_reply' then null else o.template_name end,o.purpose,e.requirement_code,o.sent_at,o.delivered_at,o.read_at,o.state='failed',false,
 case when o.send_phase='reconciliation_required' then 'Delivery outcome uncertain — review before retrying'
 when o.state='failed' then 'Failed — review required' else null end
 from public.whatsapp_outbound_messages o left join public.employer_requirements e on e.id=o.requirement_id where o.contact_id=p_contact_id
 ) u order by created_at desc,id desc,direction desc limit 100 offset p_offset)t);
end;$$;


revoke all on function private.operator_reply_window(uuid),private.operator_reply_eligible(uuid),public.console_claim_operator_reply(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_operator_reply(uuid,text) to service_role;
revoke all on function public.admin_console_reply_window(uuid),public.admin_console_prepare_reply(uuid,text,uuid),public.admin_console_reply_status(uuid),public.admin_console_operator_reply_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_reply_window(uuid),public.admin_console_prepare_reply(uuid,text,uuid),public.admin_console_reply_status(uuid),public.admin_console_operator_reply_boundary(uuid,text,text,text) to authenticated;
revoke all on function public.claim_whatsapp_outbound_batch(text,integer,integer) from public,anon,authenticated;
grant execute on function public.claim_whatsapp_outbound_batch(text,integer,integer) to service_role;

create function public.admin_console_cancel_unsent_reply(p_message_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if public.admin_console_access() is not true then raise exception 'Admin access required' using errcode='42501';end if;
 update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=clock_timestamp(),last_error_category='operator_cancelled',last_error_code='unsent_reply_discarded',updated_at=clock_timestamp()
 where id=p_message_id and purpose='operator_reply' and operator_user_id=auth.uid() and state='queued' and send_phase='ready' and attempt_count=0;
 return found;
end;$$;
revoke all on function public.admin_console_cancel_unsent_reply(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_cancel_unsent_reply(uuid) to authenticated;
commit;
