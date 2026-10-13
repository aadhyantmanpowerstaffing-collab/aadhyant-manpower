-- New operator console. Canonical contacts/campaigns/outbox, no parallel delivery system.
-- Install only after the separately authorized retirement purge has completed.
begin;
do $$ begin
 if exists(select 1 from public.whatsapp_contacts) or exists(select 1 from public.whatsapp_campaigns)
 or exists(select 1 from public.whatsapp_outbound_messages) or exists(select 1 from public.whatsapp_inbound_messages)
 or exists(select 1 from public.whatsapp_campaign_recipients) or exists(select 1 from public.whatsapp_webhook_events)
 or exists(select 1 from public.whatsapp_message_events) then raise exception 'Complete the authorized retirement purge before enabling the new console'; end if;
end; $$;
create table private.whatsapp_console_config(singleton boolean primary key default true check(singleton),sender_ready boolean not null default false);
insert into private.whatsapp_console_config(singleton) values(true);
alter table private.whatsapp_console_config enable row level security;
revoke all on private.whatsapp_console_config from public,anon,authenticated,service_role;
create table public.whatsapp_template_catalog(
 id uuid primary key default gen_random_uuid(),meta_id text not null unique,name text not null,
 language text not null,version text not null default '1',status text not null,
 body text not null,buttons jsonb not null default '[]',compatible boolean not null default false,
 synced_at timestamptz not null default clock_timestamp(),unique(name,language),
 check(name ~ '^[a-z0-9_]{1,160}$'),check(language ~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$'),
 check(length(body) between 1 and 4096),check(jsonb_typeof(buttons)='array' and jsonb_array_length(buttons)<=10));
alter table public.whatsapp_template_catalog enable row level security;
revoke all on public.whatsapp_template_catalog from public,anon,authenticated,service_role;
alter table public.whatsapp_campaigns add column console_template_id uuid references public.whatsapp_template_catalog(id),
 add column console_template_snapshot jsonb,add column scheduled_for timestamptz;

create function public.admin_console_access()
returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and private.can_manage_whatsapp_campaigns()$$;

create function public.admin_console_templates()
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return jsonb_build_object('sender_ready',(select sender_ready from private.whatsapp_console_config where singleton),
 'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by t.name,t.language),'[]'::jsonb) from public.whatsapp_template_catalog t));
end; $$;

-- Only the verified backend reads Meta and supplies fresh template metadata.
create function public.console_sync_templates(p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare r jsonb; b jsonb; v_body text; v_buttons jsonb; seen text[]:='{}'; n integer:=0;
begin
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>500 or octet_length(p_rows::text)>2000000 then raise exception 'Invalid template response'; end if;
 for r in select value from jsonb_array_elements(p_rows) loop
  if coalesce(r->>'id','')!~ '^[0-9]{1,40}$' or coalesce(r->>'name','')!~ '^[a-z0-9_]{1,160}$'
    or coalesce(r->>'language','')!~ '^[A-Za-z]{2,3}(_[A-Za-z]{2})?$' or jsonb_typeof(r->'components') is distinct from 'array' then raise exception 'Invalid template metadata'; end if;
  seen:=array_append(seen,r->>'id');v_body:=null;v_buttons:='[]';
  for b in select value from jsonb_array_elements(r->'components') loop
   if b->>'type'='BODY' then v_body:=b->>'text'; end if;
   if b->>'type'='BUTTONS' then v_buttons:=b->'buttons'; end if;
  end loop;
  if v_body is null then
   update public.whatsapp_template_catalog set status=coalesce(r->>'status','UNKNOWN'),compatible=false,synced_at=clock_timestamp() where meta_id=r->>'id';
   continue;
  end if;
  insert into public.whatsapp_template_catalog(meta_id,name,language,status,body,buttons,compatible,synced_at)
   values(r->>'id',r->>'name',r->>'language',coalesce(r->>'status','UNKNOWN'),v_body,coalesce(v_buttons,'[]'),
    r->>'name'='aadhyant_vacancy_alert_v1' and r->>'language'='en'
    and (select count(*) from jsonb_array_elements(coalesce(v_buttons,'[]')))=2
    and v_buttons->0->>'type'='QUICK_REPLY' and v_buttons->1->>'type'='QUICK_REPLY'
    and lower(v_buttons->0->>'text')='interested' and lower(v_buttons->1->>'text')='stop alerts'
    and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BODY')=1
    and (select count(*) from jsonb_array_elements(r->'components') x where x->>'type'='BUTTONS')=1
    and not exists(select 1 from jsonb_array_elements(r->'components') x where x->>'type' not in ('BODY','BUTTONS','FOOTER'))
    and v_body like '%{{1}}%' and v_body like '%{{2}}%'
    and replace(replace(v_body,'{{1}}',''),'{{2}}','') not like '%{{%',clock_timestamp())
   on conflict(meta_id) do update set name=excluded.name,language=excluded.language,status=excluded.status,
     body=excluded.body,buttons=excluded.buttons,compatible=excluded.compatible,synced_at=excluded.synced_at;
  n:=n+1;
 end loop;
 update public.whatsapp_template_catalog set status='UNAVAILABLE',compatible=false where not(meta_id=any(seen));
 return n;
end; $$;

create function public.admin_console_contacts(p_list text default null,p_tag text default null,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
  select w.id contact_id,left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
   '+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,w.candidate_id,
   w.marketing_consent_status consent,w.resolution_status,
   coalesce(w.imported_profile->'Lists','[]') lists,coalesce(w.imported_profile->'Tags','[]') tags,
   w.imported_profile->>'State' state,w.imported_profile->>'District' district
  from public.whatsapp_contacts w left join public.candidates c on c.id=w.candidate_id
  where (p_list is null or coalesce(w.imported_profile->'Lists','[]')?p_list)
   and (p_tag is null or coalesce(w.imported_profile->'Tags','[]')?p_tag)
  order by w.created_at desc,w.id limit 100 offset p_offset)t);
end; $$;

create function public.admin_console_label_contacts(p_ids uuid[],p_lists jsonb,p_tags jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare a jsonb; v jsonb; n integer;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if cardinality(p_ids) is null or cardinality(p_ids) not between 1 and 500 or array_position(p_ids,null) is not null then raise exception 'Choose contacts'; end if;
 foreach a in array array[p_lists,p_tags] loop
  if a is null or jsonb_typeof(a)<>'array' or jsonb_array_length(a)>20 then raise exception 'Invalid labels'; end if;
  for v in select value from jsonb_array_elements(a) loop
   if jsonb_typeof(v)<>'string' or length(btrim(v#>>'{}')) not between 1 and 60 then raise exception 'Invalid label'; end if;
  end loop;
 end loop;
 update public.whatsapp_contacts set imported_profile=imported_profile||jsonb_build_object('Lists',p_lists,'Tags',p_tags),updated_at=clock_timestamp() where id=any(p_ids);
 get diagnostics n=row_count;return n;
end; $$;

create function public.admin_console_import_contacts(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 return public.admin_import_sharing_contacts(p_rows);
end; $$;

create function public.admin_console_import_numbers(p_numbers jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb; phone text; candidate uuid; matches integer; target uuid; added integer:=0; reused integer:=0;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if jsonb_typeof(p_numbers) is distinct from 'array' or jsonb_array_length(p_numbers) not between 1 and 500 then raise exception 'Import 1 to 500 numbers'; end if;
 for v in select value from jsonb_array_elements(p_numbers) loop
  phone:=regexp_replace(v#>>'{}','[[:space:]()+-]','','g');
  if phone ~ '^91[6-9][0-9]{9}$' then phone:=substr(phone,3); end if;
  if jsonb_typeof(v)<>'string' or phone !~ '^[6-9][0-9]{9}$' then raise exception 'Invalid Indian mobile number'; end if;
  select count(distinct c.id),min(c.id::text)::uuid into matches,candidate from public.candidates c
   where c.profile_status='active' and c.status<>'inactive' and (c.mobile=phone or c.whatsapp_number=phone);
  target:=null;
  insert into public.whatsapp_contacts(provider_address,indian_mobile_key,candidate_id,resolution_status,imported_profile)
   values('+91'||phone,phone,case when matches=1 then candidate else null end,
    case when matches=1 then 'resolved' when matches>1 then 'ambiguous' else 'unresolved' end,'{"Source":"number_import"}')
   on conflict(provider,provider_address) do nothing returning id into target;
  if target is null then reused:=reused+1;else added:=added+1;end if;
 end loop;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.numbers_imported','whatsapp_contact','admin',jsonb_build_object('added',added,'reused',reused));
 return jsonb_build_object('added',added,'reused',reused,'consent_changed',false,'queued',0);
end; $$;

create function public.admin_console_record_consent(p_contact_id uuid,p_source text,p_received_at timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
declare w public.whatsapp_contacts%rowtype;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_source is null or p_source not in ('phone_call','written_permission','in_person') or p_received_at is null
  or p_received_at>clock_timestamp() or p_received_at<clock_timestamp()-interval '365 days' then raise exception 'Actual consent source and date are required'; end if;
 select * into strict w from public.whatsapp_contacts where id=p_contact_id for update;
 if w.marketing_consent_status='opted_out' or w.resolution_status in ('blocked','ambiguous') then raise exception 'Opted-out or blocked contacts must re-enroll themselves'; end if;
 update public.whatsapp_contacts set marketing_consent_status='opted_in',consent_source=p_source,
  consent_scope='vacancy_alerts',consent_recorded_at=p_received_at,consent_policy_version='job-console-consent-v1',updated_at=clock_timestamp() where id=w.id;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),'staff','whatsapp.consent_recorded','whatsapp_contact',w.id,'admin',jsonb_build_object('source',p_source,'received_at',p_received_at));
 return true;
end; $$;

create function public.admin_console_audience(p_requirement_id uuid,p_source text default 'registered',p_view text default 'suggested',p_offset integer default 0,p_list text default null,p_tag text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare req public.employer_requirements%rowtype; result jsonb;
begin
 if not private.can_manage_whatsapp_campaigns() or auth.uid() is null then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_source is null or p_source not in ('registered','contacts') or p_view is null or p_view not in ('suggested','all') or p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid audience query'; end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id and requirement_stage='open' and requirement_visibility='public';
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
  select w.id contact_id,w.candidate_id,
    left(coalesce(c.full_name,w.imported_profile->>'Name','Contact'),1)||'•••' name_masked,
    case when w.id is null then 'Unavailable' else '+91XXXXXX'||right(w.indian_mobile_key,4) end mobile_masked,
    c.highest_qualification qualification,c.specialization trade,
    coalesce(c.current_location,w.imported_profile->>'District') location,
    w.marketing_consent_status consent,w.sharing_subscription->>'scope' alert_scope,
    private.selected_job_contact_eligible(w.id,req.id) eligible,
    case when w.id is null then 'WhatsApp contact unavailable' when w.resolution_status in ('blocked','ambiguous') then 'Contact blocked or ambiguous'
      when w.marketing_consent_status<>'opted_in' then 'Consent required'
      when w.candidate_id is not null and (c.profile_status<>'active' or c.status='inactive') then 'Inactive candidate'
      when exists(select 1 from public.candidate_applications a where a.candidate_id=w.candidate_id and a.requirement_id=req.id) then 'Already applied'
      when w.sharing_subscription<>'{}'::jsonb and not private.sharing_contact_eligible(w.id,req.id) then 'Subscriber preference does not match'
      when private.selected_job_contact_eligible(w.id,req.id) then 'Can select' else 'Contact needs review' end status,
    coalesce(m.suggested,false) suggested,m.reasons match_reasons
  from public.whatsapp_contacts w full join public.candidates c on c.id=w.candidate_id
  cross join lateral (select array_remove(array[
    case when nullif(btrim(req.qualification),'') is not null and lower(coalesce(c.highest_qualification,''))<>lower(req.qualification) then 'Qualification differs' end,
    case when nullif(btrim(req.iti_trade),'') is not null and lower(coalesce(c.specialization,''))<>lower(req.iti_trade) then 'Trade differs' end,
    case when req.experience_requirement is not null and req.experience_requirement<>'Both' and c.candidate_type is distinct from req.experience_requirement then 'Experience differs' end,
    case when nullif(btrim(coalesce(req.job_location,req.company_location)),'') is not null and
      lower(coalesce(c.current_location,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.district,''))<>lower(coalesce(req.job_location,req.company_location)) and
      lower(coalesce(c.state,''))<>lower(coalesce(req.job_location,req.company_location)) then 'Location differs' end
  ],null) reasons) reasons
  cross join lateral (select reasons.reasons, c.id is not null and cardinality(reasons.reasons)=0 suggested) m
  where (w.provider='whatsapp' or w.id is null) and ((p_source='registered' and c.id is not null) or (p_source='contacts' and w.imported_profile<>'{}'::jsonb))
    and (p_view='all' or p_source='contacts' or m.suggested)
  and (nullif(btrim(p_list),'') is null or w.imported_profile->'Lists' ? btrim(p_list))
    and (nullif(btrim(p_tag),'') is null or w.imported_profile->'Tags' ? btrim(p_tag))
  order by m.suggested desc,w.created_at desc nulls last,w.id,c.id limit 100 offset p_offset
 ) t;
 return result;
end; $$;

create function private.console_template_valid(p_campaign_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_campaigns c join public.whatsapp_template_catalog t on t.id=c.console_template_id
 where c.id=p_campaign_id and t.status='APPROVED' and t.compatible and t.synced_at>clock_timestamp()-interval '24 hours'
 and c.console_template_snapshot=jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons));
$$;
revoke all on function private.console_template_valid(uuid) from public,anon,authenticated,service_role;

create function public.admin_console_prepare(p_job_id uuid,p_template_id uuid,p_contact_ids uuid[],p_name text,p_operation uuid,p_scheduled_for timestamptz default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.whatsapp_template_catalog%rowtype; v_id uuid; c public.whatsapp_campaigns%rowtype; snapshot jsonb;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_scheduled_for is not null and (p_scheduled_for<=clock_timestamp() or p_scheduled_for>clock_timestamp()+interval '90 days') then raise exception 'Choose a future time within 90 days'; end if;
 select * into strict t from public.whatsapp_template_catalog where id=p_template_id and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours' for share;
 snapshot:=jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons);
 v_id:=public.admin_prepare_selected_job_campaign(p_job_id,p_operation,p_contact_ids,p_name,t.name,t.language,t.version);
 select * into strict c from public.whatsapp_campaigns where whatsapp_campaigns.id=v_id for update;
 if c.console_template_id is not null then
  if c.console_template_id<>t.id or c.scheduled_for is distinct from p_scheduled_for or c.console_template_snapshot<>snapshot then raise exception 'Campaign operation conflicts'; end if;
 else
  if c.campaign_status<>'audience_ready' then raise exception 'Fresh audience required'; end if;
  update public.whatsapp_campaigns set console_template_id=t.id,console_template_snapshot=snapshot,scheduled_for=p_scheduled_for where whatsapp_campaigns.id=v_id;
 end if;
 return v_id;
end; $$;

create function public.admin_console_approve(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if not private.console_template_valid(p_campaign_id) then raise exception 'Template changed or approval expired; sync and prepare again'; end if;
 return public.admin_approve_selected_job_campaign(p_campaign_id);
end; $$;

create function public.admin_console_queue(p_campaign_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare c public.whatsapp_campaigns%rowtype; n integer;
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if not (select sender_ready from private.whatsapp_console_config where singleton) then raise exception 'Sender connection is not verified'; end if;
 select * into strict c from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null for update;
 if not private.console_template_valid(c.id) then raise exception 'Template changed or approval expired'; end if;
 n:=public.admin_queue_selected_job_campaign(c.id);
 update public.whatsapp_outbound_messages o set next_attempt_at=greatest(o.next_attempt_at,coalesce(c.scheduled_for,clock_timestamp()))
 where o.id in(select cr.outbound_message_id from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id)
  and o.state='queued' and o.send_phase='ready';
 return n;
end; $$;

create function public.admin_console_cancel(p_campaign_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() or not exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null) then raise exception 'Console campaign required'; end if;
 return public.admin_cancel_whatsapp_campaign(p_campaign_id);
end; $$;

create function public.admin_console_campaigns(p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select c.id,c.campaign_name,c.campaign_status,c.created_at,c.scheduled_for,c.requirement_id,r.requirement_code,r.job_role,
 c.template_name,c.template_language,c.console_template_snapshot,
 (select count(*) from public.whatsapp_campaign_recipients cr where cr.campaign_id=c.id) audience_count,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='sent') sent,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='delivered') delivered,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='read') read,
 (select count(*) from public.whatsapp_campaign_recipients cr join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=c.id and o.state='failed') failed
 from public.whatsapp_campaigns c join public.employer_requirements r on r.id=c.requirement_id
 where c.console_template_id is not null order by c.created_at desc,c.id limit 50 offset p_offset)t);
end; $$;

create function public.admin_console_report(p_campaign_id uuid,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() or not exists(select 1 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null) then raise exception 'Console campaign required'; end if;
 if p_offset is null or p_offset<0 or p_offset>5000 then raise exception 'Invalid offset'; end if;
 return (select coalesce(jsonb_agg(to_jsonb(t)),'[]') from (
 select cr.id,'+91XXXXXX'||right(w.indian_mobile_key,4) mobile_masked,
 coalesce(o.state,cr.recipient_status) status,o.sent_at,o.delivered_at,o.read_at,o.failed_at,o.last_error_category failure,
 o.next_attempt_at from public.whatsapp_campaign_recipients cr join public.whatsapp_contacts w on w.id=cr.whatsapp_contact_id
 left join public.whatsapp_outbound_messages o on o.id=cr.outbound_message_id where cr.campaign_id=p_campaign_id
 order by cr.created_at,cr.id limit 100 offset p_offset)t);
end; $$;

revoke all on function public.admin_console_access(),public.admin_console_templates(),public.admin_console_contacts(text,text,integer),
 public.admin_console_label_contacts(uuid[],jsonb,jsonb),public.admin_console_import_contacts(jsonb),public.admin_console_import_numbers(jsonb),public.admin_console_record_consent(uuid,text,timestamptz),
 public.admin_console_audience(uuid,text,text,integer,text,text),public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),
 public.admin_console_approve(uuid),public.admin_console_queue(uuid),public.admin_console_cancel(uuid),public.admin_console_campaigns(integer),
 public.admin_console_report(uuid,integer),public.console_sync_templates(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_access(),public.admin_console_templates(),public.admin_console_contacts(text,text,integer),
 public.admin_console_label_contacts(uuid[],jsonb,jsonb),public.admin_console_import_contacts(jsonb),public.admin_console_import_numbers(jsonb),public.admin_console_record_consent(uuid,text,timestamptz),
 public.admin_console_audience(uuid,text,text,integer,text,text),public.admin_console_prepare(uuid,uuid,uuid[],text,uuid,timestamptz),
 public.admin_console_approve(uuid),public.admin_console_queue(uuid),public.admin_console_cancel(uuid),public.admin_console_campaigns(integer),public.admin_console_report(uuid,integer) to authenticated;
grant execute on function public.console_sync_templates(jsonb) to service_role;
commit;
