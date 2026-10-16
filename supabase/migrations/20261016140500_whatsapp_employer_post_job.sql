-- User-initiated employer entry point; no vacancy authority or candidate alerts are granted by a phone message.
begin;
alter table public.whatsapp_outbound_messages drop constraint whatsapp_outbound_messages_message_type_check;
alter table public.whatsapp_outbound_messages add constraint whatsapp_outbound_messages_message_type_check check (
 message_type='template' or (message_type='session_text' and consent_class='transactional' and template_version='1' and max_attempts=1
 and ((purpose='interested_registration' and template_name='aadhyant_interested_registration')
 or (purpose='registration_chat' and template_name='aadhyant_chat_registration' and registration_chat_id is not null)
 or (purpose='employer_post_job' and template_name='aadhyant_employer_post_job' and candidate_id is null and requirement_id is null))));
alter table private.whatsapp_console_config add column employer_post_job_enabled boolean not null default false,
 add column employer_post_job_enabled_at timestamptz;
create index whatsapp_employer_reply_rate_idx on public.whatsapp_outbound_messages(contact_id,created_at) where purpose='employer_post_job';
create function public.admin_console_employer_post_job() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return (select jsonb_build_object('enabled',employer_post_job_enabled,'sender_ready',sender_ready and verified_at>clock_timestamp()-interval '24 hours',
 'form_url','https://aadhyantmanpower.in/post-job/','command','POST JOB') from private.whatsapp_console_config where singleton);
end; $$;
create function public.admin_console_set_employer_post_job(p_enabled boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_enabled is null then raise exception 'Choose enabled or disabled';end if;
 perform 1 from private.whatsapp_console_config where singleton for update;
 update private.whatsapp_console_config set employer_post_job_enabled=p_enabled,
 employer_post_job_enabled_at=case when p_enabled then clock_timestamp() else employer_post_job_enabled_at end where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.employer_post_job_configured','whatsapp_outbound_message','admin',jsonb_build_object('enabled',p_enabled));
 return true;
end; $$;
create function private.employer_post_job_reply_eligible(p_message_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o
 join public.whatsapp_inbound_messages m on m.id=o.correlation_id and m.contact_id=o.contact_id
 join public.whatsapp_webhook_events e on e.id=m.webhook_event_id and e.signature_verified
 join public.whatsapp_contacts w on w.id=o.contact_id cross join private.whatsapp_console_config cfg
 where o.id=p_message_id and cfg.singleton and cfg.employer_post_job_enabled
 and m.action_id='POST_JOB' and m.message_type in ('text','button') and m.processing_status='processed'
 and m.provider_timestamp<=clock_timestamp() and m.provider_timestamp>clock_timestamp()-interval '24 hours'
 and m.provider_timestamp>=date_trunc('second',cfg.employer_post_job_enabled_at)
 and o.purpose='employer_post_job' and o.consent_class='transactional' and o.message_type='session_text'
 and o.template_name='aadhyant_employer_post_job' and o.template_language='en' and o.template_version='1'
 and o.requirement_id is null and o.candidate_id is null and o.destination=w.provider_address
 and o.template_variables='{"entry_point":"post_job_v1"}'::jsonb and o.max_attempts=1
 and o.idempotency_key='employer-post-job:'||m.id
 and w.resolution_status not in ('blocked','ambiguous') and w.marketing_consent_status<>'opted_out' and w.transactional_contact_status<>'suppressed');
$$;
create function public.console_process_employer_post_job(p_inbound_message_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype; w public.whatsapp_contacts%rowtype; rid uuid;
begin
 select * into strict m from public.whatsapp_inbound_messages where id=p_inbound_message_id for update;
 if m.action_id is distinct from 'POST_JOB' or m.message_type not in ('text','button') then return jsonb_build_object('handled',false);end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-employer-post-job:'||m.contact_id,0));
 select * into strict w from public.whatsapp_contacts where id=m.contact_id for update;
 if not exists(select 1 from private.whatsapp_console_config where singleton and employer_post_job_enabled and m.provider_timestamp>=date_trunc('second',employer_post_job_enabled_at))
 or not exists(select 1 from public.whatsapp_webhook_events where id=m.webhook_event_id and signature_verified)
 or m.provider_timestamp is null or m.provider_timestamp>clock_timestamp() or m.provider_timestamp<=clock_timestamp()-interval '24 hours'
 or w.resolution_status in ('blocked','ambiguous') or w.marketing_consent_status='opted_out' or w.transactional_contact_status='suppressed'
 then return jsonb_build_object('handled',true,'status','unavailable');end if;
 select id into rid from public.whatsapp_outbound_messages where idempotency_key='employer-post-job:'||m.id;
 if found then return jsonb_build_object('handled',true,'status','replay','outbound_id',rid);end if;
 if (select count(*) from public.whatsapp_outbound_messages where contact_id=w.id and purpose='employer_post_job' and created_at>clock_timestamp()-interval '10 minutes')>=3 then
  update public.whatsapp_inbound_messages set processing_status='ignored',processed_at=clock_timestamp(),last_error_category='post_job_rate_limited' where id=m.id;
  return jsonb_build_object('handled',true,'status','rate_limited');
 end if;
 insert into public.whatsapp_outbound_messages(contact_id,purpose,consent_class,message_type,template_name,template_language,template_version,
 template_variables,destination,idempotency_key,correlation_id,max_attempts)
 values(w.id,'employer_post_job','transactional','session_text','aadhyant_employer_post_job','en','1',
 '{"entry_point":"post_job_v1"}',w.provider_address,'employer-post-job:'||m.id,m.id,1) returning id into rid;
 update public.whatsapp_inbound_messages set processing_status='processed',processed_at=clock_timestamp(),last_error_category=null,last_error_code=null where id=m.id;
 return jsonb_build_object('handled',true,'status','queued','outbound_id',rid);
end; $$;
create function public.console_claim_employer_post_job(p_message_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,message_type text,purpose text,consent_class text,template_variables jsonb)
language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 if p_worker_id is null or length(btrim(p_worker_id)) not between 1 and 160 then raise exception 'Worker required';end if;
 select o.contact_id into contact from public.whatsapp_outbound_messages o where o.id=p_message_id and o.purpose='employer_post_job';
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-employer-post-job:'||contact,0));
 update public.whatsapp_outbound_messages set state='failed',send_phase=case when send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,last_error_category='reply_lease_expired',last_error_code='no_automatic_retry',updated_at=clock_timestamp()
 where id=p_message_id and state='sending' and lease_expires_at<=clock_timestamp();
 if not exists(select 1 from private.whatsapp_console_config where singleton and employer_post_job_enabled and sender_ready and verified_at>clock_timestamp()-interval '24 hours')
 or not private.employer_post_job_reply_eligible(p_message_id) then return;end if;
 return query update public.whatsapp_outbound_messages o set state='sending',send_phase='claimed',attempt_count=1,lease_owner=btrim(p_worker_id),
 lease_expires_at=clock_timestamp()+interval '120 seconds',updated_at=clock_timestamp()
 where o.id=p_message_id and o.state='queued' and o.send_phase='ready' and o.attempt_count=0
 returning o.id,o.destination,o.message_type,o.purpose,o.consent_class,o.template_variables;
end;$$;

create function public.console_employer_post_job_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare contact uuid;
begin
 select contact_id into contact from public.whatsapp_outbound_messages where id=p_message_id and purpose='employer_post_job';
 if not found then raise exception 'Chat lease unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended('wa-employer-post-job:'||contact,0));
 perform 1 from public.whatsapp_outbound_messages where id=p_message_id and state='sending' and send_phase='claimed'
 and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() for update;
 if not found then raise exception 'Chat lease unavailable';end if;
 perform 1 from public.whatsapp_contacts where id=contact for share;
 perform 1 from private.whatsapp_console_config where singleton and employer_post_job_enabled and sender_ready and phone_number_id=p_phone_id
 and business_account_id=p_account_id and verified_at>clock_timestamp()-interval '24 hours' for share;
 if not found or not private.employer_post_job_reply_eligible(p_message_id) then raise exception 'Chat eligibility changed';end if;
 update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=clock_timestamp() where id=p_message_id and lease_expires_at>clock_timestamp();
 if not found then raise exception 'Chat lease expired';end if;
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
    where o.purpose<>'employer_post_job' and o.state='sending' and o.lease_expires_at<=pg_catalog.clock_timestamp()
      and (o.send_phase='provider_call_started' or (o.send_phase='claimed' and o.attempt_count>=o.max_attempts))
    returning o.id,o.correlation_id,o.last_error_category,o.last_error_code
  ) insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',e.id,'whatsapp',e.correlation_id,
      pg_catalog.jsonb_build_object('failure_kind',case when e.last_error_category='ambiguous_provider_outcome' then 'ambiguous' else 'exhausted' end,
        'error_category',e.last_error_category,'error_code',e.last_error_code) from expired e;
  return query with claimable as (
    select o.id from public.whatsapp_outbound_messages o
    where o.purpose<>'employer_post_job' and ((o.state='queued' and o.next_attempt_at<=pg_catalog.clock_timestamp())
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


revoke all on function private.employer_post_job_reply_eligible(uuid),public.console_process_employer_post_job(uuid),public.console_claim_employer_post_job(uuid,text),public.console_employer_post_job_boundary(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.console_process_employer_post_job(uuid),public.console_claim_employer_post_job(uuid,text),public.console_employer_post_job_boundary(uuid,text,text,text) to service_role;
revoke all on function public.admin_console_employer_post_job(),public.admin_console_set_employer_post_job(boolean) from public,anon;
grant execute on function public.admin_console_employer_post_job(),public.admin_console_set_employer_post_job(boolean) to authenticated;
revoke all on function public.claim_whatsapp_outbound_batch(text,integer,integer) from public,anon,authenticated;
grant execute on function public.claim_whatsapp_outbound_batch(text,integer,integer) to service_role;
commit;
