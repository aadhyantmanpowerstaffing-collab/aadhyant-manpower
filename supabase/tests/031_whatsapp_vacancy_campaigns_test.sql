-- W7B rollback checkpoint: vacancy campaigns, audience safety, W7A outbox reuse, and zero residue.

begin;

do $$
begin
  if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname in ('whatsapp_campaigns','whatsapp_campaign_recipients'))<>2 then
    raise exception 'W7B exact two-table contract is incomplete';
  end if;
  if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname in ('whatsapp_campaigns','whatsapp_campaign_recipients') and not c.relrowsecurity) then
    raise exception 'W7B RLS is incomplete';
  end if;
  if exists(select 1 from information_schema.role_table_grants where table_schema='public'
      and table_name in ('whatsapp_campaigns','whatsapp_campaign_recipients') and grantee in ('anon','authenticated')) then
    raise exception 'W7B browser base-table grant detected';
  end if;
  if (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in ('admin_preview_whatsapp_campaign_audience','admin_create_whatsapp_campaign',
      'admin_freeze_whatsapp_campaign_audience','admin_approve_whatsapp_campaign','admin_queue_whatsapp_campaign',
      'admin_cancel_whatsapp_campaign','admin_list_whatsapp_campaigns','admin_get_whatsapp_campaign'))<>8 then
    raise exception 'W7B RPC contract is incomplete';
  end if;
  if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname like '%whatsapp_campaign%'
      and n.nspname in ('public','private') and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%search_path=%') then
    raise exception 'W7B SECURITY DEFINER search_path posture is incomplete';
  end if;
end;
$$;

-- Synthetic authorization and canonical domain fixtures. The whole checkpoint rolls back.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
('89500000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7b-admin@test.local','x','{}','{}',now(),now()),
('89500000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w7b-viewer@test.local','x','{}','{}',now(),now());
insert into public.admin_users(user_id) values('89500000-0000-0000-0000-000000000001');
insert into public.staff_profiles(user_id,display_name,status) values('89500000-0000-0000-0000-000000000002','W7B Viewer','active');
insert into public.staff_roles(user_id,role,status,granted_by) values('89500000-0000-0000-0000-000000000002','viewer','active','89500000-0000-0000-0000-000000000001');

insert into public.employer_requirements(id,company_name,contact_person,mobile,company_location,job_role,required_headcount,
  qualification,iti_trade,experience_requirement,consent,status,requirement_code,job_location,filled_positions,requirement_visibility,requirement_stage)
values('89500000-0000-0000-0001-000000000001','W7B Employer','Contact','9876500000','Chennai','Fitter',2,
  'ITI','Fitter','Both',true,'in_progress','REQ-W7B-001','Chennai',0,'private','open');
insert into public.candidates(id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,specialization,
  candidate_type,interview_available,consent,status,profile_status,profile_completion_status,current_employment_status,availability_status)
values
('89500000-0000-0000-0002-000000000001','W7B Eligible',24,'Female','9876500001','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Fresher','Yes',true,'new','active','complete','unemployed','available'),
('89500000-0000-0000-0002-000000000002','W7B Excluded',25,'Male','9876500002','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','Yes',true,'new','active','complete','employed','open_to_opportunities'),
('89500000-0000-0000-0002-000000000003','W7B Suppressed',26,'Female','9876500003','Chennai','Chennai','Tamil Nadu','ITI','Fitter','Experienced','Yes',true,'new','active','complete','unknown','available');

set local role service_role;
select set_config('w7b.contact1',public.upsert_whatsapp_inbound_contact('+919876500001')::text,true);
select set_config('w7b.contact2',public.upsert_whatsapp_inbound_contact('+919876500002')::text,true);
select set_config('w7b.contact3',public.upsert_whatsapp_inbound_contact('+919876500003')::text,true);
update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source='synthetic_test',consent_scope='vacancy_campaign',
  consent_recorded_at=now(),consent_policy_version='w7b-test' where id in (current_setting('w7b.contact1')::uuid,current_setting('w7b.contact2')::uuid);
update public.whatsapp_contacts set marketing_consent_status='opted_out',opted_out_at=now(),opt_out_source='synthetic_test'
  where id=current_setting('w7b.contact3')::uuid;
reset role;

-- Non-Admin denial.
select set_config('request.jwt.claim.sub','89500000-0000-0000-0000-000000000002',true);
set local role authenticated;
do $$ begin
  begin perform public.admin_list_whatsapp_campaigns(null,25,0); raise exception 'Viewer campaign access accepted';
  exception when raise_exception then if sqlerrm='Viewer campaign access accepted' then raise; end if; end;
end $$;
reset role;

-- Admin lifecycle, matching, masking, suppression, manual exclusion, approval and queue idempotency.
select set_config('request.jwt.claim.sub','89500000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$
declare test_campaign_id uuid; first_queue integer; second_queue integer; preview_count integer; candidate_before bigint; application_before bigint;
begin
  select count(*) into candidate_before from public.candidates;
  select count(*) into application_before from public.candidate_applications;
  select count(*) into preview_count from public.admin_preview_whatsapp_campaign_audience(
    '89500000-0000-0000-0001-000000000001','{"qualification":"ITI","specialization":"Fitter","avoid_existing_application":true}'::jsonb,50,0)
    where contact_masked not like '%9876500001%' and candidate_name not like '%Eligible%';
  if preview_count<2 then raise exception 'Safe matching preview or masking failed'; end if;
  if not exists(select 1 from public.admin_preview_whatsapp_campaign_audience(
      '89500000-0000-0000-0001-000000000001','{}'::jsonb,50,0)
      where candidate_id='89500000-0000-0000-0002-000000000003' and not eligible and eligibility_reason='opted_out') then
    raise exception 'Suppression preview posture failed';
  end if;
  test_campaign_id:=public.admin_create_whatsapp_campaign('89500000-0000-0000-0001-000000000001','W7B Test Campaign',
    'vacancy_interest','en','1','{"qualification":"ITI","specialization":"Fitter"}'::jsonb);
  begin perform public.admin_approve_whatsapp_campaign(test_campaign_id); raise exception 'Draft approval accepted';
  exception when raise_exception then if sqlerrm='Draft approval accepted' then raise; end if; end;
  if public.admin_freeze_whatsapp_campaign_audience(test_campaign_id,
      array['89500000-0000-0000-0002-000000000001'::uuid,'89500000-0000-0000-0002-000000000001'::uuid],
      array['89500000-0000-0000-0002-000000000002'::uuid],1)<>1 then
    raise exception 'Audience freeze count failed';
  end if;
  begin perform public.admin_freeze_whatsapp_campaign_audience(test_campaign_id,
      array['89500000-0000-0000-0002-000000000003'::uuid],'{}'::uuid[],1); raise exception 'Suppressed include accepted';
  exception when raise_exception then if sqlerrm='Suppressed include accepted' then raise; end if; end;
  if not public.admin_approve_whatsapp_campaign(test_campaign_id) then raise exception 'Approval failed'; end if;
  first_queue:=public.admin_queue_whatsapp_campaign(test_campaign_id);
  second_queue:=public.admin_queue_whatsapp_campaign(test_campaign_id);
  if first_queue<>1 or second_queue<>1 then raise exception 'Queue idempotency failed'; end if;
  if (select count(*) from public.whatsapp_outbound_messages where requirement_id='89500000-0000-0000-0001-000000000001')<>1
     or (select count(*) from public.whatsapp_campaign_recipients where campaign_id=test_campaign_id and outbound_message_id is not null)<>1 then
    raise exception 'W7A outbox reuse failed';
  end if;
  if (select template_variables->>'action_id' from public.whatsapp_outbound_messages where requirement_id='89500000-0000-0000-0001-000000000001')<>'INTERESTED' then
    raise exception 'Future INTERESTED metadata is missing';
  end if;
  if candidate_before<>(select count(*) from public.candidates) or application_before<>(select count(*) from public.candidate_applications) then
    raise exception 'Campaign mutated Candidate or Application state';
  end if;
  if not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.campaign_created')
     or not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.audience_frozen')
     or not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.recipients_included')
     or not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.recipients_excluded')
     or not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.campaign_approved')
     or not exists(select 1 from public.audit_logs where entity_id=test_campaign_id and action='whatsapp.campaign_queued') then
    raise exception 'Campaign audit trail is incomplete';
  end if;
end;
$$;
reset role;

-- Unique constraints and row locks in freeze/approve/queue are the queue-race boundary.
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.whatsapp_campaign_recipients'::regclass
      and contype='u' and pg_get_constraintdef(oid) ilike '%campaign_id%candidate_id%') then
    raise exception 'Campaign Candidate race constraint is missing';
  end if;
  if exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_contacts wc on wc.id=cr.whatsapp_contact_id
      where wc.marketing_consent_status='opted_out' and cr.recipient_status in ('included','queued')) then
    raise exception 'Suppressed recipient entered campaign audience';
  end if;
end;
$$;

rollback;

-- After execution, fixture IDs 89500000-* and W7B audit/outbox rows must remain zero by transaction rollback.
