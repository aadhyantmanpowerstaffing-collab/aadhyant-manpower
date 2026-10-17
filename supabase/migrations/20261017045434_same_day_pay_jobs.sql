-- Same-Day Pay Jobs extend canonical vacancies/applications. No payments processed here.
begin;
do $$ begin
 if to_regprocedure('private.registered_alert_variables(uuid)') is null
 or to_regprocedure('private.prepare_registered_publication(uuid)') is null
 or to_regprocedure('private.whatsapp_vacancy_send_eligible(uuid)') is null
 or position('registered_summary_v4' in pg_get_functiondef('private.registered_alert_variables(uuid)'::regprocedure))=0 then
 raise exception 'Same-Day Pay requires the canonical v4 alert contract';end if;
end; $$;
alter table public.employer_requirements add column work_engagement text not null default 'regular'
 check(work_engagement in ('regular','same_day_pay'));
create table private.same_day_job_terms(
 requirement_id uuid primary key references public.employer_requirements(id) on delete cascade,
 work_date date not null, starts_at time not null, ends_at time not null,
 pay_amount numeric(10,2) not null check(pay_amount>0 and pay_amount<=100000),
 payment_time time not null, payment_method text not null check(payment_method in ('cash','upi','cash_or_upi')),
 payment_by text not null check(payment_by in ('company','contractor')),
 reporting_point text not null check(length(reporting_point) between 1 and 300),
 contact_name text not null check(length(contact_name) between 1 and 100),
 contact_phone text not null check(contact_phone ~ '^[6-9][0-9]{9}$'),
 facilities text not null default '' check(length(facilities)<=500),
 area text not null default 'sanand_gidc' check(area='sanand_gidc'),
 check(ends_at>starts_at and ends_at-starts_at<=interval '16 hours'),
 check(payment_time>=ends_at and payment_time>=time '16:00')
);
create table private.same_day_preferences(
 candidate_id uuid primary key references public.candidates(id) on delete cascade,
 enabled boolean not null default false, area text not null default 'sanand_gidc' check(area='sanand_gidc'),
 changed_at timestamptz not null default clock_timestamp()
);
create table private.same_day_work_status(
 application_id uuid primary key references public.candidate_applications(id) on delete cascade,
 work_status text not null default 'available' check(work_status in ('available','confirmed','attended','completed','paid','cancelled')),
 payment_received_at timestamptz, payment_reported_at timestamptz,
 payment_reference text check(length(payment_reference)<=100),
 updated_at timestamptz not null default clock_timestamp(),
 check(payment_received_at is null or work_status='paid')
);
create table private.same_day_submit_requests(
 actor_id uuid not null references auth.users(id), request_key uuid not null,
 payload jsonb not null, requirement_id uuid references public.employer_requirements(id),
 primary key(actor_id,request_key)
);
alter table private.same_day_job_terms enable row level security;
alter table private.same_day_preferences enable row level security;
alter table private.same_day_work_status enable row level security;
alter table private.same_day_submit_requests enable row level security;
revoke all on private.same_day_job_terms,private.same_day_preferences,private.same_day_work_status,private.same_day_submit_requests from public,anon,authenticated,service_role;

create function private.same_day_owner(p_requirement_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.employer_requirements r where r.id=p_requirement_id and (
 (private.can_manage_company_portal() and r.company_id=private.current_company_portal_id(true) and r.source_type='employer_portal')
 or (private.can_manage_contractor_vacancies() and exists(select 1 from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' and rc.contractor_id=private.current_contractor_portal_id(true)))
 ))
$$;

create function public.submit_same_day_job(p_role text,p_payload jsonb,p_request_key uuid,p_requirement_id uuid default null)
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
 or (d+s) at time zone 'Asia/Kolkata'<=clock_timestamp() or e<=s or e-s>interval '16 hours' or payment<e
 or payment<time '16:00' or amount<=0 or amount>100000 or count_needed not between 1 and 100000
 or length(btrim(coalesce(p_payload->>'job_role',''))) not between 1 and 120
 or length(btrim(coalesce(p_payload->>'job_location',''))) not between 1 and 200
 then raise exception 'Enter a future shift, fixed pay and same-day payment time after the shift';end if;
 if p_requirement_id is not null then
  perform 1 from public.employer_requirements r where r.id=p_requirement_id and r.work_engagement='same_day_pay' and private.same_day_owner(r.id) and private.normalized_vacancy_review_status(r.id) in ('draft','correction_required') for update;
  if not found then raise exception 'Only your draft or correction-required Same-Day Pay job can be edited';end if;
 end if;
 notes:='Same-Day Pay Job. Payment by '||coalesce(p_payload->>'payment_by','')||' at '||payment::text||' IST using '||coalesce(p_payload->>'payment_method','')||'. Reporting: '||coalesce(p_payload->>'reporting_point','')||'. Facilities: '||coalesce(p_payload->>'facilities','');
 perform set_config('aadhyant.same_day_edit','yes',true);
 old_review:=private.normalized_vacancy_review_status(p_requirement_id);
 if p_role='company' then
  select x.id into v_id from public.manage_company_portal_requirement(
   p_action=>case when p_requirement_id is null then 'create' else 'update' end,p_requirement_id=>p_requirement_id,
   p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed,
   p_shift_details=>d::text||' '||s::text||' to '||e::text||' IST',p_working_hours=>(extract(epoch from(e-s))/3600)::text||' hours',p_additional_notes=>notes) x;
 else
  select x.id into v_id from public.manage_contractor_portal_vacancy(
   p_action=>case when p_requirement_id is null then 'create' else 'update' end,p_requirement_id=>p_requirement_id,p_client_name=>btrim(p_payload->>'company_name'),
   p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed,
   p_shift_details=>d::text||' '||s::text||' to '||e::text||' IST',p_working_hours=>(extract(epoch from(e-s))/3600)::text||' hours',p_additional_notes=>notes) x;
 end if;
 if v_id is null then raise exception 'Canonical vacancy was not created';end if;
 insert into private.same_day_job_terms(requirement_id,work_date,starts_at,ends_at,pay_amount,payment_time,payment_method,payment_by,reporting_point,contact_name,contact_phone,facilities)
 values(v_id,d,s,e,amount,payment,p_payload->>'payment_method',p_payload->>'payment_by',btrim(p_payload->>'reporting_point'),btrim(p_payload->>'contact_name'),p_payload->>'contact_phone',coalesce(p_payload->>'facilities',''))
 on conflict(requirement_id) do update set work_date=excluded.work_date,starts_at=excluded.starts_at,ends_at=excluded.ends_at,pay_amount=excluded.pay_amount,payment_time=excluded.payment_time,payment_method=excluded.payment_method,payment_by=excluded.payment_by,reporting_point=excluded.reporting_point,contact_name=excluded.contact_name,contact_phone=excluded.contact_phone,facilities=excluded.facilities;
 update public.employer_requirements set work_engagement='same_day_pay',salary_wage='INR '||amount||' for the complete shift; paid the same evening' where id=v_id;
 if p_role='company' then perform public.manage_company_portal_requirement(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id);
 else perform public.manage_contractor_portal_vacancy(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id,p_client_name=>btrim(p_payload->>'company_name'),p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed);end if;
 update private.same_day_submit_requests set requirement_id=v_id where actor_id=actor and request_key=p_request_key;
 return v_id;
end; $$;

create function public.set_same_day_preferences(p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();
begin
 if cid is null or p_enabled is null then raise exception 'Active Candidate access required' using errcode='42501';end if;
 insert into private.same_day_preferences(candidate_id,enabled) values(cid,p_enabled)
 on conflict(candidate_id) do update set enabled=excluded.enabled,changed_at=clock_timestamp();
 return p_enabled;
end; $$;
create function public.get_same_day_preferences() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();begin
 if cid is null then raise exception 'Active Candidate access required';end if;
 return jsonb_build_object('enabled',coalesce((select enabled from private.same_day_preferences where candidate_id=cid),false),'area','sanand_gidc');end; $$;

create function public.list_same_day_jobs(p_scope text default 'public',p_limit integer default 25,p_offset integer default 0,p_code text default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_scope not in ('public','owner','admin') or p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset<0 then raise exception 'Invalid listing';end if;
 if p_scope='owner' and auth.uid() is null or p_scope='admin' and not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied' using errcode='42501';end if;
 return query select jsonb_build_object('id',r.id,'requirement_code',r.requirement_code,'company_name',r.company_name,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,
 'review_status',private.normalized_vacancy_review_status(r.id),'review_feedback',case when p_scope<>'public' then coalesce(r.review_feedback,(select rc.review_feedback from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' limit 1)) end,'stage',r.requirement_stage,'terms',to_jsonb(t)-'requirement_id',
 'hours',extract(epoch from(t.ends_at-t.starts_at))/3600,'expired',(t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp(),
 'my_application',(select a.id from public.candidate_applications a where a.requirement_id=r.id and a.candidate_id=private.current_candidate_portal_id() limit 1))
 from public.employer_requirements r join private.same_day_job_terms t on t.requirement_id=r.id
 where r.work_engagement='same_day_pay' and (p_code is null or r.requirement_code=p_code) and (
 (p_scope='public' and private.vacancy_is_application_eligible(r.id) and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp())
 or (p_scope='owner' and private.same_day_owner(r.id)) or p_scope='admin')
 order by t.work_date,t.starts_at,r.id limit p_limit offset p_offset;
end; $$;

create function public.apply_same_day_job(p_requirement_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id(); job public.employer_requirements%rowtype; t private.same_day_job_terms%rowtype; aid uuid;
begin
 if cid is null then raise exception 'Active Candidate access required';end if;
 select * into job from public.employer_requirements where id=p_requirement_id and work_engagement='same_day_pay' for update;
 select * into t from private.same_day_job_terms where requirement_id=job.id;
 if job.id is null or t.requirement_id is null or not private.vacancy_is_application_eligible(job.id) or (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp() then raise exception 'This shift is not available';end if;
 select id into aid from public.candidate_applications where requirement_id=job.id and candidate_id=cid;
 if aid is null then aid:=public.apply_candidate_job(job.requirement_code);end if;
 insert into private.same_day_work_status(application_id) values(aid) on conflict do nothing;
 return aid;
end; $$;

create function public.list_same_day_applications(p_requirement_id uuid default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id();begin
 return query select jsonb_build_object('application_id',a.id,'requirement_id',r.id,'requirement_code',r.requirement_code,'job_role',r.job_role,'work_date',t.work_date,'pay_amount',t.pay_amount,'payment_time',t.payment_time,
 'candidate_name',c.full_name,'candidate_phone',case when private.same_day_owner(r.id) or private.can_review_vacancies() then c.mobile else null end,
 'work_status',coalesce(w.work_status,'available'),'payment_received_at',w.payment_received_at,'payment_reported_at',w.payment_reported_at,'payment_reference',w.payment_reference)
 from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id join private.same_day_job_terms t on t.requirement_id=r.id join public.candidates c on c.id=a.candidate_id
 left join private.same_day_work_status w on w.application_id=a.id
 where (p_requirement_id is null or r.id=p_requirement_id) and (a.candidate_id=cid or private.same_day_owner(r.id) or private.can_review_vacancies())
 order by t.work_date desc,a.id limit 100;
end; $$;

create function public.update_same_day_work(p_application_id uuid,p_action text,p_reference text default null)
returns boolean language plpgsql security definer set search_path='' as $$
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
  if exists(select 1 from private.same_day_work_status sw join public.candidate_applications ca on ca.id=sw.application_id join private.same_day_job_terms st on st.requirement_id=ca.requirement_id where ca.candidate_id=cid and ca.id<>aid and sw.work_status in ('confirmed','attended','completed','paid') and st.work_date=t.work_date and st.starts_at<t.ends_at and st.ends_at>t.starts_at) then raise exception 'Candidate already has an overlapping confirmed shift';end if;
  update private.same_day_work_status set work_status=target,updated_at=clock_timestamp() where application_id=aid;
 elsif (p_action='attend' and w.work_status='confirmed' and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp())
 or (p_action='complete' and w.work_status='attended' and (t.work_date+t.ends_at) at time zone 'Asia/Kolkata'<=clock_timestamp())
 or (p_action='paid' and w.work_status='completed')
 or (p_action='cancel' and w.work_status in ('available','confirmed')) then
  update private.same_day_work_status set work_status=target,payment_reported_at=case when target='paid' then clock_timestamp() else payment_reported_at end,
   payment_reference=case when target='paid' then nullif(btrim(p_reference),'') else payment_reference end,updated_at=clock_timestamp() where application_id=aid;
 else raise exception 'Invalid work or payment transition';end if;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
 values(auth.uid(),case when p_action='received' then 'candidate' else 'staff' end,'same_day.'||p_action,'candidate_application',aid,'same_day_pay',jsonb_build_object('previous_status',w.work_status,'requirement_id',rid));
 return true;
end; $$;

-- Defence in depth: regular Apply/public-interest callers cannot bypass expiry or full shift capacity.
alter function private.vacancy_is_application_eligible(uuid) rename to vacancy_is_application_eligible_before_same_day;
create function private.vacancy_is_application_eligible(p_requirement_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.vacancy_is_application_eligible_before_same_day(p_requirement_id)
 and (not exists(select 1 from public.employer_requirements where id=p_requirement_id and work_engagement='same_day_pay')
 or exists(select 1 from private.same_day_job_terms t join public.employer_requirements r on r.id=t.requirement_id
 where t.requirement_id=p_requirement_id and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp()
 and (select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid'))<r.required_headcount))
$$;
revoke all on function private.vacancy_is_application_eligible_before_same_day(uuid),private.vacancy_is_application_eligible(uuid) from public,anon,authenticated,service_role;
create function private.guard_same_day_application() returns trigger language plpgsql security definer set search_path='' as $$
declare t private.same_day_job_terms%rowtype; job public.employer_requirements%rowtype;
begin
 select * into job from public.employer_requirements where id=new.requirement_id for update;
 if job.work_engagement<>'same_day_pay' then return new;end if;
 select * into t from private.same_day_job_terms where requirement_id=job.id;
 if t.requirement_id is null or not private.vacancy_is_application_eligible(job.id) or (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp()
 or (select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=job.id and w.work_status in ('confirmed','attended','completed','paid'))>=job.required_headcount then raise exception 'Same-Day Pay shift is unavailable or fully booked';end if;
 return new;
end; $$;
create trigger guard_same_day_application before insert on public.candidate_applications for each row execute function private.guard_same_day_application();

revoke all on function private.same_day_owner(uuid),private.guard_same_day_application() from public,anon,authenticated,service_role;
revoke all on function public.submit_same_day_job(text,jsonb,uuid,uuid),public.set_same_day_preferences(boolean),public.get_same_day_preferences(),public.list_same_day_jobs(text,integer,integer,text),public.apply_same_day_job(uuid),public.list_same_day_applications(uuid),public.update_same_day_work(uuid,text,text) from public,anon;
grant execute on function public.submit_same_day_job(text,jsonb,uuid,uuid),public.set_same_day_preferences(boolean),public.get_same_day_preferences(),public.list_same_day_jobs(text,integer,integer,text),public.apply_same_day_job(uuid),public.list_same_day_applications(uuid),public.update_same_day_work(uuid,text,text) to authenticated;
grant execute on function public.list_same_day_jobs(text,integer,integer,text) to anon;

create function private.same_day_alert_eligible(p_requirement_id uuid,p_contact_id uuid,p_stamp timestamptz default null)
returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.employer_requirements r where r.id=p_requirement_id and r.work_engagement='same_day_pay')
 or exists(select 1 from private.same_day_job_terms t join public.whatsapp_contacts wc on wc.id=p_contact_id
 join private.same_day_preferences pref on pref.candidate_id=wc.candidate_id
 join public.employer_requirements r on r.id=t.requirement_id
 where t.requirement_id=p_requirement_id and pref.enabled and pref.area=t.area
 and (p_stamp is null or pref.changed_at<=p_stamp)
 and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp()
 and (select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid'))<r.required_headcount)
$$;
alter function private.registered_alert_variables(uuid) rename to registered_alert_variables_before_same_day;
create function private.registered_alert_variables(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; t private.same_day_job_terms%rowtype;begin
 result:=private.registered_alert_variables_before_same_day(p_requirement_id);
 select * into t from private.same_day_job_terms where requirement_id=p_requirement_id;
 if not found then return result;end if;
 return result||jsonb_build_object('job_role','Same-Day Pay: '||(result->>'job_role'),
 'salary','INR '||t.pay_amount::text||' for the complete shift',
 'take_home','Payment same day at '||to_char(t.payment_time,'HH24:MI')||' IST ('||replace(t.payment_method,'_',' ')||')',
 'duty',t.work_date::text||'; '||to_char(t.starts_at,'HH24:MI')||' to '||to_char(t.ends_at,'HH24:MI')||' IST',
 'benefits','Payment by '||t.payment_by||'; see full shift details',
 'job_fingerprint',encode(sha256(convert_to((result->>'job_fingerprint')||to_jsonb(t)::text,'UTF8')),'hex'));
end; $$;
create or replace function private.prepare_registered_publication(p_requirement_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare pub private.whatsapp_job_publications%rowtype; req public.employer_requirements%rowtype;
 t public.whatsapp_template_catalog%rowtype; cid uuid; vars jsonb; stamp timestamptz; n integer;
begin
 select * into strict pub from private.whatsapp_job_publications where requirement_id=p_requirement_id for update;
 if pub.campaign_id is not null or pub.authorized_by is null or pub.outcome='disabled' then return;end if;
 select * into strict req from public.employer_requirements where id=p_requirement_id;
 if not private.vacancy_is_application_eligible(req.id) or pub.job_snapshot is distinct from private.registered_alert_variables(req.id) then return;end if;
 vars:=pub.job_snapshot;stamp:=pub.published_at;
 select * into t from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v4' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours';
 if not found or not private.whatsapp_safe_flat_json(vars) or coalesce(vars->>'requirement_code','') !~ '^[A-Za-z0-9_-]{1,160}$' or exists(select 1 from jsonb_each_text(vars) e where nullif(btrim(e.value),'') is null) then
 update private.whatsapp_job_publications set outcome='template_unavailable' where requirement_id=req.id;return;end if;
 insert into public.whatsapp_campaigns(operation_key,requirement_id,campaign_name,campaign_status,purpose,consent_class,template_name,template_language,template_version,
 criteria,created_by,approved_by,approved_at,queued_at,audience_frozen_at,audience_mode,console_template_id,console_template_snapshot)
 values(gen_random_uuid(),req.id,'Auto job alert: '||left(req.requirement_code,100),'queued','vacancy_campaign','marketing',t.name,t.language,t.version,'{}',
 pub.authorized_by,pub.authorized_by,stamp,stamp,stamp,'registered_alerts',t.id,
 jsonb_build_object('name',t.name,'language',t.language,'version',t.version,'body',t.body,'buttons',t.buttons)) returning id into cid;
 insert into public.whatsapp_campaign_recipients(campaign_id,candidate_id,whatsapp_contact_id,inclusion_source,recipient_status,match_reasons)
 select cid,w.candidate_id,w.id,'matched','included','["registered_all_job_alerts","no_matching_filter"]' from public.whatsapp_contacts w
 where private.registered_alert_contact_eligible(w.id) and private.same_day_alert_eligible(req.id,w.id,stamp) and w.consent_recorded_at<=stamp and w.created_at<=stamp and exists(select 1 from public.candidates pc where pc.id=w.candidate_id and pc.created_at<=stamp);
 get diagnostics n=row_count;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata) values(pub.authorized_by,'staff','whatsapp.automatic_campaign_prepared','whatsapp_campaign',cid,'whatsapp',jsonb_build_object('requirement_id',req.id,'audience_count',n,'standing_approval',true));
 update private.whatsapp_job_publications set campaign_id=cid,outcome=case when n=0 then 'empty' else 'queued' end where requirement_id=req.id;
 if n=0 then update public.whatsapp_campaigns set campaign_status='completed',completed_at=stamp where id=cid; end if;

end; $$;

alter function private.whatsapp_vacancy_send_eligible(uuid) rename to whatsapp_vacancy_send_eligible_before_same_day;
create function private.whatsapp_vacancy_send_eligible(p_message_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.whatsapp_vacancy_send_eligible_before_same_day(p_message_id)
 and exists(select 1 from public.whatsapp_outbound_messages o where o.id=p_message_id and private.same_day_alert_eligible(o.requirement_id,o.contact_id))
$$;
create function private.freeze_same_day_canonical_terms() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.work_engagement='same_day_pay' and current_setting('aadhyant.same_day_edit',true) is distinct from 'yes' and
 row(new.department,new.job_role,new.job_location,new.company_name,new.required_headcount,new.shift_details,new.working_hours,new.salary_wage,new.work_engagement)
 is distinct from row(old.department,old.job_role,old.job_location,old.company_name,old.required_headcount,old.shift_details,old.working_hours,old.salary_wage,old.work_engagement)
 then raise exception 'Edit Same-Day Pay terms in the dedicated workspace before review';end if;
 return new;
end; $$;
create trigger freeze_same_day_canonical_terms before update on public.employer_requirements for each row execute function private.freeze_same_day_canonical_terms();
revoke all on function private.same_day_alert_eligible(uuid,uuid,timestamptz),private.registered_alert_variables_before_same_day(uuid),private.registered_alert_variables(uuid),private.whatsapp_vacancy_send_eligible_before_same_day(uuid),private.whatsapp_vacancy_send_eligible(uuid),private.freeze_same_day_canonical_terms() from public,anon,authenticated,service_role;
commit;
