-- Return only the canonical campaign route to an authenticated administrator.
-- Keep campaign tables inaccessible to direct service/client REST reads.
create function public.admin_console_vacancy_route(p_campaign_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare route jsonb;
begin
 if auth.uid() is null or not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 select jsonb_build_object('id',id,'template_name',template_name,'template_language',template_language) into route
 from public.whatsapp_campaigns where id=p_campaign_id and console_template_id is not null;
 if route is null then raise exception 'Saved vacancy campaign required' using errcode='22023'; end if;
 return route;
end;$$;
revoke all on function public.admin_console_vacancy_route(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_vacancy_route(uuid) to authenticated;
