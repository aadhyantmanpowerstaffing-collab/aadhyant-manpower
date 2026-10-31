// Pure mapping for the provider-generated aadhyant_vacancy_alert_v1 (en)
// Notification API schema. This helper does not authenticate, select recipients,
// grant consent, send, retry, or infer delivery. Its caller must retain the
// canonical campaign lease and final eligibility/provider boundary.
export function wanotifierVacancyNotificationPayload(input:{destination:string;vacancyReference:string;role:string}){
 if(!/^\+91[6-9]\d{9}$/.test(input.destination))throw Error('Invalid notification destination');
 if(!/^AAD-\d{4}-\d{6}$/.test(input.vacancyReference))throw Error('Invalid vacancy reference');
 if(typeof input.role!=='string'||!input.role.trim()||Array.from(input.role).length>200||/[\u0000-\u001f\u007f]/.test(input.role))throw Error('Invalid vacancy role');
 return {data:{body_variables:[input.vacancyReference,input.role.trim()]},recipients:[{whatsapp_number:input.destination}]};
}

export function wanotifierInterviewNotificationPayload(input:{destination:string;language:'en'|'hi';variables:Record<string,string>}){
 if(!/^\+91[6-9]\d{9}$/.test(input.destination)||!['en','hi'].includes(input.language))throw Error('Invalid interview notification route');
 const fields=['requirement_code','job_role','interview_date','interview_time','interview_mode','interview_location','candidate_instructions'];
 const body=fields.map(key=>input.variables?.[key]);
 if(body.some(v=>typeof v!=='string'||!v.trim()||Array.from(v).length>500||/[\u0000-\u001f\u007f]/.test(v)))throw Error('Invalid interview notification variables');
 return {data:{body_variables:body},recipients:[{whatsapp_number:input.destination}]};
}

// Verified against the provider-generated approved v4 English Notification form.
export function wanotifierRegisteredNotificationPayload(row:any){
 const fields=['requirement_code','company','job_role','job_location','qualification','salary','take_home','overtime','duty','benefits'];
 const v=row.template_variables;
 if(row.template_name!=='aadhyant_registered_job_alert_v4'||row.template_language!=='en'||row.template_version!=='1'
 ||row.purpose!=='vacancy_campaign'||row.consent_class!=='marketing'||v?.template_contract!=='registered_summary_v4'
 ||!/^\+91[6-9]\d{9}$/.test(row.destination)||!/^[A-Za-z0-9_-]{1,160}$/.test(v?.requirement_code||'')
 ||!/^[a-f0-9]{64}$/.test(v?.job_fingerprint||'')
 ||fields.some(k=>typeof v[k]!=='string'||!v[k].trim()||Array.from(v[k]).length>300||/[\u0000-\u001f\u007f]| {5}/.test(v[k])))throw Error('Unsupported registered notification');
 return {data:{body_variables:fields.map(k=>v[k]),button_variables:[v.requirement_code]},recipients:[{whatsapp_number:row.destination}]};
}

export function wanotifierNotificationTransport(endpoint:string,fetcher:typeof fetch=fetch){
 let url:URL;try{url=new URL(endpoint);}catch{throw Error('Notification endpoint is not configured');}
 if(url.origin!=='https://app.wanotifier.com'||url.username||url.password||url.hash
 ||!/^\/api\/v1\/notifications\/[A-Za-z0-9]{6,80}$/.test(url.pathname)
 ||[...url.searchParams.keys()].some(k=>k!=='key')||url.searchParams.getAll('key').length!==1
 ||!/^\S{8,256}$/.test(url.searchParams.get('key')||''))throw Error('Notification endpoint is not configured');
 return async(payload:{data:Record<string,unknown>;recipients:{whatsapp_number:string}[]})=>{
  // Validate cardinality again at the network boundary; never forward bulk lists.
  if(payload.recipients.length!==1||!/^\+91[6-9]\d{9}$/.test(payload.recipients[0].whatsapp_number))throw Error('Single notification recipient required');
  try{
   const response=await fetcher(url,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(payload),redirect:'error',signal:AbortSignal.timeout(15000)});
   const data=await response.json();
   if(!response.ok||data?.error===true)throw Error('Provider response unconfirmed');
   // No response body/URL is logged. The canonical dispatcher validates receipts.
   return data;
  }catch{throw Error('Notification result requires review in WANotifier');}
 };
}
