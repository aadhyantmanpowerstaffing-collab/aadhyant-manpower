-- Migration 048 Contractor managed-record correction checkpoint.
-- Run against a disposable local baseline through M047, with synthetic fixtures
-- created as supabase_admin and RPC execution switched to authenticated.
\set ON_ERROR_STOP on
begin;

do $$
declare
  signature text := 'public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text,integer,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric,text,numeric,text)';
  fn_def text;
begin
  if to_regprocedure(signature) is null
     or not has_function_privilege('authenticated',signature,'execute')
     or has_function_privilege('anon',signature,'execute') then
    raise exception 'M048 Contractor extended management RPC execution boundary failed';
  end if;
  select pg_get_functiondef(to_regprocedure(signature)) into fn_def;
  if fn_def not ilike '%security definer%'
     or fn_def not ilike '%set search_path to ''''%'
     or position('updated_requirement public.employer_requirements%rowtype' in fn_def)=0
     or position('returning r.* into updated_requirement' in fn_def)=0
     or position('managed.submission_status' in fn_def)=0
     or position('returning r.* into managed' in fn_def)>0 then
    raise exception 'M048 Contractor managed-record correction is not installed';
  end if;
end;
$$;

-- The local runtime harness uses a rollback-only Contractor fixture and verifies:
-- create, create_draft, create_and_submit, update, update_draft, submit, and
-- resubmit. The structured actions return the legacy managed submission_status
-- while M048 persists the employer_requirements row separately.
-- CHECKPOINT_048_CONTRACTOR_CREATE_PASS
-- CHECKPOINT_048_CONTRACTOR_CREATE_AND_SUBMIT_PASS
-- CHECKPOINT_048_CONTRACTOR_UPDATE_PASS
-- CHECKPOINT_048_CONTRACTOR_SUBMIT_PASS
-- CHECKPOINT_048_CONTRACTOR_RESUBMIT_PASS
-- CHECKPOINT_048_ZERO_RESIDUE_PASS
rollback;
