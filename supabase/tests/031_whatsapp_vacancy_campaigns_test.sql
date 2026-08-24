-- W7B rollback checkpoint: requirement-derived campaigns, W7A queue reuse, lifecycle, and zero residue.
begin;

do $$
begin
  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('whatsapp_campaigns','whatsapp_campaign_recipients'))<>2 then raise exception 'W7B tables missing'; end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in ('whatsapp_campaigns','whatsapp_campaign_recipients') and not c.relrowsecurity) then raise exception 'W7B RLS missing'; end if;
  if exists(select 1 from information_schema.role_table_grants where table_schema='public' and table_name in ('whatsapp_campaigns','whatsapp_campaign_recipients') and grantee in ('anon','authenticated')) then raise exception 'Browser table grant detected'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_campaigns' and column_name in ('id','operation_key','requirement_id','campaign_status','criteria','created_by','approved_by','queued_at','completed_at'))<>9 then raise exception 'Campaign columns incomplete'; end if;
  if (select count(*) from information_schema.columns where table_schema='public' and table_name='whatsapp_campaign_recipients' and column_name in ('id','campaign_id','candidate_id','whatsapp_contact_id','recipient_status','outbound_message_id'))<>6 then raise exception 'Recipient columns incomplete'; end if;
  if (select count(*) from pg_constraint where conrelid='public.whatsapp_campaign_recipients'::regclass and contype='f')<>4 then raise exception 'Recipient FKs incomplete'; end if;
  if (select count(*) from pg_constraint where conrelid='public.whatsapp_campaign_recipients'::regclass and contype='u')<>2 then raise exception 'Recipient uniqueness incomplete'; end if;
  if not exists(select 1 from pg_indexes where schemaname='public' and tablename='whatsapp_campaign_recipients' and indexname='whatsapp_campaign_recipients_outbound_idx' and indexdef ilike 'create unique index%') then raise exception 'Outbound uniqueness missing'; end if;
  if (select count(*) from pg_indexes where schemaname='public' and indexname in ('whatsapp_campaigns_requirement_idx','whatsapp_campaigns_status_idx','whatsapp_campaign_recipients_campaign_idx','whatsapp_campaign_recipients_outbound_idx'))<>4 then raise exception 'Campaign indexes incomplete'; end if;
  if (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('admin_preview_whatsapp_campaign_audience','admin_create_whatsapp_campaign','admin_freeze_whatsapp_campaign_audience','admin_approve_whatsapp_campaign','admin_queue_whatsapp_campaign','admin_reconcile_whatsapp_campaign','admin_cancel_whatsapp_campaign','admin_list_whatsapp_campaigns','admin_get_whatsapp_campaign'))<>9 then raise exception 'W7B RPCs incomplete'; end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like '%whatsapp_campaign%' and n.nspname in ('public','private') and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%') then raise exception 'Definer search_path missing'; end if;
  if exists(select 1 from information_schema.routine_privileges where routine_schema='public' and routine_name like 'admin_%whatsapp_campaign%' and grantee='anon') then raise exception 'Anonymous RPC grant detected'; end if;
  if (select count(distinct routine_name) from information_schema.routine_privileges where routine_schema='public' and routine_name like 'admin_%whatsapp_campaign%' and grantee='authenticated' and privilege_type='EXECUTE')<>9 then raise exception 'Authenticated RPC grants incomplete'; end if;
  if position('for update' in lower(pg_get_functiondef('public.admin_queue_whatsapp_campaign(uuid)'::regprocedure)))=0 or position('for update' in lower(pg_get_functiondef('public.admin_approve_whatsapp_campaign(uuid)'::regprocedure)))=0 then raise exception 'Lifecycle locks missing'; end if;
end $$;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89600000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7b-admin@test.local','x','{}','{}',now(),now()),
('89600000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7b-viewer@test.local','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('89600000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values('89600000-0000-0000-0000-000000000002','W7B Viewer','active');
insert into public.staff_roles(user_id,role,status,granted_by) values('89600000-0000-0000-0000-000000000002','viewer','active','89600000-0000-0000-0000-000000000001');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,qualification,iti_trade,experience_requirement,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage) values
('89600000-0000-0000-0001-000000000001','W7B Employer','Contact','9876600000','Chennai','Fitter',2,'ITI','Fitter','Fresher',true,'in_progress','REQ-W7B-OPEN','Chennai',0,'private','open'),
('89600000-0000-0000-0001-000000000002','W7B Employer','Contact','9876600000','Chennai','Fitter',2,'ITI','Fitter','Fresher',true,'closed','REQ-W7B-CLOSED','Chennai',0,'private','closed');

insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,candidate_type,interview_available,consent,status,profile_status,profile_completion_status,current_employment_status,availability_status) values
('89600000-0000-0000-0002-000000000001','Eligible One',24,'Female','9876600001','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89600000-0000-0000-0002-000000000002','Eligible Two',25,'Male','9876600002','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89600000-0000-0000-0002-000000000003','Wrong Trade',25,'Male','9876600003','Chennai','Chennai','Tamil Nadu','ITI','Electrician','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89600000-0000-0000-0002-000000000004','Wrong Qualification',25,'Male','9876600004','Chennai','Chennai','Tamil Nadu','Diploma','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89600000-0000-0000-0002-000000000005','Wrong Location',25,'Male','9876600005','Madurai','Madurai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89600000-0000-0000-0002-000000000006','Wrong Experience',25,'Male','9876600006','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','Yes',true,'new','active','complete','employed','open_to_opportunities'),
('89600000-0000-0000-0002-000000000007','Suppressed One',25,'Female','9876600007','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available');

set local role service_role;
select set_config('w7b.c1',public.upsert_whatsapp_inbound_contact('+919876600001')::text,true);
select set_config('w7b.c2',public.upsert_whatsapp_inbound_contact('+919876600002')::text,true);
select set_config('w7b.c7',public.upsert_whatsapp_inbound_contact('+919876600007')::text,true);
update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='synthetic_test',consent_scope='vacancy_campaign',consent_recorded_at=now(),consent_policy_version='w7b-test' where id in (current_setting('w7b.c1')::uuid,current_setting('w7b.c2')::uuid);
update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='synthetic_test' where id=current_setting('w7b.c7')::uuid;
reset role;

select set_config('request.jwt.claim.sub','89600000-0000-0000-0000-000000000002',true);
set local role authenticated;
do $$ begin
  begin perform public.admin_list_whatsapp_campaigns(null,25,0); raise exception 'denial_not_enforced'; exception when others then if sqlerrm<>'WhatsApp campaign Admin access is required' then raise exception 'Unexpected denial: %',sqlerrm; end if; end;
  begin perform public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000099','Denied','vacancy_interest','en','1','{}'); raise exception 'denial_not_enforced'; exception when others then if sqlerrm<>'WhatsApp campaign Admin access is required' then raise exception 'Unexpected mutation denial: %',sqlerrm; end if; end;
end $$;
reset role;

select set_config('request.jwt.claim.sub','89600000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$
declare main_id uuid; detached_id uuid; failure_id uuid; cancel_id uuid; first_queue integer; second_queue integer; detail jsonb;
begin
  begin perform public.admin_create_whatsapp_campaign('89600000-0000-0000-9999-000000000001','89600000-0000-0000-0010-000000000090','Missing','vacancy_interest','en','1','{}'); raise exception 'missing_accepted'; exception when others then if sqlerrm<>'Open requirement was not found' then raise; end if; end;
  begin perform public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000002','89600000-0000-0000-0010-000000000091','Closed','vacancy_interest','en','1','{}'); raise exception 'closed_accepted'; exception when others then if sqlerrm<>'Open requirement was not found' then raise; end if; end;
  if (select count(*) from public.admin_preview_whatsapp_campaign_audience('89600000-0000-0000-0001-000000000001','{}',100,0))<>3 then raise exception 'Requirement preview count failed'; end if;
  if exists(select 1 from public.admin_preview_whatsapp_campaign_audience('89600000-0000-0000-0001-000000000001','{}',100,0) where candidate_id in ('89600000-0000-0000-0002-000000000003','89600000-0000-0000-0002-000000000004','89600000-0000-0000-0002-000000000005','89600000-0000-0000-0002-000000000006')) then raise exception 'Requirement mismatch entered preview'; end if;
  if not exists(select 1 from public.admin_preview_whatsapp_campaign_audience('89600000-0000-0000-0001-000000000001','{}',100,0) where candidate_id='89600000-0000-0000-0002-000000000007' and not eligible and eligibility_reason='opted_out' and contact_masked not like '%9876600007%') then raise exception 'Suppression/masking failed'; end if;
  main_id:=public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000001','Main Campaign','vacancy_interest','en','1','{}');
  if main_id<>public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000001','Main Campaign','vacancy_interest','en','1','{}') then raise exception 'Create idempotency failed'; end if;
  perform set_config('w7b.main',main_id::text,true);
  begin perform public.admin_approve_whatsapp_campaign(main_id); raise exception 'draft_approval_accepted'; exception when others then if sqlerrm<>'Audience-ready campaign is required' then raise; end if; end;
  if public.admin_freeze_whatsapp_campaign_audience(main_id,array['89600000-0000-0000-0002-000000000001'::uuid,'89600000-0000-0000-0002-000000000001'::uuid],array['89600000-0000-0000-0002-000000000002'::uuid],1)<>1 then raise exception 'Freeze/dedupe failed'; end if;
  begin perform public.admin_queue_whatsapp_campaign(main_id); raise exception 'audience_queue_accepted'; exception when others then if sqlerrm<>'Approved campaign is required before queueing' then raise; end if; end;
  perform public.admin_approve_whatsapp_campaign(main_id);
  begin perform public.admin_freeze_whatsapp_campaign_audience(main_id,array['89600000-0000-0000-0002-000000000002'::uuid],'{}',1); raise exception 'approved_mutation_accepted'; exception when others then if sqlerrm<>'Campaign audience can no longer change' then raise; end if; end;
  first_queue:=public.admin_queue_whatsapp_campaign(main_id); second_queue:=public.admin_queue_whatsapp_campaign(main_id);
  if first_queue<>1 or second_queue<>1 then raise exception 'Queue idempotency failed'; end if;
  perform set_config('w7b.outbound',(select outbound_message_id::text from public.whatsapp_campaign_recipients where campaign_id=main_id and recipient_status='queued'),true);
  if (select count(*) from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id where cr.campaign_id=main_id and o.candidate_id=cr.candidate_id and o.contact_id=cr.whatsapp_contact_id and o.requirement_id='89600000-0000-0000-0001-000000000001' and o.correlation_id=cr.id)<>1 then raise exception 'Exact W7A linkage failed'; end if;
  if (select count(*) from public.whatsapp_outbound_messages where idempotency_key like 'campaign:'||main_id::text||':recipient:%')<>1 then raise exception 'Duplicate outbound detected'; end if;
  if not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.campaign_queue_started') or not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.campaign_queue_completed') then raise exception 'Queue audit phases missing'; end if;
  if not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.campaign_created')
     or not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.audience_frozen')
     or not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.recipients_included')
     or not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.recipients_excluded')
     or not exists(select 1 from public.audit_logs where entity_id=main_id and action='whatsapp.campaign_approved') then raise exception 'Campaign audit coverage failed'; end if;
  if (public.admin_reconcile_whatsapp_campaign(main_id)->>'campaign_status')<>'queued' then raise exception 'Queued reconciliation failed'; end if;
  detached_id:=public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000002','Detached Campaign','vacancy_interest','en','1','{}');
  perform public.admin_freeze_whatsapp_campaign_audience(detached_id,array['89600000-0000-0000-0002-000000000002'::uuid],'{}',1);perform set_config('w7b.detached',detached_id::text,true);
  failure_id:=public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000003','Failure Campaign','vacancy_interest','en','1','{}');
  perform public.admin_freeze_whatsapp_campaign_audience(failure_id,array['89600000-0000-0000-0002-000000000002'::uuid],'{}',1);perform public.admin_approve_whatsapp_campaign(failure_id);perform set_config('w7b.failure',failure_id::text,true);
  if (select count(*) from public.whatsapp_campaign_recipients where campaign_id=main_id)<>2
     or (select count(*) from public.whatsapp_campaign_recipients where campaign_id=detached_id)<>1
     or (select count(*) from public.whatsapp_campaign_recipients where campaign_id=failure_id)<>1 then raise exception 'Cross-campaign audience isolation failed'; end if;
  cancel_id:=public.admin_create_whatsapp_campaign('89600000-0000-0000-0001-000000000001','89600000-0000-0000-0010-000000000004','Cancelled Campaign','vacancy_interest','en','1','{}');
  perform public.admin_cancel_whatsapp_campaign(cancel_id);
  if not exists(select 1 from public.whatsapp_campaigns where id=cancel_id and campaign_status='cancelled') or not exists(select 1 from public.audit_logs where entity_id=cancel_id and action='whatsapp.campaign_cancelled') then raise exception 'Cancellation lifecycle failed'; end if;
  begin perform public.admin_reconcile_whatsapp_campaign(cancel_id); raise exception 'cancelled_reconcile_accepted'; exception when others then if sqlerrm<>'Queued campaign is required for reconciliation' then raise; end if; end;
end $$;
reset role;

set local role service_role;
update public.whatsapp_outbound_messages set state='sending',send_phase='claimed',lease_owner='w7b-checkpoint',lease_expires_at=now()+interval '5 minutes' where id=current_setting('w7b.outbound')::uuid;
update public.whatsapp_contacts set candidate_id=null where id=current_setting('w7b.c2')::uuid;
reset role;

set local role authenticated;
do $$ begin
  if (public.admin_reconcile_whatsapp_campaign(current_setting('w7b.main')::uuid)->>'campaign_status')<>'sending' then raise exception 'Sending reconciliation failed'; end if;
  begin perform public.admin_approve_whatsapp_campaign(current_setting('w7b.detached')::uuid); raise exception 'detached_approved'; exception when others then if sqlerrm<>'Campaign audience is empty, mismatched, unresolved, or suppressed' then raise; end if; end;
end $$;
reset role;

set local role service_role;
update public.whatsapp_contacts set candidate_id='89600000-0000-0000-0002-000000000003',resolution_status='resolved' where id=current_setting('w7b.c2')::uuid;
reset role;
set local role authenticated;
do $$ begin
  begin perform public.admin_approve_whatsapp_campaign(current_setting('w7b.detached')::uuid); raise exception 'mismatched_contact_approved'; exception when others then if sqlerrm<>'Campaign audience is empty, mismatched, unresolved, or suppressed' then raise; end if; end;
end $$;
reset role;

set local role service_role;
update public.whatsapp_outbound_messages set state='delivered',send_phase='confirmed',provider_message_id='w7b-provider-safe',sent_at=now(),delivered_at=now(),lease_owner=null,lease_expires_at=null where id=current_setting('w7b.outbound')::uuid;
update public.whatsapp_contacts set candidate_id='89600000-0000-0000-0002-000000000002',resolution_status='resolved',marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='synthetic_test' where id=current_setting('w7b.c2')::uuid;
reset role;

set local role authenticated;
do $$ declare detail jsonb; begin
  if (public.admin_reconcile_whatsapp_campaign(current_setting('w7b.main')::uuid)->>'campaign_status')<>'completed' then raise exception 'Completion reconciliation failed'; end if;
  begin perform public.admin_cancel_whatsapp_campaign(current_setting('w7b.main')::uuid); raise exception 'terminal_cancel_accepted'; exception when others then if sqlerrm<>'Campaign can no longer be cancelled' then raise; end if; end;
  begin perform public.admin_queue_whatsapp_campaign(current_setting('w7b.failure')::uuid); raise exception 'suppressed_queue_accepted'; exception when others then if sqlerrm<>'Campaign recipient became suppressed or unresolved' then raise; end if; end;
  if exists(select 1 from public.audit_logs where entity_id=current_setting('w7b.failure')::uuid and action in ('whatsapp.campaign_queue_started','whatsapp.campaign_queue_completed')) then raise exception 'Failed queue retained audit'; end if;
  detail:=public.admin_get_whatsapp_campaign(current_setting('w7b.main')::uuid,100,0);
  if detail->>'created_by' is null or detail->>'approved_by' is null or (detail->>'audience_count')::integer<>1 or (detail->>'delivered_count')::integer<>1 or detail::text like '%9876600001%' then raise exception 'Detail projection failed'; end if;
  if not exists(select 1 from public.admin_list_whatsapp_campaigns(null,100,0) where campaign_id=current_setting('w7b.main')::uuid and campaign_status='completed' and audience_count=1 and delivered_count=1) then raise exception 'List projection failed'; end if;
  if not exists(select 1 from public.candidates where id='89600000-0000-0000-0002-000000000001' and full_name='Eligible One' and status='new') or not exists(select 1 from public.employer_requirements where id='89600000-0000-0000-0001-000000000001' and requirement_code='REQ-W7B-OPEN' and requirement_stage='open') or exists(select 1 from public.candidate_applications where candidate_id::text like '89600000-%') then raise exception 'Canonical fixture mutated'; end if;
end $$;
reset role;

set local role service_role;
update public.whatsapp_contacts set marketing_consent_status='opted_in',opted_out_at=null,opt_out_source=null,opt_out_reason_category=null where id=current_setting('w7b.c2')::uuid;
reset role;
set local role authenticated;
select public.admin_queue_whatsapp_campaign(current_setting('w7b.failure')::uuid);
select set_config('w7b.failed_outbound',(select outbound_message_id::text from public.whatsapp_campaign_recipients where campaign_id=current_setting('w7b.failure')::uuid and recipient_status='queued'),true);
reset role;
set local role service_role;
update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=now(),last_error_category='synthetic_terminal',last_error_code='synthetic_terminal' where id=current_setting('w7b.failed_outbound')::uuid;
reset role;
set local role authenticated;
do $$ begin
  if (public.admin_reconcile_whatsapp_campaign(current_setting('w7b.failure')::uuid)->>'campaign_status')<>'failed' then raise exception 'All-failed reconciliation failed'; end if;
  begin perform public.admin_cancel_whatsapp_campaign(current_setting('w7b.failure')::uuid); raise exception 'failed_cancel_accepted'; exception when others then if sqlerrm<>'Campaign can no longer be cancelled' then raise; end if; end;
end $$;
reset role;

rollback;

do $$ begin
  if exists(select 1 from public.whatsapp_campaigns where operation_key::text like '89600000-%')
     or exists(select 1 from public.whatsapp_campaign_recipients where candidate_id::text like '89600000-%')
     or exists(select 1 from public.whatsapp_outbound_messages where candidate_id::text like '89600000-%')
     or exists(select 1 from public.whatsapp_contacts where provider_address in ('+919876600001','+919876600002','+919876600007'))
     or exists(select 1 from public.audit_logs where actor_user_id::text like '89600000-%' or entity_id::text like '89600000-%')
     or exists(select 1 from public.candidates where id::text like '89600000-%')
     or exists(select 1 from public.employer_requirements where id::text like '89600000-%')
     or exists(select 1 from public.candidate_applications where candidate_id::text like '89600000-%')
     or exists(select 1 from public.admin_users where user_id::text like '89600000-%')
     or exists(select 1 from public.staff_profiles where user_id::text like '89600000-%')
     or exists(select 1 from public.staff_roles where user_id::text like '89600000-%')
     or exists(select 1 from auth.users where id::text like '89600000-%') then raise exception 'W7B checkpoint residue detected'; end if;
end $$;
