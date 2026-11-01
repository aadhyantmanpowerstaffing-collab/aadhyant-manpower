-- Canonical recruitment updates. All provider switches remain disabled.
begin;
alter table public.interviews
 add column candidate_response text not null default 'pending' check(candidate_response in ('pending','attending','unavailable')),
 add column candidate_response_at timestamptz,
 add column candidate_response_revision bigint,
 add column candidate_response_inbound_id uuid references public.whatsapp_inbound_messages(id);
alter table public.candidate_joinings
 add column reporting_time time,
 add column reporting_location text check(length(reporting_location)<=300),
 add column candidate_instructions text check(length(candidate_instructions)<=300),
 add column notification_revision bigint not null default 0;
alter table private.whatsapp_console_config
 add column recruitment_updates_enabled boolean not null default false,
 add column recruitment_templates_verified_at timestamptz,
 add column recruitment_notification_language text not null default 'hi' check(recruitment_notification_language in ('en','hi'));
alter table public.whatsapp_outbound_messages
 add column recruitment_kind text check(recruitment_kind in ('interview_confirmation','interview_reminder','joining_details')),
 add column recruitment_revision bigint,
 add constraint recruitment_notification_shape check(
 (purpose<>'recruitment_update' and recruitment_kind is null and recruitment_revision is null) or
 (purpose='recruitment_update' and recruitment_kind is not null and recruitment_revision is not null
 and recruitment_revision>=0 and consent_class='transactional' and message_type='template' and max_attempts=1
 and candidate_id is not null and requirement_id is not null
 and template_language in ('en','hi') and template_version='1'
 and template_name='aadhyant_'||recruitment_kind||'_'||template_language||'_v1'));
create index interview_response_inbound_idx on public.interviews(candidate_response_inbound_id) where candidate_response_inbound_id is not null;
create index recruitment_notification_entity_idx on public.whatsapp_outbound_messages(correlation_id,recruitment_kind) where purpose='recruitment_update';

create function private.reset_interview_candidate_response()
returns trigger language plpgsql set search_path='' as $$
begin
 if (new.status,new.scheduled_at,new.mode,new.location,new.application_id,new.meeting_link,new.instructions)
 is distinct from (old.status,old.scheduled_at,old.mode,old.location,old.application_id,old.meeting_link,old.instructions) then
  new.candidate_response:='pending';new.candidate_response_at:=null;new.candidate_response_revision:=null;new.candidate_response_inbound_id:=null;
 end if;
 return new;
end;$$;
create trigger reset_interview_candidate_response before update on public.interviews
 for each row execute function private.reset_interview_candidate_response();
-- Include candidate-facing online venue/instructions in schedule revision identity.
create or replace function private.set_interview_notification_revision()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then new.whatsapp_notification_revision:=0;
 elsif (new.status,new.scheduled_at,new.mode,new.location,new.application_id,new.meeting_link,new.instructions)
 is distinct from (old.status,old.scheduled_at,old.mode,old.location,old.application_id,old.meeting_link,old.instructions)
 then new.whatsapp_notification_revision:=old.whatsapp_notification_revision+1;
 else new.whatsapp_notification_revision:=old.whatsapp_notification_revision;end if;
 return new;
end;$$;
create function private.set_joining_notification_revision()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then new.notification_revision:=0;
 elsif (new.application_id,new.joining_status,new.expected_joining_date,new.reporting_time,new.reporting_location,new.candidate_instructions)
 is distinct from (old.application_id,old.joining_status,old.expected_joining_date,old.reporting_time,old.reporting_location,old.candidate_instructions)
 then new.notification_revision:=old.notification_revision+1;
 else new.notification_revision:=old.notification_revision;end if;
 return new;
end;$$;
create trigger set_joining_notification_revision before insert or update on public.candidate_joinings
 for each row execute function private.set_joining_notification_revision();

create function public.candidate_respond_to_interview(p_interview_id uuid,p_revision bigint,p_response text)
returns boolean language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id(); i public.interviews%rowtype;
begin
 if cid is null then raise exception 'Active Candidate Portal access is required';end if;
 if p_response is null or p_response not in ('attending','unavailable') then raise exception 'Choose attending or unavailable';end if;
 select x.* into i from public.interviews x join public.candidate_applications a on a.id=x.application_id
 where x.id=p_interview_id and a.candidate_id=cid for update of x;
 if not found or i.status<>'scheduled' or i.scheduled_at<=clock_timestamp() or i.whatsapp_notification_revision<>p_revision then
 raise exception 'Schedule changed or closed. Refresh your interviews.';end if;
 update public.interviews set candidate_response=p_response,candidate_response_at=clock_timestamp(),
 candidate_response_revision=p_revision,candidate_response_inbound_id=null where id=i.id;
 return true;
end;$$;
create function public.list_candidate_interview_responses(p_limit integer default 100,p_offset integer default 0)
returns table(interview_id uuid,requirement_code text,job_role text,scheduled_at timestamptz,mode text,location text,
 interview_round text,status text,result text,schedule_revision bigint,candidate_response text,meeting_link text,instructions text)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();
begin
 if cid is null then raise exception 'Active Candidate Portal access is required';end if;
 return query select i.id,r.requirement_code,r.job_role,i.scheduled_at,i.mode,i.location,i.interview_round::text,i.status,i.result,
 i.whatsapp_notification_revision,i.candidate_response,i.meeting_link,i.instructions
 from public.interviews i join public.candidate_applications a on a.id=i.application_id
 join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=cid
 order by i.scheduled_at desc nulls last,i.id limit least(greatest(coalesce(p_limit,100),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;$$;

create function private.recruitment_notification_snapshot(p_kind text,p_entity uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare i public.interviews%rowtype;j public.candidate_joinings%rowtype;a public.candidate_applications%rowtype;
 r public.employer_requirements%rowtype;v jsonb;rev bigint;
begin
 if p_kind in ('interview_confirmation','interview_reminder') then
 select * into i from public.interviews where id=p_entity;
 if not found or i.status<>'scheduled' or i.scheduled_at<=now() then return null;end if;
 if p_kind='interview_reminder' and not exists(select 1 from public.whatsapp_outbound_messages o where o.purpose='recruitment_update' and o.correlation_id=i.id and o.recruitment_kind='interview_confirmation' and o.recruitment_revision=i.whatsapp_notification_revision and o.state in ('sent','delivered','read') and o.sent_at<=now()-interval '1 hour') then return null;end if;
 if p_kind='interview_reminder' and (i.scheduled_at>now()+interval '24 hours' or i.scheduled_at<=now()+interval '30 minutes' or i.candidate_response='unavailable') then return null;end if;
 select * into a from public.candidate_applications where id=i.application_id;
 if not found or a.application_status not in ('interested','applied','screening','shortlisted','interview') then return null;end if;
 rev:=i.whatsapp_notification_revision;
 v:=jsonb_build_object('event_date',to_char(i.scheduled_at at time zone 'Asia/Kolkata','DD Mon YYYY'),
 'event_time',to_char(i.scheduled_at at time zone 'Asia/Kolkata','HH12:MI AM')||' IST',
 'venue',coalesce(nullif(btrim(i.meeting_link),''),nullif(btrim(i.location),''),'Review Candidate portal'),
 'instructions',coalesce(nullif(btrim(i.instructions),''),'Review your Candidate account for details.'));
 elsif p_kind='joining_details' then
 select * into j from public.candidate_joinings where id=p_entity;
 if not found or j.joining_status not in ('pending','confirmed') or j.expected_joining_date<(now() at time zone 'Asia/Kolkata')::date
 or j.reporting_time is null or nullif(btrim(j.reporting_location),'') is null then return null;end if;
 select * into a from public.candidate_applications where id=j.application_id;
 if not found or a.application_status not in ('selected','joining_pending') then return null;end if;
 rev:=j.notification_revision;
 v:=jsonb_build_object('event_date',to_char(j.expected_joining_date,'DD Mon YYYY'),
 'event_time',to_char(j.reporting_time,'HH12:MI AM')||' IST','venue',j.reporting_location,
 'instructions',coalesce(nullif(btrim(j.candidate_instructions),''),'Review the joining document checklist in your Candidate account.'));
 else return null;end if;
 if not exists(select 1 from public.candidates where id=a.candidate_id and status<>'inactive') then return null;end if;
 select * into r from public.employer_requirements where id=a.requirement_id;
 if not found then return null;end if;
 v:=v||jsonb_build_object('requirement_code',r.requirement_code,'job_role',r.job_role);
 if not private.whatsapp_safe_flat_json(v) or exists(select 1 from jsonb_each_text(v) e where e.value is null or length(btrim(e.value)) not between 1 and 300 or e.value~'[[:cntrl:]]') then return null;end if;
 return jsonb_build_object('candidate_id',a.candidate_id,'requirement_id',a.requirement_id,'revision',rev,'variables',v);
end;$$;

create function public.prepare_recruitment_notifications()
returns integer language plpgsql security definer set search_path='' as $$
declare cfg private.whatsapp_console_config%rowtype;e record;s jsonb;w public.whatsapp_contacts%rowtype;mid uuid;n integer:=0;
begin
 select * into cfg from private.whatsapp_console_config where singleton;
 if not found then return 0;end if;
 -- The new confirmation replaces legacy schedule automation; never run both.
 if not cfg.recruitment_updates_enabled or cfg.interview_notifications_enabled or cfg.recruitment_templates_verified_at is null
 or cfg.recruitment_templates_verified_at<=clock_timestamp()-interval '24 hours' then return 0;end if;
 for e in
 select i.id,'interview_confirmation'::text kind from public.interviews i where i.status='scheduled' and i.scheduled_at>now()
 union all select i.id,'interview_reminder' from public.interviews i where i.status='scheduled' and i.scheduled_at between now()+interval '30 minutes' and now()+interval '24 hours'
 union all select j.id,'joining_details' from public.candidate_joinings j where j.joining_status in ('pending','confirmed') and j.expected_joining_date>=(now() at time zone 'Asia/Kolkata')::date
 
 loop
  exit when n>=100;
  -- Entity lock before outbox lock, shared by responses and final send checks.
  if e.kind='joining_details' then perform 1 from public.candidate_joinings where id=e.id for update;
  else perform 1 from public.interviews where id=e.id for update;end if;
  s:=private.recruitment_notification_snapshot(e.kind,e.id);if s is null then continue;end if;
  if (select count(*) from public.whatsapp_contacts where candidate_id=(s->>'candidate_id')::uuid)<>1 then continue;end if;
  select * into w from public.whatsapp_contacts where candidate_id=(s->>'candidate_id')::uuid for share;
  if w.resolution_status<>'resolved' or w.marketing_consent_status='opted_out' or not private.whatsapp_contact_allows_purpose(w.id,'transactional') then continue;end if;
  if exists(select 1 from public.whatsapp_outbound_messages where purpose='recruitment_update' and correlation_id=e.id
   and recruitment_kind=e.kind and recruitment_revision=(s->>'revision')::bigint) then continue;end if;
  mid:=public.enqueue_whatsapp_outbound_message(w.id,(s->>'candidate_id')::uuid,(s->>'requirement_id')::uuid,
   'recruitment_update','transactional','aadhyant_'||e.kind||'_'||cfg.recruitment_notification_language||'_v1',
   cfg.recruitment_notification_language,'1',s->'variables','recruitment:'||e.kind||':'||e.id||':'||(s->>'revision'),e.id,1);
  -- Insert shape fields are populated by the binding trigger before insertion.
  n:=n+1;
 end loop;
 return n;
end;$$;
create function private.bind_recruitment_notification()
returns trigger language plpgsql security definer set search_path='' as $$
declare s jsonb;
begin
 if new.purpose='recruitment_update' then
 new.recruitment_kind:=substring(new.template_name from '^aadhyant_(interview_confirmation|interview_reminder|joining_details)_(en|hi)_v1$');
 s:=private.recruitment_notification_snapshot(new.recruitment_kind,new.correlation_id);
 if s is null or new.candidate_id is distinct from (s->>'candidate_id')::uuid
 or new.requirement_id is distinct from (s->>'requirement_id')::uuid or new.template_variables is distinct from s->'variables' then raise exception 'Recruitment notification linkage mismatch';end if;
 new.recruitment_revision:=(s->>'revision')::bigint;
 end if;
 return new;
end;$$;
create trigger bind_recruitment_notification before insert or update of purpose,correlation_id,candidate_id,requirement_id,template_name,template_variables,recruitment_kind,recruitment_revision
 on public.whatsapp_outbound_messages for each row execute function private.bind_recruitment_notification();

create function private.recruitment_notification_current(p_message_id uuid)
returns boolean language sql volatile security definer set search_path='' as $$
 select exists(select 1 from public.whatsapp_outbound_messages o
 join public.whatsapp_contacts w on w.id=o.contact_id
 join private.whatsapp_console_config cfg on cfg.singleton
 cross join lateral (select private.recruitment_notification_snapshot(o.recruitment_kind,o.correlation_id) s) x
 where o.id=p_message_id and o.purpose='recruitment_update' and cfg.recruitment_updates_enabled and not cfg.interview_notifications_enabled
 and cfg.recruitment_templates_verified_at>clock_timestamp()-interval '24 hours' and cfg.recruitment_notification_language=o.template_language
 and x.s->'variables'=o.template_variables and (x.s->>'revision')::bigint=o.recruitment_revision
 and (x.s->>'candidate_id')::uuid=o.candidate_id and (x.s->>'requirement_id')::uuid=o.requirement_id
 and w.candidate_id=o.candidate_id and w.resolution_status='resolved' and w.provider_address=o.destination
 and w.marketing_consent_status<>'opted_out' and private.whatsapp_contact_allows_purpose(w.id,'transactional')
 and (select count(*) from public.whatsapp_contacts where candidate_id=o.candidate_id)=1);
$$;
create function public.console_claim_recruitment_notifications(p_worker_id text)
returns table(message_id uuid,destination text,template_language text,template_name text,template_variables jsonb)
language plpgsql security definer set search_path='' as $$
declare o record;worker text:=btrim(coalesce(p_worker_id,''));
begin
 if length(worker) not between 1 and 160 then raise exception 'Valid worker required';end if;
 if not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours') then return;end if;
 update public.whatsapp_outbound_messages set state='failed',failed_at=clock_timestamp(),lease_owner=null,lease_expires_at=null,
 send_phase=case when send_phase='provider_call_started' then 'reconciliation_required' else 'terminal' end,
 last_error_category='attempts_exhausted',last_error_code='recruitment_lease_expired',updated_at=clock_timestamp()
 where purpose='recruitment_update' and state='sending' and lease_expires_at<=clock_timestamp();
 for o in select id,recruitment_kind,correlation_id from public.whatsapp_outbound_messages where purpose='recruitment_update'
 and state='queued' and send_phase='ready' and attempt_count=0 order by created_at,id limit 10 loop
 if o.recruitment_kind='joining_details' then perform 1 from public.candidate_joinings where id=o.correlation_id for share skip locked;
 else perform 1 from public.interviews where id=o.correlation_id for share skip locked;end if;
 if not found then continue;end if;
 perform 1 from public.whatsapp_outbound_messages where id=o.id and state='queued' and attempt_count=0 and next_attempt_at<=clock_timestamp() for update skip locked;
 if not found then continue;end if;
 if not private.recruitment_notification_current(o.id) then
 update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=clock_timestamp(),last_error_category='eligibility_changed',last_error_code='schedule_changed' where id=o.id;
 else
 return query update public.whatsapp_outbound_messages m set state='sending',send_phase='claimed',attempt_count=1,
 lease_owner=worker,lease_expires_at=clock_timestamp()+interval '60 seconds',updated_at=clock_timestamp() where m.id=o.id
 returning m.id,m.destination,m.template_language,m.template_name,m.template_variables;
 end if;
 end loop;
end;$$;
create function public.console_recruitment_provider_boundary(p_message_id uuid,p_worker_id text,p_phone_id text,p_account_id text)
returns boolean language plpgsql security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype; appid uuid;
begin
 select * into o from public.whatsapp_outbound_messages where id=p_message_id and purpose='recruitment_update';
 if not found then raise exception 'Recruitment notification required';end if;
 if o.recruitment_kind='joining_details' then select application_id into appid from public.candidate_joinings where id=o.correlation_id for share;
 else select application_id into appid from public.interviews where id=o.correlation_id for share;end if;
 perform 1 from public.candidate_applications where id=appid for share;
 perform 1 from public.candidates where id=o.candidate_id for share;
 perform 1 from public.employer_requirements where id=o.requirement_id for share;
 perform 1 from public.whatsapp_contacts where id=o.contact_id for share;
 perform 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours'
 and phone_number_id=p_phone_id and business_account_id=p_account_id for share;
 if not found then raise exception 'Verified sender required';end if;
 perform 1 from public.whatsapp_outbound_messages where id=o.id and state='sending' and send_phase='claimed'
 and lease_owner=btrim(p_worker_id) and lease_expires_at>clock_timestamp() and attempt_count=1 for update;
 if not found or not private.recruitment_notification_current(o.id) then raise exception 'Recruitment notification changed';end if;
 return public.mark_whatsapp_provider_call_started(o.id,p_worker_id);
end;$$;

create function public.process_interview_whatsapp_response(p_inbound_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare m public.whatsapp_inbound_messages%rowtype;o public.whatsapp_outbound_messages%rowtype;i public.interviews%rowtype;response text;cnt integer;iid uuid;
begin
 select * into m from public.whatsapp_inbound_messages where id=p_inbound_id;
 if not found or m.message_type not in ('button','list') or m.correlation_key is null then return false;end if;
 response:=case upper(btrim(m.action_id)) when 'WILL ATTEND' then 'attending' when 'CANNOT ATTEND' then 'unavailable' else null end;
 if response is null then return false;end if;
 select count(*) into cnt from public.whatsapp_outbound_messages where provider_message_id=m.correlation_key and contact_id=m.contact_id
 and purpose='recruitment_update' and recruitment_kind in ('interview_confirmation','interview_reminder');
 if cnt<>1 then return false;end if;
 select * into o from public.whatsapp_outbound_messages where provider_message_id=m.correlation_key and contact_id=m.contact_id and purpose='recruitment_update';
 select * into i from public.interviews where id=o.correlation_id for update;
 if not found or i.status<>'scheduled' or i.scheduled_at<=clock_timestamp() or i.whatsapp_notification_revision<>o.recruitment_revision
 or i.candidate_response_inbound_id=m.id or i.candidate_response_at>=m.provider_timestamp then return false;end if;
 if not exists(select 1 from public.candidate_applications a join public.candidates c on c.id=a.candidate_id
 join public.whatsapp_contacts w on w.candidate_id=c.id where a.id=i.application_id and a.candidate_id=o.candidate_id
 and a.requirement_id=o.requirement_id and c.status<>'inactive' and w.id=m.contact_id and w.resolution_status='resolved'
 and w.marketing_consent_status<>'opted_out' and private.whatsapp_contact_allows_purpose(w.id,'transactional')) then return false;end if;
 if m.provider_timestamp is null or m.provider_timestamp<o.created_at-interval '5 minutes' then return false;end if;
 update public.interviews set candidate_response=response,candidate_response_at=m.provider_timestamp,
 candidate_response_revision=i.whatsapp_notification_revision,candidate_response_inbound_id=m.id where id=i.id;
 return true;
end;$$;

create function public.admin_recruitment_followups(p_filter text default 'all',p_limit integer default 100,p_offset integer default 0)
returns table(entity_id uuid,entity_kind text,candidate_name text,requirement_code text,job_role text,event_at timestamptz,
 follow_up text,candidate_response text,message_state text)
language plpgsql stable security definer set search_path='' as $$
begin
 if private.can_manage_recruitment_operations() is not true then raise exception 'Recruitment access is required';end if;
 if p_filter not in ('all','awaiting_reply','unavailable','attendance_check','no_show','joining') then raise exception 'Invalid follow-up filter';end if;
 return query select q.* from (
 select i.id entity_id,'interview'::text entity_kind,c.full_name candidate_name,r.requirement_code,r.job_role,i.scheduled_at event_at,
 case when i.status='absent' then 'no_show' when i.candidate_response='unavailable' then 'unavailable'
 when i.scheduled_at<=now() and i.status='scheduled' then 'attendance_check' when i.candidate_response='pending' then 'awaiting_reply' else 'confirmed' end follow_up,
 i.candidate_response,coalesce((select o.state from public.whatsapp_outbound_messages o where (o.interview_id=i.id or (o.purpose='recruitment_update' and o.correlation_id=i.id)) order by o.created_at desc limit 1),'not_queued') message_state
 from public.interviews i join public.candidate_applications a on a.id=i.application_id join public.candidates c on c.id=a.candidate_id
 join public.employer_requirements r on r.id=a.requirement_id where i.status in ('scheduled','absent')
 union all
 select j.id,'joining',c.full_name,r.requirement_code,r.job_role,(j.expected_joining_date+j.reporting_time) at time zone 'Asia/Kolkata',
 case when j.joining_status='no_show' then 'no_show' else 'joining' end,'not_applicable',coalesce((select o.state from public.whatsapp_outbound_messages o
 where o.purpose='recruitment_update' and o.correlation_id=j.id order by o.created_at desc limit 1),'not_queued')
 from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id join public.candidates c on c.id=a.candidate_id
 join public.employer_requirements r on r.id=a.requirement_id where j.joining_status in ('pending','confirmed','deferred','no_show')
 ) q where p_filter='all' or q.follow_up=p_filter
 order by q.event_at nulls last,q.entity_id limit least(greatest(coalesce(p_limit,100),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;$$;

create function public.admin_set_joining_message_details(p_joining_id uuid,p_reporting_time time,p_location text,p_instructions text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if private.can_manage_joinings() is not true then raise exception 'Joining management access is required';end if;
 if p_reporting_time is null or length(btrim(coalesce(p_location,''))) not between 1 and 300 or length(coalesce(p_instructions,''))>300
 or coalesce(p_location,'')~'[[:cntrl:]]' or coalesce(p_instructions,'')~'[[:cntrl:]]' then raise exception 'Valid reporting details required';end if;
 update public.candidate_joinings set reporting_time=p_reporting_time,reporting_location=btrim(p_location),candidate_instructions=nullif(btrim(p_instructions),'')
 where id=p_joining_id and joining_status in ('pending','confirmed','deferred');
 if not found then raise exception 'Active joining not found';end if;
 return true;
end;$$;

create function public.admin_get_joining_message_details(p_joining_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if private.can_manage_joinings() is not true then raise exception 'Joining management access is required';end if;
 return (select jsonb_build_object('reporting_time',j.reporting_time,'reporting_location',j.reporting_location,'candidate_instructions',j.candidate_instructions)
 from public.candidate_joinings j where j.id=p_joining_id);
end;$$;
create function public.list_candidate_joining_details(p_limit integer default 100,p_offset integer default 0)
returns table(requirement_code text,job_role text,expected_joining_date date,actual_joining_date date,joining_status text,
 reporting_time time,reporting_location text,candidate_instructions text)
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();
begin
 if cid is null then raise exception 'Active Candidate Portal access is required';end if;
 return query select r.requirement_code,r.job_role,j.expected_joining_date,j.actual_joining_date,j.joining_status,
 j.reporting_time,j.reporting_location,j.candidate_instructions from public.candidate_joinings j
 join public.candidate_applications a on a.id=j.application_id join public.employer_requirements r on r.id=a.requirement_id
 where a.candidate_id=cid order by j.expected_joining_date desc nulls last,j.id
 limit least(greatest(coalesce(p_limit,100),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;$$;
revoke all on function public.admin_get_joining_message_details(uuid),public.list_candidate_joining_details(integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_get_joining_message_details(uuid),public.list_candidate_joining_details(integer,integer) to authenticated;

-- Explicit grants. No new direct table write surface.
revoke all on function private.reset_interview_candidate_response(),private.set_joining_notification_revision(),
 private.recruitment_notification_snapshot(text,uuid),private.bind_recruitment_notification(),private.recruitment_notification_current(uuid),
 public.candidate_respond_to_interview(uuid,bigint,text),public.list_candidate_interview_responses(integer,integer),
 public.admin_recruitment_followups(text,integer,integer),public.admin_set_joining_message_details(uuid,time,text,text),
 public.prepare_recruitment_notifications(),public.console_claim_recruitment_notifications(text),
 public.console_recruitment_provider_boundary(uuid,text,text,text),public.process_interview_whatsapp_response(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.candidate_respond_to_interview(uuid,bigint,text),public.list_candidate_interview_responses(integer,integer),
 public.admin_recruitment_followups(text,integer,integer),public.admin_set_joining_message_details(uuid,time,text,text) to authenticated;
grant execute on function public.prepare_recruitment_notifications(),public.console_claim_recruitment_notifications(text),
 public.console_recruitment_provider_boundary(uuid,text,text,text),public.process_interview_whatsapp_response(uuid) to service_role;
commit;
