-- Preserve day shifts; infer the next calendar day when end time is earlier than start time.
begin;
alter table private.same_day_job_terms drop constraint same_day_job_terms_check;
alter table private.same_day_job_terms add constraint same_day_shift_duration check(
 ends_at<>starts_at and starts_at<time '24:00' and ends_at<time '24:00'
 and ends_at-starts_at+case when ends_at<starts_at then interval '24 hours' else interval '0 hours' end<=interval '16 hours');
alter table private.same_day_job_terms add column end_date date generated always as (work_date+case when ends_at<starts_at then 1 else 0 end) stored;
alter table private.same_day_job_terms add column payment_date date generated always as (work_date+case when ends_at<starts_at then 1 else 0 end) stored;
create or replace function public.submit_same_day_job(p_role text,p_payload jsonb,p_request_key uuid,p_requirement_id uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); v_id uuid; request private.same_day_submit_requests%rowtype;
 d date; s time; e time; payment time; amount numeric; count_needed integer; notes text; old_review text;
begin
 if actor is null or p_request_key is null or p_role is null or p_role not in ('company','contractor') or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'Valid signed-in submission required';end if;
 if (p_role='company' and not coalesce(private.can_manage_company_portal(),false)) or (p_role='contractor' and not coalesce(private.can_manage_contractor_vacancies(),false)) then raise exception 'Active employer management access required' using errcode='42501';end if;
 insert into private.same_day_submit_requests(actor_id,request_key,payload) values(actor,p_request_key,jsonb_build_object('role',p_role,'job',p_requirement_id,'data',p_payload)) on conflict do nothing;
 select * into strict request from private.same_day_submit_requests where actor_id=actor and request_key=p_request_key for update;
 if request.payload is distinct from jsonb_build_object('role',p_role,'job',p_requirement_id,'data',p_payload) then raise exception 'Submission key conflicts with different details';end if;
 if request.requirement_id is not null then return request.requirement_id;end if;
 d:=(p_payload->>'work_date')::date;s:=(p_payload->>'starts_at')::time;e:=(p_payload->>'ends_at')::time;payment:=(p_payload->>'payment_time')::time;amount:=(p_payload->>'pay_amount')::numeric;count_needed:=(p_payload->>'required_headcount')::integer;
 if d is null or s is null or e is null or payment is null or amount is null or count_needed is null
 or d<(clock_timestamp() at time zone 'Asia/Kolkata')::date or d>(clock_timestamp() at time zone 'Asia/Kolkata')::date+90
 or (d+s) at time zone 'Asia/Kolkata'<=clock_timestamp() or e=s or s>=time '24:00' or e>=time '24:00' or (e-s+case when e<s then interval '24 hours' else interval '0 hours' end)>interval '16 hours' or payment<>e
 or amount<=0 or amount>100000 or count_needed not between 1 and 100000
 or length(btrim(coalesce(p_payload->>'job_role',''))) not between 1 and 120
 or length(btrim(coalesce(p_payload->>'job_location',''))) not between 1 and 200
 then raise exception 'Enter a future shift, fixed pay and payment immediately at shift completion';end if;
 if p_requirement_id is not null then
  perform 1 from public.employer_requirements r where r.id=p_requirement_id and r.work_engagement='same_day_pay' and private.same_day_owner(r.id) and private.normalized_vacancy_review_status(r.id) in ('draft','correction_required') for update;
  if not found then raise exception 'Only your draft or correction-required Same-Day Pay job can be edited';end if;
 end if;
 notes:='Same-Day Pay Job. Payment immediately after shift completion by '||coalesce(p_payload->>'payment_by','')||' on '||(d+case when e<s then 1 else 0 end)::text||' at '||payment::text||' IST using '||coalesce(p_payload->>'payment_method','')||'. Reporting: '||coalesce(p_payload->>'reporting_point','')||'. Facilities: '||coalesce(p_payload->>'facilities','');
 perform set_config('aadhyant.same_day_edit','yes',true);
 old_review:=private.normalized_vacancy_review_status(p_requirement_id);
 if p_role='company' then
  select x.id into v_id from public.manage_company_portal_requirement(
   p_action=>case when p_requirement_id is null then 'create' else 'update' end,p_requirement_id=>p_requirement_id,
   p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed,
   p_shift_details=>d::text||' '||s::text||' to '||(d+case when e<s then 1 else 0 end)::text||' '||e::text||' IST',p_working_hours=>(extract(epoch from (e-s+case when e<s then interval '24 hours' else interval '0 hours' end))/3600)::text||' hours',p_additional_notes=>notes) x;
 else
  select x.id into v_id from public.manage_contractor_portal_vacancy(
   p_action=>case when p_requirement_id is null then 'create' else 'update' end,p_requirement_id=>p_requirement_id,p_client_name=>btrim(p_payload->>'company_name'),
   p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed,
   p_shift_details=>d::text||' '||s::text||' to '||(d+case when e<s then 1 else 0 end)::text||' '||e::text||' IST',p_working_hours=>(extract(epoch from (e-s+case when e<s then interval '24 hours' else interval '0 hours' end))/3600)::text||' hours',p_additional_notes=>notes) x;
 end if;
 if v_id is null then raise exception 'Canonical vacancy was not created';end if;
 insert into private.same_day_job_terms(requirement_id,work_date,starts_at,ends_at,pay_amount,payment_time,payment_method,payment_by,reporting_point,contact_name,contact_phone,facilities)
 values(v_id,d,s,e,amount,payment,p_payload->>'payment_method',p_payload->>'payment_by',btrim(p_payload->>'reporting_point'),btrim(p_payload->>'contact_name'),p_payload->>'contact_phone',coalesce(p_payload->>'facilities',''))
 on conflict(requirement_id) do update set work_date=excluded.work_date,starts_at=excluded.starts_at,ends_at=excluded.ends_at,pay_amount=excluded.pay_amount,payment_time=excluded.payment_time,payment_method=excluded.payment_method,payment_by=excluded.payment_by,reporting_point=excluded.reporting_point,contact_name=excluded.contact_name,contact_phone=excluded.contact_phone,facilities=excluded.facilities;
 update public.employer_requirements set work_engagement='same_day_pay',salary_wage='INR '||amount||' for the complete shift; paid immediately after shift completion' where id=v_id;
 if p_role='company' then perform public.manage_company_portal_requirement(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id);
 else perform public.manage_contractor_portal_vacancy(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id,p_client_name=>btrim(p_payload->>'company_name'),p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed);end if;
 update private.same_day_submit_requests set requirement_id=v_id where actor_id=actor and request_key=p_request_key;
 return v_id;
end; $$;
create or replace function public.list_same_day_jobs(p_scope text default 'public',p_limit integer default 25,p_offset integer default 0,p_code text default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_scope not in ('public','owner','admin') or p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset<0 then raise exception 'Invalid listing';end if;
 if p_scope='owner' and auth.uid() is null or p_scope='admin' and not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied' using errcode='42501';end if;
 return query select jsonb_build_object('id',r.id,'requirement_code',r.requirement_code,'company_name',r.company_name,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,
 'confirmed_count',(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid')),
 'remaining_places',greatest(0,r.required_headcount-(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid'))),
 'review_status',private.normalized_vacancy_review_status(r.id),'review_feedback',case when p_scope<>'public' then coalesce(r.review_feedback,(select rc.review_feedback from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' limit 1)) end,'stage',r.requirement_stage,'terms',case when p_scope='public' then to_jsonb(t)-array['requirement_id','contact_name','contact_phone'] else to_jsonb(t)-'requirement_id' end,
 'hours',extract(epoch from((t.end_date+t.ends_at)-(t.work_date+t.starts_at)))/3600,'expired',(t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp(),
 'my_application',(select a.id from public.candidate_applications a where a.requirement_id=r.id and a.candidate_id=private.current_candidate_portal_id() limit 1))
 from public.employer_requirements r join private.same_day_job_terms t on t.requirement_id=r.id
 where r.work_engagement='same_day_pay' and (p_code is null or r.requirement_code=p_code) and (
 (p_scope='public' and private.vacancy_is_application_eligible_before_same_day(r.id) and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp())
 or (p_scope='owner' and private.same_day_owner(r.id)) or p_scope='admin')
 order by t.work_date,t.starts_at,r.id limit p_limit offset p_offset;
end; $$;
create or replace function public.list_same_day_applications(p_requirement_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();begin
 return query select jsonb_build_object('application_id',a.id,'requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,'work_date',t.work_date,'pay_amount',t.pay_amount,'payment_time',t.payment_time,'end_date',t.end_date,'payment_date',t.payment_date,
 'candidate_name',c.full_name,'candidate_phone',case when private.same_day_owner(r.id) or private.can_review_vacancies() then c.mobile else null end,
 'work_status',coalesce(w.work_status,'available'),'payment_received_at',w.payment_received_at,'payment_reported_at',w.payment_reported_at,'payment_reference',w.payment_reference)
 from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id join private.same_day_job_terms t on t.requirement_id=r.id join public.candidates c on c.id=a.candidate_id
 left join private.same_day_work_status w on w.application_id=a.id
 where (p_requirement_id is null or r.id=p_requirement_id) and (a.candidate_id=cid or private.same_day_owner(r.id) or private.can_review_vacancies())
 order by t.work_date desc,a.id limit 100;
end; $$;

CREATE OR REPLACE FUNCTION public.update_same_day_work(p_application_id uuid, p_action text, p_reference text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare aid uuid; rid uuid; cid uuid; job public.employer_requirements%rowtype; w private.same_day_work_status%rowtype; t private.same_day_job_terms%rowtype; target text;
begin
 if auth.uid() is null then raise exception 'Sign in required';end if;
 select a.requirement_id into rid from public.candidate_applications a where a.id=p_application_id;
 select * into job from public.employer_requirements where id=rid and work_engagement='same_day_pay' for update;
 if job.id is null then raise exception 'Same-Day Pay application not found';end if;
 select a.id,a.candidate_id into aid,cid from public.candidate_applications a where a.id=p_application_id and a.requirement_id=rid for update;
 if aid is null then raise exception 'Application not found';end if;
 perform 1 from public.candidates where id=cid for update;
 if p_action='received' then
  if cid is distinct from private.current_candidate_portal_id() then raise exception 'Only the candidate can confirm receipt' using errcode='42501';end if;
 elsif not coalesce(private.same_day_owner(rid),false) and not coalesce(private.can_review_vacancies(),false) then raise exception 'Only the responsible employer or Admin can update work' using errcode='42501';end if;
 insert into private.same_day_work_status(application_id) values(aid) on conflict do nothing;
 select * into strict w from private.same_day_work_status where application_id=aid for update;
 select * into strict t from private.same_day_job_terms where requirement_id=rid;
 target:=case p_action when 'confirm' then 'confirmed' when 'attend' then 'attended' when 'complete' then 'completed' when 'paid' then 'paid' when 'cancel' then 'cancelled' else null end;
 if p_action='received' then
  if w.work_status<>'paid' then raise exception 'Employer must record payment first';end if;
  update private.same_day_work_status set payment_received_at=coalesce(payment_received_at,clock_timestamp()),updated_at=clock_timestamp() where application_id=aid;
 elsif target=w.work_status then return true;
 elsif p_action='confirm' and w.work_status='available' then
  if not private.vacancy_is_application_eligible(rid) or (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp() then raise exception 'Shift is no longer available';end if;
  if (select count(*) from private.same_day_work_status sw join public.candidate_applications ca on ca.id=sw.application_id where ca.requirement_id=rid and sw.work_status in ('confirmed','attended','completed','paid'))>=job.required_headcount then raise exception 'All shift places are confirmed';end if;
  if exists(select 1 from private.same_day_work_status sw join public.candidate_applications ca on ca.id=sw.application_id join private.same_day_job_terms st on st.requirement_id=ca.requirement_id where ca.candidate_id=cid and ca.id<>aid and sw.work_status in ('confirmed','attended','completed','paid') and (st.work_date+st.starts_at)<(t.end_date+t.ends_at) and (st.end_date+st.ends_at)>(t.work_date+t.starts_at)) then raise exception 'Candidate already has an overlapping confirmed shift';end if;
  update private.same_day_work_status set work_status=target,updated_at=clock_timestamp() where application_id=aid;
 elsif (p_action='attend' and w.work_status='confirmed' and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp())
 or (p_action='complete' and w.work_status='attended' and (t.end_date+t.ends_at) at time zone 'Asia/Kolkata'<=clock_timestamp())
 or (p_action='paid' and w.work_status='completed')
 or (p_action='cancel' and w.work_status in ('available','confirmed')) then
  update private.same_day_work_status set work_status=target,payment_reported_at=case when target='paid' then clock_timestamp() else payment_reported_at end,
   payment_reference=case when target='paid' then nullif(btrim(p_reference),'') else payment_reference end,updated_at=clock_timestamp() where application_id=aid;
 else raise exception 'Invalid work or payment transition';end if;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),case when p_action='received' then 'candidate' else 'staff' end,'same_day.'||p_action,'candidate_application',aid,case when p_action='received' then 'candidate' when private.can_review_vacancies() then 'admin' when job.source_type='contractor_portal' then 'contractor' else 'company' end,jsonb_build_object('previous_status',w.work_status,'requirement_id',rid));
 return true;
end; $function$;
CREATE OR REPLACE FUNCTION private.registered_alert_variables_before_hindi(p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; t private.same_day_job_terms%rowtype;begin
 result:=private.registered_alert_variables_before_same_day(p_requirement_id);
 select * into t from private.same_day_job_terms where requirement_id=p_requirement_id;
 if not found then return result;end if;
 return result||jsonb_build_object('job_role','Same-Day Pay: '||(result->>'job_role'),
 'salary','INR '||t.pay_amount::text||' for the complete shift',
 'take_home','Payment on '||t.payment_date::text||' at '||to_char(t.payment_time,'HH24:MI')||' IST ('||replace(t.payment_method,'_',' ')||')',
 'duty',t.work_date::text||'; '||to_char(t.starts_at,'HH24:MI')||' to '||t.end_date::text||' '||to_char(t.ends_at,'HH24:MI')||' IST',
 'benefits','Payment by '||t.payment_by||'; see full shift details',
 'job_fingerprint',encode(sha256(convert_to((result->>'job_fingerprint')||to_jsonb(t)::text,'UTF8')),'hex'));
end; $function$;
CREATE OR REPLACE FUNCTION private.registered_alert_variables(p_requirement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior jsonb; t private.same_day_job_terms%rowtype; r public.employer_requirements%rowtype;
begin
 prior:=private.registered_alert_variables_before_hindi(p_requirement_id);
 select * into r from public.employer_requirements where id=p_requirement_id;
 if r.work_engagement is distinct from 'same_day_pay' then return prior;end if;
 select * into strict t from private.same_day_job_terms where requirement_id=p_requirement_id;
 if t.end_date>t.work_date then return prior;end if;
 return jsonb_build_object('template_contract','same_day_hi_v1','requirement_code',r.requirement_code,
 'job_location',btrim(regexp_replace(r.job_location,'[[:space:]]+',' ','g')),
 'job_role',btrim(regexp_replace(r.job_role,'[[:space:]]+',' ','g')),
 'work_date',to_char(t.work_date,'DD-MM-YYYY'),
 'shift',to_char(t.starts_at,'HH24:MI')||' – '||to_char(t.ends_at,'HH24:MI')||' IST ('||(extract(epoch from (t.ends_at-t.starts_at))/3600)::numeric(5,2)::text||' घंटे)',
 'headcount',r.required_headcount::text,'pay','₹'||t.pay_amount::text,
 'payment',case when t.payment_time=t.ends_at then 'शिफ्ट पूरी होते ही, ' else '' end||to_char(t.payment_time,'HH24:MI')||' IST, '||case t.payment_method when 'upi' then 'UPI' when 'cash' then 'नकद' else replace(t.payment_method,'_',' ') end,
 'job_fingerprint',prior->>'job_fingerprint');
end; $function$;
CREATE OR REPLACE FUNCTION private.prepare_registered_publication(p_requirement_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select * into t from public.whatsapp_template_catalog where name=case when vars->>'template_contract'='same_day_hi_v1' then 'aadhyant_same_day_pay_hi_v1' else 'aadhyant_registered_job_alert_v4' end and language=case when vars->>'template_contract'='same_day_hi_v1' then 'hi' else 'en' end and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
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

end; $function$;
commit;
