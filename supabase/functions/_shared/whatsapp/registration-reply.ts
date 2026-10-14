// Only called after signed ingress and canonical Interested processing.
// All sends use a durable canonical outbox lease and a final database boundary.
type Rpc = (name: string, body: Record<string, unknown>) => Promise<any>;
export function registrationPayload(row: any) {
  const code = row.template_variables?.requirement_code;
  if (row.purpose !== 'interested_registration' || row.consent_class !== 'transactional'
    || row.message_type !== 'session_text' || !/^\+91[6-9]\d{9}$/.test(row.destination)
    || typeof code !== 'string' || !/^[A-Z0-9_-]{1,64}$/.test(code)) throw Error('Unsupported registration reply');
  const url = 'https://aadhyantmanpower.in/candidate/portal/register.html?requirement=' + encodeURIComponent(code);
  if (row.flow_id || row.flow_token) {
    if (!/^\d{8,40}$/.test(row.flow_id) || !/^[a-f0-9]{64}$/.test(row.flow_token)) throw Error('Invalid Flow binding');
    return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'interactive',interactive:{type:'flow',body:{text:`Aadhyant: ${code} માટે આ WhatsApp formમાં registration કરો. Job alertsની સંમતિ formમાં અલગથી પસંદ કરી શકો છો.`},action:{name:'flow',parameters:{flow_message_version:'3',flow_id:row.flow_id,flow_token:row.flow_token,flow_cta:'Registration કરો',flow_action:'navigate',flow_action_payload:{screen:'PERSONAL',data:{requirement_code:code}}}}}};
  }
  return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'text',text:{preview_url:false,
    body:`Aadhyant Manpower & Staffing\nતમારો ${code} માટેનો રસ નોંધાયો છે.\nઆ job માટે અરજી કરવા registration પૂર્ણ કરો:\n${url}\nપહેલેથી account હોય તો આ પેજ પરથી Sign In કરો અને job પર Apply દબાવો.\nInterested દબાવવાથી ભવિષ્યના job alerts માટે subscription થતું નથી.`}};
}
export async function sendRegistrationReply(inboundId: string, rpc: Rpc,
  config: {ready:boolean;phone_id:string;account_id:string}, token: string, fetcher: typeof fetch = fetch) {
  if (!config?.ready || !/^\d{8,40}$/.test(config.phone_id) || !/^\d{8,40}$/.test(config.account_id) || !token) return;
  const worker = 'registration:' + crypto.randomUUID();
  const rows = await rpc('console_claim_registration_reply', {p_inbound_message_id:inboundId,p_worker_id:worker});
  if (!Array.isArray(rows) || rows.length > 1) throw Error('Invalid registration claim');
  for (const row of rows) {
    let payload;
    try { payload = registrationPayload(row); }
    catch { await rpc('mark_whatsapp_outbound_failure', {p_message_id:row.message_id,p_worker_id:worker,p_error_category:'unsupported_reply',p_error_code:'payload_rejected',p_failure_kind:'permanent',p_retry_at:null}); return; }
    try {
      if (await rpc('console_registration_boundary',{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:config.phone_id,p_account_id:config.account_id}) !== true) throw Error('Boundary rejected');
    } catch {
      await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'reply_ineligible',p_error_code:'boundary_rejected',p_failure_kind:'permanent',p_retry_at:null});return;
    }
    // One provider call only. Webhook replay cannot reclaim this attempt.
    try {
      const sent = await fetcher('https://graph.facebook.com/v25.0/'+config.phone_id+'/messages', {method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(15000)});
      const result = await sent.json();
      if (!sent.ok) {
        const code=String(result?.error?.code||'provider_rejected').replace(/[^0-9a-z_]/gi,'').slice(0,80);
        await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'provider_rejected',p_error_code:code,p_failure_kind:'permanent',p_retry_at:null});return;
      }
      const id=result?.messages?.[0]?.id;
      if (typeof id !== 'string' || !id.startsWith('wamid.') || id.length>240) throw Error('Ambiguous provider receipt');
      if (await rpc('mark_whatsapp_outbound_sent',{p_message_id:row.message_id,p_worker_id:worker,p_provider_message_id:id,p_provider_timestamp:null}) !== true) throw Error('Receipt not confirmed');
    } catch {
      try {await rpc('mark_whatsapp_outbound_failure',{p_message_id:row.message_id,p_worker_id:worker,p_error_category:'ambiguous_provider_outcome',p_error_code:'reconcile_before_retry',p_failure_kind:'ambiguous',p_retry_at:null});}catch{}
    }
  }
}
