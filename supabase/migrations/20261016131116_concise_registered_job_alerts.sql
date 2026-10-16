-- User-approved concise summary; full job detail and application remain on the existing job page.
begin;
create or replace function private.registered_alert_body() returns text language sql immutable set search_path='' as $$ select E'Hello,\n\n*Aadhyant Manpower & Staffing* has a new job opening. Review the summary below and share this opportunity with someone looking for work.\n\n*Job details*\n• Vacancy: {{1}}\n• Company: {{2}}\n• Role: {{3}}\n• Location: {{4}}\n\n*Qualification*\n{{5}}\n\n*Salary & duty*\n• CTC / Salary: {{6}}\n• Approx. take home: {{7}}\n• Overtime: {{8}}\n• Duty: {{9}}\n\n*Benefits*\n{{10}}\n\nTap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.\nTo stop WhatsApp job alerts, tap Stop alerts or reply STOP.' $$;
create function private.registered_alert_render(p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text:=private.registered_alert_body(); k text; n integer:=0;
begin
 foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop n:=n+1;rendered:=replace(rendered,'{{'||n||'}}',coalesce(p_vars->>k,''));end loop;
 return rendered;
end; $$;
alter function private.whatsapp_safe_flat_json(jsonb) rename to whatsapp_safe_flat_json_before_summary_job;
revoke all on function private.whatsapp_safe_flat_json_before_summary_job(jsonb) from public,anon,authenticated,service_role;
create function private.whatsapp_safe_flat_json(p_value jsonb) returns boolean language plpgsql immutable security definer set search_path='' as $$
declare k text; v jsonb;
begin
 if p_value->>'template_contract' is distinct from 'registered_summary_v4' then return private.whatsapp_safe_flat_json_before_summary_job(p_value);end if;
 if jsonb_typeof(p_value)<>'object' or octet_length(p_value::text)>16384 then return false;end if;
 for k,v in select key,value from jsonb_each(p_value) loop
  if k=any(array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits']) then
   if jsonb_typeof(v)<>'string' or char_length(v#>>'{}') not between 1 and 300 or (v#>>'{}') ~ '[\n\r\t]' or (v#>>'{}') ~ ' {5}' then return false;end if;
  elsif k not in ('template_contract','job_fingerprint','campaign_id','recipient_id') then return false;
  end if;
 end loop;
 if exists(select 1 from unnest(array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits']) wanted where not p_value ? wanted) or coalesce(p_value->>'job_fingerprint','') !~ '^[a-f0-9]{64}$' then return false;end if;
 return private.whatsapp_safe_flat_json_before_full_job(p_value) and char_length(private.registered_alert_render(p_value))<=1024;
end; $$;
create or replace function private.registered_alert_variables(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb; salary text; home text; overtime text; duty text; benefits text; cadence text; result jsonb; k text; v text;
begin
 select to_jsonb(r) into strict j from public.employer_requirements r where r.id=p_requirement_id;
 cadence:=replace(coalesce(nullif(j->>'compensation_cadence',''),'period not specified'),'_',' ');
 salary:=case when nullif(j->>'salary_min','') is not null and nullif(j->>'salary_max','') is not null then 'INR '||(j->>'salary_min')||' to '||(j->>'salary_max')||' ('||cadence||')'
 when nullif(j->>'ctc','') is not null then 'INR '||(j->>'ctc')||' ('||cadence||')'
 else coalesce(nullif(j->>'salary_wage',''),'See full job details') end;
 home:=case when nullif(j->>'approx_in_hand','') is not null then 'INR '||(j->>'approx_in_hand')||' ('||cadence||')' else 'See full job details' end;
 overtime:=case when nullif(j->>'overtime_rate','') is not null then 'INR '||(j->>'overtime_rate')||' ('||replace(coalesce(nullif(j->>'overtime_rate_basis',''),'basis not specified'),'_',' ')||')' else coalesce(nullif(j->>'overtime_details',''),'See full job details') end;
 duty:=concat_ws('; ',case when j->>'working_hours' ~ '^[0-9]+([.][0-9]+)?$' then (j->>'working_hours')||' hours' else nullif(j->>'working_hours','') end,nullif(j->>'shift_details',''));
 benefits:=concat_ws('; ',case when coalesce((j->>'employee_pf')::numeric,0)>0 or coalesce((j->>'employer_pf')::numeric,0)>0 then 'PF listed' end,
 case when coalesce((j->>'employee_esic')::numeric,0)>0 or coalesce((j->>'employer_esic')::numeric,0)>0 then 'ESIC listed' end,
 case when j->>'transport_status'='free' then 'Free transport' when j->>'transport_status'='chargeable' then 'Transport charges apply' end,
 case when j->>'canteen_status'='free' then 'Free canteen' when j->>'canteen_status'='chargeable' then 'Canteen charges apply' end,
 case when j->>'accommodation_status'='free' then 'Free accommodation' when j->>'accommodation_status'='chargeable' then 'Accommodation charges apply' end,
 case when coalesce((j->>'attendance_bonus')::numeric,0)>0 then 'Attendance bonus listed' end);
 if char_length(benefits)>180 then benefits:='Benefits listed; see full job for amounts, conditions and charges';end if;
 result:=jsonb_build_object('template_contract','registered_summary_v4','requirement_code',j->>'requirement_code',
 'company',coalesce(nullif(j->>'company_name',''),'See full job details'),'job_role',j->>'job_role',
 'job_location',coalesce(nullif(j->>'job_location',''),nullif(j->>'company_location',''),'See full job details'),
 'qualification',coalesce(nullif(j->>'qualification',''),'See full job details'),'salary',salary,'take_home',home,'overtime',overtime,
 'duty',coalesce(nullif(duty,''),'See full job details'),'benefits',coalesce(nullif(benefits,''),'See full job for benefits and conditions'),
 -- Changes to any full public job term still pause a frozen publication even when not printed in the summary.
 'job_fingerprint',encode(sha256(convert_to(private.registered_alert_variables_before_readable_job(p_requirement_id)::text,'UTF8')),'hex'));
 for k,v in select key,value from jsonb_each_text(result) loop result:=jsonb_set(result,array[k],to_jsonb(btrim(regexp_replace(v,'[[:space:]]+',' ','g'))));end loop;
 return result;
end; $$;
create or replace function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=public.console_sync_templates_before_registered(p_rows);
 -- Meta may return review samples on URL buttons; samples are not message bindings.
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_registered_job_alert_v4' and t.language='en';
 update public.whatsapp_template_catalog t set compatible=
  t.body=private.registered_alert_body() and t.buttons=private.registered_alert_buttons()
  and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1
    and not exists(select 1 from jsonb_array_elements(r->'components') b where b->>'type' not in ('BODY','BUTTONS')))
 where t.name='aadhyant_registered_job_alert_v4' and t.language='en';
 return n;
end; $$;
create or replace function public.admin_console_automatic_alerts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select jsonb_build_object('enabled',automatic_alerts_enabled,'daily_limit',automatic_alerts_daily_limit,
 'worker_ready',automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes',
 'template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v4' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
 'eligible_subscribers',(select count(*) from public.whatsapp_contacts w where private.registered_alert_contact_eligible(w.id)),
 'recent_publications',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
 select r.requirement_code,p.published_at,p.campaign_id,p.outcome,
 case when p.authorized_by is not null and p.job_snapshot is distinct from private.registered_alert_variables(r.id) then 'Job changed; pending messages paused' else null end attention
 from private.whatsapp_job_publications p join public.employer_requirements r on r.id=p.requirement_id order by p.published_at desc limit 25)x))
 from private.whatsapp_console_config where singleton);
end; $$;
create or replace function public.admin_console_set_automatic_alerts(p_enabled boolean,p_daily_limit integer default 100)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_enabled is null or p_daily_limit is null or p_daily_limit not between 10 and 1000 then raise exception 'Daily limit must be 10 to 1000'; end if;
 perform 1 from private.whatsapp_console_config where singleton for update;
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v4' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours')
 or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours' and automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes')) then
 raise exception 'Approved template, verified sender and running automatic worker required'; end if;
 update private.whatsapp_console_config set automatic_alerts_enabled=p_enabled,automatic_alerts_daily_limit=p_daily_limit,
 automatic_alerts_approved_by=case when p_enabled then auth.uid() else automatic_alerts_approved_by end,
 automatic_alerts_enabled_at=case when p_enabled then clock_timestamp() else automatic_alerts_enabled_at end where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.automatic_alerts_configured','whatsapp_campaign','admin',jsonb_build_object('enabled',p_enabled,'daily_limit',p_daily_limit));
 return true;
end; $$;
create or replace function private.prepare_registered_publication(p_requirement_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v4' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
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
revoke all on function private.whatsapp_safe_flat_json(jsonb),private.registered_alert_variables(uuid) from public,anon,authenticated,service_role;
create or replace function public.admin_console_preview_full_job_alert(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; rendered text;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);rendered:=private.registered_alert_render(vars);
 return jsonb_build_object('template_name','aadhyant_registered_job_alert_v4','message',rendered,'within_limits',private.whatsapp_safe_flat_json(vars),
 'body_limit',1024,'body_characters',char_length(rendered),'detail_mode','summary_with_full_job_link');
end; $$;
revoke all on function public.admin_console_preview_full_job_alert(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_preview_full_job_alert(uuid) to authenticated;
create or replace function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare mode text;
begin
 select c.audience_mode into mode from public.whatsapp_campaigns c join public.whatsapp_campaign_recipients cr on cr.campaign_id=c.id where cr.outbound_message_id=p_message_id;
 if mode is distinct from 'registered_alerts' then
  if exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and template_name in ('aadhyant_registered_job_alert_v1','aadhyant_registered_job_alert_v2','aadhyant_registered_job_alert_v3','aadhyant_registered_job_alert_v4')) then return false; end if;
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


revoke all on function private.registered_alert_render(jsonb) from public,anon,authenticated,service_role;
commit;
