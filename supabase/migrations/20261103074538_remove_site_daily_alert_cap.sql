begin;
-- NULL is the explicit no-site-cap state. Existing client integer arguments are
-- retained for pause compatibility but cannot reinstate an internal daily cap.
alter table private.whatsapp_console_config alter column automatic_alerts_daily_limit drop not null;
alter table private.whatsapp_console_config alter column automatic_alerts_daily_limit set default null;
update private.whatsapp_console_config set automatic_alerts_daily_limit=null where singleton;
create or replace function public.admin_console_set_automatic_alerts(p_enabled boolean,p_daily_limit integer default null)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if not public.admin_console_access() then raise exception 'Admin access required' using errcode='42501'; end if;
 if p_enabled is null then raise exception 'Enabled flag required'; end if;
 if p_enabled and p_daily_limit is not null then raise exception 'Refresh the page to enable alerts without a site daily cap';end if;
 perform 1 from private.whatsapp_console_config where singleton for update;
 if p_enabled and (not exists(select 1 from public.whatsapp_template_catalog where name='aadhyant_registered_job_alert_v5' and language='en' and status='APPROVED' and compatible and synced_at>clock_timestamp()-interval '24 hours')
 or not exists(select 1 from private.whatsapp_console_config where singleton and sender_ready and verified_at>clock_timestamp()-interval '24 hours' and automatic_alerts_worker_verified_at>clock_timestamp()-interval '15 minutes')) then
 raise exception 'Approved template, verified sender and running automatic worker required'; end if;
 update private.whatsapp_console_config set automatic_alerts_enabled=p_enabled,automatic_alerts_daily_limit=null,
 automatic_alerts_approved_by=case when p_enabled then auth.uid() else automatic_alerts_approved_by end,
 automatic_alerts_enabled_at=case when p_enabled then clock_timestamp() else automatic_alerts_enabled_at end where singleton;
 insert into public.audit_logs(actor_user_id,actor_type,action,entity_type,source,metadata)
 values(auth.uid(),'staff','whatsapp.automatic_alerts_configured','whatsapp_campaign','admin',jsonb_build_object('enabled',p_enabled,'daily_limit',null,'site_daily_cap',false));
 return true;
end; $$;
create or replace function public.console_claim_registered_alerts_before_registration_catchup(p_worker_id text)
returns table(message_id uuid,destination text,template_name text,template_language text,template_version text,template_variables jsonb,purpose text,consent_class text,attempt_count integer,correlation_id uuid)
language plpgsql security definer set search_path='' as $$
declare cfg private.whatsapp_console_config%rowtype; c public.whatsapp_campaigns%rowtype; cr record; pending record; oid uuid; vars jsonb;
begin
 -- Serialize canonical claims. Provider limits remain authoritative; no site daily cap.
 select * into strict cfg from private.whatsapp_console_config where singleton for update;
 if not cfg.automatic_alerts_enabled then return; end if;
 for pending in select requirement_id from private.whatsapp_job_publications where outcome='template_unavailable' and authorized_by is not null and campaign_id is null order by published_at limit 10 loop
  perform private.prepare_registered_publication(pending.requirement_id);
 end loop;
 update public.whatsapp_campaigns wc set campaign_status=case when exists(select 1 from public.whatsapp_campaign_recipients r join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id where r.campaign_id=wc.id and o.state='failed') then 'failed' else 'completed' end,completed_at=clock_timestamp()
 where wc.audience_mode='registered_alerts' and wc.campaign_status in ('queued','sending')
 and not exists(select 1 from public.whatsapp_campaign_recipients r left join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id
 where r.campaign_id=wc.id and (r.recipient_status='included' or o.state in ('queued','sending')));

 select wc.* into c from public.whatsapp_campaigns wc join private.whatsapp_job_publications p on p.campaign_id=wc.id
 where wc.audience_mode='registered_alerts' and wc.campaign_status in ('queued','sending') and wc.cancelled_at is null
 and private.console_template_valid(wc.id) and private.vacancy_is_application_eligible(wc.requirement_id)
 and p.job_snapshot=private.registered_alert_variables(wc.requirement_id)
 and exists(select 1 from public.whatsapp_campaign_recipients r left join public.whatsapp_outbound_messages o on o.id=r.outbound_message_id
 where r.campaign_id=wc.id and (r.recipient_status='included' or (o.state='queued' and private.whatsapp_vacancy_send_eligible(o.id)) or o.state='sending'))
 order by wc.created_at,wc.id limit 1 for update of wc;
 if not found then return; end if;
 select p.job_snapshot into vars from private.whatsapp_job_publications p where p.campaign_id=c.id;
 for cr in select * from public.whatsapp_campaign_recipients where campaign_id=c.id and recipient_status='included' order by id limit 10 for update loop
  if not private.registered_alert_contact_eligible(cr.whatsapp_contact_id) then
   update public.whatsapp_campaign_recipients set recipient_status='excluded',exclusion_reason='suppressed' where id=cr.id;
  else
   oid:=public.enqueue_whatsapp_outbound_message(cr.whatsapp_contact_id,cr.candidate_id,c.requirement_id,'vacancy_campaign','marketing',c.template_name,c.template_language,c.template_version,
    vars||jsonb_build_object('campaign_id',c.id,'recipient_id',cr.id),'campaign:'||c.id||':recipient:'||cr.id,cr.id,1);
   update public.whatsapp_campaign_recipients set recipient_status='queued',outbound_message_id=oid where id=cr.id;
  end if;
 end loop;
 return query select * from public.console_claim_campaign_before_registered(c.id,p_worker_id);
end; $$;
revoke all on function public.admin_console_set_automatic_alerts(boolean,integer) from public,anon,authenticated,service_role;
grant execute on function public.admin_console_set_automatic_alerts(boolean,integer) to authenticated;
revoke all on function public.console_claim_registered_alerts_before_registration_catchup(text) from public,anon,authenticated,service_role;
grant execute on function public.console_claim_registered_alerts_before_registration_catchup(text) to service_role;
commit;
