// Operator-controlled, single-use rollout check. Normal automation stays disabled.
// Reuses the canonical outbox and the same provider transport/receipt parser.
import {constantTimeEqual} from '../_shared/whatsapp/signature.ts';
import {runtimeServerKey,serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';
import {wanotifierNotificationTransport} from '../_shared/whatsapp/wanotifier-notification.ts';
import {wanotifierMessageId} from '../_shared/whatsapp/job-message.ts';

export const receiptTestVariables={requirement_code:'API TEST ONLY',job_role:'Server receipt verification - no real interview',event_date:'Technical test only',event_time:'No attendance required',venue:'Aadhyant server integration test',instructions:'This is an authorized test. No interview has been scheduled.'};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function handleReceiptTest(req:Request,get:(key:string)=>string,fetcher:typeof fetch=fetch,now=Date.now()){
 const reply=(status:number,body:unknown)=>Response.json(body,{status,headers:{'cache-control':'no-store'}});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 const operatorKey=get('SUPABASE_SERVICE_ROLE_KEY');let projectSecret='';
 try{projectSecret=runtimeServerKey(get);}catch{/* deny unknown server key configuration */}
 const legacyOperator=operatorKey.length>=32&&constantTimeEqual(req.headers.get('x-operator-authorization')||req.headers.get('authorization')||'','Bearer '+operatorKey);
 const currentOperator=projectSecret.length>=32&&constantTimeEqual(req.headers.get('apikey')||'',projectSecret);
 if(!legacyOperator&&!currentOperator)return reply(401,{error:'Project operator authorization required'});
 const id=get('WANOTIFIER_TEST_MESSAGE_ID'),destination=get('WANOTIFIER_TEST_DESTINATION');
 const expiry=Date.parse(get('WANOTIFIER_TEST_EXPIRES_AT'));
 if(get('WANOTIFIER_TEST_ENABLED')!=='true'||!uuid.test(id)||!/^\+91[6-9]\d{9}$/.test(destination)||!Number.isFinite(expiry)||expiry<=now||expiry-now>30*60*1000
 ||get('SUPABASE_URL')!=='https://wsuctjhbqiedttfnwjvf.supabase.co'||get('WANOTIFIER_SENDER_NUMBER')!=='+919624453543'
 ||get('WANOTIFIER_PHONE_NUMBER_ID')!=='1415347881659158'||get('WANOTIFIER_BUSINESS_ACCOUNT_ID')!=='1386833723249335')return reply(503,{error:'Receipt test is disabled or expired'});
 if(req.headers.get('content-type')?.split(';')[0]!=='application/json')return reply(415,{error:'JSON required'});
 const reader=req.body?.getReader();let size=0;const parts:Uint8Array[]=[];
 if(!reader)return reply(400,{error:'Explicit test action required'});
 for(;;){const r=await reader.read();if(r.done)break;size+=r.value.length;if(size>64){await reader.cancel();return reply(413,{error:'Request too large'});}parts.push(r.value);}
 try{const b=new Uint8Array(size);let p=0;for(const part of parts){b.set(part,p);p+=part.length;}const action=JSON.parse(new TextDecoder().decode(b));if(Object.keys(action).length!==1||action.action!=='send_test')throw Error();}catch{return reply(400,{error:'Explicit test action required'});}
 let claimed=false,providerStarted=false,httpStatus:number|null=null;
 const worker='receipt-test:'+crypto.randomUUID();
 try{
  const send=wanotifierNotificationTransport(get('WANOTIFIER_INTERVIEW_CONFIRMATION_EN_URL'),async(input,init)=>{const r=await fetcher(input,init);httpStatus=r.status;return r;});
  const base=get('SUPABASE_URL')+'/rest/v1';const headers={...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'};
  const db=async(path:string,init:RequestInit={})=>{const r=await fetcher(base+path,{...init,headers:{...headers,...init.headers},redirect:'error',signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Canonical operation failed');return r.json();};
  const probe=async(action:string)=>db('/rpc/operator_whatsapp_receipt_test',{method:'POST',body:JSON.stringify({p_message_id:id,p_destination:destination,p_action:action,p_worker:worker})});
  const rows=await probe('read');
  const row=rows?.[0];
  if(rows.length!==1||row.destination!==destination||row.purpose!=='provider_diagnostic'||row.state!=='queued'||row.send_phase!=='ready'||row.attempt_count!==0||row.max_attempts!==1
   ||row.template_name!=='aadhyant_interview_confirmation_en_v1'||row.template_language!=='en'||row.template_version!=='1'
   ||Object.keys(row.template_variables||{}).length!==6||Object.entries(receiptTestVariables).some(([k,v])=>row.template_variables[k]!==v))return reply(409,{error:'Test already attempted or row does not match'});
  const contact=await probe('contact');
  if(contact.length!==1||contact[0].opted_out_at||!['unknown','allowed'].includes(contact[0].transactional_contact_status))return reply(409,{error:'Contact is suppressed'});
  // Atomic compare-and-set means concurrent clicks and timeouts cannot resend.
  const lease=await probe('claim');
  if(lease.length!==1)return reply(409,{error:'Test already claimed'});claimed=true;
  const finalContact=await probe('contact');
  if(Date.now()>=expiry||Date.now()>=now+60000||finalContact.length!==1||finalContact[0].opted_out_at||!['unknown','allowed'].includes(finalContact[0].transactional_contact_status))throw Error('Test expired or suppressed');
  providerStarted=true;
  const receipt=await send({data:{body_variables:Object.values(receiptTestVariables)},recipients:[{whatsapp_number:destination}]});
  const wamid=wanotifierMessageId(receipt);
  if(await db('/rpc/mark_whatsapp_outbound_sent',{method:'POST',body:JSON.stringify({p_message_id:id,p_worker_id:worker,p_provider_message_id:wamid})})!==true)throw Error('Receipt persistence unconfirmed');
  return reply(200,{sent:true,message_id:id,provider_http_status:httpStatus,wamid,delivery:'Check WANotifier; acceptance is not delivery'});
 }catch{
  // Never include provider responses, request URLs or credentials in diagnostics.
  if(claimed){try{await fetcher(get('SUPABASE_URL')+'/rest/v1/rpc/mark_whatsapp_outbound_failure',{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify({p_message_id:id,p_worker_id:worker,p_error_category:providerStarted?'ambiguous_provider_outcome':'test_preflight',p_error_code:providerStarted?'reconcile_before_retry':'test_expired',p_failure_kind:providerStarted?'ambiguous':'permanent'}),redirect:'error',signal:AbortSignal.timeout(10000)});}catch{/* retain lease for reconciliation */}}
  return reply(503,{error:claimed?'Test requires review; do not resend':'Receipt test configuration unavailable',provider_http_status:httpStatus,retry:false});
 }
}
const deno=(globalThis as any).Deno;
if(deno?.serve)deno.serve((req:Request)=>handleReceiptTest(req,(key:string)=>deno.env.get(key)||''));
