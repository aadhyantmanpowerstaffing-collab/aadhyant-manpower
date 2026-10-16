-- Upgrade only; preserve installed migrations, canonical outbox and current OFF state.
begin;
create or replace function private.registered_alert_body() returns text language sql immutable set search_path='' as $$
 select E'Hello,\n\nAadhyant Manpower & Staffing has a new job opening. The employer has provided the following job information.\n\n*Vacancy reference*\n{{1}}\n\n*Company and role*\n{{2}}\n\n*Location and openings*\n{{3}}\n\n*Candidate requirements*\n{{4}}\n\n*Salary and earnings*\n{{5}}\n\n*Employee deductions*\n{{6}}\n\n*Employer contributions and CTC provisions*\n{{7}}\n\n*Duty, shifts and overtime*\n{{8}}\n\n*Facilities and charges*\n{{9}}\n\n*Leave and holidays*\n{{10}}\n\n*Employment terms*\n{{11}}\n\n*Interview and joining*\n{{12}}\n\n*Additional benefits*\n{{13}}\n\n*Job description*\n{{14}}\n\n*Job description continued*\n{{15}}\n\nView the job and apply, or share this opportunity with someone looking for work. To stop WhatsApp job alerts, tap Stop alerts or reply STOP.'
$$;
-- A narrowly scoped v2 envelope permits at most 1000 characters per public job section.
-- The original validator still checks all non-section values and all legacy messages.
alter function private.whatsapp_safe_flat_json(jsonb) rename to whatsapp_safe_flat_json_before_full_job;
revoke all on function private.whatsapp_safe_flat_json_before_full_job(jsonb) from public,anon,authenticated,service_role;
create function private.whatsapp_safe_flat_json(p_value jsonb) returns boolean language plpgsql immutable security definer set search_path='' as $$
declare cleaned jsonb:=p_value; k text; v jsonb;
begin
 if p_value->>'template_contract' is distinct from 'registered_full_v2' then return private.whatsapp_safe_flat_json_before_full_job(p_value);end if;
 if jsonb_typeof(p_value)<>'object' or octet_length(p_value::text)>16384 then return false;end if;
 for k,v in select key,value from jsonb_each(p_value) loop
  if k=any(array['requirement_code','job_identity','job_location','eligibility','earnings','deductions','employer_cost','duty','facilities','leave_terms','employment_terms','interview_joining','candidate_benefits','description_1','description_2']) then
   if jsonb_typeof(v)<>'string' or char_length(v#>>'{}') not between 1 and 1000 or (v#>>'{}') ~ '[\n\r\t]' then return false;end if;
   cleaned:=jsonb_set(cleaned,array[k],to_jsonb('checked public job section'::text));
  elsif k not in ('template_contract','campaign_id','recipient_id') then return false;
  end if;
 end loop;
 return private.whatsapp_safe_flat_json_before_full_job(cleaned);
end; $$;
create function private.full_job_section(p_job jsonb,p_fields jsonb) returns text language plpgsql immutable security definer set search_path='' as $$
declare field jsonb; result text:=''; v text;
begin
 for field in select value from jsonb_array_elements(p_fields) loop
  v:=nullif(btrim(regexp_replace(coalesce(p_job->>(field->>0),''),'[[:space:]]+',' ','g')),'');
  if v is not null then result:=concat_ws('; ',nullif(result,''),(field->>1)||': '||replace(v,'_',' '));end if;
 end loop;
 return coalesce(nullif(result,''),'No details supplied for this section.');
end; $$;
create or replace function private.registered_alert_variables(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare j jsonb; result jsonb; benefits jsonb; b jsonb; benefit_text text:=''; description text; interview text;
begin
 select to_jsonb(r) into strict j from public.employer_requirements r where r.id=p_requirement_id;
 j:=j||jsonb_build_object('job_location',coalesce(nullif(j->>'job_location',''),j->>'company_location'),
 'open_positions',greatest(coalesce((j->>'required_headcount')::integer,0)-coalesce((j->>'filled_positions')::integer,0),0));
 if nullif(j->>'interview_date','') is not null then
  j:=j||jsonb_build_object('interview_date_display',to_char((j->>'interview_date')::timestamptz at time zone 'Asia/Kolkata','DD Mon YYYY HH24:MI')||' IST');
 end if;
 result:=jsonb_build_object('template_contract','registered_full_v2','requirement_code',j->>'requirement_code');
 result:=result||jsonb_build_object('job_identity',private.full_job_section(j,'[["company_name", "Company / worksite"], ["department", "Department"], ["job_role", "Role"]]'::jsonb));
 result:=result||jsonb_build_object('job_location',private.full_job_section(j,'[["job_location", "Location"], ["open_positions", "Open positions"], ["required_headcount", "Total openings"]]'::jsonb));
 result:=result||jsonb_build_object('eligibility',private.full_job_section(j,'[["qualification", "Qualification"], ["iti_trade", "Trade / specialization"], ["experience_requirement", "Experience"], ["gender_preference", "Gender"], ["age_min", "Minimum age"], ["age_max", "Maximum age"]]'::jsonb));
 result:=result||jsonb_build_object('earnings',private.full_job_section(j,'[["compensation_cadence", "Salary period"], ["salary_min", "Minimum CTC (INR)"], ["salary_max", "Maximum CTC (INR)"], ["salary_wage", "Salary information"], ["payable_days", "Payable days"], ["basic_da", "Basic + DA (INR)"], ["attendance_bonus", "Attendance bonus (INR)"], ["monthly_bonus", "Monthly bonus (INR)"], ["leave_amount", "Leave amount (INR)"], ["other_fixed_earning", "Other fixed earnings (INR)"], ["gross_wages", "Gross wages (INR)"], ["approx_in_hand", "Approx. take home (INR)"], ["ctc", "CTC (INR)"]]'::jsonb));
 result:=result||jsonb_build_object('deductions',private.full_job_section(j,'[["employee_pf", "Employee PF (INR)"], ["employee_esic", "Employee ESIC (INR)"], ["canteen_deduction", "Canteen deduction (INR)"], ["other_deduction", "Other deduction (INR)"]]'::jsonb));
 result:=result||jsonb_build_object('employer_cost',private.full_job_section(j,'[["employer_pf", "Employer PF (INR)"], ["employer_esic", "Employer ESIC (INR)"], ["gratuity_provision", "Gratuity provision (INR)"], ["bonus_provision", "Bonus provision (INR)"], ["leave_provision", "Leave provision (INR)"], ["other_ctc_component", "Other CTC component (INR)"]]'::jsonb));
 result:=result||jsonb_build_object('duty',private.full_job_section(j,'[["working_hours", "Duty hours"], ["shift_details", "Shift"], ["working_days_per_week", "Working days / week"], ["weekly_off_count", "Weekly offs"], ["overtime_rate", "OT rate"], ["overtime_rate_basis", "OT rate basis"], ["overtime_details", "OT information"]]'::jsonb));
 result:=result||jsonb_build_object('facilities',private.full_job_section(j,'[["canteen_status", "Canteen"], ["canteen_charge_amount", "Canteen charge (INR)"], ["canteen_charge_basis", "Canteen charge basis"], ["canteen", "Canteen information"], ["transport_status", "Transport"], ["transport_charge_amount", "Transport charge (INR)"], ["transport_charge_basis", "Transport charge basis"], ["transport", "Transport information"], ["accommodation_status", "Accommodation"], ["accommodation_charge_amount", "Accommodation charge (INR)"], ["accommodation_charge_basis", "Accommodation charge basis"], ["accommodation", "Accommodation information"]]'::jsonb));
 result:=result||jsonb_build_object('leave_terms',private.full_job_section(j,'[["paid_leave_days_per_year", "Paid leave days / year"], ["casual_leave_days_per_year", "Casual leave days / year"], ["sick_leave_days_per_year", "Sick leave days / year"], ["national_holiday_days_per_year", "National holiday days / year"], ["festival_holiday_days_per_year", "Festival holiday days / year"]]'::jsonb));
 result:=result||jsonb_build_object('employment_terms',private.full_job_section(j,'[["employment_type", "Employment"], ["payroll_type", "Payroll"], ["contract_duration_months", "Contract months"], ["probation_period_months", "Probation months"], ["training_period_days", "Training days"], ["notice_period_days", "Notice days"]]'::jsonb));
 result:=result||jsonb_build_object('interview_joining',private.full_job_section(j,'[["interview_location", "Interview location"], ["interview_date_display", "Interview date / time"], ["expected_joining_date", "Expected joining date"]]'::jsonb));
 benefits:=private.vacancy_candidate_benefits_projection(p_requirement_id);
 for b in select value from jsonb_array_elements(benefits) loop
  benefit_text:=concat_ws('; ',nullif(benefit_text,''),initcap(replace(b->>'benefit_type','_',' '))||': '||
   case when b->>'benefit_value_type'='provided' then 'provided' else 'INR '||(b->>'amount')||' '||replace(b->>'amount_basis','_',' ') end);
 end loop;
 description:=btrim(regexp_replace(coalesce(j->>'additional_notes',''),'[[:space:]]+',' ','g'));
 result:=result||jsonb_build_object('candidate_benefits',coalesce(nullif(benefit_text,''),'No additional benefits supplied.'),
 'description_1',coalesce(nullif(substr(description,1,1000),''),'No job description supplied.'),
 'description_2',coalesce(nullif(substr(description,1001,1000),''),'No further description supplied.'));
 -- No silent truncation: an unsupported longer legacy description blocks the message for review.
 if char_length(description)>2000 then result:=result||jsonb_build_object('description_2',description);end if;
 return result;
end; $$;
create or replace function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=public.console_sync_templates_before_registered(p_rows);
 -- Meta may return review samples on URL buttons; samples are not message bindings.
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_registered_job_alert_v2' and t.language='en';
 update public.whatsapp_template_catalog t set compatible=
  t.body=private.registered_alert_body() and t.buttons=private.registered_alert_buttons()
  and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
    and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1
    and not exists(select 1 from jsonb_array_elements(r->'components') b where b->>'type' not in ('BODY','BUTTONS')))
 where t.name='aadhyant_registered_job_alert_v2' and t.language='en';
 return n;
end; $$;
create or replace function public.admin_console_automatic_alerts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return (select jsonb_build_object('enabled',automatic_alerts_enabled,'daily_limit',automatic_alerts_daily_limit,
 'worker_ready',automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes',
 'template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v2' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
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
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v2' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours')
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
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v2' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
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
revoke all on function private.whatsapp_safe_flat_json(jsonb),private.full_job_section(jsonb,jsonb),private.registered_alert_variables(uuid) from public,anon,authenticated,service_role;
create function public.admin_console_preview_full_job_alert(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; preview text:=private.registered_alert_body(); k text; n integer:=0;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);
 foreach k in array array['requirement_code','job_identity','job_location','eligibility','earnings','deductions','employer_cost','duty','facilities','leave_terms','employment_terms','interview_joining','candidate_benefits','description_1','description_2'] loop n:=n+1;preview:=replace(preview,'{{'||n||'}}',coalesce(vars->>k,''));end loop;
 return jsonb_build_object('template_name','aadhyant_registered_job_alert_v2','message',preview,
 'within_limits',private.whatsapp_safe_flat_json(vars),'section_limit',1000,'description_limit',2000);
end; $$;
revoke all on function public.admin_console_preview_full_job_alert(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_preview_full_job_alert(uuid) to authenticated;
create or replace function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare mode text;
begin
 select c.audience_mode into mode from public.whatsapp_campaigns c join public.whatsapp_campaign_recipients cr on cr.campaign_id=c.id where cr.outbound_message_id=p_message_id;
 if mode is distinct from 'registered_alerts' then
  if exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and template_name in ('aadhyant_registered_job_alert_v1','aadhyant_registered_job_alert_v2')) then return false; end if;
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
commit;
