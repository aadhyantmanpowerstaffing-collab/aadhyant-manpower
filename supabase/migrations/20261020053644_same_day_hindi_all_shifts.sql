-- Existing approved Hindi template for every Same-Day Pay shift, as requested.
-- Retain actual overnight dates/duration, canonical fingerprint, consent and template approval gates.
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
 return jsonb_build_object('template_contract','same_day_hi_v1','requirement_code',r.requirement_code,
 'job_location',btrim(regexp_replace(r.job_location,'[[:space:]]+',' ','g')),
 'job_role',btrim(regexp_replace(r.job_role,'[[:space:]]+',' ','g')),
 'work_date',to_char(t.work_date,'DD-MM-YYYY')||case when t.end_date>t.work_date then ' से '||to_char(t.end_date,'DD-MM-YYYY') else '' end,
 'shift',to_char(t.starts_at,'HH24:MI')||' – '||to_char(t.ends_at,'HH24:MI')||' IST ('||(extract(epoch from ((t.end_date+t.ends_at)-(t.work_date+t.starts_at)))/3600)::numeric(5,2)::text||' घंटे)',
 'headcount',r.required_headcount::text,'pay','₹'||t.pay_amount::text,
 'payment',case when t.payment_date>t.work_date then to_char(t.payment_date,'DD-MM-YYYY')||', ' else '' end||case when t.payment_time=t.ends_at then 'शिफ्ट पूरी होते ही, ' else '' end||to_char(t.payment_time,'HH24:MI')||' IST, '||case t.payment_method when 'upi' then 'UPI' when 'cash' then 'नकद' else replace(t.payment_method,'_',' ') end,
 'job_fingerprint',prior->>'job_fingerprint');
end; $function$;
