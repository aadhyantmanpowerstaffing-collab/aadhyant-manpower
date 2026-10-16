'use strict';
const fs=require('node:fs');
const {setup:base}=require('./automatic-alert-runtime-setup');
const map=JSON.parse(fs.readFileSync('docs/whatsapp/full-job-field-map.json','utf8'));
const upgrade=fs.readFileSync('supabase/migrations/20261016114752_complete_whatsapp_job_information.sql','utf8');
async function setup(){const f=await base(),db=f.db;
 const columns=(await db.query("select column_name from information_schema.columns where table_name='employer_requirements' and table_schema='public'")).rows.map(x=>x.column_name);
 const fields=[...Object.values(map.sections).flat().map(x=>x[0]),'additional_notes','interview_date'];
 for(const k of fields)if(!columns.includes(k)&&!['open_positions','interview_date_display'].includes(k))await db.exec('alter table public.employer_requirements add column '+k+' text');
 await db.exec(`create table private.vacancy_candidate_benefits(requirement_id uuid,benefit_type text,benefit_value_type text,amount numeric,amount_basis text);
 create function private.vacancy_candidate_benefits_projection(uuid) returns jsonb language sql stable as $$select coalesce(jsonb_agg(jsonb_build_object('benefit_type',benefit_type,'benefit_value_type',benefit_value_type,'amount',amount,'amount_basis',amount_basis) order by benefit_type),'[]') from private.vacancy_candidate_benefits where requirement_id=$1$$;`);
 await db.exec(upgrade);return {...f,db};}

module.exports={setup};
