-- W7A WhatsApp integration core: durable ingress, normalized messages and server-only outbox.

begin;

do $$
begin
  if to_regclass('public.candidates') is null
     or to_regclass('public.employer_requirements') is null
     or to_regclass('public.audit_logs') is null
     or to_regprocedure('extensions.gen_random_uuid()') is null
     or to_regprocedure('private.is_bootstrap_recruitment_admin()') is null
     or to_regprocedure('private.has_staff_role(text)') is null then
    raise exception 'W7A prerequisites are missing';
  end if;
  if exists(select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('whatsapp_contacts','whatsapp_webhook_events',
      'whatsapp_inbound_messages','whatsapp_outbound_messages','whatsapp_message_events')) then
    raise exception 'W7A objects already exist; inspect database state instead of re-running';
  end if;
end;
$$;

create table public.whatsapp_contacts (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'whatsapp' check (provider='whatsapp'),
  provider_address text not null check (provider_address ~ '^\+91[6-9][0-9]{9}$'),
  indian_mobile_key text not null check (indian_mobile_key ~ '^[6-9][0-9]{9}$'),
  candidate_id uuid references public.candidates(id) on delete set null,
  resolution_status text not null default 'unresolved'
    check (resolution_status in ('unresolved','resolved','ambiguous','blocked')),
  marketing_consent_status text not null default 'unknown'
    check (marketing_consent_status in ('unknown','opted_in','opted_out')),
  transactional_contact_status text not null default 'unknown'
    check (transactional_contact_status in ('unknown','allowed','suppressed')),
  consent_source text check (consent_source is null or length(consent_source) between 1 and 80),
  consent_scope text check (consent_scope is null or length(consent_scope) between 1 and 160),
  consent_recorded_at timestamptz,
  consent_policy_version text check (consent_policy_version is null or length(consent_policy_version) between 1 and 80),
  opted_out_at timestamptz,
  opt_out_source text check (opt_out_source is null or length(opt_out_source) between 1 and 80),
  opt_out_reason_category text check (opt_out_reason_category is null or length(opt_out_reason_category) between 1 and 80),
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider,provider_address),
  constraint whatsapp_contacts_address_key_match check (provider_address='+91'||indian_mobile_key),
  constraint whatsapp_contacts_resolution_check check (
    (resolution_status='resolved' and candidate_id is not null)
    or (resolution_status in ('unresolved','ambiguous','blocked') and candidate_id is null)),
  constraint whatsapp_contacts_opt_out_attribution_check check (
    (marketing_consent_status='opted_out' and opted_out_at is not null and opt_out_source is not null)
    or (marketing_consent_status<>'opted_out' and opted_out_at is null and opt_out_source is null and opt_out_reason_category is null)),
  constraint whatsapp_contacts_consent_attribution_check check (
    marketing_consent_status<>'opted_in'
    or (consent_source is not null and consent_scope is not null and consent_recorded_at is not null and consent_policy_version is not null))
);
create unique index whatsapp_contacts_whatsapp_candidate_key on public.whatsapp_contacts(candidate_id)
  where provider='whatsapp' and candidate_id is not null;
create index whatsapp_contacts_mobile_idx on public.whatsapp_contacts(indian_mobile_key);
create index whatsapp_contacts_resolution_idx on public.whatsapp_contacts(resolution_status,updated_at desc);
create index whatsapp_contacts_consent_idx on public.whatsapp_contacts(marketing_consent_status,transactional_contact_status);

create table public.whatsapp_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'whatsapp' check (provider='whatsapp'),
  provider_event_key text not null unique check (length(provider_event_key) between 1 and 240),
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  event_category text not null check (event_category in ('message','message_status','flow','verification','unknown')),
  signature_verified boolean not null check (signature_verified),
  processing_status text not null default 'accepted'
    check (processing_status in ('accepted','processing','processed','ignored','failed')),
  received_at timestamptz not null default now(),
  processing_started_at timestamptz,
  processed_at timestamptz,
  attempt_count integer not null default 0 check (attempt_count between 0 and 20),
  last_error_category text check (last_error_category is null or length(last_error_category) between 1 and 80),
  last_error_code text check (last_error_code is null or length(last_error_code) between 1 and 120),
  redacted_payload jsonb check (redacted_payload is null or
    (jsonb_typeof(redacted_payload)='object' and pg_catalog.octet_length(redacted_payload::text)<=65536)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index whatsapp_webhook_events_processing_idx on public.whatsapp_webhook_events(processing_status,received_at);
create index whatsapp_webhook_events_category_idx on public.whatsapp_webhook_events(event_category,received_at desc);
create index whatsapp_webhook_events_hash_idx on public.whatsapp_webhook_events(payload_sha256);

create table public.whatsapp_inbound_messages (
  id uuid primary key default gen_random_uuid(),
  webhook_event_id uuid not null references public.whatsapp_webhook_events(id) on delete restrict,
  contact_id uuid not null references public.whatsapp_contacts(id) on delete restrict,
  provider_message_id text not null unique check (length(provider_message_id) between 1 and 240),
  provider_timestamp timestamptz,
  message_type text not null check (message_type in ('text','button','list','flow','unsupported','unknown')),
  safe_text text check (safe_text is null or length(safe_text)<=2000),
  action_id text check (action_id is null or length(action_id)<=200),
  correlation_key text check (correlation_key is null or length(correlation_key)<=240),
  redacted_response jsonb check (redacted_response is null or
    (jsonb_typeof(redacted_response)='object' and pg_catalog.octet_length(redacted_response::text)<=16384)),
  processing_status text not null default 'received'
    check (processing_status in ('received','normalized','ignored','failed')),
  last_error_category text check (last_error_category is null or length(last_error_category)<=80),
  last_error_code text check (last_error_code is null or length(last_error_code)<=120),
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index whatsapp_inbound_contact_idx on public.whatsapp_inbound_messages(contact_id,created_at desc);
create index whatsapp_inbound_webhook_idx on public.whatsapp_inbound_messages(webhook_event_id);
create index whatsapp_inbound_processing_idx on public.whatsapp_inbound_messages(processing_status,created_at);

create table public.whatsapp_outbound_messages (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.whatsapp_contacts(id) on delete restrict,
  candidate_id uuid references public.candidates(id) on delete set null,
  requirement_id uuid references public.employer_requirements(id) on delete set null,
  purpose text not null check (length(purpose) between 1 and 80),
  consent_class text not null check (consent_class in ('marketing','transactional')),
  message_type text not null default 'template' check (message_type='template'),
  template_name text not null check (pg_catalog.char_length(template_name) between 1 and 512 and template_name ~ '^[a-z0-9_]+$'),
  template_language text not null check (template_language ~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'),
  template_version text not null check (length(template_version) between 1 and 80),
  template_variables jsonb not null default '{}'::jsonb
    check (jsonb_typeof(template_variables)='object' and pg_catalog.octet_length(template_variables::text)<=16384),
  destination text not null check (destination ~ '^\+91[6-9][0-9]{9}$'),
  idempotency_key text not null unique check (length(idempotency_key) between 1 and 240),
  provider_message_id text unique check (provider_message_id is null or length(provider_message_id) between 1 and 240),
  state text not null default 'queued' check (state in ('queued','sending','sent','delivered','read','failed')),
  send_phase text not null default 'ready'
    check (send_phase in ('ready','claimed','provider_call_started','confirmed','terminal','reconciliation_required')),
  attempt_count integer not null default 0 check (attempt_count between 0 and 10),
  max_attempts integer not null default 3 check (max_attempts between 1 and 10),
  next_attempt_at timestamptz not null default now(),
  lease_owner text check (lease_owner is null or length(lease_owner) between 1 and 160),
  lease_expires_at timestamptz,
  last_error_category text check (last_error_category is null or length(last_error_category)<=80),
  last_error_code text check (last_error_code is null or length(last_error_code)<=120),
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,
  correlation_id uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint whatsapp_outbound_lease_pair_check check ((lease_owner is null)=(lease_expires_at is null)),
  constraint whatsapp_outbound_phase_state_check check (
    (state='queued' and send_phase='ready' and lease_owner is null)
    or (state='sending' and send_phase in ('claimed','provider_call_started') and lease_owner is not null)
    or (state in ('sent','delivered','read') and send_phase='confirmed' and lease_owner is null)
    or (state='failed' and send_phase in ('terminal','reconciliation_required') and lease_owner is null)),
  constraint whatsapp_outbound_attempt_check check (attempt_count<=max_attempts),
  constraint whatsapp_outbound_provider_state_check check
    (state not in ('sent','delivered','read') or provider_message_id is not null),
  constraint whatsapp_outbound_timestamp_check check
    ((state<>'delivered' and state<>'read') or delivered_at is not null)
);
create index whatsapp_outbound_claim_idx on public.whatsapp_outbound_messages(state,next_attempt_at,created_at)
  where state in ('queued','sending');
create index whatsapp_outbound_lease_idx on public.whatsapp_outbound_messages(lease_expires_at)
  where state='sending';
create index whatsapp_outbound_contact_idx on public.whatsapp_outbound_messages(contact_id,created_at desc);
create index whatsapp_outbound_candidate_idx on public.whatsapp_outbound_messages(candidate_id,created_at desc) where candidate_id is not null;
create index whatsapp_outbound_requirement_idx on public.whatsapp_outbound_messages(requirement_id,created_at desc) where requirement_id is not null;
create index whatsapp_outbound_failed_idx on public.whatsapp_outbound_messages(failed_at desc) where state='failed';
create index whatsapp_outbound_correlation_idx on public.whatsapp_outbound_messages(correlation_id);

create table public.whatsapp_message_events (
  id uuid primary key default gen_random_uuid(),
  outbound_message_id uuid not null references public.whatsapp_outbound_messages(id) on delete restrict,
  webhook_event_id uuid not null references public.whatsapp_webhook_events(id) on delete restrict,
  provider_event_key text not null unique check (length(provider_event_key) between 1 and 240),
  provider_message_id text not null check (length(provider_message_id) between 1 and 240),
  status text not null check (status in ('accepted','sent','delivered','read','failed')),
  provider_timestamp timestamptz,
  payload_sha256 text not null check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  provider_error_category text check (provider_error_category is null or length(provider_error_category)<=80),
  provider_error_code text check (provider_error_code is null or length(provider_error_code)<=120),
  created_at timestamptz not null default now()
);
create index whatsapp_message_events_outbound_idx on public.whatsapp_message_events(outbound_message_id,created_at);
create index whatsapp_message_events_provider_message_idx on public.whatsapp_message_events(provider_message_id,provider_timestamp);
create index whatsapp_message_events_status_idx on public.whatsapp_message_events(status,created_at desc);

create function private.sync_whatsapp_contact_candidate_detach()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.candidate_id is not null and new.candidate_id is null and old.resolution_status='resolved' then
    new.resolution_status:='unresolved';
    new.updated_at:=pg_catalog.clock_timestamp();
  end if;
  return new;
end;
$$;
create trigger whatsapp_contacts_candidate_detach before update of candidate_id on public.whatsapp_contacts
  for each row execute function private.sync_whatsapp_contact_candidate_detach();

create function private.whatsapp_safe_flat_json(p_value jsonb)
returns boolean language plpgsql immutable security definer set search_path = '' as $$
declare v_key text; v_item jsonb; v_normalized_key text; v_count integer:=0;
begin
  if p_value is null then return true; end if;
  if pg_catalog.jsonb_typeof(p_value)<>'object' or pg_catalog.octet_length(p_value::text)>16384 then return false; end if;
  for v_key,v_item in select e.key,e.value from pg_catalog.jsonb_each(p_value) e loop
    v_count:=v_count+1;
    if v_count>50 or pg_catalog.char_length(v_key) not between 1 and 80 then return false; end if;
    v_normalized_key:=pg_catalog.lower(pg_catalog.regexp_replace(v_key,'[^a-zA-Z0-9]','','g'));
    if v_normalized_key in ('aadhaar','aadhar','aadhaarnumber','aadharnumber','aadhaarfingerprint','aadharfingerprint',
      'bankaccount','bankaccountnumber','bankdetails','accountnumber','accountno','uan','uannumber','esic','esicnumber','esicip',
      'documenturl','documenturi','documentpath','documentcontent','fileurl','storagepath','storageobject','signedurl',
      'accesstoken','token','servicerolekey','appsecret','clientsecret','secret') then return false; end if;
    if pg_catalog.jsonb_typeof(v_item) not in ('string','number','boolean','null') then return false; end if;
    if pg_catalog.jsonb_typeof(v_item)='string' and pg_catalog.char_length(v_item #>> '{}')>500 then return false; end if;
  end loop;
  return true;
end;
$$;

create function private.normalize_indian_whatsapp_phone(p_value text)
returns table(indian_mobile_key text,provider_address text)
language plpgsql immutable security definer set search_path = '' as $$
declare v_input text:=pg_catalog.btrim(pg_catalog.coalesce(p_value,'')); v_compact text; v_digits text;
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

create function private.can_admin_whatsapp()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'));
$$;

create function private.whatsapp_contact_allows_purpose(p_contact_id uuid,p_consent_class text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.whatsapp_contacts c where c.id=p_contact_id
    and c.resolution_status<>'blocked'
    and ((p_consent_class='marketing' and c.marketing_consent_status='opted_in')
      or (p_consent_class='transactional' and c.transactional_contact_status='allowed')));
$$;

create function private.apply_whatsapp_delivery_projection(p_outbound_message_id uuid,p_status text,p_provider_timestamp timestamptz)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text:=pg_catalog.lower(pg_catalog.btrim(pg_catalog.coalesce(p_status,''))); v_now timestamptz:=pg_catalog.coalesce(p_provider_timestamp,pg_catalog.clock_timestamp());
begin
  if v_status in ('accepted','sent') then
    update public.whatsapp_outbound_messages set state='sent',send_phase='confirmed',sent_at=pg_catalog.coalesce(sent_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent');
  elsif v_status='delivered' then
    update public.whatsapp_outbound_messages set state='delivered',send_phase='confirmed',sent_at=pg_catalog.coalesce(sent_at,v_now),delivered_at=pg_catalog.coalesce(delivered_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent','delivered','failed');
  elsif v_status='read' then
    update public.whatsapp_outbound_messages set state='read',send_phase='confirmed',sent_at=pg_catalog.coalesce(sent_at,v_now),delivered_at=pg_catalog.coalesce(delivered_at,v_now),read_at=pg_catalog.coalesce(read_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state<>'read';
  elsif v_status='failed' then
    update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=pg_catalog.coalesce(failed_at,v_now),lease_owner=null,lease_expires_at=null,updated_at=pg_catalog.clock_timestamp()
      where id=p_outbound_message_id and state in ('queued','sending','sent');
  else raise exception 'Unsupported WhatsApp delivery status'; end if;
end;
$$;

create function public.accept_whatsapp_webhook_event(p_provider_event_key text,p_payload_sha256 text,p_event_category text,p_redacted_payload jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not (select private.whatsapp_safe_flat_json(p_redacted_payload)) then
    raise exception 'WhatsApp webhook metadata contains prohibited or unsupported fields';
  end if;
  insert into public.whatsapp_webhook_events(provider_event_key,payload_sha256,event_category,signature_verified,redacted_payload)
  values(pg_catalog.btrim(p_provider_event_key),pg_catalog.lower(pg_catalog.btrim(p_payload_sha256)),pg_catalog.lower(pg_catalog.btrim(p_event_category)),true,p_redacted_payload)
  on conflict(provider_event_key) do update set provider_event_key=excluded.provider_event_key
    where whatsapp_webhook_events.payload_sha256=excluded.payload_sha256
      and whatsapp_webhook_events.event_category=excluded.event_category
  returning id into v_id;
  if v_id is null then raise exception 'WhatsApp webhook idempotency key conflicts with existing event'; end if;
  return v_id;
end;
$$;

create function public.upsert_whatsapp_inbound_contact(p_phone text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_key text; v_address text; v_candidate uuid; v_count integer; v_id uuid;
begin
  select n.indian_mobile_key,n.provider_address into v_key,v_address from private.normalize_indian_whatsapp_phone(p_phone) n;
  select pg_catalog.count(*) into v_count from public.candidates c
    where c.mobile=v_key and c.profile_status='active' and c.status<>'inactive';
  if v_count=1 then
    select c.id into v_candidate from public.candidates c
      where c.mobile=v_key and c.profile_status='active' and c.status<>'inactive';
  end if;
  insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,last_inbound_at)
  values(v_address,v_key,case when v_count=1 then v_candidate else null end,
    case when v_count=1 then 'resolved' when v_count>1 then 'ambiguous' else 'unresolved' end,pg_catalog.clock_timestamp())
  on conflict(provider,provider_address) do update set last_inbound_at=excluded.last_inbound_at,
    candidate_id=case when whatsapp_contacts.resolution_status='blocked' then null else excluded.candidate_id end,
    resolution_status=case when whatsapp_contacts.resolution_status='blocked' then 'blocked' else excluded.resolution_status end,
    updated_at=pg_catalog.clock_timestamp() returning id into v_id; return v_id;
end;
$$;

create function public.record_whatsapp_inbound_message(p_webhook_event_id uuid,p_contact_id uuid,p_provider_message_id text,
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
  update public.whatsapp_contacts set last_inbound_at=pg_catalog.greatest(pg_catalog.coalesce(last_inbound_at,'-infinity'::timestamptz),
    pg_catalog.coalesce(p_provider_timestamp,pg_catalog.clock_timestamp())),updated_at=pg_catalog.clock_timestamp() where id=p_contact_id;
  return v_id;
end;
$$;

create function public.enqueue_whatsapp_outbound_message(p_contact_id uuid,p_candidate_id uuid,p_requirement_id uuid,p_purpose text,
  p_consent_class text,p_template_name text,p_template_language text,p_template_version text,p_template_variables jsonb,
  p_idempotency_key text,p_correlation_id uuid default null,p_max_attempts integer default 3)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_contact public.whatsapp_contacts%rowtype; v_existing public.whatsapp_outbound_messages%rowtype; v_id uuid;
  v_purpose text:=pg_catalog.btrim(p_purpose); v_consent text:=pg_catalog.lower(pg_catalog.btrim(p_consent_class));
  v_template text:=pg_catalog.lower(pg_catalog.btrim(p_template_name)); v_language text:=pg_catalog.btrim(p_template_language);
  v_version text:=pg_catalog.btrim(p_template_version); v_variables jsonb:=pg_catalog.coalesce(p_template_variables,'{}'::jsonb);
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
    pg_catalog.coalesce(p_correlation_id,extensions.gen_random_uuid()),p_max_attempts)
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

create function public.claim_whatsapp_outbound_batch(p_worker_id text,p_batch_size integer default 25,p_lease_seconds integer default 60)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,
  purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path = '' as $$
declare v_worker text:=pg_catalog.btrim(pg_catalog.coalesce(p_worker_id,'')); v_batch integer:=pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_batch_size,25),1),100);
  v_lease integer:=pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_lease_seconds,60),15),900);
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

create function public.mark_whatsapp_provider_call_started(p_message_id uuid,p_worker_id text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.whatsapp_outbound_messages set send_phase='provider_call_started',updated_at=pg_catalog.clock_timestamp()
    where id=p_message_id and state='sending' and send_phase='claimed' and lease_owner=pg_catalog.btrim(p_worker_id)
      and lease_expires_at>pg_catalog.clock_timestamp();
  if not found then raise exception 'WhatsApp send lease is not ready for provider invocation'; end if;
  return true;
end;
$$;

create function public.mark_whatsapp_outbound_sent(p_message_id uuid,p_worker_id text,p_provider_message_id text,p_provider_timestamp timestamptz default null)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  update public.whatsapp_outbound_messages set provider_message_id=pg_catalog.btrim(p_provider_message_id),state='sent',send_phase='confirmed',
    sent_at=pg_catalog.coalesce(p_provider_timestamp,pg_catalog.clock_timestamp()),lease_owner=null,lease_expires_at=null,
    last_error_category=null,last_error_code=null,updated_at=pg_catalog.clock_timestamp()
  where id=p_message_id and state='sending' and send_phase='provider_call_started' and lease_owner=pg_catalog.btrim(p_worker_id);
  if not found then raise exception 'WhatsApp send lease does not match'; end if;
  update public.whatsapp_contacts c set last_outbound_at=pg_catalog.clock_timestamp(),updated_at=pg_catalog.clock_timestamp()
    from public.whatsapp_outbound_messages o where o.id=p_message_id and c.id=o.contact_id;
  return true;
end;
$$;

create function public.mark_whatsapp_outbound_failure(p_message_id uuid,p_worker_id text,p_error_category text,p_error_code text,
  p_failure_kind text,p_retry_at timestamptz default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_kind text:=pg_catalog.lower(pg_catalog.btrim(pg_catalog.coalesce(p_failure_kind,''))); v_attempt integer; v_max integer;
begin
  if v_kind not in ('transient','permanent','ambiguous') or pg_catalog.length(pg_catalog.coalesce(p_error_category,'')) not between 1 and 80
    or pg_catalog.length(pg_catalog.coalesce(p_error_code,'')) not between 1 and 120 then raise exception 'Safe WhatsApp failure details are required'; end if;
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

create function public.record_whatsapp_message_event(p_outbound_message_id uuid,p_webhook_event_id uuid,p_provider_event_key text,
  p_provider_message_id text,p_status text,p_provider_timestamp timestamptz,p_payload_sha256 text,
  p_provider_error_category text default null,p_provider_error_code text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not exists(select 1 from public.whatsapp_outbound_messages o where o.id=p_outbound_message_id
      and o.provider_message_id=p_provider_message_id) then
    raise exception 'WhatsApp provider message linkage does not match';
  end if;
  insert into public.whatsapp_message_events(outbound_message_id,webhook_event_id,provider_event_key,provider_message_id,status,
    provider_timestamp,payload_sha256,provider_error_category,provider_error_code)
  values(p_outbound_message_id,p_webhook_event_id,pg_catalog.btrim(p_provider_event_key),pg_catalog.btrim(p_provider_message_id),
    pg_catalog.lower(pg_catalog.btrim(p_status)),p_provider_timestamp,pg_catalog.lower(pg_catalog.btrim(p_payload_sha256)),
    p_provider_error_category,p_provider_error_code)
  on conflict(provider_event_key) do update set provider_event_key=excluded.provider_event_key
    where whatsapp_message_events.outbound_message_id=excluded.outbound_message_id
      and whatsapp_message_events.webhook_event_id=excluded.webhook_event_id
      and whatsapp_message_events.provider_message_id=excluded.provider_message_id
      and whatsapp_message_events.status=excluded.status
      and whatsapp_message_events.payload_sha256=excluded.payload_sha256
  returning id into v_id;
  if v_id is null then raise exception 'WhatsApp status idempotency key conflicts with existing event'; end if;
  perform private.apply_whatsapp_delivery_projection(p_outbound_message_id,p_status,p_provider_timestamp); return v_id;
end;
$$;

create function public.set_whatsapp_contact_suppression(p_contact_id uuid,p_suppressed boolean,p_source text,p_reason_category text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_source text:=pg_catalog.btrim(pg_catalog.coalesce(p_source,''));
begin
  if pg_catalog.length(v_source) not between 1 and 80 or pg_catalog.length(pg_catalog.coalesce(p_reason_category,''))>80 then
    raise exception 'Safe WhatsApp suppression attribution is required'; end if;
  update public.whatsapp_contacts set marketing_consent_status=case when p_suppressed then 'opted_out' else 'unknown' end,
    transactional_contact_status=case when p_suppressed then 'suppressed' else transactional_contact_status end,
    opted_out_at=case when p_suppressed then pg_catalog.clock_timestamp() else null end,
    opt_out_source=case when p_suppressed then v_source else null end,
    opt_out_reason_category=case when p_suppressed then pg_catalog.nullif(pg_catalog.btrim(p_reason_category),'') else null end,
    updated_at=pg_catalog.clock_timestamp() where id=p_contact_id;
  if not found then raise exception 'WhatsApp contact was not found'; end if;
  insert into public.audit_logs(actor_type,action,entity_type,entity_id,source,metadata)
  values('service',case when p_suppressed then 'whatsapp.contact_suppressed' else 'whatsapp.contact_suppression_cleared' end,
    'whatsapp_contact',p_contact_id,'whatsapp',pg_catalog.jsonb_build_object('source',v_source,'reason_category',p_reason_category));
  return true;
end;
$$;

create function public.get_whatsapp_core_health()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return pg_catalog.jsonb_build_object('contacts',(select pg_catalog.count(*) from public.whatsapp_contacts),
    'accepted_webhooks',(select pg_catalog.count(*) from public.whatsapp_webhook_events where processing_status='accepted'),
    'queued',(select pg_catalog.count(*) from public.whatsapp_outbound_messages where state='queued'),
    'failed',(select pg_catalog.count(*) from public.whatsapp_outbound_messages where state='failed'));
end;
$$;

create function public.list_whatsapp_recent_inbound(p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_id uuid,contact_masked text,message_type text,action_id text,processing_status text,provider_timestamp timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select m.id,m.contact_id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),m.message_type,m.action_id,m.processing_status,m.provider_timestamp
    from public.whatsapp_inbound_messages m join public.whatsapp_contacts c on c.id=m.contact_id order by m.created_at desc
    limit pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_limit,50),1),100) offset pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_offset,0),0),5000);
end;
$$;

create function public.list_whatsapp_recent_outbound(p_state text default null,p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_id uuid,contact_masked text,purpose text,state text,template_name text,attempt_count integer,created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select o.id,o.contact_id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),o.purpose,o.state,o.template_name,o.attempt_count,o.created_at
    from public.whatsapp_outbound_messages o join public.whatsapp_contacts c on c.id=o.contact_id
    where p_state is null or o.state=pg_catalog.lower(pg_catalog.btrim(p_state)) order by o.created_at desc
    limit pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_limit,50),1),100) offset pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_offset,0),0),5000);
end;
$$;

create function public.list_whatsapp_failed_outbound(p_limit integer default 50,p_offset integer default 0)
returns table(message_id uuid,contact_masked text,purpose text,error_category text,error_code text,attempt_count integer,failed_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select o.id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),o.purpose,o.last_error_category,o.last_error_code,o.attempt_count,o.failed_at
    from public.whatsapp_outbound_messages o join public.whatsapp_contacts c on c.id=o.contact_id where o.state='failed' order by o.failed_at desc
    limit pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_limit,50),1),100) offset pg_catalog.least(pg_catalog.greatest(pg_catalog.coalesce(p_offset,0),0),5000);
end;
$$;

create function public.get_whatsapp_contact_communication_status(p_contact_id uuid)
returns table(contact_id uuid,contact_masked text,resolution_status text,marketing_consent_status text,transactional_contact_status text,
  last_inbound_at timestamptz,last_outbound_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_admin_whatsapp()) then raise exception 'WhatsApp Admin access is required'; end if;
  return query select c.id,'+91XXXXXX'||pg_catalog.right(c.indian_mobile_key,4),c.resolution_status,c.marketing_consent_status,
    c.transactional_contact_status,c.last_inbound_at,c.last_outbound_at from public.whatsapp_contacts c where c.id=p_contact_id;
end;
$$;

alter table public.whatsapp_contacts enable row level security;
alter table public.whatsapp_webhook_events enable row level security;
alter table public.whatsapp_inbound_messages enable row level security;
alter table public.whatsapp_outbound_messages enable row level security;
alter table public.whatsapp_message_events enable row level security;

revoke all on table public.whatsapp_contacts from public,anon,authenticated;
revoke all on table public.whatsapp_webhook_events from public,anon,authenticated;
revoke all on table public.whatsapp_inbound_messages from public,anon,authenticated;
revoke all on table public.whatsapp_outbound_messages from public,anon,authenticated;
revoke all on table public.whatsapp_message_events from public,anon,authenticated;
revoke update,delete on table public.whatsapp_message_events from service_role;

revoke all on function private.sync_whatsapp_contact_candidate_detach(),private.whatsapp_safe_flat_json(jsonb),
  private.normalize_indian_whatsapp_phone(text),private.can_admin_whatsapp(),
  private.whatsapp_contact_allows_purpose(uuid,text),private.apply_whatsapp_delivery_projection(uuid,text,timestamptz)
  from public,anon,authenticated;

revoke all on function public.accept_whatsapp_webhook_event(text,text,text,jsonb),public.upsert_whatsapp_inbound_contact(text),
  public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb),
  public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer),
  public.claim_whatsapp_outbound_batch(text,integer,integer),public.mark_whatsapp_provider_call_started(uuid,text),
  public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz),
  public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz),
  public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text),
  public.set_whatsapp_contact_suppression(uuid,boolean,text,text) from public,anon,authenticated;

grant execute on function public.accept_whatsapp_webhook_event(text,text,text,jsonb),public.upsert_whatsapp_inbound_contact(text),
  public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb),
  public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer),
  public.claim_whatsapp_outbound_batch(text,integer,integer),public.mark_whatsapp_provider_call_started(uuid,text),
  public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz),
  public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz),
  public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text),
  public.set_whatsapp_contact_suppression(uuid,boolean,text,text) to service_role;

revoke all on function public.get_whatsapp_core_health(),public.list_whatsapp_recent_inbound(integer,integer),
  public.list_whatsapp_recent_outbound(text,integer,integer),public.list_whatsapp_failed_outbound(integer,integer),
  public.get_whatsapp_contact_communication_status(uuid) from public,anon,authenticated;
grant execute on function public.get_whatsapp_core_health(),public.list_whatsapp_recent_inbound(integer,integer),
  public.list_whatsapp_recent_outbound(text,integer,integer),public.list_whatsapp_failed_outbound(integer,integer),
  public.get_whatsapp_contact_communication_status(uuid) to authenticated;

commit;
