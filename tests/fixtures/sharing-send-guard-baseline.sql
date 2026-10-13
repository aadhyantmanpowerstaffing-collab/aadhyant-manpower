CREATE OR REPLACE FUNCTION private.whatsapp_vacancy_send_eligible(p_message_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 SELECT EXISTS (
 SELECT 1 FROM public.whatsapp_outbound_messages o
 JOIN public.whatsapp_campaign_recipients cr ON cr.outbound_message_id=o.id
 JOIN public.whatsapp_campaigns wc ON wc.id=cr.campaign_id
 WHERE o.id=p_message_id AND o.purpose='vacancy_campaign' AND o.consent_class='marketing'
 AND cr.recipient_status='queued' AND cr.id=o.correlation_id
 AND cr.candidate_id=o.candidate_id AND cr.whatsapp_contact_id=o.contact_id
 AND wc.requirement_id=o.requirement_id AND wc.campaign_status IN ('queued','sending')
 AND wc.approved_at IS NOT NULL AND wc.queued_at IS NOT NULL AND wc.cancelled_at IS NULL
 AND private.vacancy_is_application_eligible(o.requirement_id)
 AND NOT EXISTS(SELECT 1 FROM public.candidate_applications a
   WHERE a.candidate_id=o.candidate_id AND a.requirement_id=o.requirement_id)
 );
$function$
