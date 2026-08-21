-- W6: Candidate Portal and private document-onboarding foundation.
-- Extends canonical recruitment records; no parallel candidate/application workflow is created.

begin;

do $$
begin
  if to_regclass('public.candidates') is null
     or to_regclass('public.candidate_preferences') is null
     or to_regclass('public.candidate_applications') is null
     or to_regclass('public.interviews') is null
     or to_regclass('public.candidate_joinings') is null
     or to_regclass('public.platform_users') is null
     or to_regclass('public.admin_users') is null
     or to_regclass('public.staff_profiles') is null
     or to_regclass('public.company_users') is null
     or to_regclass('public.contractor_users') is null
     or to_regclass('public.audit_logs') is null
     or to_regprocedure('private.can_manage_candidates()') is null then
    raise exception 'W6 candidate/recruitment prerequisites are missing';
  end if;
  if to_regclass('public.candidate_documents') is not null
     or to_regclass('public.candidate_onboarding_details') is not null
     or to_regprocedure('public.get_candidate_portal_context()') is not null
     or exists(select 1 from storage.buckets b where b.id='candidate-private') then
    raise exception 'W6 objects already exist; inspect partial/manual changes instead of re-running';
  end if;
end;
$$;

alter table public.candidates
  add column aadhaar_fingerprint text,
  add column aadhaar_last4 text,
  add column mobile_verified boolean not null default false,
  add column date_of_birth date,
  add column pincode text;

alter table public.candidates
  add constraint candidates_aadhaar_fingerprint_key unique (aadhaar_fingerprint),
  add constraint candidates_aadhaar_pair_check check (
    (aadhaar_fingerprint is null and aadhaar_last4 is null)
    or (aadhaar_fingerprint ~ '^[0-9a-f]{64}$' and aadhaar_last4 ~ '^[0-9]{4}$')
  ),
  add constraint candidates_pincode_check check (pincode is null or pincode ~ '^[0-9]{6}$'),
  add constraint candidates_date_of_birth_check check (
    date_of_birth is null or date_of_birth between (current_date - interval '75 years')::date and (current_date - interval '16 years')::date
  );

create table public.candidate_onboarding_details (
  candidate_id uuid primary key references public.candidates(id) on delete restrict,
  account_holder_name text,
  bank_name text,
  bank_account_fingerprint text,
  bank_account_last4 text,
  ifsc text,
  has_existing_uan boolean,
  uan_number text,
  has_existing_esic_ip boolean,
  esic_ip_number text,
  documentation_override_approved boolean not null default false,
  documentation_override_reason text,
  documentation_override_by uuid references auth.users(id) on delete set null,
  documentation_override_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_onboarding_bank_pair_check check (
    (bank_account_fingerprint is null and bank_account_last4 is null)
    or (bank_account_fingerprint ~ '^[0-9a-f]{64}$' and bank_account_last4 ~ '^[0-9]{4}$')
  ),
  constraint candidate_onboarding_ifsc_check check (ifsc is null or ifsc ~ '^[A-Z]{4}0[A-Z0-9]{6}$'),
  constraint candidate_onboarding_uan_check check (
    (has_existing_uan is distinct from true and uan_number is null)
    or (has_existing_uan is true and uan_number ~ '^[0-9]{12}$')
  ),
  constraint candidate_onboarding_esic_check check (
    (has_existing_esic_ip is distinct from true and esic_ip_number is null)
    or (has_existing_esic_ip is true and esic_ip_number ~ '^[0-9]{10,17}$')
  ),
  constraint candidate_onboarding_override_check check (
    (documentation_override_approved is false and documentation_override_reason is null
      and documentation_override_by is null and documentation_override_at is null)
    or (documentation_override_approved is true
      and length(btrim(documentation_override_reason)) between 10 and 1000
      and documentation_override_by is not null and documentation_override_at is not null)
  )
);

create table public.candidate_documents (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null references public.candidates(id) on delete restrict,
  document_type text not null check (document_type in (
    'resume','aadhaar','aadhaar_front','aadhaar_back','pan','candidate_photo',
    '10th_certificate','12th_certificate','iti_certificate','iti_marksheet',
    'diploma_certificate','degree_certificate','education_other',
    'experience_certificate','previous_employment','bank_proof','bank_passbook','cancelled_cheque',
    'driving_licence','passport','other'
  )),
  storage_object_name text not null unique,
  display_file_name text not null check (length(btrim(display_file_name)) between 1 and 240),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  file_size_bytes bigint not null check (file_size_bytes between 1 and 10485760),
  verification_status text not null default 'uploaded'
    check (verification_status in ('uploaded','under_verification','verified','reupload_required')),
  verification_feedback text check (verification_feedback is null or length(btrim(verification_feedback)) between 1 and 1000),
  active boolean not null default true,
  uploaded_at timestamptz not null default now(),
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  replaced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint candidate_documents_verification_check check (
    (verification_status = 'verified' and verified_at is not null and verified_by is not null and verification_feedback is null)
    or (verification_status = 'reupload_required' and verified_at is null and verified_by is not null and verification_feedback is not null)
    or (verification_status in ('uploaded','under_verification') and verified_at is null and verified_by is null and verification_feedback is null)
  )
);

create unique index candidate_documents_active_single_idx
  on public.candidate_documents(candidate_id, document_type) where active;
create index candidate_documents_candidate_uploaded_idx
  on public.candidate_documents(candidate_id, uploaded_at desc);
create index candidate_documents_verification_idx
  on public.candidate_documents(verification_status, uploaded_at);

create trigger candidate_onboarding_details_set_updated_at before update on public.candidate_onboarding_details
  for each row execute function private.set_updated_at();
create trigger candidate_documents_set_updated_at before update on public.candidate_documents
  for each row execute function private.set_updated_at();

alter table public.candidate_onboarding_details enable row level security;
alter table public.candidate_documents enable row level security;
revoke all on public.candidate_onboarding_details from anon, authenticated;
revoke all on public.candidate_documents from anon, authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('candidate-private','candidate-private',false,10485760,array['application/pdf','image/jpeg','image/png']);

create function private.current_candidate_portal_id()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_candidate_id uuid; v_count integer;
begin
  if (select auth.uid()) is null then return null; end if;
  select count(*), (array_agg(c.id))[1] into v_count,v_candidate_id
  from public.candidates c
  join public.platform_users pu on pu.user_id=c.user_id
  where c.user_id=(select auth.uid()) and pu.account_type='candidate'
    and pu.account_status='active' and c.profile_status='active' and c.status<>'inactive';
  return case when v_count=1 then v_candidate_id else null end;
end;
$$;

create function private.can_verify_candidate_documents()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select private.is_bootstrap_recruitment_admin())
    or (select private.has_staff_role('super_admin'))
    or (select private.has_staff_role('admin'));
$$;

create function public.get_candidate_onboarding_eligibility()
returns boolean language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
    and not exists(select 1 from public.platform_users pu where pu.user_id=(select auth.uid()))
    and not exists(select 1 from public.candidates c where c.user_id=(select auth.uid()))
    and not exists(select 1 from public.admin_users au where au.user_id=(select auth.uid()))
    and not exists(select 1 from public.staff_profiles sp where sp.user_id=(select auth.uid()))
    and not exists(select 1 from public.company_users cu where cu.user_id=(select auth.uid()))
    and not exists(select 1 from public.contractor_users cu where cu.user_id=(select auth.uid()))
    and exists(select 1 from auth.users u where u.id=(select auth.uid()));
$$;

create function public.create_candidate_portal_profile(p_full_name text,p_mobile text,p_aadhaar text,p_date_of_birth date,
  p_gender text,p_current_location text,p_district text,p_state text,p_pincode text,p_highest_qualification text,
  p_specialization text,p_candidate_type text,p_consent boolean)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_auth uuid:=(select auth.uid()); v_mobile text; v_aadhaar text; v_age integer; v_candidate uuid;
begin
  if v_auth is null then raise exception 'Authentication is required'; end if;
  if exists(select 1 from public.platform_users pu where pu.user_id=v_auth)
     or exists(select 1 from public.candidates c where c.user_id=v_auth)
     or exists(select 1 from public.admin_users au where au.user_id=v_auth)
     or exists(select 1 from public.staff_profiles sp where sp.user_id=v_auth)
     or exists(select 1 from public.company_users cu where cu.user_id=v_auth)
     or exists(select 1 from public.contractor_users cu where cu.user_id=v_auth) then raise exception 'Candidate account already exists or requires review'; end if;
  v_mobile:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
  v_aadhaar:=regexp_replace(coalesce(p_aadhaar,''),'[^0-9]','','g');
  if p_consent is not true or v_mobile !~ '^[6-9][0-9]{9}$' or v_aadhaar !~ '^[0-9]{12}$'
     or p_date_of_birth is null or p_date_of_birth not between (current_date-interval '75 years')::date and (current_date-interval '16 years')::date then
    raise exception 'Valid required Candidate details and consent are required';
  end if;
  v_age:=extract(year from age(current_date,p_date_of_birth))::integer;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w6-mobile:'||v_mobile,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w6-aadhaar:'||v_aadhaar,0));
  if exists(select 1 from public.candidates c where c.mobile=v_mobile or c.aadhaar_fingerprint=encode(extensions.digest(v_aadhaar,'sha256'),'hex')) then
    raise exception 'Candidate details require review';
  end if;
  insert into public.platform_users(user_id,account_type,display_name,mobile,email,account_status)
    select v_auth,'candidate',btrim(p_full_name),v_mobile,u.email,'active' from auth.users u where u.id=v_auth;
  insert into public.candidates(full_name,age,gender,mobile,current_location,district,state,pincode,highest_qualification,
    specialization,candidate_type,interview_available,consent,status,user_id,profile_status,profile_completion_status,
    current_employment_status,availability_status,aadhaar_fingerprint,aadhaar_last4,date_of_birth)
  values(btrim(p_full_name),v_age,p_gender,v_mobile,btrim(p_current_location),btrim(p_district),btrim(p_state),
    nullif(btrim(p_pincode),''),p_highest_qualification,nullif(btrim(p_specialization),''),p_candidate_type,'Yes',true,
    'new',v_auth,'active','complete','unknown','open_to_opportunities',encode(extensions.digest(v_aadhaar,'sha256'),'hex'),right(v_aadhaar,4),p_date_of_birth)
  returning id into v_candidate;
  insert into public.candidate_preferences(candidate_id,source) values(v_candidate,'candidate');
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_auth,'candidate','candidate.portal_profile_created','candidate',v_candidate,'candidate','{}');
  return v_candidate;
exception when unique_violation or check_violation or not_null_violation or string_data_right_truncation then
  raise exception 'Candidate details are invalid or already in use';
end;
$$;

create function public.get_candidate_portal_context()
returns table(candidate_id uuid,display_name text,platform_status text,candidate_status text,
  profile_completion integer,profile_complete boolean,mobile_verified boolean,aadhaar_masked text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select c.id,c.full_name,pu.account_status,c.profile_status,
    ((case when c.full_name<>'' then 1 else 0 end + case when c.mobile ~ '^[6-9][0-9]{9}$' then 1 else 0 end
      +case when c.aadhaar_last4 is not null then 1 else 0 end +case when c.highest_qualification is not null then 1 else 0 end
      +case when c.current_location<>'' and c.district<>'' and c.state<>'' then 1 else 0 end
      +case when exists(select 1 from public.candidate_preferences cp where cp.candidate_id=c.id) then 1 else 0 end
      +case when exists(select 1 from public.candidate_documents d where d.candidate_id=c.id and d.document_type='resume' and d.active) then 1 else 0 end) * 100 / 7)::integer,
    (c.mobile ~ '^[6-9][0-9]{9}$' and c.aadhaar_last4 is not null and c.full_name<>''
      and c.highest_qualification is not null and c.current_location<>'' and c.district<>'' and c.state<>''),
    c.mobile_verified,case when c.aadhaar_last4 is null then null else 'XXXX XXXX '||c.aadhaar_last4 end
  from public.candidates c join public.platform_users pu on pu.user_id=c.user_id where c.id=v_id;
end;
$$;

create function public.get_candidate_portal_profile()
returns table(full_name text,mobile text,mobile_verified boolean,aadhaar_masked text,date_of_birth date,age integer,
  gender text,current_location text,district text,state text,pincode text,highest_qualification text,specialization text,
  candidate_type text,total_experience text,previous_job_role text,interview_available text,preferred_job_location text,
  preferred_locations text[],preferred_job_roles text[],expected_salary_min numeric,expected_salary_max numeric,
  preferred_shift text,immediate_joining boolean,joining_availability_date date)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select c.full_name,c.mobile,c.mobile_verified,
    case when c.aadhaar_last4 is null then null else 'XXXX XXXX '||c.aadhaar_last4 end,c.date_of_birth,c.age,c.gender,
    c.current_location,c.district,c.state,c.pincode,c.highest_qualification,c.specialization,c.candidate_type,
    c.total_experience,c.previous_job_role,c.interview_available,c.preferred_job_location,
    coalesce(cp.preferred_locations,'{}'),coalesce(cp.preferred_job_roles,'{}'),cp.expected_salary_min,
    cp.expected_salary_max,cp.preferred_shift,cp.immediate_joining,cp.joining_availability_date
  from public.candidates c left join public.candidate_preferences cp on cp.candidate_id=c.id where c.id=v_id;
end;
$$;

create function public.update_candidate_portal_profile(p_full_name text,p_mobile text,p_aadhaar text,p_date_of_birth date,
  p_gender text,p_current_location text,p_district text,p_state text,p_pincode text,p_highest_qualification text,
  p_specialization text,p_candidate_type text,p_total_experience text,p_previous_job_role text,p_interview_available text,
  p_preferred_locations text[],p_preferred_job_roles text[],p_expected_salary_min numeric,p_expected_salary_max numeric,
  p_preferred_shift text,p_immediate_joining boolean,p_joining_availability_date date)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_mobile text; v_aadhaar text; v_age integer;
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  v_mobile:=regexp_replace(coalesce(p_mobile,''),'[^0-9]','','g');
  v_aadhaar:=regexp_replace(coalesce(p_aadhaar,''),'[^0-9]','','g');
  if v_mobile !~ '^[6-9][0-9]{9}$' or v_aadhaar !~ '^[0-9]{12}$' then raise exception 'A valid mobile and Aadhaar number are required'; end if;
  if p_date_of_birth is null or p_date_of_birth not between (current_date-interval '75 years')::date and (current_date-interval '16 years')::date then raise exception 'Date of birth is invalid'; end if;
  v_age:=extract(year from age(current_date,p_date_of_birth))::integer;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w6-mobile:'||v_mobile,0));
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('w6-aadhaar:'||v_aadhaar,0));
  if exists(select 1 from public.candidates c where c.id<>v_id and c.mobile=v_mobile) then raise exception 'Profile details require review'; end if;
  if exists(select 1 from public.candidates c where c.id<>v_id and c.aadhaar_fingerprint=encode(extensions.digest(v_aadhaar,'sha256'),'hex')) then raise exception 'Profile details require review'; end if;
  update public.candidates c set full_name=btrim(p_full_name),mobile=v_mobile,
    aadhaar_fingerprint=encode(extensions.digest(v_aadhaar,'sha256'),'hex'),aadhaar_last4=right(v_aadhaar,4),
    date_of_birth=p_date_of_birth,age=v_age,gender=p_gender,current_location=btrim(p_current_location),
    district=btrim(p_district),state=btrim(p_state),pincode=nullif(btrim(p_pincode),''),
    highest_qualification=p_highest_qualification,specialization=nullif(btrim(p_specialization),''),candidate_type=p_candidate_type,
    total_experience=nullif(btrim(p_total_experience),''),previous_job_role=nullif(btrim(p_previous_job_role),''),
    interview_available=p_interview_available,preferred_job_location=nullif((p_preferred_locations)[1],''),
    profile_completion_status='complete' where c.id=v_id;
  update public.platform_users pu set display_name=btrim(p_full_name),mobile=v_mobile where pu.user_id=(select auth.uid()) and pu.account_type='candidate';
  insert into public.candidate_preferences(candidate_id,preferred_locations,preferred_job_roles,expected_salary_min,
    expected_salary_max,preferred_shift,immediate_joining,joining_availability_date,source)
  values(v_id,coalesce(p_preferred_locations,'{}'),coalesce(p_preferred_job_roles,'{}'),p_expected_salary_min,
    p_expected_salary_max,nullif(btrim(p_preferred_shift),''),coalesce(p_immediate_joining,false),
    case when p_immediate_joining then null else p_joining_availability_date end,'candidate')
  on conflict(candidate_id) do update set preferred_locations=excluded.preferred_locations,
    preferred_job_roles=excluded.preferred_job_roles,expected_salary_min=excluded.expected_salary_min,
    expected_salary_max=excluded.expected_salary_max,preferred_shift=excluded.preferred_shift,
    immediate_joining=excluded.immediate_joining,joining_availability_date=excluded.joining_availability_date,source='candidate';
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'candidate','candidate.profile_updated','candidate',v_id,'candidate',
      jsonb_build_object('mobile_changed',true,'aadhaar_updated',true));
  return true;
exception when unique_violation or check_violation or not_null_violation or string_data_right_truncation then
  raise exception 'Profile details are invalid or already in use';
end;
$$;

create function public.get_candidate_dashboard_metrics()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return jsonb_build_object('applications',(select count(*) from public.candidate_applications a where a.candidate_id=v_id),
    'interviews',(select count(*) from public.interviews i join public.candidate_applications a on a.id=i.application_id where a.candidate_id=v_id),
    'selected',(select count(*) from public.candidate_applications a where a.candidate_id=v_id and a.application_status in ('selected','joining_pending')),
    'joining_pending',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.candidate_id=v_id and j.joining_status in ('pending','confirmed','deferred')),
    'joined',(select count(*) from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id where a.candidate_id=v_id and j.joining_status='joined'));
end;
$$;

create function public.list_candidate_job_opportunities(p_search text default null,p_limit integer default 25,p_offset integer default 0)
returns table(requirement_code text,job_role text,department text,job_location text,open_positions integer,
  qualification text,iti_trade text,experience_requirement text,age_min integer,age_max integer,gender_preference text,salary_min numeric,salary_max numeric,
  shift_details text,working_hours text,overtime_details text,canteen text,transport text,accommodation text,
  interview_location text,expected_joining_date date,safe_description text,already_applied boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_search text:=nullif(btrim(p_search),'');
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,r.department,r.job_location,
    greatest(r.required_headcount-r.filled_positions,0)::integer,r.qualification,r.iti_trade,r.experience_requirement,
    r.age_min,r.age_max,r.gender_preference,r.salary_min,r.salary_max,r.shift_details,r.working_hours,r.overtime_details,r.canteen,r.transport,r.accommodation,
    r.interview_location,r.expected_joining_date,r.additional_notes,
    exists(select 1 from public.candidate_applications a where a.candidate_id=v_id and a.requirement_id=r.id)
  from public.employer_requirements r where r.requirement_stage='open' and r.requirement_visibility='public'
    and r.required_headcount>r.filled_positions and r.requirement_code is not null
    and (v_search is null or r.requirement_code ilike '%'||v_search||'%' or r.job_role ilike '%'||v_search||'%'
      or coalesce(r.job_location,'') ilike '%'||v_search||'%')
  order by coalesce(r.published_at,r.created_at) desc,r.requirement_code desc
  limit least(greatest(coalesce(p_limit,25),1),50) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create function public.apply_candidate_job(p_requirement_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_requirement public.employer_requirements%rowtype; v_application uuid;
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  if not exists(select 1 from public.candidates c where c.id=v_id and c.mobile ~ '^[6-9][0-9]{9}$' and c.aadhaar_last4 is not null and c.profile_completion_status='complete')
     or not exists(select 1 from public.candidate_documents d where d.candidate_id=v_id and d.document_type='resume' and d.active) then raise exception 'Complete the required Candidate profile and Resume before applying'; end if;
  select r.* into v_requirement from public.employer_requirements r where r.requirement_code=upper(btrim(p_requirement_code))
    and r.requirement_stage='open' and r.requirement_visibility='public' and r.required_headcount>r.filled_positions for share;
  if not found then raise exception 'Opportunity is not available'; end if;
  insert into public.candidate_applications(candidate_id,requirement_id,source_type,application_status,created_by,source_reference)
    values(v_id,v_requirement.id,'direct','applied',(select auth.uid()),'candidate_portal') returning id into v_application;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'candidate','candidate.application_created','candidate_application',v_application,'candidate',jsonb_build_object('requirement_id',v_requirement.id));
  return v_application;
exception when unique_violation then raise exception 'You already have an application for this opportunity';
end;
$$;

create function public.list_candidate_portal_applications(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,job_location text,application_stage text,applied_at timestamptz,
  interview_status text,joining_status text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,r.job_location,a.application_status,a.applied_at,
    (select i.status from public.interviews i where i.application_id=a.id order by i.created_at desc limit 1),j.joining_status
  from public.candidate_applications a join public.employer_requirements r on r.id=a.requirement_id
  left join public.candidate_joinings j on j.application_id=a.id where a.candidate_id=v_id
  order by a.applied_at desc limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create function public.list_candidate_portal_interviews(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,scheduled_at timestamptz,mode text,location text,interview_round text,status text,result text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,i.scheduled_at,i.mode,i.location,i.interview_round,i.status,i.result
  from public.interviews i join public.candidate_applications a on a.id=i.application_id
  join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=v_id
  order by i.scheduled_at desc nulls last limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create function public.list_candidate_portal_joinings(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,expected_joining_date date,actual_joining_date date,joining_status text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,j.expected_joining_date,j.actual_joining_date,j.joining_status
  from public.candidate_joinings j join public.candidate_applications a on a.id=j.application_id
  join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=v_id
  order by j.created_at desc limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

create function public.list_candidate_portal_documents()
returns table(document_id uuid,document_type text,display_file_name text,mime_type text,file_size_bytes bigint,
  verification_status text,verification_feedback text,uploaded_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select d.id,d.document_type,d.display_file_name,d.mime_type,d.file_size_bytes,
    d.verification_status,d.verification_feedback,d.uploaded_at from public.candidate_documents d
  where d.candidate_id=v_id and d.active order by d.document_type;
end;
$$;

create function public.register_candidate_document(p_document_type text,p_storage_object_name text,p_display_file_name text,
  p_mime_type text,p_file_size_bytes bigint)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_auth uuid:=(select auth.uid()); v_document uuid;
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  if p_storage_object_name !~ ('^'||v_auth::text||'/[0-9a-f-]{36}/[A-Za-z0-9._-]{1,160}$')
     or p_display_file_name like '%/%' or p_display_file_name like '%\%' then raise exception 'Document details are invalid'; end if;
  if (p_document_type='resume' and p_mime_type<>'application/pdf')
     or (p_document_type='candidate_photo' and p_mime_type not in ('image/jpeg','image/png'))
     or (p_mime_type='application/pdf' and p_storage_object_name !~ '\.pdf$')
     or (p_mime_type='image/jpeg' and p_storage_object_name !~ '\.(jpg|jpeg)$')
     or (p_mime_type='image/png' and p_storage_object_name !~ '\.png$') then raise exception 'Document type and file format do not match'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='candidate-private' and o.name=p_storage_object_name
    and coalesce(o.metadata->>'mimetype','')=p_mime_type
    and coalesce(nullif(o.metadata->>'size',''),'0')::bigint=p_file_size_bytes) then raise exception 'Uploaded document could not be verified'; end if;
  update public.candidate_documents d set active=false,replaced_at=now() where d.candidate_id=v_id and d.document_type=p_document_type and d.active;
  insert into public.candidate_documents(candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes)
    values(v_id,p_document_type,p_storage_object_name,btrim(p_display_file_name),p_mime_type,p_file_size_bytes) returning id into v_document;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values(v_auth,'candidate','candidate.document_uploaded','candidate_document',v_document,'candidate',jsonb_build_object('document_type',p_document_type));
  return v_document;
end;
$$;

create function public.get_candidate_document_access(p_document_id uuid)
returns table(bucket_name text,object_name text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select 'candidate-private'::text,d.storage_object_name from public.candidate_documents d
    where d.id=p_document_id and d.candidate_id=v_id and d.active;
end;
$$;

create function public.get_candidate_joining_document_checklist()
returns table(document_type text,label text,required boolean,verification_status text,complete boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query with required_docs(document_type,label,required) as (values
    ('mobile'::text,'Mobile Number',true),('aadhaar_number','Aadhaar Number',true),('bank_details','Bank Details',true),
    ('aadhaar','Aadhaar Document',true),('candidate_photo','Candidate Photo',true),('bank_proof','Bank Proof',true),
    ('pan','PAN',false),('iti_certificate','ITI Certificate',false),('experience_certificate','Experience Certificate',false))
  select rd.document_type,rd.label,rd.required,
    case when rd.document_type='mobile' then case when c.mobile_verified then 'verified' else 'uploaded' end
      when rd.document_type='aadhaar_number' then case when c.aadhaar_last4 is not null then 'verified' else null end
      when rd.document_type='bank_details' then case when o.bank_account_last4 is not null and o.ifsc is not null then 'uploaded' else null end
      else d.verification_status end,
    case when rd.document_type='mobile' then c.mobile_verified
      when rd.document_type='aadhaar_number' then c.aadhaar_last4 is not null
      when rd.document_type='bank_details' then o.bank_account_last4 is not null and o.ifsc is not null
      else coalesce(d.verification_status='verified',false) end
  from required_docs rd cross join public.candidates c
  left join public.candidate_onboarding_details o on o.candidate_id=c.id
  left join public.candidate_documents d on d.candidate_id=v_id and d.document_type=rd.document_type and d.active
  where c.id=v_id
  order by rd.required desc,rd.label;
end;
$$;

create function public.get_candidate_onboarding_details()
returns table(account_holder_name text,bank_name text,bank_account_masked text,ifsc text,has_existing_uan boolean,
  uan_masked text,has_existing_esic_ip boolean,esic_ip_masked text,documentation_override_approved boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select o.account_holder_name,o.bank_name,
    case when o.bank_account_last4 is null then null else 'XXXX XXXX '||o.bank_account_last4 end,o.ifsc,o.has_existing_uan,
    case when o.uan_number is null then null else 'XXXXXXXX'||right(o.uan_number,4) end,o.has_existing_esic_ip,
    case when o.esic_ip_number is null then null else repeat('X',greatest(length(o.esic_ip_number)-4,0))||right(o.esic_ip_number,4) end,
    o.documentation_override_approved from public.candidate_onboarding_details o where o.candidate_id=v_id;
end;
$$;

create function public.update_candidate_onboarding_details(p_account_holder_name text,p_bank_name text,p_bank_account_number text,
  p_ifsc text,p_has_existing_uan boolean,p_uan_number text,p_has_existing_esic_ip boolean,p_esic_ip_number text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id()); v_account text; v_ifsc text:=upper(btrim(coalesce(p_ifsc,'')));
  v_uan text:=regexp_replace(coalesce(p_uan_number,''),'[^0-9]','','g'); v_esic text:=regexp_replace(coalesce(p_esic_ip_number,''),'[^0-9]','','g');
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  v_account:=regexp_replace(coalesce(p_bank_account_number,''),'[^0-9]','','g');
  if length(btrim(coalesce(p_account_holder_name,''))) not between 1 and 160 or length(btrim(coalesce(p_bank_name,''))) not between 1 and 160
    or v_account !~ '^[0-9]{6,20}$' or v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$'
    or (coalesce(p_has_existing_uan,false) and v_uan !~ '^[0-9]{12}$')
    or (coalesce(p_has_existing_esic_ip,false) and v_esic !~ '^[0-9]{10,17}$') then raise exception 'Joining onboarding details are invalid'; end if;
  insert into public.candidate_onboarding_details(candidate_id,account_holder_name,bank_name,bank_account_fingerprint,
    bank_account_last4,ifsc,has_existing_uan,uan_number,has_existing_esic_ip,esic_ip_number)
  values(v_id,btrim(p_account_holder_name),btrim(p_bank_name),encode(extensions.digest(v_account,'sha256'),'hex'),right(v_account,4),v_ifsc,
    coalesce(p_has_existing_uan,false),case when p_has_existing_uan then v_uan else null end,
    coalesce(p_has_existing_esic_ip,false),case when p_has_existing_esic_ip then v_esic else null end)
  on conflict(candidate_id) do update set account_holder_name=excluded.account_holder_name,bank_name=excluded.bank_name,
    bank_account_fingerprint=excluded.bank_account_fingerprint,bank_account_last4=excluded.bank_account_last4,ifsc=excluded.ifsc,
    has_existing_uan=excluded.has_existing_uan,uan_number=excluded.uan_number,has_existing_esic_ip=excluded.has_existing_esic_ip,
    esic_ip_number=excluded.esic_ip_number;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'candidate','candidate.onboarding_details_updated','candidate',v_id,'candidate',jsonb_build_object('bank_updated',true,'uan_declared',coalesce(p_has_existing_uan,false),'esic_declared',coalesce(p_has_existing_esic_ip,false)));
  return true;
end;
$$;

create function public.admin_list_candidate_documents(p_candidate_id uuid)
returns table(document_id uuid,document_type text,display_file_name text,mime_type text,file_size_bytes bigint,
  verification_status text,verification_feedback text,uploaded_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_verify_candidate_documents()) then raise exception 'Candidate document verification access is required'; end if;
  return query select d.id,d.document_type,d.display_file_name,d.mime_type,d.file_size_bytes,
    d.verification_status,d.verification_feedback,d.uploaded_at from public.candidate_documents d
  where d.candidate_id=p_candidate_id and d.active order by d.document_type;
end;
$$;

create function public.admin_get_candidate_document_access(p_document_id uuid)
returns table(bucket_name text,object_name text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (select private.can_verify_candidate_documents()) then raise exception 'Candidate document verification access is required'; end if;
  return query select 'candidate-private'::text,d.storage_object_name from public.candidate_documents d
    where d.id=p_document_id and d.active;
end;
$$;

create function public.admin_review_candidate_document(p_document_id uuid,p_status text,p_feedback text default null)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_status text:=lower(btrim(coalesce(p_status,''))); v_candidate uuid;
begin
  if not (select private.can_verify_candidate_documents()) then raise exception 'Candidate document verification access is required'; end if;
  if v_status not in ('verified','reupload_required') or (v_status='reupload_required' and length(btrim(coalesce(p_feedback,''))) not between 5 and 1000) then raise exception 'Document review details are invalid'; end if;
  update public.candidate_documents d set verification_status=v_status,
    verification_feedback=case when v_status='reupload_required' then btrim(p_feedback) else null end,
    verified_at=case when v_status='verified' then now() else null end,verified_by=(select auth.uid())
    where d.id=p_document_id and d.active returning d.candidate_id into v_candidate;
  if v_candidate is null then raise exception 'Candidate document was not found'; end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','candidate.document_reviewed','candidate_document',p_document_id,'admin',jsonb_build_object('status',v_status));
  return true;
end;
$$;

create function public.admin_set_candidate_documentation_override(p_candidate_id uuid,p_approved boolean,p_reason text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not (select private.can_verify_candidate_documents()) then raise exception 'Candidate documentation override access is required'; end if;
  if p_approved is not true or length(btrim(coalesce(p_reason,''))) not between 10 and 1000 then raise exception 'A documented approval reason is required'; end if;
  insert into public.candidate_onboarding_details(candidate_id,documentation_override_approved,documentation_override_reason,
    documentation_override_by,documentation_override_at) values(p_candidate_id,true,btrim(p_reason),(select auth.uid()),now())
  on conflict(candidate_id) do update set documentation_override_approved=true,documentation_override_reason=excluded.documentation_override_reason,
    documentation_override_by=excluded.documentation_override_by,documentation_override_at=excluded.documentation_override_at;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'staff','candidate.documentation_override_approved','candidate',p_candidate_id,'admin','{}');
  return true;
end;
$$;

revoke all on function private.current_candidate_portal_id() from public,anon,authenticated;
revoke all on function private.can_verify_candidate_documents() from public,anon,authenticated;

revoke all on function public.get_candidate_portal_context() from public,anon,authenticated;
revoke all on function public.get_candidate_onboarding_eligibility() from public,anon,authenticated;
revoke all on function public.create_candidate_portal_profile(text,text,text,date,text,text,text,text,text,text,text,text,boolean) from public,anon,authenticated;
revoke all on function public.get_candidate_portal_profile() from public,anon,authenticated;
revoke all on function public.update_candidate_portal_profile(text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,text[],text[],numeric,numeric,text,boolean,date) from public,anon,authenticated;
revoke all on function public.get_candidate_dashboard_metrics() from public,anon,authenticated;
revoke all on function public.list_candidate_job_opportunities(text,integer,integer) from public,anon,authenticated;
revoke all on function public.apply_candidate_job(text) from public,anon,authenticated;
revoke all on function public.list_candidate_portal_applications(integer,integer) from public,anon,authenticated;
revoke all on function public.list_candidate_portal_interviews(integer,integer) from public,anon,authenticated;
revoke all on function public.list_candidate_portal_joinings(integer,integer) from public,anon,authenticated;
revoke all on function public.list_candidate_portal_documents() from public,anon,authenticated;
revoke all on function public.register_candidate_document(text,text,text,text,bigint) from public,anon,authenticated;
revoke all on function public.get_candidate_document_access(uuid) from public,anon,authenticated;
revoke all on function public.get_candidate_joining_document_checklist() from public,anon,authenticated;
revoke all on function public.get_candidate_onboarding_details() from public,anon,authenticated;
revoke all on function public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text) from public,anon,authenticated;
revoke all on function public.admin_list_candidate_documents(uuid) from public,anon,authenticated;
revoke all on function public.admin_get_candidate_document_access(uuid) from public,anon,authenticated;
revoke all on function public.admin_review_candidate_document(uuid,text,text) from public,anon,authenticated;
revoke all on function public.admin_set_candidate_documentation_override(uuid,boolean,text) from public,anon,authenticated;

grant execute on function public.get_candidate_portal_context(),public.get_candidate_portal_profile(),
  public.get_candidate_onboarding_eligibility(),
  public.create_candidate_portal_profile(text,text,text,date,text,text,text,text,text,text,text,text,boolean),
  public.update_candidate_portal_profile(text,text,text,date,text,text,text,text,text,text,text,text,text,text,text,text[],text[],numeric,numeric,text,boolean,date),
  public.get_candidate_dashboard_metrics(),public.list_candidate_job_opportunities(text,integer,integer),
  public.apply_candidate_job(text),public.list_candidate_portal_applications(integer,integer),
  public.list_candidate_portal_interviews(integer,integer),public.list_candidate_portal_joinings(integer,integer),
  public.list_candidate_portal_documents(),public.register_candidate_document(text,text,text,text,bigint),
  public.get_candidate_document_access(uuid),public.get_candidate_joining_document_checklist(),
  public.get_candidate_onboarding_details(),public.update_candidate_onboarding_details(text,text,text,text,boolean,text,boolean,text),
  public.admin_list_candidate_documents(uuid),public.admin_review_candidate_document(uuid,text,text),
  public.admin_get_candidate_document_access(uuid),
  public.admin_set_candidate_documentation_override(uuid,boolean,text) to authenticated;

drop policy if exists "Candidate owns private uploads" on storage.objects;
create policy "Candidate owns private uploads" on storage.objects for insert to authenticated
with check (bucket_id='candidate-private' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Candidate reads private uploads" on storage.objects;
create policy "Candidate reads private uploads" on storage.objects for select to authenticated
using (bucket_id='candidate-private' and ((storage.foldername(name))[1]=(select auth.uid())::text
  or (select private.can_verify_candidate_documents())));
drop policy if exists "Candidate replaces private uploads" on storage.objects;
create policy "Candidate replaces private uploads" on storage.objects for update to authenticated
using (bucket_id='candidate-private' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='candidate-private' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists "Candidate removes unregistered private uploads" on storage.objects;
create policy "Candidate removes unregistered private uploads" on storage.objects for delete to authenticated
using (bucket_id='candidate-private' and (storage.foldername(name))[1]=(select auth.uid())::text
  and not exists(select 1 from public.candidate_documents d where d.storage_object_name=name and d.active));

commit;
