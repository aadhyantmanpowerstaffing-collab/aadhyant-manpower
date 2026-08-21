-- W6 corrective migration: preserve the Candidate interview RPC text contract.

begin;

do $$
begin
  if to_regprocedure('public.list_candidate_portal_interviews(integer,integer)') is null
     or to_regprocedure('private.current_candidate_portal_id()') is null then
    raise exception 'W6 Candidate interview projection prerequisites are missing';
  end if;
end;
$$;

create or replace function public.list_candidate_portal_interviews(p_limit integer default 50,p_offset integer default 0)
returns table(requirement_code text,job_role text,scheduled_at timestamptz,mode text,location text,interview_round text,status text,result text)
language plpgsql stable security definer set search_path = '' as $$
declare v_id uuid := (select private.current_candidate_portal_id());
begin
  if v_id is null then raise exception 'Active Candidate Portal access is required'; end if;
  return query select r.requirement_code,r.job_role,i.scheduled_at,i.mode,i.location,i.interview_round::text,i.status,i.result
  from public.interviews i join public.candidate_applications a on a.id=i.application_id
  join public.employer_requirements r on r.id=a.requirement_id where a.candidate_id=v_id
  order by i.scheduled_at desc nulls last limit least(greatest(coalesce(p_limit,50),1),100) offset least(greatest(coalesce(p_offset,0),0),5000);
end;
$$;

revoke all on function public.list_candidate_portal_interviews(integer,integer) from public,anon,authenticated;
grant execute on function public.list_candidate_portal_interviews(integer,integer) to authenticated;

commit;
