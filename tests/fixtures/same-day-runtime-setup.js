'use strict';
const fs=require('node:fs');
const {setup:full}=require('./full-job-runtime-setup');
const {value}=require('./whatsapp-console-runtime-helpers');
const migration=fs.readFileSync('supabase/migrations/20261017045434_same_day_pay_jobs.sql','utf8');
const company='00000000-0000-0000-0000-000000000011',contractor='00000000-0000-0000-0000-000000000012';
async function setup(){const f=await full(),db=f.db;
 await db.exec(fs.readFileSync('supabase/migrations/20261016124516_readable_whatsapp_job_layout.sql','utf8'));await db.exec(fs.readFileSync('supabase/migrations/20261016131116_concise_registered_job_alerts.sql','utf8'));
 await db.exec(`alter table public.employer_requirements alter column id set default gen_random_uuid();alter table public.employer_requirements add column if not exists company_id uuid,add column if not exists source_type text,add column if not exists review_feedback text;
 alter table public.candidate_applications add column id uuid primary key default gen_random_uuid();create unique index on public.candidate_applications(candidate_id,requirement_id);
 create table public.requirement_contractors(requirement_id uuid,contractor_id uuid,origin_type text,submission_status text,review_feedback text);
 create function private.current_candidate_portal_id() returns uuid language sql stable as $$select nullif(current_setting('test.candidate',true),'')::uuid$$;
 create function private.can_review_vacancies() returns boolean language sql stable as $$select current_setting('test.role',true)='admin'$$;
 create function private.can_manage_company_portal() returns boolean language sql stable as $$select current_setting('test.role',true)='company'$$;
 create function private.can_manage_contractor_vacancies() returns boolean language sql stable as $$select current_setting('test.role',true)='contractor'$$;
 create function private.current_company_portal_id(boolean) returns uuid language sql stable as $$select case when current_setting('test.role',true)='company' then coalesce(nullif(current_setting('test.company',true),''),'${company}')::uuid end$$;
 create function private.current_contractor_portal_id(boolean) returns uuid language sql stable as $$select case when current_setting('test.role',true)='contractor' then '${contractor}'::uuid end$$;
 create function private.normalized_vacancy_review_status(uuid) returns text language sql stable as $$select review_status from public.employer_requirements where id=$1$$;
 -- Minimal canonical RPC adapters: exercise this migration's actual functions, not real customer accounts or a provider.
 create function public.manage_company_portal_requirement(p_action text,p_requirement_id uuid default null,p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,p_shift_details text default null,p_working_hours text default null,p_additional_notes text default null)
 returns table(id uuid) language plpgsql as $f$declare rid uuid:=p_requirement_id;begin
 if not private.can_manage_company_portal() then raise exception 'denied';end if;
 if p_action='create' then insert into public.employer_requirements(company_id,source_type,company_name,requirement_code,job_role,job_location,required_headcount,filled_positions,requirement_stage,requirement_visibility,review_status,shift_details,working_hours,additional_notes) values(private.current_company_portal_id(true),'employer_portal','Synthetic Company','TEST_'||replace(gen_random_uuid()::text,'-',''),p_job_role,p_job_location,p_required_headcount,0,'draft','private','draft',p_shift_details,p_working_hours,p_additional_notes) returning employer_requirements.id into rid;
 elsif p_action='update' then update public.employer_requirements set job_role=p_job_role,job_location=p_job_location,required_headcount=p_required_headcount,shift_details=p_shift_details,working_hours=p_working_hours,additional_notes=p_additional_notes where employer_requirements.id=rid;
 elsif p_action in ('submit','resubmit') then update public.employer_requirements set review_status='pending_review' where employer_requirements.id=rid;else raise exception 'unknown action';end if;
 return query select rid;end;$f$;
 create function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,p_shift_details text default null,p_working_hours text default null,p_additional_notes text default null)
 returns table(id uuid) language plpgsql as $f$declare rid uuid:=p_requirement_id;begin
 if not private.can_manage_contractor_vacancies() then raise exception 'denied';end if;
 if p_action='create' then insert into public.employer_requirements(source_type,company_name,requirement_code,job_role,job_location,required_headcount,filled_positions,requirement_stage,requirement_visibility,review_status,shift_details,working_hours,additional_notes) values('contractor_portal',p_client_name,'TEST_'||replace(gen_random_uuid()::text,'-',''),p_job_role,p_job_location,p_required_headcount,0,'draft','private','draft',p_shift_details,p_working_hours,p_additional_notes) returning employer_requirements.id into rid;
 insert into public.requirement_contractors values(rid,'${contractor}','contractor_submission','draft');
 elsif p_action='update' then update public.employer_requirements set job_role=p_job_role,job_location=p_job_location where employer_requirements.id=rid;
 elsif p_action in ('submit','resubmit') then update public.employer_requirements set review_status='pending_review' where employer_requirements.id=rid;update public.requirement_contractors set submission_status='submitted' where requirement_id=rid;end if;return query select rid;end;$f$;
 create function public.apply_candidate_job(text) returns uuid language plpgsql as $$declare aid uuid;begin insert into public.candidate_applications(candidate_id,requirement_id) select private.current_candidate_portal_id(),r.id from public.employer_requirements r where r.requirement_code=$1 returning id into aid;return aid;end;$$;
 select set_config('test.role','company',false);
 `);
 await db.exec(migration);
 const tomorrow=(await value(db,"select ((clock_timestamp() at time zone 'Asia/Kolkata')::date+1)::text d")).d;
 const payload={job_role:'Packing Helper',job_location:'Sanand GIDC, Gate 2',company_name:'Synthetic Client',required_headcount:'1',work_date:tomorrow,starts_at:'08:00',ends_at:'12:00',pay_amount:'350',payment_time:'18:00',payment_method:'upi',payment_by:'company',reporting_point:'Gate 2',contact_name:'Synthetic Supervisor',contact_phone:'9876543210',facilities:'Bring safety shoes'};
 return {db,payload};
}
async function submit(db,p,role='company',key=crypto.randomUUID(),id=null){return(await value(db,'select public.submit_same_day_job($1,$2::jsonb,$3,$4) id',[role,JSON.stringify(p),key,id])).id;}
async function publish(db,id){await db.query("update public.employer_requirements set review_status='approved',requirement_stage='open',requirement_visibility='public' where id=$1",[id]);}
async function candidate(db,phone='9876543211'){const c=(await value(db,"insert into public.candidates(full_name,mobile,whatsapp_number,profile_status,status) values('Synthetic Candidate',$1,$1,'active','new') returning id",[phone])).id;await db.query("select set_config('test.candidate',$1,false)",[c]);await db.exec("select set_config('test.role','candidate',false)");return c;}

module.exports={setup,submit,publish,candidate,company,contractor,value};
