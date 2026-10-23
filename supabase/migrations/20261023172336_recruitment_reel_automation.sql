-- Derived media only. Canonical requirement, approval and messaging boundaries stay intact.
begin;
create table private.reel_config(singleton boolean primary key default true check(singleton),enabled boolean not null default false,workflow_sha text,worker_seen_at timestamptz,contact_name text not null default 'Hitesh Gadhavi',contact_phone text not null default '9586785800',daily_limit integer not null default 30 check(daily_limit between 1 and 100));
insert into private.reel_config(singleton) values(true);
create table private.requirement_reels(
 id uuid primary key default gen_random_uuid(),requirement_id uuid not null references public.employer_requirements(id),fingerprint text not null,payload jsonb not null,
 state text not null default 'queued' check(state in ('queued','rendering','ready','failed','cancelled')),attempts integer not null default 0,
 claim_token uuid,worker_id text,lease_until timestamptz,object_path text,created_at timestamptz not null default clock_timestamp(),updated_at timestamptz not null default clock_timestamp(),
 unique(requirement_id,fingerprint));
create index requirement_reels_queue on private.requirement_reels(state,created_at);
alter table private.reel_config enable row level security;
alter table private.requirement_reels enable row level security;
revoke all on private.reel_config,private.requirement_reels from public,anon,authenticated,service_role;

create function private.reel_payload(p_requirement_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;t text;c private.reel_config%rowtype;
begin
 if not private.vacancy_is_application_eligible(p_requirement_id) then return null;end if;
 select * into strict c from private.reel_config where singleton;
 v:=private.registered_alert_variables(p_requirement_id);
 if v->>'template_contract'='same_day_hi_v1' then
 t:=concat_ws(E'\n','रोकड़ी काम। उसी शाम भुगतान।','स्थान: '||(v->>'job_location'),'काम: '||(v->>'job_role'),'तारीख: '||(v->>'work_date'),'समय: '||(v->>'shift'),'ज़रूरत: '||(v->>'headcount'),'मेहनताना: '||(v->>'pay'),'भुगतान: '||(v->>'payment'));
 else
 t:=concat_ws(E'\n','कंपनी: '||(v->>'company'),'पद: '||(v->>'job_role'),'स्थान: '||(v->>'job_location'),'योग्यता: '||(v->>'qualification'),'CTC / वेतन: '||(v->>'salary'),'अनुमानित हाथ में वेतन: '||(v->>'take_home'),'ओवरटाइम: '||(v->>'overtime'),'ड्यूटी: '||(v->>'duty'),'सुविधाएँ: '||(v->>'benefits'));
 end if;
 if length(t)>1800 then return null;end if;
 return jsonb_build_object('title','नौकरी का नया अवसर','text',t,'name',c.contact_name,'phone',c.contact_phone);
end;$$;

create function private.enqueue_requirement_reel(p_requirement_id uuid,p_retry boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare p jsonb;f text;rid uuid;
begin
 if not (select enabled from private.reel_config where singleton) then return null;end if;
 p:=private.reel_payload(p_requirement_id);if p is null then return null;end if;f:=md5(p::text);
 update private.requirement_reels set state='cancelled',updated_at=clock_timestamp() where requirement_id=p_requirement_id and fingerprint<>f and state<>'cancelled';
 insert into private.requirement_reels(requirement_id,fingerprint,payload) values(p_requirement_id,f,p) on conflict(requirement_id,fingerprint) do nothing returning id into rid;
 if rid is null then
 select id into rid from private.requirement_reels where requirement_id=p_requirement_id and fingerprint=f;
 if p_retry then update private.requirement_reels set state='queued',attempts=0,claim_token=null,lease_until=null,object_path=null,updated_at=clock_timestamp() where id=rid and state in ('failed','cancelled');end if;
 end if;return rid;
end;$$;
create function private.requirement_reel_publication() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if private.vacancy_is_application_eligible(new.id) then perform private.enqueue_requirement_reel(new.id);
 else update private.requirement_reels set state='cancelled',updated_at=clock_timestamp() where requirement_id=new.id and state<>'cancelled';end if;
 return new;
exception when others then return new; -- Media failure must never block a recruitment save.
end;$$;
create trigger requirement_reel_publication after insert or update on public.employer_requirements for each row execute function private.requirement_reel_publication();

create function public.admin_reels(p_requirement_id uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return jsonb_build_object('enabled',(select enabled from private.reel_config where singleton),'worker_seen_at',(select worker_seen_at from private.reel_config where singleton),'jobs',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select j.id,j.requirement_id,r.requirement_code,r.company_name,r.job_role,r.job_location,j.state,j.attempts,j.created_at,j.updated_at from private.requirement_reels j join public.employer_requirements r on r.id=j.requirement_id where (p_requirement_id is null or j.requirement_id=p_requirement_id) and j.state<>'cancelled' order by j.created_at desc limit 50) x));
end;$$;
create function public.admin_reel_jobs() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(x),'[]'::jsonb) from (select id,requirement_code,company_name,job_role,job_location from public.employer_requirements where private.vacancy_is_application_eligible(id) order by created_at desc limit 100) x);
end;$$;
create function public.admin_queue_reel(p_requirement_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 if not private.vacancy_is_application_eligible(p_requirement_id) then raise exception 'Only approved open public jobs can have a Reel';end if;
 rid:=private.enqueue_requirement_reel(p_requirement_id,true);if rid is null then raise exception 'Reel service is paused or post text exceeds supported size';end if;return rid;
end;$$;
create function public.admin_reel_object(p_id uuid) returns text language plpgsql stable security definer set search_path='' as $$
declare j private.requirement_reels%rowtype;begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501';end if;
 select * into j from private.requirement_reels where id=p_id and state='ready';
 if j.id is null or j.payload is distinct from private.reel_payload(j.requirement_id) then return null;end if;return j.object_path;
end;$$;
create function public.reel_worker_gate() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('workflow_sha',workflow_sha) from private.reel_config where singleton$$;
create function public.reel_worker_claim(p_worker text) returns jsonb language plpgsql security definer set search_path='' as $$
declare j private.requirement_reels%rowtype;tok uuid:=gen_random_uuid();begin
 update private.reel_config set worker_seen_at=clock_timestamp() where singleton;
 if not (select enabled from private.reel_config where singleton) then return null;end if;
 update private.requirement_reels set state=case when attempts>=3 then 'failed' else 'queued' end,claim_token=null,lease_until=null,updated_at=clock_timestamp() where state='rendering' and lease_until<clock_timestamp();
 if (select count(*) from private.requirement_reels where attempts>0 and updated_at>clock_timestamp()-interval '24 hours') >= (select daily_limit from private.reel_config where singleton) then return null;end if;
 for j in select * from private.requirement_reels where state='queued' and attempts<3 order by created_at for update skip locked loop
 if j.payload is distinct from private.reel_payload(j.requirement_id) then update private.requirement_reels set state='cancelled',updated_at=clock_timestamp() where id=j.id;continue;end if;
 update private.requirement_reels set state='rendering',attempts=attempts+1,claim_token=tok,worker_id=p_worker,lease_until=clock_timestamp()+interval '15 minutes',updated_at=clock_timestamp() where id=j.id;
 return jsonb_build_object('id',j.id,'claim',tok,'payload',j.payload);end loop;return null;
end;$$;
create function public.reel_worker_check(p_id uuid,p_claim uuid,p_worker text) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from private.requirement_reels j where j.id=p_id and j.state='rendering' and j.claim_token=p_claim and j.worker_id=p_worker and j.lease_until>clock_timestamp() and j.payload=private.reel_payload(j.requirement_id))$$;
create function public.reel_worker_finish(p_id uuid,p_claim uuid,p_worker text,p_success boolean) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.reel_worker_check(p_id,p_claim,p_worker) then return false;end if;
 update private.requirement_reels set state=case when p_success then 'ready' when attempts<3 then 'queued' else 'failed' end,object_path=case when p_success then id::text||'/'||claim_token::text||'.mp4' else null end,claim_token=null,lease_until=null,updated_at=clock_timestamp() where id=p_id;return true;
end;$$;
revoke all on function private.reel_payload(uuid),private.enqueue_requirement_reel(uuid,boolean),private.requirement_reel_publication(),public.admin_reels(uuid),public.admin_reel_jobs(),public.admin_queue_reel(uuid),public.admin_reel_object(uuid),public.reel_worker_gate(),public.reel_worker_claim(text),public.reel_worker_check(uuid,uuid,text),public.reel_worker_finish(uuid,uuid,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.admin_reels(uuid),public.admin_reel_jobs(),public.admin_queue_reel(uuid),public.admin_reel_object(uuid) to authenticated;
grant execute on function public.reel_worker_gate(),public.reel_worker_claim(text),public.reel_worker_check(uuid,uuid,text),public.reel_worker_finish(uuid,uuid,text,boolean) to service_role;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('recruitment-reels','recruitment-reels',false,25000000,array['video/mp4']);
commit;
