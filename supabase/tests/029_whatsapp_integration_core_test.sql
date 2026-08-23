-- W7A WhatsApp integration core checkpoint. Synthetic fixtures only; one transaction, zero residue.
\set ON_ERROR_STOP on
begin;

do $$
declare v_tables text[]:=array['whatsapp_contacts','whatsapp_webhook_events','whatsapp_inbound_messages','whatsapp_outbound_messages','whatsapp_message_events']; v_table text;
begin
  if (select count(*) from information_schema.tables where table_schema='public' and table_name=any(v_tables))<>5 then
    raise exception 'W7A exact five-table contract is incomplete';
  end if;
  if exists(select 1 from information_schema.tables where table_schema='public' and table_name like 'whatsapp_%'
    and table_name not in ('whatsapp_contacts','whatsapp_webhook_events','whatsapp_inbound_messages','whatsapp_outbound_messages','whatsapp_message_events')) then
    raise exception 'Unexpected W7A WhatsApp table exists';
  end if;
  foreach v_table in array v_tables loop
    if not exists(select 1 from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relrowsecurity) then raise exception 'RLS is not enabled on %',v_table; end if;
    if exists(select 1 from information_schema.role_table_grants g where g.table_schema='public' and g.table_name=v_table
      and g.grantee in ('PUBLIC','anon','authenticated')) then raise exception 'Browser table grant exists on %',v_table; end if;
  end loop;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_contacts'
      and column_name in ('provider_address','indian_mobile_key','candidate_id','resolution_status','marketing_consent_status',
        'transactional_contact_status','consent_source','consent_scope','consent_recorded_at','consent_policy_version','opted_out_at','opt_out_source'))<>12
    or (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_webhook_events'
      and column_name in ('provider_event_key','payload_sha256','event_category','signature_verified','processing_status','redacted_payload'))<>6
    or (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_inbound_messages'
      and column_name in ('webhook_event_id','contact_id','provider_message_id','message_type','safe_text','action_id','correlation_key','redacted_response'))<>8
    or (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_outbound_messages'
      and column_name in ('contact_id','candidate_id','requirement_id','consent_class','template_variables','idempotency_key','provider_message_id',
        'state','attempt_count','max_attempts','next_attempt_at','lease_owner','lease_expires_at','correlation_id'))<>14
    or (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_message_events'
      and column_name in ('outbound_message_id','webhook_event_id','provider_event_key','provider_message_id','status','payload_sha256'))<>6 then
    raise exception 'W7A expected column contract is incomplete';
  end if;
  if (select count(*) from pg_catalog.pg_indexes where schemaname='public' and tablename like 'whatsapp_%')<20 then
    raise exception 'W7A justified index contract is incomplete';
  end if;
end;
$$;

do $$
declare v_reg regprocedure; v_name text;
begin
  foreach v_name in array array[
    'private.normalize_indian_whatsapp_phone(text)','private.can_admin_whatsapp()',
    'private.whatsapp_contact_allows_purpose(uuid,text)','private.apply_whatsapp_delivery_projection(uuid,text,timestamptz)'] loop
    v_reg:=to_regprocedure(v_name); if v_reg is null then raise exception 'Missing helper %',v_name; end if;
    if pg_get_functiondef(v_reg) not ilike '%security definer%' or pg_get_functiondef(v_reg) not ilike '%set search_path to ''''%' then
      raise exception 'Helper security posture failed for %',v_name; end if;
    if has_function_privilege('anon',v_reg,'execute') or has_function_privilege('authenticated',v_reg,'execute') then
      raise exception 'Browser helper execution exists for %',v_name; end if;
  end loop;
  foreach v_name in array array[
    'public.accept_whatsapp_webhook_event(text,text,text,jsonb)','public.upsert_whatsapp_inbound_contact(text)',
    'public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)',
    'public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)',
    'public.claim_whatsapp_outbound_batch(text,integer,integer)','public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz)',
    'public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz)',
    'public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text)',
    'public.set_whatsapp_contact_suppression(uuid,boolean,text,text)'] loop
    v_reg:=to_regprocedure(v_name); if v_reg is null then raise exception 'Missing server RPC %',v_name; end if;
    if has_function_privilege('anon',v_reg,'execute') or has_function_privilege('authenticated',v_reg,'execute')
       or not has_function_privilege('service_role',v_reg,'execute') then raise exception 'Server RPC grant boundary failed for %',v_name; end if;
    if pg_get_functiondef(v_reg) not ilike '%security definer%' or pg_get_functiondef(v_reg) not ilike '%set search_path to ''''%' then
      raise exception 'Server RPC security posture failed for %',v_name; end if;
  end loop;
  if pg_get_functiondef('public.claim_whatsapp_outbound_batch(text,integer,integer)'::regprocedure) not ilike '%for update skip locked%'
     or pg_get_functiondef('public.claim_whatsapp_outbound_batch(text,integer,integer)'::regprocedure) not ilike '%least%100%'
     or pg_get_functiondef('public.claim_whatsapp_outbound_batch(text,integer,integer)'::regprocedure) not ilike '%last_error_category is distinct from ''ambiguous''%' then
    raise exception 'Outbox claim locking, bounding or ambiguity contract is missing';
  end if;
  if pg_get_functiondef('private.apply_whatsapp_delivery_projection(uuid,text,timestamptz)'::regprocedure) ilike '%execute %'
     or pg_get_functiondef('public.record_whatsapp_message_event(uuid,uuid,text,text,text,timestamptz,text,text,text)'::regprocedure) ilike '%execute %' then
    raise exception 'Dynamic SQL is prohibited in delivery processing';
  end if;
end;
$$;

-- Exact phone normalization contract.
do $$ declare v_key text; v_address text;
begin
  select indian_mobile_key,provider_address into v_key,v_address from private.normalize_indian_whatsapp_phone('+91 98765 43210');
  if v_key<>'9876543210' or v_address<>'+919876543210' then raise exception 'Indian phone normalization failed'; end if;
  select indian_mobile_key,provider_address into v_key,v_address from private.normalize_indian_whatsapp_phone('919876543210');
  if v_key<>'9876543210' then raise exception '91-prefixed phone normalization failed'; end if;
  begin perform private.normalize_indian_whatsapp_phone('1234567890'); raise exception 'Invalid Indian mobile accepted';
  exception when raise_exception then if sqlerrm='Invalid Indian mobile accepted' then raise; end if; end;
end;
$$;

-- Synthetic authorization fixtures.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89300000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-admin@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-recruiter@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-operations@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-candidate@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-company@test.local','x','{}','{}',now(),now()),
('89300000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-contractor@test.local','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('89300000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values
('89300000-0000-0000-0000-000000000002','W7A Recruiter','active'),('89300000-0000-0000-0000-000000000003','W7A Operations','active');
insert into public.staff_roles(user_id,role,status,granted_by) values
('89300000-0000-0000-0000-000000000002','recruiter','active','89300000-0000-0000-0000-000000000001'),
('89300000-0000-0000-0000-000000000003','operations','active','89300000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('89300000-0000-0000-0000-000000000004','candidate','W7A Candidate','w7a-candidate@test.local','active'),
('89300000-0000-0000-0000-000000000005','company','W7A Company','w7a-company@test.local','active'),
('89300000-0000-0000-0000-000000000006','contractor','W7A Contractor','w7a-contractor@test.local','active');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,
  interview_available,consent,status,user_id,profile_status,profile_completion_status) values
('89300000-0000-0000-0001-000000000001','W7A Candidate',25,'Female','9876543210','Chennai','Chennai','Tamil Nadu','ITI','Fresher','Yes',true,'new','89300000-0000-0000-0000-000000000004','active','complete'),
('89300000-0000-0000-0001-000000000002','W7A Ambiguous One',26,'Male','9876543211','Pune','Pune','Maharashtra','Diploma','Experienced','Yes',true,'new',null,'active','complete'),
('89300000-0000-0000-0001-000000000003','W7A Ambiguous Two',27,'Female','9876543211','Pune','Pune','Maharashtra','Graduate','Experienced','Yes',true,'new',null,'active','complete');

-- Server ingress/contact/message dedupe.
set local role service_role;
select set_config('w7a.contact',public.upsert_whatsapp_inbound_contact('+91 98765 43210')::text,true);
select set_config('w7a.contact.duplicate',public.upsert_whatsapp_inbound_contact('919876543210')::text,true);
select set_config('w7a.contact.ambiguous',public.upsert_whatsapp_inbound_contact('9876543211')::text,true);
select set_config('w7a.webhook.message',public.accept_whatsapp_webhook_event('message:wamid.w7a.1',repeat('a',64),'message','{"message_type":"text"}'::jsonb)::text,true);
select set_config('w7a.webhook.message.duplicate',public.accept_whatsapp_webhook_event('message:wamid.w7a.1',repeat('a',64),'message','{"message_type":"text"}'::jsonb)::text,true);
select set_config('w7a.inbound',public.record_whatsapp_inbound_message(current_setting('w7a.webhook.message')::uuid,current_setting('w7a.contact')::uuid,
  'wamid.w7a.1',now(),'text','Synthetic hello',null,null,null)::text,true);
select set_config('w7a.inbound.duplicate',public.record_whatsapp_inbound_message(current_setting('w7a.webhook.message')::uuid,current_setting('w7a.contact')::uuid,
  'wamid.w7a.1',now(),'text','Synthetic hello',null,null,null)::text,true);
do $$ begin
  if current_setting('w7a.contact')<>current_setting('w7a.contact.duplicate') then raise exception 'Contact dedupe failed'; end if;
  if current_setting('w7a.webhook.message')<>current_setting('w7a.webhook.message.duplicate') then raise exception 'Webhook dedupe failed'; end if;
  if current_setting('w7a.inbound')<>current_setting('w7a.inbound.duplicate') then raise exception 'Inbound dedupe failed'; end if;
  if (select c.resolution_status from public.whatsapp_contacts c where c.id=current_setting('w7a.contact')::uuid)<>'resolved'
     or (select c.candidate_id from public.whatsapp_contacts c where c.id=current_setting('w7a.contact')::uuid)<>'89300000-0000-0000-0001-000000000001' then
    raise exception 'Unique Candidate contact resolution failed'; end if;
  if (select c.resolution_status from public.whatsapp_contacts c where c.id=current_setting('w7a.contact.ambiguous')::uuid)<>'ambiguous'
     or (select c.candidate_id from public.whatsapp_contacts c where c.id=current_setting('w7a.contact.ambiguous')::uuid) is not null then
    raise exception 'Ambiguous Candidate phone did not fail closed'; end if;
end $$;
reset role;

-- Establish explicit consent without using a browser grant.
update public.whatsapp_contacts set marketing_consent_status='opted_in',transactional_contact_status='allowed',
  consent_source='synthetic_test',consent_scope='marketing_and_transactional',consent_recorded_at=now(),consent_policy_version='w7a-test-1'
  where id=current_setting('w7a.contact')::uuid;

set local role service_role;
select set_config('w7a.outbound',public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,
  '89300000-0000-0000-0001-000000000001',null,'core_test','marketing','w7a_test_template','en','1','{"role":"Synthetic"}'::jsonb,'w7a-outbound-1',null,3)::text,true);
select set_config('w7a.outbound.duplicate',public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,
  '89300000-0000-0000-0001-000000000001',null,'core_test','marketing','w7a_test_template','en','1','{"role":"Synthetic"}'::jsonb,'w7a-outbound-1',null,3)::text,true);
do $$ declare r record;
begin
  if current_setting('w7a.outbound')<>current_setting('w7a.outbound.duplicate') then raise exception 'Outbound idempotency failed'; end if;
  select * into r from public.claim_whatsapp_outbound_batch('worker-w7a',1000,1);
  if r.message_id is distinct from current_setting('w7a.outbound')::uuid or r.attempt_count<>1 then raise exception 'Atomic bounded claim failed'; end if;
  begin perform public.mark_whatsapp_outbound_sent(r.message_id,'wrong-worker','wamid.outbound.1',now()); raise exception 'Wrong lease owner finalized send';
  exception when raise_exception then if sqlerrm='Wrong lease owner finalized send' then raise; end if; end;
  perform public.mark_whatsapp_outbound_sent(r.message_id,'worker-w7a','wamid.outbound.1',now());
end $$;

select set_config('w7a.webhook.read',public.accept_whatsapp_webhook_event('status:wamid.outbound.1:read:1',repeat('b',64),'message_status','{"status":"read"}'::jsonb)::text,true);
select set_config('w7a.event.read',public.record_whatsapp_message_event(current_setting('w7a.outbound')::uuid,current_setting('w7a.webhook.read')::uuid,
  'status:wamid.outbound.1:read:1','wamid.outbound.1','read',now(),repeat('b',64),null,null)::text,true);
select set_config('w7a.event.read.duplicate',public.record_whatsapp_message_event(current_setting('w7a.outbound')::uuid,current_setting('w7a.webhook.read')::uuid,
  'status:wamid.outbound.1:read:1','wamid.outbound.1','read',now(),repeat('b',64),null,null)::text,true);
select set_config('w7a.webhook.delivered',public.accept_whatsapp_webhook_event('status:wamid.outbound.1:delivered:0',repeat('c',64),'message_status','{"status":"delivered"}'::jsonb)::text,true);
select public.record_whatsapp_message_event(current_setting('w7a.outbound')::uuid,current_setting('w7a.webhook.delivered')::uuid,
  'status:wamid.outbound.1:delivered:0','wamid.outbound.1','delivered',now()-interval '1 minute',repeat('c',64),null,null);
select set_config('w7a.webhook.failed',public.accept_whatsapp_webhook_event('status:wamid.outbound.1:failed:2',repeat('d',64),'message_status','{"status":"failed"}'::jsonb)::text,true);
select public.record_whatsapp_message_event(current_setting('w7a.outbound')::uuid,current_setting('w7a.webhook.failed')::uuid,
  'status:wamid.outbound.1:failed:2','wamid.outbound.1','failed',now()+interval '1 minute',repeat('d',64),'provider','safe_code');
do $$ begin
  if current_setting('w7a.event.read')<>current_setting('w7a.event.read.duplicate') then raise exception 'Status event dedupe failed'; end if;
  if (select state from public.whatsapp_outbound_messages where id=current_setting('w7a.outbound')::uuid)<>'read' then
    raise exception 'Out-of-order delivered/failed event regressed read state'; end if;
  if (select count(*) from public.whatsapp_message_events where outbound_message_id=current_setting('w7a.outbound')::uuid)<>3 then
    raise exception 'Immutable status ledger count is incorrect'; end if;
end $$;

-- Retry, lease expiry/reclaim and exhaustion.
select set_config('w7a.retry',public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,
  '89300000-0000-0000-0001-000000000001',null,'retry_test','transactional','w7a_retry_template','en','1','{}','w7a-retry-1',null,2)::text,true);
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-retry',25,15) where message_id=current_setting('w7a.retry')::uuid;
  perform public.mark_whatsapp_outbound_failure(r.message_id,'worker-retry','network','timeout','transient',now()+interval '1 minute');
  if (select state from public.whatsapp_outbound_messages where id=r.message_id)<>'queued' then raise exception 'Transient retry was not scheduled'; end if;
end $$;
reset role;
update public.whatsapp_outbound_messages set next_attempt_at=now()-interval '1 minute' where id=current_setting('w7a.retry')::uuid;
set local role service_role;
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-retry-2',25,15) where message_id=current_setting('w7a.retry')::uuid;
  perform public.mark_whatsapp_outbound_failure(r.message_id,'worker-retry-2','network','timeout','transient',now()+interval '1 minute');
  if (select state from public.whatsapp_outbound_messages where id=r.message_id)<>'failed' then raise exception 'Retry exhaustion did not finalize failure'; end if;
end $$;

select set_config('w7a.lease',public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,
  '89300000-0000-0000-0001-000000000001',null,'lease_test','transactional','w7a_lease_template','en','1','{}','w7a-lease-1',null,3)::text,true);
do $$ declare r record; begin select * into r from public.claim_whatsapp_outbound_batch('worker-expired',25,15) where message_id=current_setting('w7a.lease')::uuid; end $$;
reset role;
update public.whatsapp_outbound_messages set lease_expires_at=now()-interval '1 minute' where id=current_setting('w7a.lease')::uuid;
set local role service_role;
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-reclaim',25,15) where message_id=current_setting('w7a.lease')::uuid;
  if r.attempt_count<>2 then raise exception 'Expired safe lease was not reclaimed'; end if;
  perform public.mark_whatsapp_outbound_failure(r.message_id,'worker-reclaim','provider','ambiguous','ambiguous',null);
  if (select last_error_category from public.whatsapp_outbound_messages where id=r.message_id)<>'ambiguous' then raise exception 'Ambiguous outcome was not quarantined'; end if;
end $$;

-- Enqueue succeeds while opted in, then STOP suppression prevents claim and future marketing enqueue.
select set_config('w7a.suppressed',public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,
  '89300000-0000-0000-0001-000000000001',null,'suppression_test','marketing','w7a_stop_template','en','1','{}','w7a-stop-1',null,3)::text,true);
select public.set_whatsapp_contact_suppression(current_setting('w7a.contact')::uuid,true,'stop_keyword','candidate_stop');
do $$ begin
  if exists(select 1 from public.claim_whatsapp_outbound_batch('worker-stop',25,15) where message_id=current_setting('w7a.suppressed')::uuid) then
    raise exception 'Opted-out marketing message was claimed'; end if;
  begin
    perform public.enqueue_whatsapp_outbound_message(current_setting('w7a.contact')::uuid,'89300000-0000-0000-0001-000000000001',null,
      'suppression_test','marketing','w7a_stop_template','en','1','{}','w7a-stop-2',null,3);
    raise exception 'Opted-out marketing enqueue succeeded';
  exception when raise_exception then if sqlerrm='Opted-out marketing enqueue succeeded' then raise; end if; end;
end $$;
reset role;

-- Browser roles cannot read base tables or call server functions.
set local role authenticated;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000004',true);
do $$ begin
  begin perform count(*) from public.whatsapp_contacts; raise exception 'Candidate read WhatsApp contacts';
  exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Candidate read WhatsApp contacts' then raise; end if; end;
  begin perform public.accept_whatsapp_webhook_event('browser',repeat('e',64),'unknown',null); raise exception 'Candidate executed server ingress';
  exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Candidate executed server ingress' then raise; end if; end;
  begin perform public.get_whatsapp_core_health(); raise exception 'Candidate read WhatsApp Admin projection';
  exception when raise_exception then if sqlerrm='Candidate read WhatsApp Admin projection' then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000002',true);
do $$ begin begin perform public.get_whatsapp_core_health(); raise exception 'Recruiter read WhatsApp Admin projection';
  exception when raise_exception then if sqlerrm='Recruiter read WhatsApp Admin projection' then raise; end if; end; end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000003',true);
do $$ begin begin perform public.get_whatsapp_core_health(); raise exception 'Operations read WhatsApp Admin projection';
  exception when raise_exception then if sqlerrm='Operations read WhatsApp Admin projection' then raise; end if; end; end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000005',true);
do $$ begin begin perform public.get_whatsapp_core_health(); raise exception 'Company read WhatsApp Admin projection';
  exception when raise_exception then if sqlerrm='Company read WhatsApp Admin projection' then raise; end if; end; end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000006',true);
do $$ begin begin perform public.get_whatsapp_core_health(); raise exception 'Contractor read WhatsApp Admin projection';
  exception when raise_exception then if sqlerrm='Contractor read WhatsApp Admin projection' then raise; end if; end; end $$;
select set_config('request.jwt.claim.sub','89300000-0000-0000-0000-000000000001',true);
do $$ declare health jsonb;
begin
  health:=public.get_whatsapp_core_health(); if health is null then raise exception 'Admin health projection failed'; end if;
  if exists(select 1 from public.list_whatsapp_recent_inbound(10,0) r where r.contact_masked not like '+91XXXXXX____') then raise exception 'Admin inbound phone was not masked'; end if;
  if exists(select 1 from public.list_whatsapp_recent_outbound(null,10,0) r where r.contact_masked not like '+91XXXXXX____') then raise exception 'Admin outbound phone was not masked'; end if;
  if exists(select 1 from public.list_whatsapp_failed_outbound(10,0) r where r.contact_masked not like '+91XXXXXX____') then raise exception 'Admin failed phone was not masked'; end if;
  if not exists(select 1 from public.get_whatsapp_contact_communication_status(current_setting('w7a.contact')::uuid)) then raise exception 'Admin contact projection failed'; end if;
end $$;
reset role;

set local role anon;
do $$ begin begin perform public.get_whatsapp_core_health(); raise exception 'Anonymous read WhatsApp Admin projection';
  exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Anonymous read WhatsApp Admin projection' then raise; end if; end; end $$;
reset role;

-- Privacy, audit and immutable ledger assertions.
do $$
begin
  if exists(select 1 from public.audit_logs a where a.entity_type like 'whatsapp_%'
    and (a.metadata::text ilike '%synthetic hello%' or a.metadata::text ilike '%provider_address%' or a.metadata::text ilike '%token%'
      or a.metadata::text ilike '%aadhaar%' or a.metadata::text ilike '%bank%')) then raise exception 'Sensitive WhatsApp audit content detected'; end if;
  if not exists(select 1 from public.audit_logs a where a.action='whatsapp.contact_suppressed' and a.entity_id=current_setting('w7a.contact')::uuid)
     or (select count(*) from public.audit_logs a where a.action='whatsapp.outbound_failed')<2 then raise exception 'W7A control/failure audit events are incomplete'; end if;
  if exists(select 1 from public.whatsapp_webhook_events e where e.redacted_payload::text ilike '%synthetic hello%') then
    raise exception 'Webhook ledger retained message content'; end if;
  if (select marketing_consent_status from public.whatsapp_contacts where id=current_setting('w7a.contact')::uuid)<>'opted_out'
     or (select transactional_contact_status from public.whatsapp_contacts where id=current_setting('w7a.contact')::uuid)<>'suppressed' then
    raise exception 'Marketing and transactional suppression were not kept explicit'; end if;
end;
$$;

set local role service_role;
do $$ begin
  begin update public.whatsapp_message_events set status='sent' where id=current_setting('w7a.event.read')::uuid;
    raise exception 'Service role directly mutated immutable message events';
  exception when insufficient_privilege then null; when raise_exception then if sqlerrm='Service role directly mutated immutable message events' then raise; end if; end;
end $$;
reset role;

rollback;
