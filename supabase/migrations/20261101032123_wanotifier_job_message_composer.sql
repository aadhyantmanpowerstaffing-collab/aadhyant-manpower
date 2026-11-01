-- Reuse canonical campaigns, outbox and exact Interested correlation. No sends or flag activation.
begin;
create function private.job_message_body(p_language text) returns text language sql immutable set search_path='' as $body$
 select case p_language when 'en' then $en$Hello,

Aadhyant Manpower & Staffing has new job openings.

*Qualification:*
{{1}}

*Salary Details*

*{{2}}*
• CTC: {{3}}
• Take Home: {{4}}
• OT: {{5}}

*{{6}}*
• CTC: {{7}}
• Take Home: {{8}}
• OT: {{9}}

*Benefits*
{{10}}

Interested? Tap the Interested button below.
Call us: 96244 53543

Reply STOP to stop job alerts.$en$ when 'hi' then $hi$नमस्ते,

Aadhyant Manpower & Staffing में नौकरी के नए अवसर उपलब्ध हैं।

*योग्यता:*
{{1}}

*वेतन विवरण*

*{{2}}*
• CTC: {{3}}
• हाथ में वेतन: {{4}}
• ओवरटाइम: {{5}}

*{{6}}*
• CTC: {{7}}
• हाथ में वेतन: {{8}}
• ओवरटाइम: {{9}}

*सुविधाएँ*
{{10}}

इच्छुक हैं? नीचे Interested बटन दबाएँ।
हमें कॉल करें: 96244 53543

नौकरी के अलर्ट बंद करने के लिए STOP लिखें।$hi$ end;
$body$;
create function private.job_message_fields() returns text[] language sql immutable set search_path='' as $$
 select array['qualification','group_1','ctc_1','take_home_1','ot_1','group_2','ctc_2','take_home_2','ot_2','benefits'];
$$;
create function private.job_message_name(p_name text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_name in ('aadhyant_job_salary_details_en_v2','aadhyant_job_salary_details_hi_v2'),false);
$$;
create function private.job_message_valid(p_fields jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare k text;begin
 if p_fields is null or jsonb_typeof(p_fields)<>'object' or (select count(*) from jsonb_object_keys(p_fields))<>10 then return false;end if;
 foreach k in array private.job_message_fields() loop
  if jsonb_typeof(p_fields->k) is distinct from 'string' or length(btrim(p_fields->>k)) not between 1 and 300
   or p_fields->>k ~ '[[:cntrl:]]| {5}|\{\{|\}\}' then return false;end if;
 end loop;return true;
end;$$;
create function private.job_message_render(p_language text,p_fields jsonb) returns text language plpgsql immutable set search_path='' as $$
declare result text:=private.job_message_body(p_language);k text;n integer:=0;begin
 if result is null or not private.job_message_valid(p_fields) then raise exception 'Complete valid message fields';end if;
 foreach k in array private.job_message_fields() loop n:=n+1;result:=replace(result,'{{'||n||'}}',btrim(p_fields->>k));end loop;
 if length(result)>1024 then raise exception 'Job message exceeds 1024 characters';end if;return result;
end;$$;

alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_job_message;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 n:=public.console_sync_templates_before_job_message(p_rows);
 update public.whatsapp_template_catalog t set compatible=t.version='1'
 and t.language=case when t.name='aadhyant_job_salary_details_hi_v2' then 'hi' else 'en' end
 and t.body=private.job_message_body(t.language) and t.buttons='[{"type":"QUICK_REPLY","text":"Interested"}]'::jsonb
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
  and jsonb_array_length(r->'components')=2
  and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BODY')=1
  and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BUTTONS')=1)
 where private.job_message_name(t.name);return n;
end;$$;

-- Store one immutable message snapshot inside the existing campaign criteria.
-- Generic campaign creation must not prepare this template without its validated fields.
alter function public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz) rename to admin_console_prepare_before_job_message;
create function public.admin_console_prepare(p_job_id uuid,p_template_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_scheduled_for timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if exists(select 1 from public.whatsapp_template_catalog where id=p_template_id and private.job_message_name(name)) then raise exception 'Use Job Message to fill salary details';end if;
 return public.admin_console_prepare_before_job_message(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
end;$$;
create function public.admin_console_prepare_job_message(p_job_id uuid,p_template_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_fields jsonb,p_scheduled_for timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.whatsapp_template_catalog%rowtype;cid uuid;c public.whatsapp_campaigns%rowtype;job jsonb;fields jsonb;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict t from public.whatsapp_template_catalog where id=p_template_id and private.job_message_name(name)
 and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours' for share;
 if not private.vacancy_is_application_eligible(p_job_id) then raise exception 'Published open job required';end if;
 perform private.job_message_render(t.language,p_fields);
 select jsonb_object_agg(key,btrim(value#>>'{}')) into fields from jsonb_each(p_fields);
 job:=private.registered_alert_variables(p_job_id);
 cid:=public.admin_console_prepare_before_job_message(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
 select * into strict c from public.whatsapp_campaigns where id=cid for update;
 if c.criteria ? 'job_message' then
  if c.criteria->'job_message'<>fields or c.criteria->'job_message_job_snapshot'<>job then raise exception 'Campaign operation conflicts';end if;
 elsif c.campaign_status<>'audience_ready' then raise exception 'Fresh campaign required';
 else update public.whatsapp_campaigns set criteria=criteria||jsonb_build_object('job_message',fields,'job_message_job_snapshot',job) where id=cid;
 end if;return cid;
end;$$;

alter function private.console_template_valid(uuid) rename to console_template_valid_before_job_message;
create function private.console_template_valid(p_campaign_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;begin
 if not private.console_template_valid_before_job_message(p_campaign_id) then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id;
 if not private.job_message_name(c.template_name) then return true;end if;
 return c.audience_mode='selected_contacts' and private.job_message_valid(c.criteria->'job_message')
 and c.criteria->'job_message_job_snapshot'=private.registered_alert_variables(c.requirement_id)
 and c.console_template_snapshot->>'body'=private.job_message_body(c.template_language)
 and c.console_template_snapshot->'buttons'='[{"type":"QUICK_REPLY","text":"Interested"}]'::jsonb;
end;$$;

alter function private.whatsapp_safe_flat_json(jsonb) rename to whatsapp_safe_flat_json_before_job_message;
create function private.whatsapp_safe_flat_json(p_value jsonb) returns boolean language plpgsql immutable set search_path='' as $$
begin
 if p_value->>'template_contract' is distinct from 'salary_details_v2' then return private.whatsapp_safe_flat_json_before_job_message(p_value);end if;
 return private.job_message_valid(p_value-array['template_contract','campaign_id','recipient_id','requirement_code','job_fingerprint'])
 and (select count(*) from jsonb_object_keys(p_value))=15
 and coalesce(p_value->>'campaign_id','') ~ '^[0-9a-f-]{36}$' and coalesce(p_value->>'recipient_id','') ~ '^[0-9a-f-]{36}$'
 and coalesce(p_value->>'requirement_code','') ~ '^[A-Za-z0-9_-]{1,160}$' and coalesce(p_value->>'job_fingerprint','') ~ '^[a-f0-9]{64}$';
end;$$;

alter function public.admin_queue_selected_job_campaign(uuid) rename to admin_queue_selected_job_campaign_before_job_message;
create function public.admin_queue_selected_job_campaign(p_campaign_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;outbound uuid;n integer:=0;vars jsonb;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id for update;
 if not private.job_message_name(c.template_name) then return public.admin_queue_selected_job_campaign_before_job_message(p_campaign_id);end if;
 if c.campaign_status in ('queued','sending','completed') then return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=c.id and outbound_message_id is not null);end if;
 if c.campaign_status<>'approved' or c.audience_mode<>'selected_contacts' or not private.console_template_valid(c.id) then raise exception 'Approved unchanged Job Message required';end if;
 perform private.job_message_render(c.template_language,c.criteria->'job_message');
 vars:=c.criteria->'job_message'||jsonb_build_object('template_contract','salary_details_v2','requirement_code',c.criteria->'job_message_job_snapshot'->>'requirement_code',
 'job_fingerprint',c.criteria->'job_message_job_snapshot'->>'job_fingerprint','campaign_id',c.id::text);
 for r in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id for update loop
  if not private.selected_job_contact_eligible(r.whatsapp_contact_id,c.requirement_id) then raise exception 'Audience changed or suppressed';end if;
  outbound:=public.enqueue_whatsapp_outbound_message(r.whatsapp_contact_id,r.candidate_id,c.requirement_id,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
   vars||jsonb_build_object('recipient_id',r.id::text),'campaign:'||c.id::text||':recipient:'||r.id::text,r.id,1);
  update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound where id=r.id;n:=n+1;
 end loop;
 if n=0 then raise exception 'Empty audience';end if;
 update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=c.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.selected_job_campaign_queued','whatsapp_campaign',c.id,'admin',jsonb_build_object('count',n,'provider','wanotifier'));
 return n;
end;$$;
alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_job_message;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id;
 if not found then return false;end if;
 if not private.job_message_name(o.template_name) then return private.whatsapp_vacancy_send_eligible_before_job_message(p_message_id);end if;
 select * into r from public.whatsapp_campaign_recipients where outbound_message_id=o.id;
 if not found then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=r.campaign_id;
 return c.campaign_status in ('queued','sending') and c.approved_at is not null and c.queued_at is not null and c.cancelled_at is null
 and c.audience_mode='selected_contacts' and r.recipient_status='queued' and r.id=o.correlation_id and r.whatsapp_contact_id=o.contact_id and r.candidate_id is not distinct from o.candidate_id
 and c.requirement_id=o.requirement_id and private.vacancy_is_application_eligible(o.requirement_id) and private.selected_job_contact_eligible(o.contact_id,o.requirement_id)
 and o.purpose='vacancy_campaign' and o.consent_class='marketing' and o.template_name=c.template_name and o.template_language=c.template_language and o.template_version=c.template_version
 and c.template_version='1' and private.console_template_valid(c.id) and private.whatsapp_safe_flat_json(o.template_variables)
 and o.template_variables=(c.criteria->'job_message')||jsonb_build_object('template_contract','salary_details_v2','requirement_code',c.criteria->'job_message_job_snapshot'->>'requirement_code',
 'job_fingerprint',c.criteria->'job_message_job_snapshot'->>'job_fingerprint','campaign_id',c.id::text,'recipient_id',r.id::text);
end;$$;

-- Keep the existing lease implementation, but separate legacy and WANotifier
-- campaign selection before a row is claimed or marked as a provider attempt.
alter function public.console_claim_campaign(uuid,text) rename to console_claim_campaign_before_job_message;
create function public.console_claim_campaign(p_campaign_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 if p_campaign_id is null or exists(select 1 from public.whatsapp_campaigns c where c.id=p_campaign_id and private.job_message_name(c.template_name)) then return;end if;
 return query select * from public.console_claim_campaign_before_job_message(p_campaign_id,p_worker_id);
end;$$;
create function public.console_claim_job_message_campaign(p_campaign_id uuid,p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 if p_campaign_id is null or not exists(select 1 from public.whatsapp_campaigns c where c.id=p_campaign_id and c.audience_mode='selected_contacts' and private.job_message_name(c.template_name)) then return;end if;
 return query select * from public.console_claim_campaign_before_job_message(p_campaign_id,p_worker_id);
end;$$;
create function public.admin_console_job_message_preview(p_campaign_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id and private.job_message_name(template_name);
 return jsonb_build_object('message',private.job_message_render(c.template_language,c.criteria->'job_message'),
 'requirement_code',c.criteria->'job_message_job_snapshot'->>'requirement_code','language',c.template_language,'template_name',c.template_name);
end;$$;
create function public.admin_console_job_message_route(p_campaign_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id and private.job_message_name(template_name)
 and campaign_status in ('queued','sending','completed') and approved_at is not null and cancelled_at is null;
 if not private.console_template_valid(c.id) then raise exception 'Template or job changed';end if;
 return jsonb_build_object('template_name',c.template_name,'language',c.template_language);
end;$$;
revoke all on function public.console_claim_campaign_before_job_message(uuid,text),public.console_claim_campaign(uuid,text),public.console_claim_job_message_campaign(uuid,text),public.admin_console_job_message_preview(uuid),public.admin_console_job_message_route(uuid),private.job_message_body(text),private.job_message_fields(),private.job_message_name(text),private.job_message_valid(jsonb),private.job_message_render(text,jsonb),
 public.console_sync_templates_before_job_message(jsonb),public.console_sync_templates(jsonb),public.admin_console_prepare_before_job_message(uuid,uuid,uuid[],text,uuid,timestamptz),
 public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_prepare_job_message(uuid,uuid,uuid[],text,uuid,jsonb,timestamptz),
 private.console_template_valid_before_job_message(uuid),private.console_template_valid(uuid),private.whatsapp_safe_flat_json_before_job_message(jsonb),private.whatsapp_safe_flat_json(jsonb),
 public.admin_queue_selected_job_campaign_before_job_message(uuid),public.admin_queue_selected_job_campaign(uuid),private.whatsapp_vacancy_send_eligible_before_job_message(uuid),private.whatsapp_vacancy_send_eligible(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb),public.console_claim_campaign(uuid,text),public.console_claim_job_message_campaign(uuid,text) to service_role;
grant execute on function public.admin_console_job_message_preview(uuid),public.admin_console_job_message_route(uuid),public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_console_prepare_job_message(uuid,uuid,uuid[],text,uuid,jsonb,timestamptz) to authenticated;
commit;
