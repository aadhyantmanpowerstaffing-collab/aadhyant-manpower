-- Registration promotion: fixed reviewed Hindi contract; canonical campaign/outbox only.
begin;
create function private.registration_video_body() returns text language sql immutable set search_path='' as $body$ select '*Aadhyant Manpower & Staffing*

साणंद GIDC और आसपास नौकरी ढूंढ रहे हैं?
उपलब्ध नौकरियों के WhatsApp Job Alerts पाने के लिए आज ही रजिस्टर करें।

रजिस्ट्रेशन निःशुल्क है। नौकरी के लिए उम्मीदवारों से कोई फीस नहीं ली जाती।

नीचे Register Now बटन दबाएँ या https://aadhyantmanpower.in/ खोलें।
जानकारी के लिए कॉल करें: 9586785800

अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।' $body$;
create table private.whatsapp_console_media(
 id uuid primary key,created_by uuid not null references auth.users(id),
 object_path text not null unique,byte_size integer not null check(byte_size between 100 and 16000000),
 created_at timestamptz not null default now(),
 check(object_path=id::text||'/'||id::text||'.mp4'));
alter table private.whatsapp_console_media enable row level security;
revoke all on private.whatsapp_console_media from public,anon,authenticated,service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('whatsapp-campaign-media','whatsapp-campaign-media',false,16000000,array['video/mp4']);
alter table public.whatsapp_campaigns add column promotion_media_id uuid references private.whatsapp_console_media(id);
create index whatsapp_campaigns_promotion_media_idx on public.whatsapp_campaigns(promotion_media_id) where promotion_media_id is not null;
create index whatsapp_console_media_creator_idx on private.whatsapp_console_media(created_by);
alter table public.whatsapp_campaigns alter column requirement_id drop not null;
alter table public.whatsapp_campaigns add constraint whatsapp_campaign_job_or_promotion check(
 (requirement_id is not null and promotion_media_id is null and template_name<>'aadhyant_registration_video_hi_v1') or
 (requirement_id is null and promotion_media_id is not null and template_name='aadhyant_registration_video_hi_v1'
 and template_language='hi' and template_version='1' and audience_mode='selected_contacts'));

create function public.console_register_promotion_media(p_id uuid,p_created_by uuid,p_size integer) returns uuid
language plpgsql security definer set search_path='' as $$begin
 insert into private.whatsapp_console_media(id,created_by,object_path,byte_size)
 values(p_id,p_created_by,p_id::text||'/'||p_id::text||'.mp4',p_size);
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(p_created_by,'staff','whatsapp.promotion_video_uploaded','whatsapp_console_media',p_id,'admin',jsonb_build_object('bytes',p_size));return p_id;
end;$$;
create function public.admin_console_promotion_media() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return jsonb_build_object('body',private.registration_video_body(),'template_name','aadhyant_registration_video_hi_v1',
 'template_ready',exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registration_video_hi_v1' and language='hi' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours'),
 'videos',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from (select id,created_at,byte_size from private.whatsapp_console_media order by created_at desc,id limit 50)m));
end;$$;
alter function public.console_sync_templates(jsonb) rename to console_sync_templates_before_promotion;
create function public.console_sync_templates(p_rows jsonb) returns integer language plpgsql security definer set search_path='' as $$declare n integer;begin
 n:=public.console_sync_templates_before_promotion(p_rows);
 update public.whatsapp_template_catalog t set compatible=t.body=private.registration_video_body()
 and t.buttons='[{"type":"URL","text":"Register Now","url":"https://aadhyantmanpower.in/"},{"type":"QUICK_REPLY","text":"Stop alerts"}]'::jsonb
 and exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id
 and jsonb_array_length(r->'components')=3
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='HEADER' and c->>'format'='VIDEO')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BODY')=1
 and (select count(*) from jsonb_array_elements(r->'components') c where c->>'type'='BUTTONS')=1)
 where t.name='aadhyant_registration_video_hi_v1' and t.language='hi';return n;
end;$$;
create function private.promotion_contact_eligible(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_contacts w where w.id=p_id and w.console_archived_at is null
 and w.provider='whatsapp' and w.resolution_status in ('resolved','unresolved')
 and w.marketing_consent_status='opted_in' and private.whatsapp_contact_allows_purpose(w.id,'marketing')
 and (w.candidate_id is null or (w.resolution_status='resolved' and exists(select 1 from public.candidates c where c.id=w.candidate_id and c.profile_status='active' and c.status<>'inactive'))));
$$;
create function public.admin_console_promotion_audience(p_offset integer default 0,p_list text default null,p_tag text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset';end if;
 return (select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (
 select w.id contact_id,left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
 '+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,private.promotion_contact_eligible(w.id) eligible,
 case when private.promotion_contact_eligible(w.id) then 'Permission verified' else 'Not eligible / permission required' end status
 from public.whatsapp_contacts w left join public.candidates c on c.id=w.candidate_id
 where w.console_archived_at is null and (p_list is null or coalesce(w.imported_profile->'Lists','[]')?p_list)
 and (p_tag is null or coalesce(w.imported_profile->'Tags','[]')?p_tag)
 order by w.created_at desc,w.id limit 100 offset p_offset)r);
end;$$;
create function public.admin_console_prepare_promotion(p_media_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.whatsapp_template_catalog%rowtype;c public.whatsapp_campaigns%rowtype;cid uuid;snapshot jsonb;
begin
 if not public.admin_console_access() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501';end if;
 if p_operation is null or p_name is null or length(btrim(p_name)) not between 1 and 160 or cardinality(p_contact_ids) is null or cardinality(p_contact_ids) not between 1 and 500 or array_position(p_contact_ids,null) is not null or cardinality(p_contact_ids)<>(select count(distinct x) from unnest(p_contact_ids)x) then raise exception 'Choose a campaign name, video and 1 to 500 distinct contacts';end if;
 perform 1 from private.whatsapp_console_media where id=p_media_id for share;if not found then raise exception 'Upload a video first';end if;
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registration_video_hi_v1' and language='hi' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours' for share;
 if not found then raise exception 'Registration video template needs Meta approval; sync templates after approval';end if;
 snapshot:=jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons);
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,purpose,consent_class,template_name,template_language,template_version,criteria,created_by,audience_mode,console_template_id,console_template_snapshot,promotion_media_id)
 values(p_operation,null,btrim(p_name),'vacancy_campaign','marketing',t.name,t.language,t.version,'{}',auth.uid(),'selected_contacts',t.id,snapshot,p_media_id)
 on conflict(operation_key) do nothing returning id into cid;
 if cid is null then
  select * into strict c from public.whatsapp_campaigns where operation_key=p_operation for update;
  if c.created_by is distinct from auth.uid() or c.campaign_name<>btrim(p_name) or c.promotion_media_id is distinct from p_media_id or c.console_template_snapshot<>snapshot
  or (select array_agg(whatsapp_contact_id order by whatsapp_contact_id) from public.whatsapp_campaign_recipients where campaign_id=c.id) is distinct from (select array_agg(x order by x) from unnest(p_contact_ids)x) then raise exception 'Campaign operation conflicts';end if;return c.id;
 end if;
 perform id from public.whatsapp_contacts where id=any(p_contact_ids) order by id for share;
 if exists(select 1 from unnest(p_contact_ids)x where not private.promotion_contact_eligible(x)) then raise exception 'Audience changed or permission missing';end if;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status)
 select cid,w.candidate_id,w.id,'manual_include','included' from public.whatsapp_contacts w where w.id=any(p_contact_ids);
 update public.whatsapp_campaigns set campaign_status='audience_ready',audience_frozen_at=clock_timestamp() where id=cid;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.promotion_prepared','whatsapp_campaign',cid,'admin',jsonb_build_object('count',cardinality(p_contact_ids),'media_id',p_media_id));
 return cid;
end;$$;
alter function private.console_template_valid(uuid) rename to console_template_valid_before_promotion;
create function private.console_template_valid(p_campaign_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.console_template_valid_before_promotion(p_campaign_id) and exists(select 1 from public.whatsapp_campaigns c
 where c.id=p_campaign_id and (c.promotion_media_id is null or (c.requirement_id is null and c.template_name='aadhyant_registration_video_hi_v1'
 and c.console_template_snapshot->>'body'=private.registration_video_body()
 and exists(select 1 from private.whatsapp_console_media m where m.id=c.promotion_media_id))));
$$;
alter function public.admin_console_approve(uuid) rename to admin_console_approve_before_promotion;
create function public.admin_console_approve(p_campaign_id uuid) returns boolean language plpgsql security definer set search_path='' as $$declare c public.whatsapp_campaigns%rowtype;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id for update;
 if c.promotion_media_id is null then return public.admin_console_approve_before_promotion(p_campaign_id);end if;
 if not private.console_template_valid(c.id) then raise exception 'Approved current registration template required';end if;
 if c.campaign_status='approved' then return true;end if;
 if c.campaign_status<>'audience_ready' or not exists(select 1 from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included') or exists(select 1 from public.whatsapp_campaign_recipients where campaign_id=c.id and not private.promotion_contact_eligible(whatsapp_contact_id)) then raise exception 'Fresh eligible audience required';end if;
 update public.whatsapp_campaigns set campaign_status='approved',approved_by=auth.uid(),approved_at=clock_timestamp() where id=c.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(auth.uid(),'staff','whatsapp.promotion_approved','whatsapp_campaign',c.id,'admin','{}');return true;
end;$$;
alter function public.admin_console_queue(uuid) rename to admin_console_queue_before_promotion;
create function public.admin_console_queue(p_campaign_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;oid uuid;n integer:=0;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id for update;
 if c.promotion_media_id is null then return public.admin_console_queue_before_promotion(p_campaign_id);end if;
 if c.campaign_status in ('queued','sending','completed') then return (select count(*)::integer from public.whatsapp_campaign_recipients where campaign_id=c.id and outbound_message_id is not null);end if;
 if c.campaign_status<>'approved' or not private.console_template_valid(c.id) or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then raise exception 'Approved campaign, template and verified sender required';end if;
 for r in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id for update loop
  if not private.promotion_contact_eligible(r.whatsapp_contact_id) then raise exception 'Audience changed or suppressed';end if;
  oid:=public.enqueue_whatsapp_outbound_message(r.whatsapp_contact_id,r.candidate_id,null,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
  jsonb_build_object('template_contract','registration_promotion_v1','campaign_id',c.id::text,'recipient_id',r.id::text),
  'campaign:'||c.id::text||':recipient:'||r.id::text,r.id,3);
  update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=oid where id=r.id;n:=n+1;
 end loop;
 if n=0 then raise exception 'Empty audience';end if;
 update public.whatsapp_campaigns set campaign_status='queued',queued_at=clock_timestamp() where id=c.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(auth.uid(),'staff','whatsapp.promotion_queued','whatsapp_campaign',c.id,'admin',jsonb_build_object('count',n));return n;
end;$$;
alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_promotion;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language plpgsql stable security definer set search_path='' as $$declare o public.whatsapp_outbound_messages%rowtype;c public.whatsapp_campaigns%rowtype;r public.whatsapp_campaign_recipients%rowtype;begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id;
 if not found then return false;end if;
 if o.template_name is distinct from 'aadhyant_registration_video_hi_v1' then return private.whatsapp_vacancy_send_eligible_before_promotion(p_message_id);end if;
 select * into r from public.whatsapp_campaign_recipients where outbound_message_id=o.id;if not found then return false;end if;
 select * into strict c from public.whatsapp_campaigns where id=r.campaign_id;
 return c.promotion_media_id is not null and c.requirement_id is null and o.requirement_id is null
 and c.campaign_status in ('queued','sending') and c.approved_at is not null and c.queued_at is not null and c.cancelled_at is null
 and r.recipient_status='queued' and r.id=o.correlation_id and r.whatsapp_contact_id=o.contact_id and r.candidate_id is not distinct from o.candidate_id
 and o.destination=(select provider_address from public.whatsapp_contacts where id=o.contact_id)
 and private.promotion_contact_eligible(o.contact_id) and private.console_template_valid(c.id)
 and o.purpose='vacancy_campaign' and o.consent_class='marketing' and o.template_name=c.template_name and o.template_language='hi' and o.template_version='1'
 and o.template_variables=jsonb_build_object('template_contract','registration_promotion_v1','campaign_id',c.id::text,'recipient_id',r.id::text);
end;$$;
alter function public.console_claimed_reel_object(uuid,text) rename to console_claimed_reel_object_before_promotion;
create function public.console_claimed_reel_object(p_message_id uuid,p_worker_id text) returns text language plpgsql stable security definer set search_path='' as $$begin
 if not exists(select 1 from public.whatsapp_outbound_messages where id=p_message_id and template_name='aadhyant_registration_video_hi_v1') then return public.console_claimed_reel_object_before_promotion(p_message_id,p_worker_id);end if;
 if not private.whatsapp_vacancy_send_eligible(p_message_id) then return null;end if;
 return (select m.object_path from public.whatsapp_outbound_messages o join public.whatsapp_campaign_recipients r on r.outbound_message_id=o.id join public.whatsapp_campaigns c on c.id=r.campaign_id join private.whatsapp_console_media m on m.id=c.promotion_media_id
 where o.id=p_message_id and o.state='sending' and o.send_phase='claimed' and o.lease_owner=p_worker_id and o.lease_expires_at>clock_timestamp());
end;$$;
revoke all on function private.registration_video_body(),private.promotion_contact_eligible(uuid),private.console_template_valid_before_promotion(uuid),private.console_template_valid(uuid),private.whatsapp_vacancy_send_eligible_before_promotion(uuid),private.whatsapp_vacancy_send_eligible(uuid),public.console_sync_templates_before_promotion(jsonb),public.console_sync_templates(jsonb),public.console_register_promotion_media(uuid,uuid,integer),public.admin_console_promotion_media(),public.admin_console_promotion_audience(integer,text,text),public.admin_console_prepare_promotion(uuid,uuid[],text,uuid),public.admin_console_approve_before_promotion(uuid),public.admin_console_approve(uuid),public.admin_console_queue_before_promotion(uuid),public.admin_console_queue(uuid),public.console_claimed_reel_object_before_promotion(uuid,text),public.console_claimed_reel_object(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_templates(jsonb),public.console_register_promotion_media(uuid,uuid,integer),public.console_claimed_reel_object(uuid,text) to service_role;
grant execute on function public.admin_console_promotion_media(),public.admin_console_promotion_audience(integer,text,text),public.admin_console_prepare_promotion(uuid,uuid[],text,uuid),public.admin_console_approve(uuid),public.admin_console_queue(uuid) to authenticated;
create or replace function public.admin_console_campaigns(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select c.id,c.campaign_name,c.campaign_status,c.created_at,c.scheduled_for,c.requirement_id,r.requirement_code,r.job_role,
 c.promotion_media_id,c.template_name,c.template_language,c.console_template_snapshot,private.console_campaign_delivery(c.id) delivery,
 (select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id) audience_count,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='sent') sent,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='delivered') delivered,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='read') read,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='failed') failed
 from public.whatsapp_campaigns c left join public.employer_requirements r on r.id=c.requirement_id
 where c.console_template_id is not null order by c.created_at desc,c.id limit 50 offset p_offset)t);
end; $$;

create function public.console_promotion_media_object(p_id uuid) returns text language sql stable security definer set search_path='' as $$select object_path from private.whatsapp_console_media where id=p_id$$;
revoke all on function public.console_promotion_media_object(uuid) from public,anon,authenticated,service_role;
grant execute on function public.console_promotion_media_object(uuid) to service_role;
commit;
