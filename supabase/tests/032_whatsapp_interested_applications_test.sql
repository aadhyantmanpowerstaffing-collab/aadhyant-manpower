-- W7C rollback checkpoint: exact reply correlation, canonical Application reuse, idempotency, and zero residue.
\set ON_ERROR_STOP on
begin;

do $$
begin
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_inbound_messages'
      and column_name in ('campaign_recipient_id','application_id'))<>2 then raise exception 'W7C inbound correlation columns are incomplete'; end if;
  if (select count(*) from pg_constraint where conrelid='public.whatsapp_inbound_messages'::regclass and contype='f'
      and conname in ('whatsapp_inbound_messages_campaign_recipient_id_fkey','whatsapp_inbound_messages_application_id_fkey'))<>2 then raise exception 'W7C correlation FKs are incomplete'; end if;
  if (select count(*) from pg_indexes where schemaname='public' and indexname in
      ('whatsapp_inbound_campaign_recipient_idx','whatsapp_inbound_application_idx'))<>2 then raise exception 'W7C correlation indexes are incomplete'; end if;
  if pg_get_constraintdef((select oid from pg_constraint where conrelid='public.whatsapp_inbound_messages'::regclass
      and conname='whatsapp_inbound_messages_processing_status_check')) not ilike '%processed%' then raise exception 'Processed inbound state is missing'; end if;
  if to_regprocedure('public.process_whatsapp_interested_response(uuid)') is null then raise exception 'W7C processor is missing'; end if;
  if pg_get_functiondef('public.process_whatsapp_interested_response(uuid)'::regprocedure) not ilike '%security definer%'
     or pg_get_functiondef('public.process_whatsapp_interested_response(uuid)'::regprocedure) not ilike '%set search_path to ''''%' then
    raise exception 'W7C processor security posture is invalid';
  end if;
  if pg_get_functiondef('public.process_whatsapp_interested_response(uuid)'::regprocedure)
      ~* 'pg_catalog\.(coalesce|greatest|least|nullif)\s*\('
     or pg_get_functiondef('public.process_whatsapp_interested_response(uuid)'::regprocedure)
      ~* '(^|[^.[:alnum:]_])(btrim|upper|clock_timestamp|jsonb_build_object)\s*\(' then
    raise exception 'W7C processor function qualification is invalid';
  end if;
  if has_function_privilege('anon','public.process_whatsapp_interested_response(uuid)','execute')
     or has_function_privilege('authenticated','public.process_whatsapp_interested_response(uuid)','execute')
     or not has_function_privilege('service_role','public.process_whatsapp_interested_response(uuid)','execute') then
    raise exception 'W7C processor grant boundary is invalid';
  end if;
  if exists(select 1 from pg_class where oid in ('public.whatsapp_inbound_messages'::regclass,
      'public.candidate_applications'::regclass,'public.whatsapp_campaign_recipients'::regclass)
      and not relrowsecurity) then raise exception 'W7C canonical RLS boundary changed'; end if;
  if exists(select 1 from information_schema.role_table_grants where table_schema='public'
      and table_name in ('whatsapp_inbound_messages','whatsapp_campaign_recipients')
      and grantee in ('PUBLIC','anon','authenticated')) then raise exception 'W7C browser table grant detected'; end if;
end $$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('89700000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  'w7c-admin@test.local','x','{}','{}',now(),now());

insert into public.admin_users(user_id) values('89700000-0000-0000-0000-000000000001');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,iti_trade,experience_requirement,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage) values
('89700000-0000-0000-0001-000000000001','W7C Employer','Contact','9876700000','Chennai','Fitter',4,'ITI','Fitter','Fresher',true,'in_progress','REQ-W7C-OPEN-1','Chennai',0,'private','open'),
('89700000-0000-0000-0001-000000000002','W7C Employer','Contact','9876700000','Chennai','Fitter',4,'ITI','Fitter','Fresher',true,'in_progress','REQ-W7C-OPEN-2','Chennai',0,'private','open'),
('89700000-0000-0000-0001-000000000003','W7C Employer','Contact','9876700000','Chennai','Fitter',4,'ITI','Fitter','Fresher',true,'closed','REQ-W7C-CLOSED','Chennai',0,'private','closed'),
('89700000-0000-0000-0001-000000000004','W7C Employer','Contact','9876700000','Chennai','Fitter',4,'ITI','Fitter','Fresher',true,'in_progress','REQ-W7C-QUEUED','Chennai',0,'private','open');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,
  candidate_type,interview_available,consent,status,profile_status,profile_completion_status,current_employment_status,availability_status) values
('89700000-0000-0000-0002-000000000001','W7C New Application',24,'Female','9876700001','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89700000-0000-0000-0002-000000000002','W7C Existing Application',25,'Male','9876700002','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89700000-0000-0000-0002-000000000003','W7C Closed Requirement',26,'Female','9876700003','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89700000-0000-0000-0002-000000000004','W7C Undelivered',27,'Male','9876700004','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available');

insert into public.candidate_applications(id,candidate_id,requirement_id,source_type,application_status,created_by,source_reference)
values('89700000-0000-0000-0005-000000000002','89700000-0000-0000-0002-000000000002',
  '89700000-0000-0000-0001-000000000002','admin','applied','89700000-0000-0000-0000-000000000001','existing-admin-application');

set local role service_role;
select set_config('w7c.contact1',public.upsert_whatsapp_inbound_contact('+919876700001')::text,true);
select set_config('w7c.contact2',public.upsert_whatsapp_inbound_contact('+919876700002')::text,true);
select set_config('w7c.contact3',public.upsert_whatsapp_inbound_contact('+919876700003')::text,true);
select set_config('w7c.contact4',public.upsert_whatsapp_inbound_contact('+919876700004')::text,true);
reset role;
update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='synthetic_test',
  consent_scope='vacancy_campaign',consent_recorded_at=now(),consent_policy_version='w7c-test'
where id in (current_setting('w7c.contact1')::uuid,current_setting('w7c.contact2')::uuid,
  current_setting('w7c.contact3')::uuid,current_setting('w7c.contact4')::uuid);

insert into public.whatsapp_campaigns(id,operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,
  template_name,template_language,template_version,criteria,created_by,approved_by,approved_at,queued_at) values
('89700000-0000-0000-0006-000000000001','89700000-0000-0000-0010-000000000001','89700000-0000-0000-0001-000000000001','W7C Main','queued','vacancy_campaign','marketing','vacancy_interest','en','1','{}','89700000-0000-0000-0000-000000000001','89700000-0000-0000-0000-000000000001',now(),now()),
('89700000-0000-0000-0006-000000000002','89700000-0000-0000-0010-000000000002','89700000-0000-0000-0001-000000000002','W7C Existing','queued','vacancy_campaign','marketing','vacancy_interest','en','1','{}','89700000-0000-0000-0000-000000000001','89700000-0000-0000-0000-000000000001',now(),now()),
('89700000-0000-0000-0006-000000000003','89700000-0000-0000-0010-000000000003','89700000-0000-0000-0001-000000000003','W7C Closed','queued','vacancy_campaign','marketing','vacancy_interest','en','1','{}','89700000-0000-0000-0000-000000000001','89700000-0000-0000-0000-000000000001',now(),now()),
('89700000-0000-0000-0006-000000000004','89700000-0000-0000-0010-000000000004','89700000-0000-0000-0001-000000000004','W7C Undelivered','queued','vacancy_campaign','marketing','vacancy_interest','en','1','{}','89700000-0000-0000-0000-000000000001','89700000-0000-0000-0000-000000000001',now(),now());

set local role service_role;
select set_config('w7c.outbound1',public.enqueue_whatsapp_outbound_message(current_setting('w7c.contact1')::uuid,
  '89700000-0000-0000-0002-000000000001','89700000-0000-0000-0001-000000000001','vacancy_campaign','marketing',
  'vacancy_interest','en','1','{"action_id":"INTERESTED"}','w7c-outbound-1','89700000-0000-0000-0007-000000000001',3)::text,true);
select set_config('w7c.outbound2',public.enqueue_whatsapp_outbound_message(current_setting('w7c.contact2')::uuid,
  '89700000-0000-0000-0002-000000000002','89700000-0000-0000-0001-000000000002','vacancy_campaign','marketing',
  'vacancy_interest','en','1','{"action_id":"INTERESTED"}','w7c-outbound-2','89700000-0000-0000-0007-000000000002',3)::text,true);
select set_config('w7c.outbound3',public.enqueue_whatsapp_outbound_message(current_setting('w7c.contact3')::uuid,
  '89700000-0000-0000-0002-000000000003','89700000-0000-0000-0001-000000000003','vacancy_campaign','marketing',
  'vacancy_interest','en','1','{"action_id":"INTERESTED"}','w7c-outbound-3','89700000-0000-0000-0007-000000000003',3)::text,true);
select set_config('w7c.outbound4',public.enqueue_whatsapp_outbound_message(current_setting('w7c.contact4')::uuid,
  '89700000-0000-0000-0002-000000000004','89700000-0000-0000-0001-000000000004','vacancy_campaign','marketing',
  'vacancy_interest','en','1','{"action_id":"INTERESTED"}','w7c-outbound-4','89700000-0000-0000-0007-000000000004',3)::text,true);
reset role;

update public.whatsapp_outbound_messages set state='sent',send_phase='confirmed',provider_message_id='wamid.w7c.outbound.1',sent_at=now()
  where id=current_setting('w7c.outbound1')::uuid;
update public.whatsapp_outbound_messages set state='delivered',send_phase='confirmed',provider_message_id='wamid.w7c.outbound.2',sent_at=now(),delivered_at=now()
  where id=current_setting('w7c.outbound2')::uuid;
update public.whatsapp_outbound_messages set state='read',send_phase='confirmed',provider_message_id='wamid.w7c.outbound.3',sent_at=now(),delivered_at=now(),read_at=now()
  where id=current_setting('w7c.outbound3')::uuid;
update public.whatsapp_outbound_messages set provider_message_id='wamid.w7c.outbound.4'
  where id=current_setting('w7c.outbound4')::uuid;

insert into public.whatsapp_campaign_recipients(id,campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,
  match_reasons,outbound_message_id) values
('89700000-0000-0000-0007-000000000001','89700000-0000-0000-0006-000000000001','89700000-0000-0000-0002-000000000001',current_setting('w7c.contact1')::uuid,'matched','queued','[]',current_setting('w7c.outbound1')::uuid),
('89700000-0000-0000-0007-000000000002','89700000-0000-0000-0006-000000000002','89700000-0000-0000-0002-000000000002',current_setting('w7c.contact2')::uuid,'matched','queued','[]',current_setting('w7c.outbound2')::uuid),
('89700000-0000-0000-0007-000000000003','89700000-0000-0000-0006-000000000003','89700000-0000-0000-0002-000000000003',current_setting('w7c.contact3')::uuid,'matched','queued','[]',current_setting('w7c.outbound3')::uuid),
('89700000-0000-0000-0007-000000000004','89700000-0000-0000-0006-000000000004','89700000-0000-0000-0002-000000000004',current_setting('w7c.contact4')::uuid,'matched','queued','[]',current_setting('w7c.outbound4')::uuid);

set local role service_role;
select set_config('w7c.webhook.main',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.1',repeat('a',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.main',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.main')::uuid,current_setting('w7c.contact1')::uuid,
  'wamid.w7c.reply.1',now(),'button',null,'INTERESTED','wamid.w7c.outbound.1',null)::text,true);
select set_config('w7c.result.main',public.process_whatsapp_interested_response(current_setting('w7c.inbound.main')::uuid)::text,true);
reset role;

do $$ declare result jsonb:=current_setting('w7c.result.main')::jsonb; app_id uuid;
begin
  app_id:=(result->>'application_id')::uuid;
  perform set_config('w7c.application.main',app_id::text,true);
  if result->>'status'<>'application_created' or result->>'campaign_id'<>'89700000-0000-0000-0006-000000000001'
     or result->>'requirement_id'<>'89700000-0000-0000-0001-000000000001'
     or result->>'recipient_id'<>'89700000-0000-0000-0007-000000000001'
     or result->>'candidate_id'<>'89700000-0000-0000-0002-000000000001'
     or result->>'contact_id'<>current_setting('w7c.contact1') then raise exception 'W7C exact correlation result failed'; end if;
  if not exists(select 1 from public.candidate_applications where id=app_id and candidate_id='89700000-0000-0000-0002-000000000001'
      and requirement_id='89700000-0000-0000-0001-000000000001' and source_type='whatsapp' and application_status='interested'
      and created_by is null and correlation_id=current_setting('w7c.inbound.main')::uuid
      and source_reference='whatsapp_campaign:89700000-0000-0000-0006-000000000001:recipient:89700000-0000-0000-0007-000000000001') then
    raise exception 'Canonical WhatsApp Application creation failed'; end if;
  if not exists(select 1 from public.whatsapp_inbound_messages where id=current_setting('w7c.inbound.main')::uuid
      and processing_status='processed' and campaign_recipient_id='89700000-0000-0000-0007-000000000001' and application_id=app_id
      and safe_text is null and last_error_category is null and last_error_code is null) then raise exception 'Inbound W7C linkage failed'; end if;
  if not exists(select 1 from public.application_stage_history where application_id=app_id and to_stage='interested'
      and source='database' and correlation_id=current_setting('w7c.inbound.main')::uuid) then raise exception 'Canonical Application history was not recorded'; end if;
  if not exists(select 1 from public.audit_logs where action='whatsapp.interested_application_created' and entity_id=app_id
      and source='whatsapp' and correlation_id=current_setting('w7c.inbound.main')::uuid
      and metadata->>'campaign_id'='89700000-0000-0000-0006-000000000001'
      and metadata::text not ilike '%9876700001%') then raise exception 'Safe W7C creation audit failed'; end if;
end $$;

set local role service_role;
select set_config('w7c.result.replay',public.process_whatsapp_interested_response(current_setting('w7c.inbound.main')::uuid)::text,true);
reset role;
do $$ begin
  if current_setting('w7c.result.replay')::jsonb->>'status'<>'already_processed' then raise exception 'Exact INTERESTED replay was not idempotent'; end if;
  if (select count(*) from public.candidate_applications where candidate_id='89700000-0000-0000-0002-000000000001'
      and requirement_id='89700000-0000-0000-0001-000000000001')<>1 then raise exception 'Replay duplicated the canonical Application'; end if;
  if (select count(*) from public.audit_logs where correlation_id=current_setting('w7c.inbound.main')::uuid
      and action like 'whatsapp.interested_application_%')<>1 then raise exception 'Replay duplicated the W7C audit'; end if;
end $$;

set local role service_role;
select set_config('w7c.webhook.duplicate',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.duplicate',repeat('b',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.duplicate',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.duplicate')::uuid,current_setting('w7c.contact1')::uuid,
  'wamid.w7c.reply.duplicate',now(),'button',null,'INTERESTED','wamid.w7c.outbound.1',null)::text,true);
select set_config('w7c.result.duplicate',public.process_whatsapp_interested_response(current_setting('w7c.inbound.duplicate')::uuid)::text,true);
reset role;
do $$ begin
  if current_setting('w7c.result.duplicate')::jsonb->>'status'<>'application_exists'
     or current_setting('w7c.result.duplicate')::jsonb->>'application_id'<>current_setting('w7c.application.main') then
    raise exception 'Second INTERESTED message did not reuse the canonical Application'; end if;
end $$;

set local role service_role;
select set_config('w7c.webhook.existing',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.existing',repeat('c',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.existing',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.existing')::uuid,current_setting('w7c.contact2')::uuid,
  'wamid.w7c.reply.existing',now(),'button',null,'INTERESTED','wamid.w7c.outbound.2',null)::text,true);
select set_config('w7c.result.existing',public.process_whatsapp_interested_response(current_setting('w7c.inbound.existing')::uuid)::text,true);
reset role;
do $$ begin
  if current_setting('w7c.result.existing')::jsonb->>'status'<>'application_exists'
     or current_setting('w7c.result.existing')::jsonb->>'application_id'<>'89700000-0000-0000-0005-000000000002' then
    raise exception 'Existing canonical Application was not reused'; end if;
  if not exists(select 1 from public.candidate_applications where id='89700000-0000-0000-0005-000000000002'
      and source_type='admin' and application_status='applied' and source_reference='existing-admin-application') then
    raise exception 'Existing canonical Application was mutated'; end if;
end $$;

set local role service_role;
select set_config('w7c.webhook.missing',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.missing',repeat('d',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.missing',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.missing')::uuid,current_setting('w7c.contact1')::uuid,
  'wamid.w7c.reply.missing',now(),'button',null,'INTERESTED',null,null)::text,true);
select set_config('w7c.result.missing',public.process_whatsapp_interested_response(current_setting('w7c.inbound.missing')::uuid)::text,true);
select set_config('w7c.webhook.wrong',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.wrong',repeat('e',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.wrong',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.wrong')::uuid,current_setting('w7c.contact2')::uuid,
  'wamid.w7c.reply.wrong',now(),'button',null,'INTERESTED','wamid.w7c.outbound.1',null)::text,true);
select set_config('w7c.result.wrong',public.process_whatsapp_interested_response(current_setting('w7c.inbound.wrong')::uuid)::text,true);
select set_config('w7c.webhook.closed',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.closed',repeat('f',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.closed',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.closed')::uuid,current_setting('w7c.contact3')::uuid,
  'wamid.w7c.reply.closed',now(),'button',null,'INTERESTED','wamid.w7c.outbound.3',null)::text,true);
select set_config('w7c.result.closed',public.process_whatsapp_interested_response(current_setting('w7c.inbound.closed')::uuid)::text,true);
select set_config('w7c.webhook.queued',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.queued',repeat('1',64),'message','{"message_type":"button","action_id":"INTERESTED"}')::text,true);
select set_config('w7c.inbound.queued',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.queued')::uuid,current_setting('w7c.contact4')::uuid,
  'wamid.w7c.reply.queued',now(),'button',null,'INTERESTED','wamid.w7c.outbound.4',null)::text,true);
select set_config('w7c.result.queued',public.process_whatsapp_interested_response(current_setting('w7c.inbound.queued')::uuid)::text,true);
select set_config('w7c.webhook.other',public.accept_whatsapp_webhook_event('message:wamid.w7c.reply.other',repeat('2',64),'message','{"message_type":"button","action_id":"VIEW_JOB"}')::text,true);
select set_config('w7c.inbound.other',public.record_whatsapp_inbound_message(current_setting('w7c.webhook.other')::uuid,current_setting('w7c.contact1')::uuid,
  'wamid.w7c.reply.other',now(),'button',null,'VIEW_JOB','wamid.w7c.outbound.1',null)::text,true);
do $$ begin
  begin perform public.process_whatsapp_interested_response(current_setting('w7c.inbound.other')::uuid); raise exception 'non_interested_processed';
  exception when others then if sqlerrm<>'INTERESTED action is required' then raise; end if; end;
end $$;
reset role;

do $$ begin
  if current_setting('w7c.result.missing')::jsonb->>'reason'<>'missing_reply_context'
     or current_setting('w7c.result.wrong')::jsonb->>'reason'<>'outbound_not_found'
     or current_setting('w7c.result.closed')::jsonb->>'reason'<>'requirement_not_open'
     or current_setting('w7c.result.queued')::jsonb->>'reason'<>'campaign_delivery_ineligible' then
    raise exception 'W7C fail-closed classification failed'; end if;
  if exists(select 1 from public.whatsapp_inbound_messages where id in (current_setting('w7c.inbound.missing')::uuid,
      current_setting('w7c.inbound.wrong')::uuid,current_setting('w7c.inbound.closed')::uuid,current_setting('w7c.inbound.queued')::uuid)
      and (processing_status<>'ignored' or campaign_recipient_id is not null or application_id is not null)) then
    raise exception 'Ignored INTERESTED response retained unsafe linkage'; end if;
  if not exists(select 1 from public.whatsapp_inbound_messages where id=current_setting('w7c.inbound.other')::uuid
      and processing_status='normalized' and campaign_recipient_id is null and application_id is null) then
    raise exception 'Non-INTERESTED message state changed'; end if;
  if (select count(*) from public.candidate_applications where candidate_id::text like '89700000-%')<>2 then
    raise exception 'W7C created an unexpected canonical Application'; end if;
end $$;

set local role authenticated;
do $$ begin
  begin perform public.process_whatsapp_interested_response('89700000-0000-0000-9999-000000000001'); raise exception 'authenticated_execution_allowed';
  exception when insufficient_privilege then null; when others then if sqlerrm='authenticated_execution_allowed' then raise; end if; end;
end $$;
reset role;

rollback;

do $$ begin
  if exists(select 1 from public.whatsapp_inbound_messages where provider_message_id in (
       'wamid.w7c.reply.1','wamid.w7c.reply.duplicate','wamid.w7c.reply.existing','wamid.w7c.reply.missing',
       'wamid.w7c.reply.wrong','wamid.w7c.reply.closed','wamid.w7c.reply.queued','wamid.w7c.reply.other'))
     or exists(select 1 from public.whatsapp_webhook_events where provider_event_key in (
       'message:wamid.w7c.reply.1','message:wamid.w7c.reply.duplicate','message:wamid.w7c.reply.existing',
       'message:wamid.w7c.reply.missing','message:wamid.w7c.reply.wrong','message:wamid.w7c.reply.closed',
       'message:wamid.w7c.reply.queued','message:wamid.w7c.reply.other'))
     or exists(select 1 from public.whatsapp_outbound_messages where idempotency_key in
       ('w7c-outbound-1','w7c-outbound-2','w7c-outbound-3','w7c-outbound-4'))
     or exists(select 1 from public.whatsapp_campaign_recipients where id::text like '89700000-%')
     or exists(select 1 from public.whatsapp_campaigns where id::text like '89700000-%')
     or exists(select 1 from public.candidate_applications where candidate_id::text like '89700000-%')
     or exists(select 1 from public.application_stage_history where application_id::text like '89700000-%')
     or exists(select 1 from public.audit_logs where correlation_id::text like '89700000-%' or entity_id::text like '89700000-%')
     or exists(select 1 from public.whatsapp_contacts where provider_address in ('+919876700001','+919876700002','+919876700003','+919876700004'))
     or exists(select 1 from public.candidates where id::text like '89700000-%')
     or exists(select 1 from public.employer_requirements where id::text like '89700000-%')
     or exists(select 1 from public.admin_users where user_id::text like '89700000-%')
     or exists(select 1 from auth.users where id::text like '89700000-%') then raise exception 'W7C checkpoint residue detected'; end if;
end $$;
