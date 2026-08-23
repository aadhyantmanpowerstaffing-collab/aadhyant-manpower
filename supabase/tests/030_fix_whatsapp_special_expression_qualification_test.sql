-- W7A corrective checkpoint: execute every migration-027 replacement under rollback scope.
\set ON_ERROR_STOP on
begin;

do $$
declare v_name text; v_reg regprocedure;
begin
  foreach v_name in array array[
    'private.normalize_indian_whatsapp_phone(text)',
    'private.apply_whatsapp_delivery_projection(uuid,text,timestamptz)',
    'public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)',
    'public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)',
    'public.claim_whatsapp_outbound_batch(text,integer,integer)',
    'public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz)',
    'public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz)',
    'public.set_whatsapp_contact_suppression(uuid,boolean,text,text)',
    'public.list_whatsapp_recent_inbound(integer,integer)',
    'public.list_whatsapp_recent_outbound(text,integer,integer)',
    'public.list_whatsapp_failed_outbound(integer,integer)'
  ] loop
    v_reg:=to_regprocedure(v_name);
    if v_reg is null then raise exception 'Missing migration-027 replacement %',v_name; end if;
    if pg_get_functiondef(v_reg) not ilike '%security definer%'
       or pg_get_functiondef(v_reg) not ilike '%set search_path to ''''%' then
      raise exception 'Migration-027 security posture changed for %',v_name;
    end if;
    if pg_get_functiondef(v_reg) ~* 'pg_catalog\.(coalesce|greatest|least|nullif)\s*\(' then
      raise exception 'Invalid special-expression qualification remains in %',v_name;
    end if;
    if v_name like 'private.%' and (has_function_privilege('anon',v_reg,'execute')
       or has_function_privilege('authenticated',v_reg,'execute')) then
      raise exception 'Migration-027 private helper grant changed for %',v_name;
    end if;
  end loop;

  foreach v_name in array array[
    'public.record_whatsapp_inbound_message(uuid,uuid,text,timestamptz,text,text,text,text,jsonb)',
    'public.enqueue_whatsapp_outbound_message(uuid,uuid,uuid,text,text,text,text,text,jsonb,text,uuid,integer)',
    'public.claim_whatsapp_outbound_batch(text,integer,integer)',
    'public.mark_whatsapp_outbound_sent(uuid,text,text,timestamptz)',
    'public.mark_whatsapp_outbound_failure(uuid,text,text,text,text,timestamptz)',
    'public.set_whatsapp_contact_suppression(uuid,boolean,text,text)'
  ] loop
    v_reg:=to_regprocedure(v_name);
    if has_function_privilege('anon',v_reg,'execute')
       or has_function_privilege('authenticated',v_reg,'execute')
       or not has_function_privilege('service_role',v_reg,'execute') then
      raise exception 'Migration-027 server grant boundary changed for %',v_name;
    end if;
  end loop;

  foreach v_name in array array[
    'public.list_whatsapp_recent_inbound(integer,integer)',
    'public.list_whatsapp_recent_outbound(text,integer,integer)',
    'public.list_whatsapp_failed_outbound(integer,integer)'
  ] loop
    v_reg:=to_regprocedure(v_name);
    if has_function_privilege('anon',v_reg,'execute')
       or not has_function_privilege('authenticated',v_reg,'execute') then
      raise exception 'Migration-027 Admin projection grant changed for %',v_name;
    end if;
  end loop;
end;
$$;

-- Phone helper executes corrected coalesce expression and remains strict.
do $$
declare v_key text; v_address text;
begin
  select indian_mobile_key,provider_address into v_key,v_address
    from private.normalize_indian_whatsapp_phone('9876543210');
  if v_key<>'9876543210' or v_address<>'+919876543210' then raise exception 'Ten-digit phone execution failed'; end if;
  select indian_mobile_key,provider_address into v_key,v_address
    from private.normalize_indian_whatsapp_phone('+91 98765-43210');
  if v_key<>'9876543210' or v_address<>'+919876543210' then raise exception 'Formatted phone execution failed'; end if;
  begin perform private.normalize_indian_whatsapp_phone(null); raise exception 'Null phone accepted';
  exception when raise_exception then if sqlerrm='Null phone accepted' then raise; end if; end;
  begin perform private.normalize_indian_whatsapp_phone(''); raise exception 'Empty phone accepted';
  exception when raise_exception then if sqlerrm='Empty phone accepted' then raise; end if; end;
  begin perform private.normalize_indian_whatsapp_phone('abc9876543210'); raise exception 'Invalid phone accepted';
  exception when raise_exception then if sqlerrm='Invalid phone accepted' then raise; end if; end;
end;
$$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89400000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-027-admin@test.local','x','{}','{}',now(),now()),
('89400000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7a-027-candidate@test.local','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('89400000-0000-0000-0000-000000000001');
insert into public.platform_users(user_id,account_type,display_name,email,account_status) values
('89400000-0000-0000-0000-000000000002','candidate','W7A 027 Candidate','w7a-027-candidate@test.local','active');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,
  interview_available,consent,status,user_id,profile_status,profile_completion_status) values
('89400000-0000-0000-0001-000000000001','W7A 027 Candidate',25,'Female','9999903030','Chennai','Chennai','Tamil Nadu','ITI',
  'Fresher','Yes',true,'new','89400000-0000-0000-0000-000000000002','active','complete');

set local role service_role;
select set_config('w7a030.contact',public.upsert_whatsapp_inbound_contact('+919999903030')::text,true);
select set_config('w7a030.webhook',public.accept_whatsapp_webhook_event('w7a030:message',repeat('a',64),'message','{"message_type":"text"}'::jsonb)::text,true);
select set_config('w7a030.inbound',public.record_whatsapp_inbound_message(
  current_setting('w7a030.webhook')::uuid,current_setting('w7a030.contact')::uuid,'wamid.w7a030',null,
  'text','discarded text',null,null,'{"message_type":"text"}'::jsonb)::text,true);
reset role;

update public.whatsapp_contacts set marketing_consent_status='opted_in',transactional_contact_status='allowed',
  consent_source='synthetic_test',consent_scope='all',consent_recorded_at=now(),consent_policy_version='w7a030'
  where id=current_setting('w7a030.contact')::uuid;

set local role service_role;
select set_config('w7a030.sent',public.enqueue_whatsapp_outbound_message(
  current_setting('w7a030.contact')::uuid,'89400000-0000-0000-0001-000000000001',null,
  'runtime_compatibility','transactional','w7a_030_template','en','1',null,'w7a030-sent',null,3)::text,true);
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-w7a030',null,null)
    where message_id=current_setting('w7a030.sent')::uuid;
  if r.message_id is null or r.attempt_count<>1 then raise exception 'Corrected claim expressions did not execute'; end if;
  perform public.mark_whatsapp_provider_call_started(r.message_id,'worker-w7a030');
  perform public.mark_whatsapp_outbound_sent(r.message_id,'worker-w7a030','wamid.w7a030.outbound',null);
end;
$$;
reset role;

-- Exercise all corrected delivery-projection coalesce branches with null provider timestamps.
select private.apply_whatsapp_delivery_projection(current_setting('w7a030.sent')::uuid,'sent',null);
select private.apply_whatsapp_delivery_projection(current_setting('w7a030.sent')::uuid,'delivered',null);
select private.apply_whatsapp_delivery_projection(current_setting('w7a030.sent')::uuid,'read',null);
do $$ begin
  if (select state from public.whatsapp_outbound_messages where id=current_setting('w7a030.sent')::uuid)<>'read' then
    raise exception 'Corrected delivery projection did not execute monotonically'; end if;
end $$;

set local role service_role;
select set_config('w7a030.projection_failed',public.enqueue_whatsapp_outbound_message(
  current_setting('w7a030.contact')::uuid,'89400000-0000-0000-0001-000000000001',null,
  'projection_failure','transactional','w7a_030_projection_failure','en','1','{}','w7a030-projection-failed',null,1)::text,true);
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-w7a030-projection',null,null)
    where message_id=current_setting('w7a030.projection_failed')::uuid;
  perform public.mark_whatsapp_provider_call_started(r.message_id,'worker-w7a030-projection');
  perform public.mark_whatsapp_outbound_sent(r.message_id,'worker-w7a030-projection','wamid.w7a030.projection',null);
end;
$$;
reset role;
select private.apply_whatsapp_delivery_projection(current_setting('w7a030.projection_failed')::uuid,'failed',null);

set local role service_role;
select set_config('w7a030.failed',public.enqueue_whatsapp_outbound_message(
  current_setting('w7a030.contact')::uuid,'89400000-0000-0000-0001-000000000001',null,
  'failure_compatibility','transactional','w7a_030_failure','en','1','{}','w7a030-failed',null,1)::text,true);
do $$ declare r record;
begin
  select * into r from public.claim_whatsapp_outbound_batch('worker-w7a030-failure',null,null)
    where message_id=current_setting('w7a030.failed')::uuid;
  perform public.mark_whatsapp_outbound_failure(r.message_id,'worker-w7a030-failure','synthetic','permanent','permanent',null);
end;
$$;
select public.set_whatsapp_contact_suppression(current_setting('w7a030.contact')::uuid,true,'synthetic_stop',null);
reset role;

-- Execute corrected least/greatest/coalesce expressions in all three Admin projections.
set local role authenticated;
select set_config('request.jwt.claim.sub','89400000-0000-0000-0000-000000000001',true);
do $$ begin
  perform count(*) from public.list_whatsapp_recent_inbound(null,null);
  perform count(*) from public.list_whatsapp_recent_outbound(null,null,null);
  perform count(*) from public.list_whatsapp_failed_outbound(null,null);
end $$;
reset role;

do $$ begin
  if (select safe_text from public.whatsapp_inbound_messages where id=current_setting('w7a030.inbound')::uuid) is not null then
    raise exception 'Inbound privacy contract changed'; end if;
  if not exists(select 1 from public.whatsapp_outbound_messages where id=current_setting('w7a030.failed')::uuid
      and state='failed' and send_phase='terminal' and lease_owner is null) then
    raise exception 'Failure finalization contract changed'; end if;
  if not exists(select 1 from public.whatsapp_outbound_messages where id=current_setting('w7a030.projection_failed')::uuid
      and state='failed' and send_phase='terminal' and failed_at is not null) then
    raise exception 'Failed delivery projection expression did not execute'; end if;
  if not exists(select 1 from public.whatsapp_contacts where id=current_setting('w7a030.contact')::uuid
      and marketing_consent_status='opted_out' and transactional_contact_status='suppressed'
      and opt_out_reason_category is null) then raise exception 'Suppression/nullif contract changed'; end if;
end $$;

rollback;

do $$ begin
  if exists(select 1 from public.whatsapp_contacts where provider_address='+919999903030')
     or exists(select 1 from public.whatsapp_webhook_events where provider_event_key like 'w7a030:%')
     or exists(select 1 from public.whatsapp_inbound_messages where provider_message_id='wamid.w7a030')
     or exists(select 1 from public.whatsapp_outbound_messages where idempotency_key like 'w7a030-%')
     or exists(select 1 from public.audit_logs where source='whatsapp'
       and (metadata->>'source'='synthetic_stop' or metadata->>'error_category'='synthetic'))
     or exists(select 1 from public.candidates where id='89400000-0000-0000-0001-000000000001'::uuid)
     or exists(select 1 from public.platform_users where user_id='89400000-0000-0000-0000-000000000002'::uuid)
     or exists(select 1 from public.admin_users where user_id='89400000-0000-0000-0000-000000000001'::uuid)
     or exists(select 1 from auth.users where id in
       ('89400000-0000-0000-0000-000000000001'::uuid,'89400000-0000-0000-0000-000000000002'::uuid)) then
    raise exception 'Checkpoint 030 rollback residue detected';
  end if;
end $$;
