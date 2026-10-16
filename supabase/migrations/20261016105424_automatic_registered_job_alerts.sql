-- Automatic alerts reuse canonical campaigns/recipients/outbox. OFF on installation.
begin;
alter table private.whatsapp_console_config
 add column automatic_alerts_enabled boolean not null default false,
 add column automatic_alerts_approved_by uuid references auth.users(id),
 add column automatic_alerts_enabled_at timestamptz,
 add column automatic_alerts_daily_limit integer not null default 100 check(automatic_alerts_daily_limit between 10 and 1000),
 add column automatic_alerts_worker_verified_at timestamptz;
alter table public.whatsapp_campaigns drop constraint whatsapp_campaigns_audience_mode_check;
alter table public.whatsapp_campaigns add constraint whatsapp_campaigns_audience_mode_check
 check(audience_mode in ('candidate_matching','sharing_contacts','selected_contacts','registered_alerts'));
-- A once-per-vacancy publication marker, not a second delivery queue.
create table private.whatsapp_job_publications(
 requirement_id uuid primary key references public.employer_requirements(id),
 published_at timestamptz not null default clock_timestamp(),
 campaign_id uuid unique references public.whatsapp_campaigns(id),
 job_snapshot jsonb not null,
 authorized_by uuid references auth.users(id),
 outcome text not null check(outcome in ('disabled','template_unavailable','queued','empty'))
);
alter table private.whatsapp_job_publications enable row level security;
revoke all on private.whatsapp_job_publications from public,anon,authenticated,service_role;

create function private.registered_alert_body() returns text language sql immutable set search_path='' as $$
 select E'Hello,\n\nAadhyant Manpower & Staffing has a new job opening.\n\nVacancy: {{1}}\nRole: {{2}}\nLocation: {{3}}\n\nQualification: {{4}}\n\nSalary Details\n{{5}}\n\nBenefits & Duty\n{{6}}\n\nView the job and apply, or share it with someone looking for work.\nTo stop WhatsApp job alerts, tap Stop alerts or reply STOP.'
$$;
create function private.registered_alert_buttons() returns jsonb language sql immutable set search_path='' as $$
 select '[{"type":"URL","text":"View Job & Apply","url":"https://aadhyantmanpower.in/jobs/?requirement={{1}}"},{"type":"QUICK_REPLY","text":"Stop alerts"}]'::jsonb
$$;
-- Keep the original template sync validation for the existing manual campaign.
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_registered;
revoke all on function public.console_sync_templates_before_registered(jsonb) from public,anon,authenticated,service_role;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=public.console_sync_templates_before_registered(p_rows);
 -- Meta may return review samples on URL buttons; samples are not message bindings.
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_registered_job_alert_v1' and t.language='en';
 update public.whatsapp_template_catalog t set compatible=
  t.body=private.registered_alert_body() and t.buttons=private.registered_alert_buttons()
  and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1
    and not exists(select 1 from jsonb_array_elements(r->'components') b where b->>'type' not in ('BODY','BUTTONS')))
 where t.name='aadhyant_registered_job_alert_v1' and t.language='en';
 return n;
end; $$;
-- Explicit candidate-facing fields only. No contact details or private notes.
create function private.registered_alert_variables(p_requirement_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare j jsonb; salary text; benefits text; cadence text;
begin
 select to_jsonb(r) into strict j from public.employer_requirements r where r.id=p_requirement_id;
 cadence:=coalesce(nullif(j->>'compensation_cadence',''),'period not specified');
 salary:=concat_ws('; ',case when nullif(j->>'ctc','') is not null then 'CTC: INR '||(j->>'ctc')||' ('||cadence||')' end,
  case when nullif(j->>'approx_in_hand','') is not null then 'Approx. take home: INR '||(j->>'approx_in_hand')||' ('||cadence||')' end,
  case when nullif(j->>'salary_wage','') is not null then 'Salary: '||(j->>'salary_wage') end,
  case when nullif(j->>'overtime_rate','') is not null then 'OT: '||(j->>'overtime_rate')||' '||coalesce(j->>'overtime_rate_basis','basis not specified') else case when nullif(j->>'overtime_details','') is not null then 'OT: '||(j->>'overtime_details') end end);
 benefits:=concat_ws('; ',case when coalesce((j->>'employee_pf')::numeric,0)>0 then 'PF contribution listed' end,case when coalesce((j->>'employee_esic')::numeric,0)>0 then 'ESIC contribution listed' end,case when nullif(j->>'working_hours','') is not null then 'Duty: '||(j->>'working_hours') end,
  case when nullif(j->>'shift_details','') is not null then 'Shift: '||(j->>'shift_details') end,
  case when j->>'transport_status'='free' then 'Free transport' when j->>'transport_status'='chargeable' then 'Transport: INR '||(j->>'transport_charge_amount')||' '||(j->>'transport_charge_basis') end,
  case when j->>'canteen_status'='free' then 'Free canteen' when j->>'canteen_status'='chargeable' then 'Canteen: INR '||(j->>'canteen_charge_amount')||' '||(j->>'canteen_charge_basis') end,
  case when nullif(j->>'attendance_bonus','') is not null then 'Attendance bonus: INR '||(j->>'attendance_bonus')||' ('||cadence||')' end);
 return jsonb_build_object('requirement_code',j->>'requirement_code','job_role',j->>'job_role',
  'job_location',coalesce(nullif(j->>'job_location',''),nullif(j->>'company_location',''),'Not specified'),
  'qualification',coalesce(nullif(j->>'qualification',''),'Not specified'),
  'salary_details',coalesce(nullif(salary,''),'See job page for salary details'),
  'benefits_details',coalesce(nullif(benefits,''),'See job page for benefits and duty details'));
end; $$;
create function private.registered_alert_contact_eligible(p_contact_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_contacts w join public.candidates c on c.id=w.candidate_id
 where w.id=p_contact_id and w.provider='whatsapp' and w.resolution_status='resolved'
 and c.profile_status='active' and c.status<>'inactive'
 and (c.mobile=w.indian_mobile_key or c.whatsapp_number=w.indian_mobile_key)
 and (select count(*) from public.candidates other where other.mobile=w.indian_mobile_key or other.whatsapp_number=w.indian_mobile_key)=1
 and w.marketing_consent_status='opted_in' and w.consent_recorded_at<=clock_timestamp()
 and (w.consent_scope='all_job_alerts' or (w.consent_scope='vacancy_alerts' and w.consent_source='candidate_portal' and w.consent_policy_version='candidate-job-alerts-v1') or (w.consent_scope='job_updates_and_sharing' and w.sharing_subscription->>'scope'='all'))
 and private.whatsapp_contact_allows_purpose(w.id,'marketing'))
$$;
create function public.admin_console_automatic_alerts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select jsonb_build_object('enabled',automatic_alerts_enabled,'daily_limit',automatic_alerts_daily_limit,
 'worker_ready',automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes',
 'template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v1' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
 'eligible_subscribers',(select count(*) from public.whatsapp_contacts w where private.registered_alert_contact_eligible(w.id)),
 'recent_publications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
 select r.requirement_code,p.published_at,p.campaign_id,p.outcome,
 case when p.authorized_by is not null and p.job_snapshot is distinct from private.registered_alert_variables(r.id) then 'Job changed; pending messages paused' else null end attention
 from private.whatsapp_job_publications p join public.employer_requirements r on r.id=p.requirement_id order by p.published_at desc limit 25)x))
 from private.whatsapp_console_config where singleton);
end; $$;
create function public.admin_console_set_automatic_alerts(p_enabled boolean,p_daily_limit integer default 100)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_enabled is null or p_daily_limit is null or p_daily_limit not between 10 and 1000 then raise exception 'Daily limit must be 10 to 1000'; end if;
 perform 1 from private.whatsapp_console_config where singleton for update;
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v1' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours')
 or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours' and automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes')) then
 raise exception 'Approved template, verified sender and running automatic worker required'; end if;
 update private.whatsapp_console_config set automatic_alerts_enabled=p_enabled,automatic_alerts_daily_limit=p_daily_limit,
 automatic_alerts_approved_by=case when p_enabled then auth.uid() else automatic_alerts_approved_by end,
 automatic_alerts_enabled_at=case when p_enabled then clock_timestamp() else automatic_alerts_enabled_at end where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.automatic_alerts_configured','whatsapp_campaign','admin',jsonb_build_object('enabled',p_enabled,'daily_limit',p_daily_limit));
 return true;
end; $$;
create function private.prepare_registered_publication(p_requirement_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v1' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
 update private.whatsapp_job_publications set outcome='template_unavailable' where requirement_id=req.id;return;end if;
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,template_name,template_language,template_version,
 criteria,created_by,approved_by,approved_at,queued_at,audience_frozen_at,audience_mode,console_template_id,console_template_snapshot)
 values(gen_random_uuid(),req.id,'Auto job alert: '||left(req.requirement_code,100),'queued','vacancy_campaign','marketing',t.name,t.language,t.version,'{}',
 pub.authorized_by,pub.authorized_by,stamp,stamp,stamp,'registered_alerts',t.id,
 jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons)) returning id into cid;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
 select cid,w.candidate_id,w.id,'matched','included','["registered_all_job_alerts","no_matching_filter"]' from public.whatsapp_contacts w
 where private.registered_alert_contact_eligible(w.id) and w.consent_recorded_at<=stamp and w.created_at<=stamp and exists(select 1 from public.candidates pc where pc.id=w.candidate_id and pc.created_at<=stamp);
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(pub.authorized_by,'staff','whatsapp.automatic_campaign_prepared','whatsapp_campaign',cid,'whatsapp',jsonb_build_object('requirement_id',req.id,'audience_count',n,'standing_approval',true));
 update private.whatsapp_job_publications set campaign_id=cid,outcome=case when n=0 then 'empty' else 'queued' end where requirement_id=req.id;
 if n=0 then update public.whatsapp_campaigns set campaign_status='completed',completed_at=stamp where id=cid; end if;

end; $$;
create function private.capture_registered_job_publication() returns trigger language plpgsql security definer set search_path='' as $$
declare cfg private.whatsapp_console_config%rowtype;
begin
 if not private.vacancy_is_application_eligible(new.id) then return new; end if;
 if tg_op='UPDATE' and old.review_status is not distinct from new.review_status
 and old.requirement_stage is not distinct from new.requirement_stage
 and old.requirement_visibility is not distinct from new.requirement_visibility then return new;end if;
 select * into strict cfg from private.whatsapp_console_config where singleton for share;
 insert into private.whatsapp_job_publications(requirement_id,job_snapshot,authorized_by,outcome)
 values(new.id,private.registered_alert_variables(new.id),case when cfg.automatic_alerts_enabled then cfg.automatic_alerts_approved_by end,
 case when cfg.automatic_alerts_enabled then 'template_unavailable' else 'disabled' end) on conflict do nothing;
 if found and cfg.automatic_alerts_enabled then perform private.prepare_registered_publication(new.id);end if;
 return new;
end; $$;
-- Existing public jobs are marked without campaigns, never replayed on activation.
insert into private.whatsapp_job_publications(requirement_id,job_snapshot,outcome)
 select r.id,private.registered_alert_variables(r.id),'disabled' from public.employer_requirements r where private.vacancy_is_application_eligible(r.id);
create trigger capture_registered_job_publication after insert or update on public.employer_requirements
 for each row execute function private.capture_registered_job_publication();

alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_registered;
revoke all on function private.whatsapp_vacancy_send_eligible_before_registered(uuid) from public,anon,authenticated,service_role;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare mode text;
begin
 select c.audience_mode into mode from public.whatsapp_campaigns c join public.whatsapp_campaign_recipients cr on cr.campaign_id=c.id where cr.outbound_message_id=p_message_id;
 if mode is distinct from 'registered_alerts' then
  if exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and template_name='aadhyant_registered_job_alert_v1') then return false; end if;
  return private.whatsapp_vacancy_send_eligible_before_registered(p_message_id);
 end if;
 return exists(select 1 from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients cr on cr.outbound_message_id=o.id
 join public.whatsapp_campaigns c on c.id=cr.campaign_id join private.whatsapp_job_publications p on p.campaign_id=c.id
 cross join private.whatsapp_console_config cfg
 where o.id=p_message_id and cfg.singleton and cfg.automatic_alerts_enabled
 and cr.recipient_status='queued' and c.campaign_status in ('queued','sending') and c.cancelled_at is null and c.approved_at is not null and c.queued_at is not null
 and o.contact_id=cr.whatsapp_contact_id and o.candidate_id=cr.candidate_id and o.requirement_id=c.requirement_id and o.correlation_id=cr.id
 and o.template_name=c.template_name and o.template_language=c.template_language and o.template_version=c.template_version
 and o.purpose='vacancy_campaign' and o.consent_class='marketing'
 and private.console_template_valid(c.id) and private.vacancy_is_application_eligible(c.requirement_id)
 and private.registered_alert_contact_eligible(o.contact_id) and exists(select 1 from public.whatsapp_contacts w where w.id=o.contact_id and w.candidate_id=o.candidate_id)
 and p.job_snapshot=private.registered_alert_variables(c.requirement_id)
 and o.template_variables=p.job_snapshot||jsonb_build_object('campaign_id',c.id,'recipient_id',cr.id));
end; $$;
-- Service heartbeat is proof of an authenticated scheduler invocation, not enablement.
create function public.console_automatic_worker_heartbeat() returns boolean language plpgsql security definer set search_path='' as $$
begin update private.whatsapp_console_config set automatic_alerts_worker_verified_at=clock_timestamp() where singleton;return true;end; $$;
-- Manual processing cannot bypass the automatic quota or its separate worker gate.
alter function public.console_claim_campaign(uuid,text) rename to console_claim_campaign_before_registered;
revoke all on function public.console_claim_campaign_before_registered(uuid,text) from public,anon,authenticated,service_role;
create function public.console_claim_campaign(p_campaign_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 if p_campaign_id is null or exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and audience_mode='registered_alerts') then return; end if;
 return query select * from public.console_claim_campaign_before_registered(p_campaign_id,p_worker_id);
end; $$;
revoke all on function public.console_claim_campaign(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_campaign(uuid,text) to service_role;
create function public.console_claim_registered_alerts(p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
declare cfg private.whatsapp_console_config%rowtype; c public.whatsapp_campaigns%rowtype; cr record; pending record; oid uuid; n integer; vars jsonb;
begin
 -- Serialize automatic claims and reserve a conservative rolling 24-hour quota.
 select * into strict cfg from private.whatsapp_console_config where singleton for update;
 if not cfg.automatic_alerts_enabled then return; end if;
 for pending in select requirement_id from private.whatsapp_job_publications where outcome='template_unavailable' and authorized_by is not null and campaign_id is null order by published_at limit 10 loop
  perform private.prepare_registered_publication(pending.requirement_id);
 end loop;
 update public.whatsapp_campaigns wc set campaign_status=case when exists(select 1 from public.whatsapp_campaign_recipients r join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id where r.campaign_id=wc.id and o.state='failed') then 'failed' else 'completed' end,completed_at=clock_timestamp()
 where wc.audience_mode='registered_alerts' and wc.campaign_status in ('queued','sending')
 and not exists(select 1 from public.whatsapp_campaign_recipients r left join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id
 where r.campaign_id=wc.id and (r.recipient_status='included' or o.state in ('queued','sending')));

 select coalesce(sum(o.attempt_count),0) into n from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients r on r.outbound_message_id=o.id
 join public.whatsapp_campaigns wc on wc.id=r.campaign_id where wc.audience_mode='registered_alerts' and o.updated_at>clock_timestamp()-interval '24 hours';
 if n+10>cfg.automatic_alerts_daily_limit then return; end if;
 select wc.* into c from public.whatsapp_campaigns wc join private.whatsapp_job_publications p on p.campaign_id=wc.id
 where wc.audience_mode='registered_alerts' and wc.campaign_status in ('queued','sending') and wc.cancelled_at is null
 and private.console_template_valid(wc.id) and private.vacancy_is_application_eligible(wc.requirement_id)
 and p.job_snapshot=private.registered_alert_variables(wc.requirement_id)
 and exists(select 1 from public.whatsapp_campaign_recipients r left join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id
 where r.campaign_id=wc.id and (r.recipient_status='included' or (o.state='queued' and private.whatsapp_vacancy_send_eligible(o.id)) or o.state='sending'))
 order by wc.created_at,wc.id limit 1 for update of wc;
 if not found then return; end if;
 select p.job_snapshot into vars from private.whatsapp_job_publications p where p.campaign_id=c.id;
 for cr in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id limit 10 for update loop
  if not private.registered_alert_contact_eligible(cr.whatsapp_contact_id) then
   update public.whatsapp_campaign_recipients set recipient_status='excluded',exclusion_reason='suppressed' where id=cr.id;
  else
   oid:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,c.requirement_id,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
    vars||jsonb_build_object('campaign_id',c.id,'recipient_id',cr.id),'campaign:'||c.id||':recipient:'||cr.id,cr.id,1);
   update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=oid where id=cr.id;
  end if;
 end loop;
 return query select * from public.console_claim_campaign_before_registered(c.id,p_worker_id);
end; $$;
revoke all on function private.registered_alert_body(),private.registered_alert_buttons(),private.registered_alert_variables(uuid),private.registered_alert_contact_eligible(uuid),private.capture_registered_job_publication(),private.prepare_registered_publication(uuid),private.whatsapp_vacancy_send_eligible(uuid),
 public.console_sync_templates(jsonb),public.admin_console_automatic_alerts(),public.admin_console_set_automatic_alerts(boolean,integer),public.console_automatic_worker_heartbeat(),public.console_claim_registered_alerts(text) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb),public.console_automatic_worker_heartbeat(),public.console_claim_registered_alerts(text) to service_role;
grant execute on function public.admin_console_automatic_alerts(),public.admin_console_set_automatic_alerts(boolean,integer) to authenticated;
commit;
