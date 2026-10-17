-- Dated availability is separate from applications and WhatsApp consent.
begin;
create table private.same_day_candidate_availability (
 candidate_id uuid primary key references public.candidates(id) on delete cascade,
 available_dates date[] not null default '{}',
 local_area text not null default '' check(length(local_area)<=160),
 updated_at timestamptz not null default clock_timestamp(),
 check(cardinality(available_dates)<=2)
);
alter table private.same_day_candidate_availability enable row level security;
revoke all on private.same_day_candidate_availability from public,anon,authenticated,service_role;

create function public.get_same_day_availability() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id(); d date:=(statement_timestamp() at time zone 'Asia/Kolkata')::date;
begin
 if auth.uid() is null or cid is null then raise exception 'Active Candidate access required' using errcode='42501';end if;
 return jsonb_build_object('today',d,'tomorrow',d+1,'available_dates',coalesce((select jsonb_agg(x order by x) from private.same_day_candidate_availability a cross join lateral unnest(a.available_dates) x where a.candidate_id=cid and x between d and d+1),'[]'::jsonb),'local_area',coalesce((select local_area from private.same_day_candidate_availability where candidate_id=cid),''));
end; $$;

create function public.save_same_day_availability(p_dates date[],p_local_area text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.current_candidate_portal_id(); d date:=(statement_timestamp() at time zone 'Asia/Kolkata')::date; dates date[]; area text:=btrim(coalesce(p_local_area,''));
begin
 if auth.uid() is null or cid is null then raise exception 'Active Candidate access required' using errcode='42501';end if;
 if p_dates is null or cardinality(p_dates)>2 or exists(select 1 from unnest(p_dates) x where x is null or x<d or x>d+1) then raise exception 'Choose today or tomorrow only. Refresh after midnight.';end if;
 select coalesce(array_agg(distinct x order by x),'{}'::date[]) into dates from unnest(p_dates) x;
 if length(area)>160 or (cardinality(dates)>0 and length(area)<2) then raise exception 'Enter your local work area (2–160 characters)';end if;
 insert into private.same_day_candidate_availability(candidate_id,available_dates,local_area) values(cid,dates,area)
 on conflict(candidate_id) do update set available_dates=excluded.available_dates,local_area=excluded.local_area,updated_at=clock_timestamp();
 return public.get_same_day_availability();
end; $$;

create function public.list_same_day_available_candidates(p_date date,p_limit integer default 25,p_offset integer default 0) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(statement_timestamp() at time zone 'Asia/Kolkata')::date;
begin
 if auth.uid() is null or not (coalesce(private.can_review_vacancies(),false) or coalesce(private.can_manage_company_portal(),false) or coalesce(private.can_manage_contractor_vacancies(),false)) then raise exception 'Active employer or Admin access required' using errcode='42501';end if;
 if p_date is null or p_date not between d and d+1 or p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset<0 then raise exception 'Choose today or tomorrow and valid pagination';end if;
 return query select jsonb_build_object('candidate_name',c.full_name,'local_area',a.local_area,'available_date',p_date)
 from private.same_day_candidate_availability a join public.candidates c on c.id=a.candidate_id
 join public.platform_users pu on pu.user_id=c.user_id
 where p_date=any(a.available_dates) and c.profile_status='active' and c.status<>'inactive' and pu.account_type='candidate' and pu.account_status='active'
 order by a.updated_at desc,a.candidate_id limit p_limit offset p_offset;
end; $$;
revoke all on function public.get_same_day_availability(),public.save_same_day_availability(date[],text),public.list_same_day_available_candidates(date,integer,integer) from public,anon;
grant execute on function public.get_same_day_availability(),public.save_same_day_availability(date[],text),public.list_same_day_available_candidates(date,integer,integer) to authenticated;

create or replace function public.list_same_day_jobs(p_scope text default 'public',p_limit integer default 25,p_offset integer default 0,p_code text default null)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if p_scope not in ('public','owner','admin') or p_limit is null or p_offset is null or p_limit not between 1 and 100 or p_offset<0 then raise exception 'Invalid listing';end if;
 if p_scope='owner' and auth.uid() is null or p_scope='admin' and not coalesce(private.can_review_vacancies(),false) then raise exception 'Access denied' using errcode='42501';end if;
 return query select jsonb_build_object('id',r.id,'requirement_code',r.requirement_code,'company_name',r.company_name,'job_role',r.job_role,'job_location',r.job_location,'required_headcount',r.required_headcount,
 'confirmed_count',(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid')),
 'remaining_places',greatest(0,r.required_headcount-(select count(*) from private.same_day_work_status w join public.candidate_applications a on a.id=w.application_id where a.requirement_id=r.id and w.work_status in ('confirmed','attended','completed','paid'))),
 'review_status',private.normalized_vacancy_review_status(r.id),'review_feedback',case when p_scope<>'public' then coalesce(r.review_feedback,(select rc.review_feedback from public.requirement_contractors rc where rc.requirement_id=r.id and rc.origin_type='contractor_submission' limit 1)) end,'stage',r.requirement_stage,'terms',to_jsonb(t)-'requirement_id',
 'hours',extract(epoch from(t.ends_at-t.starts_at))/3600,'expired',(t.work_date+t.starts_at) at time zone 'Asia/Kolkata'<=clock_timestamp(),
 'my_application',(select a.id from public.candidate_applications a where a.requirement_id=r.id and a.candidate_id=private.current_candidate_portal_id() limit 1))
 from public.employer_requirements r join private.same_day_job_terms t on t.requirement_id=r.id
 where r.work_engagement='same_day_pay' and (p_code is null or r.requirement_code=p_code) and (
 (p_scope='public' and private.vacancy_is_application_eligible_before_same_day(r.id) and (t.work_date+t.starts_at) at time zone 'Asia/Kolkata'>clock_timestamp())
 or (p_scope='owner' and private.same_day_owner(r.id)) or p_scope='admin')
 order by t.work_date,t.starts_at,r.id limit p_limit offset p_offset;
end; $$;

commit;
