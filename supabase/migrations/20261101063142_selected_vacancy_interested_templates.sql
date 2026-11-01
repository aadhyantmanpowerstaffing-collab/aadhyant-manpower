-- Automatic vacancy snapshots in the existing Campaigns workflow. No sending activation.
begin;
create function private.selected_vacancy_name(p_name text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_name in ('aadhyant_selected_vacancy_en_v1','aadhyant_selected_vacancy_hi_v1'),false);
$$;
create function private.selected_vacancy_body(p_language text) returns text language sql immutable set search_path='' as $body$
 select case p_language when 'en' then $en$Hello,

*Aadhyant Manpower & Staffing* has a new job opening.

*Job details*
• Vacancy: {{1}}
• Company: {{2}}
• Role: {{3}}
• Location: {{4}}

*Qualification*
{{5}}

*Salary & duty*
• CTC / Salary: {{6}}
• Approx. take home: {{7}}
• Overtime: {{8}}
• Duty: {{9}}

*Benefits*
{{10}}

Interested? Tap Interested to receive the registration form for this job.
Call: 96244 53543
To stop job alerts, tap Stop alerts or reply STOP.$en$ when 'hi' then $hi$नमस्ते,
*Aadhyant Manpower & Staffing* में नौकरी का नया अवसर है।

*नौकरी का विवरण*
• भर्ती संदर्भ: {{1}}
• कंपनी: {{2}}
• पद: {{3}}
• स्थान: {{4}}

*योग्यता*
{{5}}

*वेतन और ड्यूटी*
• CTC / वेतन: {{6}}
• अनुमानित हाथ में वेतन: {{7}}
• ओवरटाइम: {{8}}
• ड्यूटी: {{9}}

*सुविधाएँ*
{{10}}

इस नौकरी का रजिस्ट्रेशन फॉर्म पाने के लिए Interested दबाएँ।
कॉल करें: 96244 53543
अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।$hi$ end;
$body$;
create function private.selected_vacancy_render(p_language text,p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare result text:=private.selected_vacancy_body(p_language);k text;n integer:=0;begin
 if result is null or p_vars->>'template_contract' is distinct from 'registered_summary_v4' or not private.whatsapp_safe_flat_json(p_vars) then raise exception 'Valid published vacancy details required';end if;
 foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop n:=n+1;result:=replace(result,'{{'||n||'}}',p_vars->>k);end loop;
 if char_length(result)>1024 then raise exception 'Vacancy message exceeds 1024 characters';end if;return result;
end;$$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_selected_interest;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 n:=public.console_sync_templates_before_selected_interest(p_rows);
 update public.whatsapp_template_catalog t set compatible=t.version='1'
 and t.language=case when t.name='aadhyant_selected_vacancy_hi_v1' then 'hi' else 'en' end
 and t.body=private.selected_vacancy_body(t.language)
 and t.buttons='[{"type":"QUICK_REPLY","text":"Interested"},{"type":"QUICK_REPLY","text":"Stop alerts"}]'::jsonb
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id and jsonb_array_length(r->'components')=2
 and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BUTTONS')=1)
 where private.selected_vacancy_name(t.name);return n;
end;$$;
alter function public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz) rename to admin_console_prepare_before_selected_interest;
create function public.admin_console_prepare(p_job_id uuid,p_template_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_scheduled_for timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.whatsapp_template_catalog%rowtype;cid uuid;c public.whatsapp_campaigns%rowtype;vars jsonb;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict t from public.whatsapp_template_catalog where id=p_template_id;
 if not private.selected_vacancy_name(t.name) then return public.admin_console_prepare_before_selected_interest(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);end if;
 if t.status<>'APPROVED' or not t.compatible or t.synced_at<=clock_timestamp()-interval '24 hours' then raise exception 'Approved synced vacancy template required';end if;
 if not private.vacancy_is_application_eligible(p_job_id) then raise exception 'Published open job required';end if;
 vars:=private.registered_alert_variables(p_job_id);perform private.selected_vacancy_render(t.language,vars);
 cid:=public.admin_console_prepare_before_selected_interest(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
 select * into strict c from public.whatsapp_campaigns where id=cid for update;
 if c.criteria ? 'selected_vacancy_snapshot' then
  if c.criteria->'selected_vacancy_snapshot'<>vars then raise exception 'Campaign operation conflicts';end if;
 elsif c.campaign_status<>'audience_ready' then raise exception 'Fresh campaign required';
 else update public.whatsapp_campaigns set criteria=criteria||jsonb_build_object('selected_vacancy_snapshot',vars) where id=cid;
 end if;return cid;
end;$$;
alter function private.console_template_valid(uuid) rename to console_template_valid_before_selected_interest;
create function private.console_template_valid(p_campaign_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;begin
 if not private.console_template_valid_before_selected_interest(p_campaign_id) then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id;
 if not private.selected_vacancy_name(c.template_name) then return true;end if;
 return c.audience_mode='selected_contacts' and c.criteria->'selected_vacancy_snapshot'=private.registered_alert_variables(c.requirement_id)
 and c.console_template_snapshot->>'body'=private.selected_vacancy_body(c.template_language)
 and c.console_template_snapshot->'buttons'='[{"type":"QUICK_REPLY","text":"Interested"},{"type":"QUICK_REPLY","text":"Stop alerts"}]'::jsonb;
end;$$;
alter function public.admin_queue_selected_job_campaign(uuid) rename to admin_queue_selected_job_campaign_before_selected_interest;
create function public.admin_queue_selected_job_campaign(p_campaign_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;outbound uuid;n integer:=0;vars jsonb;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id for update;
 if not private.selected_vacancy_name(c.template_name) then return public.admin_queue_selected_job_campaign_before_selected_interest(p_campaign_id);end if;
 if c.campaign_status in ('queued','sending','completed') then return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=c.id and outbound_message_id is not null);end if;
 if c.campaign_status<>'approved' or c.audience_mode<>'selected_contacts' or not private.console_template_valid(c.id) then raise exception 'Approved unchanged vacancy required';end if;
 vars:=c.criteria->'selected_vacancy_snapshot';perform private.selected_vacancy_render(c.template_language,vars);
 for r in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id for update loop
  if not private.selected_job_contact_eligible(r.whatsapp_contact_id,c.requirement_id) then raise exception 'Audience changed or suppressed';end if;
  outbound:=public.enqueue_whatsapp_outbound_message(r.whatsapp_contact_id,r.candidate_id,c.requirement_id,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
   vars||jsonb_build_object('campaign_id',c.id::text,'recipient_id',r.id::text),'campaign:'||c.id::text||':recipient:'||r.id::text,r.id,1);
  update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound where id=r.id;n:=n+1;
 end loop;
 if n=0 then raise exception 'Empty audience';end if;
 update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=c.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.selected_job_campaign_queued','whatsapp_campaign',c.id,'admin',jsonb_build_object('count',n,'provider','wanotifier'));
 return n;
end;$$;
alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_selected_interest;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id;if not found then return false;end if;
 if not private.selected_vacancy_name(o.template_name) then return private.whatsapp_vacancy_send_eligible_before_selected_interest(p_message_id);end if;
 select * into r from public.whatsapp_campaign_recipients where outbound_message_id=o.id;if not found then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=r.campaign_id;
 return c.campaign_status in ('queued','sending') and c.approved_at is not null and c.queued_at is not null and c.cancelled_at is null
 and c.audience_mode='selected_contacts' and r.recipient_status='queued' and r.id=o.correlation_id and r.whatsapp_contact_id=o.contact_id and r.candidate_id is not distinct from o.candidate_id
 and c.requirement_id=o.requirement_id and private.vacancy_is_application_eligible(o.requirement_id) and private.selected_job_contact_eligible(o.contact_id,o.requirement_id)
 and o.purpose='vacancy_campaign' and o.consent_class='marketing' and o.template_name=c.template_name and o.template_language=c.template_language and o.template_version=c.template_version
 and c.template_version='1' and private.console_template_valid(c.id) and private.whatsapp_safe_flat_json(o.template_variables)
 and o.template_variables=(c.criteria->'selected_vacancy_snapshot')||jsonb_build_object('campaign_id',c.id::text,'recipient_id',r.id::text);
end;$$;
create function public.admin_console_preview_selected_vacancy(p_requirement_id uuid,p_template_name text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare lang text;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if not private.selected_vacancy_name(p_template_name) or not private.vacancy_is_application_eligible(p_requirement_id) then raise exception 'Published vacancy and selected-vacancy template required';end if;
 lang:=case when p_template_name='aadhyant_selected_vacancy_hi_v1' then 'hi' else 'en' end;
 return jsonb_build_object('message',private.selected_vacancy_render(lang,private.registered_alert_variables(p_requirement_id)));
end;$$;
revoke all on function private.selected_vacancy_name(text),private.selected_vacancy_body(text),private.selected_vacancy_render(text,jsonb),
 public.console_sync_templates_before_selected_interest(jsonb),public.console_sync_templates(jsonb),
 public.admin_console_prepare_before_selected_interest(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),
 private.console_template_valid_before_selected_interest(uuid),private.console_template_valid(uuid),
 public.admin_queue_selected_job_campaign_before_selected_interest(uuid),public.admin_queue_selected_job_campaign(uuid),
 private.whatsapp_vacancy_send_eligible_before_selected_interest(uuid),private.whatsapp_vacancy_send_eligible(uuid),public.admin_console_preview_selected_vacancy(uuid,text)
 from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb) to service_role;
grant execute on function public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_queue_selected_job_campaign(uuid),public.admin_console_preview_selected_vacancy(uuid,text) to authenticated;
commit;
