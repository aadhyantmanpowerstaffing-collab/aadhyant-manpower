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
    return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'interactive',interactive:{type:'flow',body:{text:`Aadhyant: Register for ${code} using this WhatsApp form. Consent for future job alerts is a separate choice in the form.`},action:{name:'flow',parameters:{flow_message_version:'3',flow_id:row.flow_id,flow_token:row.flow_token,flow_cta:'Register',flow_action:'navigate',flow_action_payload:{screen:'PERSONAL',data:{requirement_code:code}}}}}};
  }
  return {messaging_product:'whatsapp',to:row.destination.slice(1),type:'text',text:{preview_url:false,
    body:`Aadhyant Manpower & Staffing\nYour interest in ${code} has been recorded.\nComplete registration to apply for this job:\n${url}\nIf you already have an account, use Sign In on this page and select Apply on the job.\nTapping Interested does not subscribe you to future job alerts.`}};
}
export async function sendRegistrationReply(inboundId: string, rpc: Rpc,
  config: {ready:boolean;phone_id:string;account_id:string}, token: string, fetcher: typeof fetch = fetch) {
  return sendSessionOutbox(inboundId,rpc,config,token,fetcher,'console_claim_registration_reply','p_inbound_message_id','console_registration_boundary',registrationPayload);
}
export async function sendSessionOutbox(id: string, rpc: Rpc,
  config: {ready:boolean;phone_id:string;account_id:string}, token: string, fetcher: typeof fetch,
  claim: string, claimKey: string, boundary: string, payloadFor: (row:any)=>any) {
  if (!config?.ready || !/^\d{8,40}$/.test(config.phone_id) || !/^\d{8,40}$/.test(config.account_id) || !token) return;
  const worker = 'registration:' + crypto.randomUUID();
  const rows = await rpc(claim, {[claimKey]:id,p_worker_id:worker});
  if (!Array.isArray(rows) || rows.length > 1) throw Error('Invalid registration claim');
  for (const row of rows) {
    let payload;
    try { payload = payloadFor(row); }
    catch { await rpc('mark_whatsapp_outbound_failure', {p_message_id:row.message_id,p_worker_id:worker,p_error_category:'unsupported_reply',p_error_code:'payload_rejected',p_failure_kind:'permanent',p_retry_at:null}); return; }
    try {
      if (await rpc(boundary,{p_message_id:row.message_id,p_worker_id:worker,p_phone_id:config.phone_id,p_account_id:config.account_id}) !== true) throw Error('Boundary rejected');
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
