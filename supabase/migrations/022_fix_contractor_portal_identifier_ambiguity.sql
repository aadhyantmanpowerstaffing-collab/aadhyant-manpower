-- W5 corrective migration: qualify identifiers in Contractor vacancy management.
begin;

create or replace function public.manage_contractor_portal_vacancy(p_action text,p_requirement_id uuid default null,p_client_name text default null,
  p_department text default null,p_job_role text default null,p_job_location text default null,p_required_headcount integer default null,
  p_qualification text default null,p_iti_trade text default null,p_experience_requirement text default 'Both',p_gender_preference text default 'Any',
  p_age_min integer default null,p_age_max integer default null,p_salary_min numeric default null,p_salary_max numeric default null,
  p_shift_details text default null,p_working_hours text default null,p_overtime_details text default null,p_canteen text default 'Not Applicable',
  p_transport text default 'Not Applicable',p_accommodation text default 'Not Applicable',p_interview_location text default null,
  p_expected_joining_date date default null,p_additional_notes text default null)
returns table(id uuid,requirement_code text,submission_status text,requirement_stage text,updated_at timestamptz)
language plpgsql security definer set search_path='' as $$
declare v_contractor_id uuid; v_contractor public.contractors%rowtype; v_requirement public.employer_requirements%rowtype;
  v_link public.requirement_contractors%rowtype;
begin
  if not (select private.can_manage_contractor_vacancies()) then raise exception 'Contractor vacancy management access is required'; end if;
  v_contractor_id:=(select private.current_contractor_portal_id(true));
  select c.* into v_contractor from public.contractors c where c.id=v_contractor_id;
  if v_contractor.main_phone is null or v_contractor.main_phone!~'^[6-9][0-9]{9}$' then
    raise exception 'A valid contractor contact phone is required before submitting vacancies'; end if;
  if p_action in ('create','update') then
    if length(btrim(coalesce(p_client_name,''))) not between 1 and 200 or length(btrim(coalesce(p_job_role,''))) not between 1 and 200
       or length(btrim(coalesce(p_job_location,''))) not between 1 and 300 or p_required_headcount is null or p_required_headcount<1 or p_required_headcount>100000 then
      raise exception 'Client, role, location, and valid openings are required'; end if;
    if p_experience_requirement not in ('Fresher','Experienced','Both') or p_gender_preference not in ('Any','Male','Female')
       or (p_age_min is not null and p_age_min not between 16 and 75) or (p_age_max is not null and p_age_max not between 16 and 75)
       or (p_age_min is not null and p_age_max is not null and p_age_min>p_age_max)
       or coalesce(p_salary_min,0)<0 or coalesce(p_salary_max,0)<0 or (p_salary_min is not null and p_salary_max is not null and p_salary_min>p_salary_max) then
      raise exception 'Vacancy criteria are invalid'; end if;
    if length(coalesce(btrim(p_qualification),''))>200 or length(coalesce(btrim(p_iti_trade),''))>200
       or length(coalesce(btrim(p_shift_details),''))>200 or length(coalesce(btrim(p_working_hours),''))>200
       or length(coalesce(btrim(p_overtime_details),''))>500 or length(coalesce(btrim(p_interview_location),''))>240
       or length(coalesce(btrim(p_additional_notes),''))>2000 then raise exception 'One or more vacancy fields are too long'; end if;
  end if;
  if p_action='create' then
    insert into public.employer_requirements(company_name,contact_person,mobile,email,company_location,job_role,required_headcount,
      qualification,iti_trade,experience_requirement,gender_preference,salary_wage,shift_details,working_hours,expected_joining_date,
      accommodation,canteen,transport,additional_notes,consent,status,created_by_user_id,department,job_location,age_min,age_max,
      salary_min,salary_max,overtime_details,interview_location,requirement_visibility,requirement_stage)
    values(btrim(p_client_name),coalesce(nullif(btrim(v_contractor.owner_name),''),v_contractor.agency_name),
      btrim(v_contractor.main_phone),v_contractor.main_email,btrim(p_job_location),btrim(p_job_role),p_required_headcount,
      nullif(btrim(p_qualification),''),nullif(btrim(p_iti_trade),''),p_experience_requirement,p_gender_preference,
      case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
      nullif(btrim(p_shift_details),''),nullif(btrim(p_working_hours),''),p_expected_joining_date,p_accommodation,p_canteen,p_transport,
      nullif(btrim(p_additional_notes),''),true,'new',(select auth.uid()),nullif(btrim(p_department),''),btrim(p_job_location),p_age_min,p_age_max,
      p_salary_min,p_salary_max,nullif(btrim(p_overtime_details),''),nullif(btrim(p_interview_location),''),'private','draft') returning * into v_requirement;
    insert into public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,assignment_status,origin_type,submission_status)
      values(v_requirement.id,v_contractor_id,p_required_headcount,'assigned','contractor_submission','draft') returning * into v_link;
  else
    select r.* into v_requirement from public.employer_requirements r
      where r.id=p_requirement_id and exists(select 1 from public.requirement_contractors link
        where link.requirement_id=r.id and link.contractor_id=v_contractor_id and link.origin_type='contractor_submission') for update;
    if not found then raise exception 'Contractor vacancy was not found'; end if;
    select link.* into v_link from public.requirement_contractors link
      where link.requirement_id=v_requirement.id and link.contractor_id=v_contractor_id and link.origin_type='contractor_submission' for update;
    if not found then raise exception 'Contractor vacancy was not found'; end if;
    if p_action='update' then
      if v_link.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be edited'; end if;
      update public.employer_requirements as r set company_name=btrim(p_client_name),department=nullif(btrim(p_department),''),job_role=btrim(p_job_role),
        company_location=btrim(p_job_location),job_location=btrim(p_job_location),required_headcount=p_required_headcount,qualification=nullif(btrim(p_qualification),''),
        iti_trade=nullif(btrim(p_iti_trade),''),experience_requirement=p_experience_requirement,gender_preference=p_gender_preference,age_min=p_age_min,age_max=p_age_max,
        salary_min=p_salary_min,salary_max=p_salary_max,salary_wage=case when p_salary_min is null and p_salary_max is null then null else concat_ws(' - ',p_salary_min,p_salary_max) end,
        shift_details=nullif(btrim(p_shift_details),''),working_hours=nullif(btrim(p_working_hours),''),overtime_details=nullif(btrim(p_overtime_details),''),
        canteen=p_canteen,transport=p_transport,accommodation=p_accommodation,interview_location=nullif(btrim(p_interview_location),''),
        expected_joining_date=p_expected_joining_date,additional_notes=nullif(btrim(p_additional_notes),''),requirement_stage='draft',requirement_visibility='private'
        where r.id=v_requirement.id returning r.* into v_requirement;
      update public.requirement_contractors as link set assigned_headcount=p_required_headcount,submission_status='draft',review_feedback=null
        where link.id=v_link.id returning link.* into v_link;
    elsif p_action='submit' then
      if v_link.submission_status not in ('draft','correction_required') then raise exception 'Only draft or correction-required vacancies can be submitted'; end if;
      update public.requirement_contractors as link set submission_status='submitted',submitted_at=now(),review_feedback=null
        where link.id=v_link.id returning link.* into v_link;
    elsif p_action='cancel' then
      if v_link.submission_status not in ('draft','submitted','correction_required') then raise exception 'This vacancy cannot be cancelled'; end if;
      update public.requirement_contractors as link set submission_status='cancelled',closed_at=now()
        where link.id=v_link.id returning link.* into v_link;
      update public.employer_requirements as r set requirement_stage='cancelled',requirement_visibility='private',status='closed',closed_at=now()
        where r.id=v_requirement.id returning r.* into v_requirement;
    else raise exception 'Unsupported Contractor vacancy action'; end if;
  end if;
  insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,entity_id,source,metadata)
    values((select auth.uid()),'contractor','contractor_vacancy_'||p_action,'employer_requirement',v_requirement.id,'contractor',
      jsonb_build_object('submission_status',v_link.submission_status));
  return query select v_requirement.id,v_requirement.requirement_code,v_link.submission_status,v_requirement.requirement_stage,v_requirement.updated_at;
end $$;

revoke all on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) from public,anon;
grant execute on function public.manage_contractor_portal_vacancy(text,uuid,text,text,text,text,integer,text,text,text,text,integer,integer,numeric,numeric,text,text,text,text,text,text,text,date,text) to authenticated;

commit;
