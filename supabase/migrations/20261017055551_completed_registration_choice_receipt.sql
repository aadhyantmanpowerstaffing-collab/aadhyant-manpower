-- Completed No/No receipt remains readable; STOP, expiry, identity and job guards stay authoritative.
begin;
create or replace function private.web_registration_context(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.whatsapp_web_registrations%rowtype; o public.whatsapp_outbound_messages%rowtype; w public.whatsapp_contacts%rowtype; r public.employer_requirements%rowtype;
begin
 if p_token is null or p_token !~ '^[a-f0-9]{64}$' or not exists(select 1 from private.whatsapp_console_config where singleton and registration_web_enabled) then return null;end if;
 select * into s from private.whatsapp_web_registrations where token_hash=sha256(convert_to(p_token,'UTF8'));
 if not found or s.expires_at<=clock_timestamp() then return null;end if;
 select * into o from public.whatsapp_outbound_messages where id=s.reply_id and registration_web_token=p_token and state in ('sent','delivered','read');
 if not found then return null;end if;
 select * into w from public.whatsapp_contacts where id=o.contact_id;
 if w.resolution_status in ('blocked','ambiguous') or (w.marketing_consent_status='opted_out' and not (s.completed_at is not null and coalesce(w.opt_out_reason_category,'')='candidate_choice')) or w.transactional_contact_status='suppressed'
 or w.provider_address is distinct from o.destination then return null;end if;
 select * into r from public.employer_requirements where id=o.requirement_id;
 if not private.vacancy_is_application_eligible(r.id) then return null;end if;
 return jsonb_build_object('status',case when s.completed_at is null then 'ready' else 'completed' end,
 'requirement_code',r.requirement_code,'job_role',r.job_role,'job_location',r.job_location,
 'phone_masked','+91XXXXXX'||right(w.indian_mobile_key,4),'expires_at',s.expires_at);
end;$$;
revoke all on function private.web_registration_context(text) from public,anon,authenticated,service_role;
commit;
