-- Late registrations join canonical publication campaigns; no second queue or direct provider send.
begin;
create function private.registration_alert_text(p_text text) returns text
language sql immutable set search_path='' as $$
 select btrim(regexp_replace(lower(replace(replace(coalesce(p_text,''),'સાણંદ','sanand'),'साणंद','sanand')),'[^[:alnum:]]+',' ','g'))
$$;
create function private.registration_alert_candidate_matches(p_candidate_id uuid,p_requirement_id uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare c public.candidates%rowtype; r public.employer_requirements%rowtype;
 q text; rq text; trade text; ctrade text; candidate_age integer; min_age integer; max_age integer;
 preferred text[]; location text; job_location text; has_preference boolean; location_matches boolean:=false;
begin
 select * into c from public.candidates where id=p_candidate_id;
 if not found or c.profile_status<>'active' or c.status='inactive' then return false;end if;
 select * into r from public.employer_requirements where id=p_requirement_id;
 if not found or not private.vacancy_is_application_eligible(r.id) then return false;end if;
 q:=private.registration_alert_text(c.highest_qualification);rq:=private.registration_alert_text(r.qualification);
 trade:=private.registration_alert_text(r.iti_trade);
 if rq<>'' and rq not in ('any','all','any qualification','all qualifications') then
  if rq='other' and trade ~ '(^| )(5th|8th|10th|12th|iti|diploma|graduate)( |$)' then
   if not ((q='below 10th' and trade ~ '(^| )(5th|8th|below 10th)( |$)') or (q<>'' and position(' '||q||' ' in ' '||trade||' ')>0)) then return false;end if;
  elsif q<>rq and (q='' or position(' '||q||' ' in ' '||rq||' ')=0) then return false;
  end if;
 end if;
 -- Education lists in Other are qualification choices, not a literal ITI trade.
 if rq<>'other' and trade not in ('','all','any','all trade','all trades','any trade','other','not applicable','na') then
  ctrade:=private.registration_alert_text(c.specialization);
  trade:=btrim(regexp_replace(' '||trade||' ','\m(engineering|diploma|graduate|trainee|iti|pass|in|and)\M',' ','g'));
  ctrade:=btrim(regexp_replace(' '||ctrade||' ','\m(engineering|diploma|graduate|trainee|iti|pass|in|and)\M',' ','g'));
  trade:=regexp_replace(trade,'[[:space:]]+',' ','g');ctrade:=regexp_replace(ctrade,'[[:space:]]+',' ','g');
  if trade<>'' and (ctrade='' or ctrade='other' or position(' '||ctrade||' ' in ' '||trade||' ')=0) then return false;end if;
 end if;
 if r.experience_requirement is not null and r.experience_requirement<>'Both' and r.experience_requirement is distinct from c.candidate_type then return false;end if;
 min_age:=nullif(to_jsonb(r)->>'age_min','')::integer;max_age:=nullif(to_jsonb(r)->>'age_max','')::integer;
 candidate_age:=case when nullif(to_jsonb(c)->>'date_of_birth','') is not null then extract(year from age((clock_timestamp() at time zone 'Asia/Kolkata')::date,(to_jsonb(c)->>'date_of_birth')::date))::integer else nullif(to_jsonb(c)->>'age','')::integer end;
 if (min_age is not null and (candidate_age is null or candidate_age<min_age)) or (max_age is not null and (candidate_age is null or candidate_age>max_age)) then return false;end if;
 select coalesce(array_agg(v),array[]::text[]) into preferred from (
  select unnest(cp.preferred_locations) v from public.candidate_preferences cp where cp.candidate_id=c.id
  union all select unnest(string_to_array(replace(coalesce(c.preferred_job_location,''),'/',','),','))
 ) choices where nullif(btrim(v),'') is not null;
 has_preference:=cardinality(preferred)>0;
 if not has_preference then preferred:=array[c.current_location,c.district];end if;
 job_location:=' '||private.registration_alert_text(coalesce(nullif(r.job_location,''),r.company_location))||' ';
 foreach location in array preferred loop
  location:=private.registration_alert_text(location);
  location:=btrim(regexp_replace(location,'\m(gidc|industrial area)\M','','g'));
  location:=regexp_replace(location,'[[:space:]]+',' ','g');
  if location in ('any','anywhere','all india','pan india','india') or (location<>'' and position(' '||location||' ' in job_location)>0) then location_matches:=true;end if;
 end loop;
 if not location_matches then return false;end if;
 return not exists(select 1 from public.candidate_applications a where a.candidate_id=c.id and a.requirement_id=r.id);
end $$;

create function private.prepare_new_candidate_job_alerts() returns integer
language plpgsql security definer set search_path='' as $$
declare item record; inserted integer; total integer:=0;
begin
 if pg_trigger_depth()>0 or not exists(select 1 from private.whatsapp_console_config where singleton and automatic_alerts_enabled) then return 0;end if;
 -- Use the canonical worker lock order: config before campaigns.
 perform 1 from private.whatsapp_console_config where singleton and automatic_alerts_enabled for update skip locked;
 if not found then return 0;end if;
 for item in
  select camp.id campaign_id,w.id contact_id,pc.id candidate_id
  from private.whatsapp_job_publications p join public.whatsapp_campaigns camp on camp.id=p.campaign_id
  join public.whatsapp_contacts w on w.provider='whatsapp'
  join public.candidates pc on pc.id=w.candidate_id
  where p.authorized_by is not null and p.outcome<>'disabled' and camp.audience_mode='registered_alerts'
   and camp.cancelled_at is null and camp.campaign_status in ('queued','sending','completed','failed')
   and greatest(pc.created_at,w.created_at,w.consent_recorded_at)>p.published_at
   and private.registered_alert_contact_eligible(w.id)
   and private.same_day_alert_eligible(camp.requirement_id,w.id,null)
   and private.job_alert_choice_allows(camp.requirement_id,w.id,null)
   and private.registration_alert_candidate_matches(pc.id,camp.requirement_id)
   and p.job_snapshot=private.registered_alert_variables(camp.requirement_id)
   and not exists(select 1 from public.whatsapp_campaign_recipients prior where prior.campaign_id=camp.id and (prior.candidate_id=pc.id or prior.whatsapp_contact_id=w.id))
   and not exists(select 1 from public.whatsapp_outbound_messages prior where prior.requirement_id=camp.requirement_id and prior.purpose='vacancy_campaign' and (prior.candidate_id=pc.id or prior.contact_id=w.id))
  order by pc.created_at,pc.id,p.published_at,camp.id limit 100
 loop
  perform 1 from public.whatsapp_campaigns where id=item.campaign_id and cancelled_at is null and campaign_status in ('queued','sending','completed','failed') for update skip locked;
  if not found then continue;end if;
  insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
  values(item.campaign_id,item.candidate_id,item.contact_id,'matched','included','["registration_catchup","qualification_trade_age_location"]') on conflict do nothing;
  get diagnostics inserted=row_count;
  if inserted>0 then
   update public.whatsapp_campaigns set campaign_status=case when campaign_status in ('completed','failed') then 'queued' else campaign_status end,completed_at=null where id=item.campaign_id;
   total:=total+inserted;
  end if;
 end loop;
 if total>0 then
  insert into public.audit_logs(actor_type,action,entity_type,source,metadata)
  values('system','whatsapp.registration_catchup_prepared','whatsapp_campaign','automation',jsonb_build_object('recipient_count',total,'standing_approval',true));
 end if;
 return total;
end $$;

alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_registration_catchup;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.whatsapp_vacancy_send_eligible_before_registration_catchup(p_message_id)
 and not exists(select 1 from public.whatsapp_campaign_recipients cr join public.whatsapp_campaigns camp on camp.id=cr.campaign_id
 where cr.outbound_message_id=p_message_id and cr.match_reasons @> '["registration_catchup"]'::jsonb
 and not private.registration_alert_candidate_matches(cr.candidate_id,camp.requirement_id))
$$;
alter function public.console_claim_registered_alerts(text) rename to console_claim_registered_alerts_before_registration_catchup;
create function public.console_claim_registered_alerts(p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
begin
 perform private.prepare_new_candidate_job_alerts();
 return query select * from public.console_claim_registered_alerts_before_registration_catchup(p_worker_id);
end $$;
alter function private.wake_registered_alert_worker() rename to wake_registered_alert_worker_before_registration_catchup;
create function private.wake_registered_alert_worker() returns bigint
language plpgsql security definer set search_path='' as $$
begin
 perform private.prepare_new_candidate_job_alerts();
 return private.wake_registered_alert_worker_before_registration_catchup();
end $$;
revoke all on function private.registration_alert_text(text),private.registration_alert_candidate_matches(uuid,uuid),private.prepare_new_candidate_job_alerts(),
 private.whatsapp_vacancy_send_eligible_before_registration_catchup(uuid),private.whatsapp_vacancy_send_eligible(uuid),
 private.wake_registered_alert_worker_before_registration_catchup(),private.wake_registered_alert_worker(),
 public.console_claim_registered_alerts_before_registration_catchup(text),public.console_claim_registered_alerts(text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_registered_alerts(text) to service_role;
commit;
