-- Public/Candidate listings never include private supervisor contact fields.
begin;
create or replace function public.list_same_day_jobs(p_scope text default 'public',p_limit integer default 25,p_offset integer default 0,p_code text default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_scope not in ('public','owner','admin') or p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset<0 then raise exception 'Invalid listing';end if;
 if p_scope='owner' and auth.uid() is null or p_scope='admin' and not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied' using errcode='42501';end if;
 return query select jsonb_build_object('id',r.id,'requirement_code',r.requirement_code,'company_name',r.company_name,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,
 'confirmed_count',(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid')),
 'remaining_places',greatest(0,r.required_headcount-(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid'))),
 'review_status',private.normalized_vacancy_review_status(r.id),'review_feedback',case when p_scope<>'public' then coalesce(r.review_feedback,(select rc.review_feedback from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' limit 1)) end,'stage',r.requirement_stage,'terms',case when p_scope='public' then to_jsonb(t)-array['requirement_id','contact_name','contact_phone'] else to_jsonb(t)-'requirement_id' end,
 'hours',extract(epoch from(t.ends_at-t.starts_at))/3600,'expired',(t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp(),
 'my_application',(select a.id from public.candidate_applications a where a.requirement_id=r.id and a.candidate_id=private.current_candidate_portal_id() limit 1))
 from public.employer_requirements r join private.same_day_job_terms t on t.requirement_id=r.id
 where r.work_engagement='same_day_pay' and (p_code is null or r.requirement_code=p_code) and (
 (p_scope='public' and private.vacancy_is_application_eligible_before_same_day(r.id) and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp())
 or (p_scope='owner' and private.same_day_owner(r.id)) or p_scope='admin')
 order by t.work_date,t.starts_at,r.id limit p_limit offset p_offset;
end; $$;
commit;
