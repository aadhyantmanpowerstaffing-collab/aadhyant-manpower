-- Keep agreed historical payment times. New and resubmitted shifts must pay at shift end.
begin;
alter table private.same_day_job_terms drop constraint same_day_job_terms_check1;
alter table private.same_day_job_terms add constraint same_day_payment_after_work check(payment_time>=ends_at);

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
 or (d+s) at time zone 'Asia/Kolkata'<=clock_timestamp() or e<=s or e-s>interval '16 hours' or payment<>e
 or amount<=0 or amount>100000 or count_needed not between 1 and 100000
 or length(btrim(coalesce(p_payload->>'job_role',''))) not between 1 and 120
 or length(btrim(coalesce(p_payload->>'job_location',''))) not between 1 and 200
 then raise exception 'Enter a future shift, fixed pay and payment immediately at shift completion';end if;
 if p_requirement_id is not null then
  perform 1 from public.employer_requirements r where r.id=p_requirement_id and r.work_engagement='same_day_pay' and private.same_day_owner(r.id) and private.normalized_vacancy_review_status(r.id) in ('draft','correction_required') for update;
  if not found then raise exception 'Only your draft or correction-required Same-Day Pay job can be edited';end if;
 end if;
 notes:='Same-Day Pay Job. Payment immediately after shift completion by '||coalesce(p_payload->>'payment_by','')||' at '||payment::text||' IST using '||coalesce(p_payload->>'payment_method','')||'. Reporting: '||coalesce(p_payload->>'reporting_point','')||'. Facilities: '||coalesce(p_payload->>'facilities','');
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
 update public.employer_requirements set work_engagement='same_day_pay',salary_wage='INR '||amount||' for the complete shift; paid immediately after shift completion' where id=v_id;
 if p_role='company' then perform public.manage_company_portal_requirement(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id);
 else perform public.manage_contractor_portal_vacancy(p_action=>case when old_review='correction_required' then 'resubmit' else 'submit' end,p_requirement_id=>v_id,p_client_name=>btrim(p_payload->>'company_name'),p_department=>'Same-Day Pay',p_job_role=>btrim(p_payload->>'job_role'),p_job_location=>btrim(p_payload->>'job_location'),p_required_headcount=>count_needed);end if;
 update private.same_day_submit_requests set requirement_id=v_id where actor_id=actor and request_key=p_request_key;
 return v_id;
end; $$;
commit;
