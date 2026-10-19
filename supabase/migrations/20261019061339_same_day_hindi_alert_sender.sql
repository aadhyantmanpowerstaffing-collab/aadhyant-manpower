-- Same-Day Pay Hindi contract; existing publication, consent and STOP boundaries retained.
begin;
create function private.same_day_alert_body() returns text language sql immutable set search_path='' as $body$ select '*रोकड़ी काम — उसी शाम भुगतान*
*Aadhyant Manpower & Staffing*

📍 *स्थान:* {{1}}
🛠️ *काम:* {{2}}
📅 *तारीख:* {{3}}
🕗 *समय:* {{4}}
👥 *ज़रूरत:* {{5}} लोग
💵 *मेहनताना:* {{6}} प्रति व्यक्ति, पूरी शिफ्ट का
✅ *भुगतान:* उसी दिन {{7}}

काम के लिए उपलब्ध हैं? नीचे बटन दबाकर आवेदन करें। कंपनी/ठेकेदार आपकी जगह की पुष्टि करेगा।

अलर्ट बंद करने के लिए *Stop alerts* दबाएँ या *STOP* लिखें।' $body$;
create function private.same_day_alert_buttons() returns jsonb language sql immutable set search_path='' as $$select '[{"type": "URL", "text": "View Details & Apply", "url": "https://aadhyantmanpower.in/same-day-pay/?role=candidate&job={{1}}"}, {"type": "QUICK_REPLY", "text": "Stop alerts"}]'::jsonb$$;
alter function private.registered_alert_render(jsonb) rename to registered_alert_render_before_hindi;
create function private.registered_alert_render(p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text; k text; n integer:=0;
begin
 if p_vars->>'template_contract' is distinct from 'same_day_hi_v1' then return private.registered_alert_render_before_hindi(p_vars);end if;
 rendered:=private.same_day_alert_body();
 foreach k in array array['job_location','job_role','work_date','shift','headcount','pay','payment'] loop n:=n+1;rendered:=replace(rendered,'{{'||n||'}}',coalesce(p_vars->>k,''));end loop;
 return rendered;
end; $$;
alter function private.whatsapp_safe_flat_json(jsonb) rename to whatsapp_safe_flat_json_before_hindi;
create function private.whatsapp_safe_flat_json(p_value jsonb) returns boolean language plpgsql immutable security definer set search_path='' as $$
declare k text; v jsonb;
begin
 if p_value->>'template_contract' is distinct from 'same_day_hi_v1' then return private.whatsapp_safe_flat_json_before_hindi(p_value);end if;
 if jsonb_typeof(p_value)<>'object' or octet_length(p_value::text)>16384 then return false;end if;
 for k,v in select key,value from jsonb_each(p_value) loop
 if k=any(array['requirement_code','job_location','job_role','work_date','shift','headcount','pay','payment']) then
 if jsonb_typeof(v)<>'string' or char_length(btrim(v#>>'{}')) not between 1 and 300 or (v#>>'{}') ~ '[\n\r\t]' or (v#>>'{}') ~ ' {5}' then return false;end if;
 elsif k not in ('template_contract','job_fingerprint','campaign_id','recipient_id') then return false;end if;
 end loop;
 if exists(select 1 from unnest(array['requirement_code','job_location','job_role','work_date','shift','headcount','pay','payment']) wanted where not p_value ? wanted)
 or coalesce(p_value->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or coalesce(p_value->>'job_fingerprint','') !~ '^[a-f0-9]{64}$' then return false;end if;
 return private.whatsapp_safe_flat_json_before_full_job(p_value) and char_length(private.registered_alert_render(p_value))<=1024;
end; $$;
alter function private.registered_alert_variables(uuid) rename to registered_alert_variables_before_hindi;
create function private.registered_alert_variables(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare prior jsonb; t private.same_day_job_terms%rowtype; r public.employer_requirements%rowtype;
begin
 prior:=private.registered_alert_variables_before_hindi(p_requirement_id);
 select * into r from public.employer_requirements where id=p_requirement_id;
 if r.work_engagement is distinct from 'same_day_pay' then return prior;end if;
 select * into strict t from private.same_day_job_terms where requirement_id=p_requirement_id;
 return jsonb_build_object('template_contract','same_day_hi_v1','requirement_code',r.requirement_code,
 'job_location',btrim(regexp_replace(r.job_location,'[[:space:]]+',' ','g')),
 'job_role',btrim(regexp_replace(r.job_role,'[[:space:]]+',' ','g')),
 'work_date',to_char(t.work_date,'DD-MM-YYYY'),
 'shift',to_char(t.starts_at,'HH24:MI')||' – '||to_char(t.ends_at,'HH24:MI')||' IST ('||(extract(epoch from (t.ends_at-t.starts_at))/3600)::numeric(5,2)::text||' घंटे)',
 'headcount',r.required_headcount::text,'pay','₹'||t.pay_amount::text,
 'payment',case when t.payment_time=t.ends_at then 'शिफ्ट पूरी होते ही, ' else '' end||to_char(t.payment_time,'HH24:MI')||' IST, '||case t.payment_method when 'upi' then 'UPI' when 'cash' then 'नकद' else replace(t.payment_method,'_',' ') end,
 'job_fingerprint',prior->>'job_fingerprint');
end; $$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_hindi;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 n:=public.console_sync_templates_before_hindi(p_rows);
 update public.whatsapp_template_catalog t set buttons=(select coalesce(jsonb_agg(b-'example' order by ordinal),'[]'::jsonb) from jsonb_array_elements(t.buttons) with ordinality e(b,ordinal)) where t.name='aadhyant_same_day_pay_hi_v1' and t.language='hi';
 update public.whatsapp_template_catalog t set compatible=t.body=private.same_day_alert_body() and t.buttons=private.same_day_alert_buttons()
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') b where b->>'type'='BUTTONS')=1
 and not exists(select 1 from jsonb_array_elements(r->'components') b where b->>'type' not in ('BODY','BUTTONS')))
 where t.name='aadhyant_same_day_pay_hi_v1' and t.language='hi';
 return n;
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
 select * into t from public.whatsapp_template_catalog where name=case when req.work_engagement='same_day_pay' then 'aadhyant_same_day_pay_hi_v1' else 'aadhyant_registered_job_alert_v4' end and language=case when req.work_engagement='same_day_pay' then 'hi' else 'en' end and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
 update private.whatsapp_job_publications set outcome='template_unavailable' where requirement_id=req.id;return;end if;
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,template_name,template_language,template_version,
 criteria,created_by,approved_by,approved_at,queued_at,audience_frozen_at,audience_mode,console_template_id,console_template_snapshot)
 values(gen_random_uuid(),req.id,'Auto job alert: '||left(req.requirement_code,100),'queued','vacancy_campaign','marketing',t.name,t.language,t.version,'{}',
 pub.authorized_by,pub.authorized_by,stamp,stamp,stamp,'registered_alerts',t.id,
 jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons)) returning id into cid;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
 select cid,w.candidate_id,w.id,'matched','included','["registered_all_job_alerts","no_matching_filter"]' from public.whatsapp_contacts w
 where private.registered_alert_contact_eligible(w.id) and private.same_day_alert_eligible(req.id,w.id,stamp) and private.job_alert_choice_allows(req.id,w.id,stamp) and w.consent_recorded_at<=stamp and w.created_at<=stamp and exists(select 1 from public.candidates pc where pc.id=w.candidate_id and pc.created_at<=stamp);
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(pub.authorized_by,'staff','whatsapp.automatic_campaign_prepared','whatsapp_campaign',cid,'whatsapp',jsonb_build_object('requirement_id',req.id,'audience_count',n,'standing_approval',true));
 update private.whatsapp_job_publications set campaign_id=cid,outcome=case when n=0 then 'empty' else 'queued' end where requirement_id=req.id;
 if n=0 then update public.whatsapp_campaigns set campaign_status='completed',completed_at=stamp where id=cid; end if;

end; $$;

create or replace function public.admin_console_preview_full_job_alert(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare vars jsonb; rendered text;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 vars:=private.registered_alert_variables(p_requirement_id);rendered:=private.registered_alert_render(vars);
 return jsonb_build_object('template_name',case when vars->>'template_contract'='same_day_hi_v1' then 'aadhyant_same_day_pay_hi_v1' else 'aadhyant_registered_job_alert_v4' end,
 'message',rendered,'within_limits',private.whatsapp_safe_flat_json(vars),'body_limit',1024,'body_characters',char_length(rendered),'detail_mode','summary_with_full_job_link');
end; $$;
-- Invalidate cached compatibility until the worker fetches actual Meta metadata; do not fabricate approval.
update public.whatsapp_template_catalog set compatible=false where name='aadhyant_same_day_pay_hi_v1';
revoke all on function private.same_day_alert_body(),private.same_day_alert_buttons(),private.registered_alert_render_before_hindi(jsonb),private.registered_alert_render(jsonb),private.whatsapp_safe_flat_json_before_hindi(jsonb),private.whatsapp_safe_flat_json(jsonb),private.registered_alert_variables_before_hindi(uuid),private.registered_alert_variables(uuid),public.console_sync_templates_before_hindi(jsonb),public.console_sync_templates(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb) to service_role;
commit;
