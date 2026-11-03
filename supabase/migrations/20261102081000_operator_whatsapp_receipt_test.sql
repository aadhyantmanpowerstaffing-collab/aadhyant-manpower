-- Narrow operator-only diagnostic access; canonical tables remain ungranted.
create function public.operator_whatsapp_receipt_test(p_message_id uuid,p_destination text,p_action text,p_worker text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.whatsapp_outbound_messages%rowtype; c public.whatsapp_contacts%rowtype;
begin
 if p_action not in ('read','claim','contact') or p_worker !~ '^receipt-test:[0-9a-f-]{36}$' or p_destination !~ '^\+91[6-9][0-9]{9}$' then return '[]'::jsonb; end if;
 select * into o from public.whatsapp_outbound_messages where id=p_message_id for update;
 if not found or o.purpose<>'provider_diagnostic' or o.destination<>p_destination or o.candidate_id is not null or o.requirement_id is not null
 or o.max_attempts<>1 or o.idempotency_key !~ '^wanotifier-server-receipt-check-[0-9]{8}-v[0-9]+$'
 or o.template_name<>'aadhyant_interview_confirmation_en_v1' or o.template_language<>'en' or o.template_version<>'1'
 or o.created_at<clock_timestamp()-interval '1 hour' or o.template_variables->>'requirement_code'<>'API TEST ONLY' then return '[]'::jsonb; end if;
 select * into c from public.whatsapp_contacts where id=o.contact_id;
 if not found or c.opted_out_at is not null or c.transactional_contact_status not in ('unknown','allowed') then return '[]'::jsonb; end if;
 if p_action='contact' then
   if o.state='sending' and o.lease_owner is distinct from p_worker then return '[]'::jsonb; end if;
   return jsonb_build_array(jsonb_build_object('id',c.id,'opted_out_at',c.opted_out_at,'transactional_contact_status',c.transactional_contact_status));
 end if;
 if p_action='claim' then
   if o.state<>'queued' or o.send_phase<>'ready' or o.attempt_count<>0 then return '[]'::jsonb; end if;
   update public.whatsapp_outbound_messages set state='sending',send_phase='provider_call_started',attempt_count=1,lease_owner=p_worker,lease_expires_at=clock_timestamp()+interval '60 seconds' where id=o.id;
 end if;
 return jsonb_build_array(jsonb_build_object('id',o.id,'contact_id',o.contact_id,'destination',o.destination,'purpose',o.purpose,'state',o.state,'send_phase',o.send_phase,'attempt_count',o.attempt_count,'max_attempts',o.max_attempts,'template_name',o.template_name,'template_language',o.template_language,'template_version',o.template_version,'template_variables',o.template_variables));
end $$;
revoke all on function public.operator_whatsapp_receipt_test(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.operator_whatsapp_receipt_test(uuid,text,text,text) to service_role;
