-- Queue preparation only; provider dispatch is deliberately not enabled here.
begin;
alter table private.whatsapp_console_config
 add column interview_notifications_enabled boolean not null default false,
 add column interview_notification_language text not null default 'en' check(interview_notification_language in ('en','hi')),
 add column interview_template_verified_at timestamptz;
alter table public.whatsapp_outbound_messages add column interview_id uuid references public.interviews(id) on delete restrict;
create index whatsapp_interview_notification_idx on public.whatsapp_outbound_messages(interview_id) where interview_id is not null;
alter table public.whatsapp_outbound_messages add constraint whatsapp_interview_notification_shape check (
 (purpose<>'interview_schedule' and interview_id is null) or
 (purpose='interview_schedule' and interview_id is not null and correlation_id=interview_id and consent_class='transactional' and message_type='template'
 and template_name='aadhyant_interview_schedule_'||template_language||'_v1' and template_language in ('en','hi')
 and template_version='1' and max_attempts=1 and candidate_id is not null and requirement_id is not null));

create function private.bind_interview_whatsapp_notification()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.purpose='interview_schedule' then
  if new.interview_id is null then new.interview_id:=new.correlation_id;end if;
  if not exists(select 1 from public.interviews i join public.candidate_applications a on a.id=i.application_id
   where i.id=new.interview_id and a.candidate_id=new.candidate_id and a.requirement_id=new.requirement_id)
  then raise exception 'Interview notification linkage mismatch';end if;
 end if;
 return new;
end;$$;
create trigger bind_interview_whatsapp_notification before insert or update on public.whatsapp_outbound_messages
 for each row execute function private.bind_interview_whatsapp_notification();

create function private.prepare_interview_whatsapp_notification(p_interview_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare i public.interviews%rowtype; a public.candidate_applications%rowtype; r public.employer_requirements%rowtype;
 w public.whatsapp_contacts%rowtype; lang text; vars jsonb; operation text; result uuid; matches integer;
begin
 select * into i from public.interviews where id=p_interview_id for update;
 if not found or i.status<>'scheduled' or i.scheduled_at<=clock_timestamp() or i.scheduled_at is null then return null;end if;
 select interview_notification_language into lang from private.whatsapp_console_config
 where singleton and interview_notifications_enabled and interview_template_verified_at>clock_timestamp()-interval '24 hours';
 if not found then return null;end if;
 select * into a from public.candidate_applications where id=i.application_id;
 if not found or a.candidate_id is null or a.requirement_id is null or a.application_status not in ('interested','applied','screening','shortlisted','interview') then return null;end if;
 if not exists(select 1 from public.candidates where id=a.candidate_id and status<>'inactive') then return null;end if;
 select * into r from public.employer_requirements where id=a.requirement_id;
 if not found or nullif(btrim(r.requirement_code),'') is null or nullif(btrim(r.job_role),'') is null then return null;end if;
 -- Ambiguous duplicate contact linkage is never resolved by choosing one row.
 select count(*) into matches from public.whatsapp_contacts where candidate_id=a.candidate_id;
 if matches<>1 then return null;end if;
 select * into w from public.whatsapp_contacts where candidate_id=a.candidate_id for share;
 if w.resolution_status<>'resolved' or w.marketing_consent_status='opted_out'
 or not private.whatsapp_contact_allows_purpose(w.id,'transactional') then return null;end if;
 vars:=jsonb_build_object('requirement_code',r.requirement_code,'job_role',r.job_role,
 'interview_date',to_char(i.scheduled_at at time zone 'Asia/Kolkata','DD Mon YYYY'),
 'interview_time',to_char(i.scheduled_at at time zone 'Asia/Kolkata','HH12:MI AM'),
 'interview_mode',i.mode,'interview_location',coalesce(nullif(btrim(i.location),''),'See Candidate portal'),
 'candidate_instructions','Sign in to your Candidate account to review the latest schedule.');
 if not private.whatsapp_safe_flat_json(vars) or exists(select 1 from jsonb_each_text(vars) v where nullif(btrim(v.value),'') is null or length(v.value)>500) then return null;end if;
 operation:='interview:'||i.id||':'||lang||':'||md5(vars::text);
 result:=public.enqueue_whatsapp_outbound_message(w.id,a.candidate_id,a.requirement_id,'interview_schedule','transactional',
 'aadhyant_interview_schedule_'||lang||'_v1',lang,'1',vars,operation,i.id,1);
 update public.whatsapp_outbound_messages set interview_id=i.id where id=result;
 return result;
end;$$;

create function private.capture_interview_whatsapp_notification()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and (new.status,new.scheduled_at,new.mode,new.location,new.application_id)
 is not distinct from (old.status,old.scheduled_at,old.mode,old.location,old.application_id) then return new;end if;
 -- Revoke only attempts that have not crossed the provider boundary.
 update public.whatsapp_outbound_messages set state='failed',send_phase='terminal',failed_at=clock_timestamp(),
 lease_owner=null,lease_expires_at=null,last_error_category='interview_changed',last_error_code='review_current_schedule',updated_at=clock_timestamp()
 where interview_id=new.id and (state='queued' or (state='sending' and send_phase='claimed'));
 perform private.prepare_interview_whatsapp_notification(new.id);
 return new;
end;$$;
create trigger capture_interview_whatsapp_notification after insert or update on public.interviews
 for each row execute function private.capture_interview_whatsapp_notification();
revoke all on function private.prepare_interview_whatsapp_notification(uuid),private.capture_interview_whatsapp_notification(),private.bind_interview_whatsapp_notification() from public,anon,authenticated,service_role;
commit;
