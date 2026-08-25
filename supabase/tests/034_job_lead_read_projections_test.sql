-- Phase B rollback checkpoint: Job Lead projections only.
begin;
do $$
begin
  if to_regprocedure('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)') is null then raise exception 'Job Lead list RPC missing'; end if;
  if to_regprocedure('public.admin_get_job_lead_detail(uuid)') is null then raise exception 'Job Lead detail RPC missing'; end if;
  if pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%security definer%' or pg_get_functiondef('public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)'::regprocedure) not ilike '%search_path to ''''%' then raise exception 'Job Lead security posture invalid'; end if;
  if has_function_privilege('anon','public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)','execute') or not has_function_privilege('authenticated','public.admin_list_job_leads(text,text,text,uuid,boolean,uuid,boolean,boolean,date,date,integer,integer)','execute') then raise exception 'Job Lead grant matrix invalid'; end if;
  if (select count(*) from information_schema.parameters where specific_name like 'admin_list_job_leads%' and parameter_name='p_limit')=0 then raise exception 'Job Lead bounded pagination contract missing'; end if;
  if pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) ilike '%phone%' or pg_get_functiondef('public.admin_get_job_lead_detail(uuid)'::regprocedure) ilike '%aadhaar%' then raise exception 'Sensitive field leaked in Job Lead detail'; end if;
end $$;
rollback;
select 'CHECKPOINT_034_STATIC_PASS' as result;
