-- Extend the existing private campaign-media store; retain canonical campaigns/outbox.
alter table private.whatsapp_console_media add column media_format text not null default 'VIDEO' check(media_format in ('VIDEO','JPEG','PNG'));
alter table private.whatsapp_console_media drop constraint whatsapp_console_media_check;
alter table private.whatsapp_console_media add constraint whatsapp_console_media_path_check check(object_path=id::text||'/'||id::text||case media_format when 'VIDEO' then '.mp4' when 'JPEG' then '.jpg' else '.png' end);
alter table private.whatsapp_console_media add constraint whatsapp_console_image_size_check check(media_format='VIDEO' or byte_size<=5000000);
update storage.buckets set allowed_mime_types=array['video/mp4','image/jpeg','image/png'] where id='whatsapp-campaign-media' and not public;
create function public.console_register_campaign_image(p_id uuid,p_created_by uuid,p_size integer,p_format text) returns uuid language plpgsql security definer set search_path='' as $$
begin
 if p_format is null or p_format not in ('JPEG','PNG') then raise exception 'JPEG or PNG required';end if;
 insert into private.whatsapp_console_media(id,created_by,object_path,byte_size,media_format) values(p_id,p_created_by,p_id::text||'/'||p_id::text||case p_format when 'JPEG' then '.jpg' else '.png' end,p_size,p_format);
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(p_created_by,'staff','whatsapp.job_image_uploaded','whatsapp_console_media',p_id,'admin',jsonb_build_object('bytes',p_size,'format',p_format));return p_id;
end;$$;
create function public.console_campaign_image_object(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('path',object_path,'format',media_format) from private.whatsapp_console_media where id=p_id and media_format in ('JPEG','PNG');
$$;
create function private.job_image_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$नमस्ते,
*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। नौकरी का पोस्टर देखें और नीचे जानकारी पढ़ें।

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

पूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे बटन दबाएँ।
अधिक जानकारी या आवेदन के लिए 9624453543 पर कॉल करें।
अलर्ट बंद करने के लिए अलर्ट बंद करें दबाएँ या STOP लिखें।$body$ $verified_body$;
create function private.job_image_render(p_vars jsonb) returns text language plpgsql immutable set search_path='' as $$
declare rendered text:=private.job_image_body();k text;n integer:=0;
begin
 if p_vars->>'template_contract' is distinct from 'registered_summary_v4' or not private.whatsapp_safe_flat_json(p_vars) then raise exception 'Published job summary required';end if;
 foreach k in array array['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'] loop n:=n+1;if nullif(btrim(p_vars->>k),'') is null then raise exception 'Complete job information required';end if;rendered:=replace(rendered,'{{'||n||'}}',p_vars->>k);end loop;
 if char_length(rendered)>1024 then raise exception 'Job image message exceeds template limits';end if;return rendered;
end;$$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_job_image;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$declare n integer;begin
 n:=public.console_sync_templates_before_job_image(p_rows);
 update public.whatsapp_template_catalog t set compatible=t.language='hi' and t.version='1' and t.body=private.job_image_body()
 and t.buttons='[{"type": "URL", "text": "नौकरी देखें और आवेदन करें", "url": "https://aadhyantmanpower.in/jobs/?requirement={{1}}"}, {"type": "QUICK_REPLY", "text": "अलर्ट बंद करें"}]'::jsonb
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id and jsonb_array_length(r->'components')=3
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='HEADER' and c->>'format'='IMAGE')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BUTTONS')=1)
 where t.name='aadhyant_registered_job_image_hi_v1';return n;
end;$$;
create function public.admin_console_prepare_job_image(p_job_id uuid,p_template_id uuid,p_media_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_scheduled_for timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$declare cid uuid;vars jsonb;c public.whatsapp_campaigns%rowtype;begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 perform 1 from public.whatsapp_template_catalog where id=p_template_id and name='aadhyant_registered_job_image_hi_v1' and language='hi' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours' for share;if not found then raise exception 'Approved current image template required';end if;
 perform 1 from private.whatsapp_console_media where id=p_media_id and media_format in ('JPEG','PNG') for share;if not found then raise exception 'Upload a job image first';end if;
 if not private.vacancy_is_application_eligible(p_job_id) then raise exception 'Published open job required';end if;
 vars:=private.registered_alert_variables(p_job_id);perform private.job_image_render(vars);
 cid:=public.admin_console_prepare(p_job_id,p_template_id,p_contact_ids,p_name,p_operation,p_scheduled_for);
 select * into strict c from public.whatsapp_campaigns where id=cid for update;
 if c.criteria ? 'job_image_snapshot' then
  if c.criteria->'job_image_snapshot'<>vars or c.criteria->>'job_image_media_id' is distinct from p_media_id::text then raise exception 'Campaign image or vacancy changed';end if;
 elsif c.campaign_status<>'audience_ready' then raise exception 'Fresh campaign required';
 else update public.whatsapp_campaigns set criteria=criteria||jsonb_build_object('job_image_snapshot',vars,'job_image_media_id',p_media_id::text) where id=cid;end if;return cid;
end;$$;
alter function private.console_template_valid(uuid) rename to console_template_valid_before_job_image;
create function private.console_template_valid(p_campaign_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$declare c public.whatsapp_campaigns%rowtype;begin
 if not private.console_template_valid_before_job_image(p_campaign_id) then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id;if c.template_name<>'aadhyant_registered_job_image_hi_v1' then return true;end if;
 return c.audience_mode='selected_contacts' and c.template_language='hi' and c.template_version='1'
 and c.criteria->'job_image_snapshot'=private.registered_alert_variables(c.requirement_id)
 and c.console_template_snapshot->>'body'=private.job_image_body()
 and exists(select 1 from private.whatsapp_console_media m where m.id::text=c.criteria->>'job_image_media_id' and m.media_format in ('JPEG','PNG'));
end;$$;
alter function public.admin_queue_selected_job_campaign(uuid) rename to admin_queue_selected_job_campaign_before_job_image;
create function public.admin_queue_selected_job_campaign(p_campaign_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;outbound uuid;n integer:=0;vars jsonb;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id for update;
 if not (c.template_name='aadhyant_registered_job_image_hi_v1') then return public.admin_queue_selected_job_campaign_before_job_image(p_campaign_id);end if;
 if c.campaign_status in ('queued','sending','completed') then return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=c.id and outbound_message_id is not null);end if;
 if c.campaign_status<>'approved' or c.audience_mode<>'selected_contacts' or not private.console_template_valid(c.id) then raise exception 'Approved unchanged vacancy required';end if;
 vars:=c.criteria->'job_image_snapshot';perform private.job_image_render(vars);
 for r in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id for update loop
  if not private.selected_job_contact_eligible(r.whatsapp_contact_id,c.requirement_id) then raise exception 'Audience changed or suppressed';end if;
  outbound:=public.enqueue_whatsapp_outbound_message(r.whatsapp_contact_id,r.candidate_id,c.requirement_id,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
   vars||jsonb_build_object('campaign_id',c.id::text,'recipient_id',r.id::text),'campaign:'||c.id::text||':recipient:'||r.id::text,r.id,1);
  update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=outbound where id=r.id;n:=n+1;
 end loop;
 if n=0 then raise exception 'Empty audience';end if;
 update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=c.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.job_image_campaign_queued','whatsapp_campaign',c.id,'admin',jsonb_build_object('count',n,'provider','wanotifier'));
 return n;
end;$$;
alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_job_image;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id;if not found then return false;end if;
 if not (o.template_name='aadhyant_registered_job_image_hi_v1') then return private.whatsapp_vacancy_send_eligible_before_job_image(p_message_id);end if;
 select * into r from public.whatsapp_campaign_recipients where outbound_message_id=o.id;if not found then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=r.campaign_id;
 return c.campaign_status in ('queued','sending') and c.approved_at is not null and c.queued_at is not null and c.cancelled_at is null
 and c.audience_mode='selected_contacts' and r.recipient_status='queued' and r.id=o.correlation_id and r.whatsapp_contact_id=o.contact_id and r.candidate_id is not distinct from o.candidate_id
 and c.requirement_id=o.requirement_id and private.vacancy_is_application_eligible(o.requirement_id) and private.selected_job_contact_eligible(o.contact_id,o.requirement_id)
 and o.purpose='vacancy_campaign' and o.consent_class='marketing' and o.template_name=c.template_name and o.template_language=c.template_language and o.template_version=c.template_version
 and c.template_version='1' and private.console_template_valid(c.id) and private.whatsapp_safe_flat_json(o.template_variables)
 and o.template_variables=(c.criteria->'job_image_snapshot')||jsonb_build_object('campaign_id',c.id::text,'recipient_id',r.id::text);
end;$$;
create function public.console_claimed_image_object(p_message_id uuid,p_worker_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.whatsapp_vacancy_send_eligible(p_message_id) then return null;end if;
 return (select jsonb_build_object('path',m.object_path,'format',m.media_format) from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients r on r.outbound_message_id=o.id join public.whatsapp_campaigns c on c.id=r.campaign_id join private.whatsapp_console_media m on m.id::text=c.criteria->>'job_image_media_id'
 where o.id=p_message_id and o.template_name='aadhyant_registered_job_image_hi_v1' and o.state='sending' and o.send_phase='claimed' and o.lease_owner=p_worker_id and o.lease_expires_at>clock_timestamp() and m.media_format in ('JPEG','PNG'));
end;$$;
create function public.admin_console_preview_job_image(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if not private.vacancy_is_application_eligible(p_requirement_id) then raise exception 'Published open job required';end if;
 return jsonb_build_object('message',private.job_image_render(private.registered_alert_variables(p_requirement_id)));
end;$$;
create or replace function public.admin_console_promotion_media() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return jsonb_build_object('body',private.registration_video_body(),'template_name','aadhyant_registration_video_hi_v1','template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registration_video_hi_v1' and language='hi' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
 'videos',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (select id,created_at,byte_size from private.whatsapp_console_media where media_format='VIDEO' order by created_at desc,id limit 50)m));
end;$$;
revoke all on function public.console_register_campaign_image(uuid,uuid,integer,text),public.console_campaign_image_object(uuid),private.job_image_body(),private.job_image_render(jsonb),public.console_sync_templates_before_job_image(jsonb),public.console_sync_templates(jsonb),public.admin_console_prepare_job_image(uuid,uuid,uuid,uuid[],text,uuid,timestamptz),private.console_template_valid_before_job_image(uuid),private.console_template_valid(uuid),public.admin_queue_selected_job_campaign_before_job_image(uuid),public.admin_queue_selected_job_campaign(uuid),private.whatsapp_vacancy_send_eligible_before_job_image(uuid),private.whatsapp_vacancy_send_eligible(uuid),public.console_claimed_image_object(uuid,text),public.admin_console_preview_job_image(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_register_campaign_image(uuid,uuid,integer,text),public.console_campaign_image_object(uuid),public.console_sync_templates(jsonb),public.console_claimed_image_object(uuid,text) to service_role;
grant execute on function public.admin_console_prepare_job_image(uuid,uuid,uuid,uuid[],text,uuid,timestamptz),public.admin_queue_selected_job_campaign(uuid),public.admin_console_preview_job_image(uuid) to authenticated;
