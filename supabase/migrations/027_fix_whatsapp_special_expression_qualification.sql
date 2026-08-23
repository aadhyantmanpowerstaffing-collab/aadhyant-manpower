-- W7A corrective migration: PostgreSQL special expressions are not schema-qualified functions.

begin;

do $$
begin
  if to_regprocedure('private.normalize_indian_whatsapp_phone(text)') is null
     or to_regprocedure('private.apply_whatsapp_delivery_projection(uuid,text,timestamptz)') is null
     or to_regprocedure('public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)') is null
     or to_regprocedure('public.claim_whatsapp_outbound_batch(text,integer,integer)') is null
     or to_regprocedure('public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz)') is null
     or to_regprocedure('public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz)') is null
     or to_regprocedure('public.set_whatsapp_contact_suppression(uuid,boolean,text,text)') is null
     or to_regprocedure('public.list_whatsapp_recent_inbound(integer,integer)') is null
     or to_regprocedure('public.list_whatsapp_recent_outbound(text,integer,integer)') is null
     or to_regprocedure('public.list_whatsapp_failed_outbound(integer,integer)') is null then
    raise exception 'Installed W7A migration 026 function prerequisites are missing';
  end if;
end;
$$;
create or replace function private.normalize_indian_whatsapp_phone(p_value text)
returns table(indian_mobile_key text,provider_address text)
language plpgsql immutable security definer set search_path = '' as $$
declare v_input text:=pg_catalog.btrim(coalesce(p_value,'')); v_compact text; v_digits text;
begin
  if v_input='' or v_input !~ '^[0-9+()[:space:]-]+$' then raise exception 'A valid Indian mobile number is required'; end if;
  v_compact:=pg_catalog.regexp_replace(v_input,'[()[:space:]-]','','g');
  if v_compact !~ '^([6-9][0-9]{9}|91[6-9][0-9]{9}|\+91[6-9][0-9]{9})$' then raise exception 'A valid Indian mobile number is required'; end if;
  v_digits:=case when pg_catalog.left(v_compact,3)='+91' then pg_catalog.substr(v_compact,4)
    when pg_catalog.length(v_compact)=12 then pg_catalog.substr(v_compact,3) else v_compact end;
  if v_digits !~ '^[6-9][0-9]{9}$' then raise exception 'A valid Indian mobile number is required'; end if;
  return query select v_digits,'+91'||v_digits;
end;
$$;

create or replace function private.apply_whatsapp_delivery_projection(p_outbound_message_id uuid,p_status text,p_provider_timestamp timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_status,''))); v_now timestamptz:=coalesce(p_provider_timestamp,pg_catalog.clock_timestamp());
begin
  if v_status in ('accepted','sent') then
    update public.whatsapp_outbound_messages set state='sent',send_phase='confirmed',sent_at=coalesce(sent_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent');
  elsif v_status='delivered' then
    update public.whatsapp_outbound_messages set state='delivered',send_phase='confirmed',sent_at=coalesce(sent_at,v_now),delivered_at=coalesce(delivered_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent','delivered','failed');
  elsif v_status='read' then
    update public.whatsapp_outbound_messages set state='read',send_phase='confirmed',sent_at=coalesce(sent_at,v_now),delivered_at=coalesce(delivered_at,v_now),read_at=coalesce(read_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state<>'read';
  elsif v_status='failed' then
    update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=coalesce(failed_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent');
  else raise exception 'Unsupported WhatsApp delivery status'; end if;
end;
$$;

create or replace function public.record_whatsapp_inbound_message(p_webhook_event_id uuid,p_contact_id uuid,p_provider_message_id text,
  p_provider_timestamp timestamptz,p_message_type text,p_safe_text text default null,p_action_id text default null,
  p_correlation_key text default null,p_redacted_response jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not (select private.whatsapp_safe_flat_json(p_redacted_response)) then
    raise exception 'WhatsApp inbound metadata contains prohibited or unsupported fields';
  end if;
  insert into public.whatsapp_inbound_messages(webhook_event_id,contact_id,provider_message_id,provider_timestamp,message_type,
    safe_text,action_id,correlation_key,redacted_response,processing_status)
  values(p_webhook_event_id,p_contact_id,pg_catalog.btrim(p_provider_message_id),p_provider_timestamp,
    pg_catalog.lower(pg_catalog.btrim(p_message_type)),null,p_action_id,p_correlation_key,p_redacted_response,'normalized')
  on conflict(provider_message_id) do update set provider_message_id=excluded.provider_message_id
    where whatsapp_inbound_messages.webhook_event_id=excluded.webhook_event_id
      and whatsapp_inbound_messages.contact_id=excluded.contact_id
      and whatsapp_inbound_messages.message_type=excluded.message_type returning id into v_id;
  if v_id is null then raise exception 'WhatsApp inbound idempotency key conflicts with existing message'; end if;
  update public.whatsapp_contacts set last_inbound_at=greatest(coalesce(last_inbound_at,'-infinity'::timestamptz),
    coalesce(p_provider_timestamp,pg_catalog.clock_timestamp())),updated_at=pg_catalog.clock_timestamp() where id=p_contact_id;
  return v_id;
end;
$$;

create or replace function public.enqueue_whatsapp_outbound_message(p_contact_id uuid,p_candidate_id uuid,p_requirement_id uuid,p_purpose text,
  p_consent_class text,p_template_name text,p_template_language text,p_template_version text,p_template_variables jsonb,
  p_idempotency_key text,p_correlation_id uuid default null,p_max_attempts integer default 3)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_contact public.whatsapp_contacts%rowtype; v_existing public.whatsapp_outbound_messages%rowtype; v_id uuid;
  v_purpose text:=pg_catalog.btrim(p_purpose); v_consent text:=pg_catalog.lower(pg_catalog.btrim(p_consent_class));
  v_template text:=pg_catalog.lower(pg_catalog.btrim(p_template_name)); v_language text:=pg_catalog.btrim(p_template_language);
  v_version text:=pg_catalog.btrim(p_template_version); v_variables jsonb:=coalesce(p_template_variables,'{}'::jsonb);
begin
  select * into v_contact from public.whatsapp_contacts where id=p_contact_id for share;
  if not found or not (select private.whatsapp_contact_allows_purpose(p_contact_id,v_consent)) then raise exception 'WhatsApp contact is suppressed for this purpose'; end if;
  if p_candidate_id is not null and v_contact.candidate_id is distinct from p_candidate_id then raise exception 'WhatsApp Candidate linkage does not match'; end if;
  if not (select private.whatsapp_safe_flat_json(v_variables)) then
    raise exception 'WhatsApp template variables contain prohibited or unsupported fields';
  end if;
  select * into v_existing from public.whatsapp_outbound_messages where idempotency_key=pg_catalog.btrim(p_idempotency_key);
  if found then
    if v_existing.contact_id is distinct from p_contact_id or v_existing.candidate_id is distinct from p_candidate_id
      or v_existing.requirement_id is distinct from p_requirement_id or v_existing.purpose is distinct from v_purpose
      or v_existing.consent_class is distinct from v_consent or v_existing.message_type<>'template'
      or v_existing.template_name is distinct from v_template or v_existing.template_language is distinct from v_language
      or v_existing.template_version is distinct from v_version or v_existing.template_variables is distinct from v_variables
      or v_existing.destination is distinct from v_contact.provider_address or v_existing.max_attempts is distinct from p_max_attempts
      or (p_correlation_id is not null and v_existing.correlation_id is distinct from p_correlation_id) then
      raise exception 'WhatsApp outbound idempotency key conflicts with existing message';
    end if;
    return v_existing.id;
  end if;
  insert into public.whatsapp_outbound_messages(contact_id,candidate_id,requirement_id,purpose,consent_class,template_name,
    template_language,template_version,template_variables,destination,idempotency_key,correlation_id,max_attempts)
  values(p_contact_id,p_candidate_id,p_requirement_id,v_purpose,v_consent,v_template,v_language,v_version,
    v_variables,v_contact.provider_address,pg_catalog.btrim(p_idempotency_key),
    coalesce(p_correlation_id,extensions.gen_random_uuid()),p_max_attempts)
  on conflict(idempotency_key) do nothing returning id into v_id;
  if v_id is null then
    select * into v_existing from public.whatsapp_outbound_messages where idempotency_key=pg_catalog.btrim(p_idempotency_key);
    if not found or v_existing.contact_id is distinct from p_contact_id or v_existing.candidate_id is distinct from p_candidate_id
      or v_existing.requirement_id is distinct from p_requirement_id or v_existing.purpose is distinct from v_purpose
      or v_existing.consent_class is distinct from v_consent or v_existing.message_type<>'template'
      or v_existing.template_name is distinct from v_template or v_existing.template_language is distinct from v_language
      or v_existing.template_version is distinct from v_version or v_existing.template_variables is distinct from v_variables
      or v_existing.destination is distinct from v_contact.provider_address or v_existing.max_attempts is distinct from p_max_attempts
      or (p_correlation_id is not null and v_existing.correlation_id is distinct from p_correlation_id) then
      raise exception 'WhatsApp outbound idempotency key conflicts with existing message';
    end if;
    v_id:=v_existing.id;
  end if;
  return v_id;
end;
$$;

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
    where o.state='sending' and o.lease_expires_at<=pg_catalog.clock_timestamp()
      and (o.send_phase='provider_call_started' or (o.send_phase='claimed' and o.attempt_count>=o.max_attempts))
    returning o.id,o.correlation_id,o.last_error_category,o.last_error_code
  ) insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
    select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',e.id,'whatsapp',e.correlation_id,
      pg_catalog.jsonb_build_object('failure_kind',case when e.last_error_category='ambiguous_provider_outcome' then 'ambiguous' else 'exhausted' end,
        'error_category',e.last_error_category,'error_code',e.last_error_code) from expired e;
  return query with claimable as (
    select o.id from public.whatsapp_outbound_messages o
    where ((o.state='queued' and o.next_attempt_at<=pg_catalog.clock_timestamp())
      or (o.state='sending' and o.send_phase='claimed' and o.lease_expires_at<=pg_catalog.clock_timestamp()
        and o.provider_message_id is null))
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

create or replace function public.mark_whatsapp_outbound_sent(p_message_id uuid,p_worker_id text,p_provider_message_id text,p_provider_timestamp timestamptz default null)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.whatsapp_outbound_messages set provider_message_id=pg_catalog.btrim(p_provider_message_id),state='sent',send_phase='confirmed',
    sent_at=coalesce(p_provider_timestamp,pg_catalog.clock_timestamp()),lease_owner=null,lease_expires_at=null,
    last_error_category=null,last_error_code=null,updated_at=pg_catalog.clock_timestamp()
  where id=p_message_id and state='sending' and send_phase='provider_call_started' and lease_owner=pg_catalog.btrim(p_worker_id);
  if not found then raise exception 'WhatsApp send lease does not match'; end if;
  update public.whatsapp_contacts c set last_outbound_at=pg_catalog.clock_timestamp(),updated_at=pg_catalog.clock_timestamp()
    from public.whatsapp_outbound_messages o where o.id=p_message_id and c.id=o.contact_id;
  return true;
end;
$$;

create or replace function public.mark_whatsapp_outbound_failure(p_message_id uuid,p_worker_id text,p_error_category text,p_error_code text,
  p_failure_kind text,p_retry_at timestamptz default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_kind text:=pg_catalog.lower(pg_catalog.btrim(coalesce(p_failure_kind,''))); v_attempt integer; v_max integer;
begin
  if v_kind not in ('transient','permanent','ambiguous') or pg_catalog.length(coalesce(p_error_category,'')) not between 1 and 80
    or pg_catalog.length(coalesce(p_error_code,'')) not between 1 and 120 then raise exception 'Safe WhatsApp failure details are required'; end if;
  select attempt_count,max_attempts into v_attempt,v_max from public.whatsapp_outbound_messages
    where id=p_message_id and state='sending' and lease_owner=pg_catalog.btrim(p_worker_id) for update;
  if not found then raise exception 'WhatsApp send lease does not match'; end if;
  if v_kind='transient' and v_attempt<v_max and p_retry_at is not null and p_retry_at>pg_catalog.clock_timestamp() then
    update public.whatsapp_outbound_messages set state='queued',send_phase='ready',next_attempt_at=p_retry_at,lease_owner=null,lease_expires_at=null,
      last_error_category=p_error_category,last_error_code=p_error_code,updated_at=pg_catalog.clock_timestamp() where id=p_message_id;
  else
    update public.whatsapp_outbound_messages set state='failed',send_phase=case when v_kind='ambiguous' then 'reconciliation_required' else 'terminal' end,
      failed_at=pg_catalog.clock_timestamp(),lease_owner=null,lease_expires_at=null,
      last_error_category=case when v_kind='ambiguous' then 'ambiguous_provider_outcome' else p_error_category end,last_error_code=p_error_code,
      updated_at=pg_catalog.clock_timestamp() where id=p_message_id;
    insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,correlation_id,metadata)
      select 'service','whatsapp.outbound_failed','whatsapp_outbound_message',o.id,'whatsapp',o.correlation_id,
        pg_catalog.jsonb_build_object('failure_kind',v_kind,'error_category',case when v_kind='ambiguous' then 'ambiguous_provider_outcome' else p_error_category end,'error_code',p_error_code)
      from public.whatsapp_outbound_messages o where o.id=p_message_id;
  end if; return true;
end;
$$;

create or replace function public.set_whatsapp_contact_suppression(p_contact_id uuid,p_suppressed boolean,p_source text,p_reason_category text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_source text:=pg_catalog.btrim(coalesce(p_source,''));
begin
  if pg_catalog.length(v_source) not between 1 and 80 or pg_catalog.length(coalesce(p_reason_category,''))>80 then
    raise exception 'Safe WhatsApp suppression attribution is required'; end if;
  update public.whatsapp_contacts set marketing_consent_status=case when p_suppressed then 'opted_out' else 'unknown' end,
    transactional_contact_status=case when p_suppressed then 'suppressed' else transactional_contact_status end,
    opted_out_at=case when p_suppressed then pg_catalog.clock_timestamp() else null end,
    opt_out_source=case when p_suppressed then v_source else null end,
    opt_out_reason_category=case when p_suppressed then nullif(pg_catalog.btrim(p_reason_category),'') else null end,
    updated_at=pg_catalog.clock_timestamp() where id=p_contact_id;
  if not found then raise exception 'WhatsApp contact was not found'; end if;
  insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,metadata)
  values('service',case when p_suppressed then 'whatsapp.contact_suppressed' else 'whatsapp.contact_suppression_cleared' end,
    'whatsapp_contact',p_contact_id,'whatsapp',pg_catalog.jsonb_build_object('source',v_source,'reason_category',p_reason_category));
  return true;
end;
$$;

create or replace function public.list_whatsapp_recent_inbound(p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_id uuid,contact_masked text,message_type text,action_id text,processing_status text,provider_timestamp timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select m.id,m.contact_id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),m.message_type,m.action_id,m.processing_status,m.provider_timestamp
    from public.whatsapp_inbound_messages m join public.whatsapp_contacts c on c.id=m.contact_id order by m.created_at desc
    limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create or replace function public.list_whatsapp_recent_outbound(p_state text default null,p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_id uuid,contact_masked text,purpose text,state text,template_name text,attempt_count integer,created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select o.id,o.contact_id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),o.purpose,o.state,o.template_name,o.attempt_count,o.created_at
    from public.whatsapp_outbound_messages o join public.whatsapp_contacts c on c.id=o.contact_id
    where p_state is null or o.state=pg_catalog.lower(pg_catalog.btrim(p_state)) order by o.created_at desc
    limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create or replace function public.list_whatsapp_failed_outbound(p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_masked text,purpose text,error_category text,error_code text,attempt_count integer,failed_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select o.id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),o.purpose,o.last_error_category,o.last_error_code,o.attempt_count,o.failed_at
    from public.whatsapp_outbound_messages o join public.whatsapp_contacts c on c.id=o.contact_id where o.state='failed' order by o.failed_at desc
    limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;
revoke all on function private.normalize_indian_whatsapp_phone(text),
  private.apply_whatsapp_delivery_projection(uuid,text,timestamptz) from public,anon,authenticated;

revoke all on function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb),
  public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer),
  public.claim_whatsapp_outbound_batch(text,integer,integer),
  public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz),
  public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz),
  public.set_whatsapp_contact_suppression(uuid,boolean,text,text) from public,anon,authenticated;

grant execute on function public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb),
  public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer),
  public.claim_whatsapp_outbound_batch(text,integer,integer),
  public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz),
  public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz),
  public.set_whatsapp_contact_suppression(uuid,boolean,text,text) to service_role;

revoke all on function public.list_whatsapp_recent_inbound(integer,integer),
  public.list_whatsapp_recent_outbound(text,integer,integer),
  public.list_whatsapp_failed_outbound(integer,integer) from public,anon,authenticated;

grant execute on function public.list_whatsapp_recent_inbound(integer,integer),
  public.list_whatsapp_recent_outbound(text,integer,integer),
  public.list_whatsapp_failed_outbound(integer,integer) to authenticated;

commit;