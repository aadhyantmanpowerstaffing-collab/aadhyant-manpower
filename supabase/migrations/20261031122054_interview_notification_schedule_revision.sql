-- Each meaningful schedule transition has its own stable notification identity.
-- An A -> B -> A change must not reuse the cancelled first A notification.
begin;
alter table public.interviews add column whatsapp_notification_revision bigint not null default 0
 check(whatsapp_notification_revision>=0);
create function private.set_interview_notification_revision()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then new.whatsapp_notification_revision:=0;
 elsif (new.status,new.scheduled_at,new.mode,new.location,new.application_id)
 is distinct from (old.status,old.scheduled_at,old.mode,old.location,old.application_id)
 then new.whatsapp_notification_revision:=old.whatsapp_notification_revision+1;
 else new.whatsapp_notification_revision:=old.whatsapp_notification_revision;
 end if;
 return new;
end;$$;
create trigger set_interview_notification_revision before insert or update on public.interviews
 for each row execute function private.set_interview_notification_revision();
revoke all on function private.set_interview_notification_revision() from public,anon,authenticated,service_role;
create or replace function private.prepare_interview_whatsapp_notification(p_interview_id uuid)
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
 operation:='interview:'||i.id||':revision:'||i.whatsapp_notification_revision||':'||lang||':'||md5(vars::text);
 result:=public.enqueue_whatsapp_outbound_message(w.id,a.candidate_id,a.requirement_id,'interview_schedule','transactional',
 'aadhyant_interview_schedule_'||lang||'_v1',lang,'1',vars,operation,i.id,1);
 update public.whatsapp_outbound_messages set interview_id=i.id where id=result;
 return result;
end;$$;

revoke all on function private.prepare_interview_whatsapp_notification(uuid) from public,anon,authenticated,service_role;
commit;
