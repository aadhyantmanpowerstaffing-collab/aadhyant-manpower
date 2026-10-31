import {calculateMetaSignature, constantTimeEqual, sha256Hex} from '../_shared/whatsapp/signature.ts';
import {parseWhatsAppWebhook, summarizeEvent} from '../_shared/whatsapp/parser.ts';
import {normalizeIndianWhatsAppPhone} from '../_shared/whatsapp/phone.ts';
import {runtimeServerKey, serverDatabaseHeaders} from '../_shared/whatsapp/server-headers.ts';

type Get = (name:string)=>string;
type Rpc = (name:string, args:Record<string,unknown>)=>Promise<any>;
const sender = '+919624453543';
const reply=(status:number)=>new Response(status===200?'EVENT_RECEIVED':'Webhook not accepted',{status,headers:{'content-type':'text/plain','cache-control':'no-store'}});

// Ingress only: no Graph calls, sending, subscription opt-ins, or chatbot execution.
export async function handleWANotifierWebhook(req:Request,get:Get,rpc:Rpc):Promise<Response>{
 if(req.method!=='POST')return reply(405);
 if(get('WANOTIFIER_INGRESS_ENABLED')!=='true'||get('WANOTIFIER_SENDER_NUMBER')!==sender||get('WANOTIFIER_WEBHOOK_SECRET').length<32||!/^\d{8,40}$/.test(get('WANOTIFIER_PHONE_NUMBER_ID'))||!/^\d{8,40}$/.test(get('WANOTIFIER_BUSINESS_ACCOUNT_ID')))return reply(503);
 if(req.headers.get('content-type')?.split(';')[0].trim()!=='application/json')return reply(415);
 if(Number(req.headers.get('content-length'))>65536)return reply(413);
 // Bound streamed bytes even when Content-Length is absent or false.
 const reader=req.body?.getReader();if(!reader)return reply(400);
 const chunks:Uint8Array[]=[];let size=0;
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>65536){await reader.cancel();return reply(413);}chunks.push(value);}
 const raw=new Uint8Array(size);let offset=0;for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.length;}
 const signature=req.headers.get('x-notifier-signature')||'';
 if(!/^[a-f0-9]{64}$/i.test(signature)||!constantTimeEqual(signature.toLowerCase(),(await calculateMetaSignature(raw,get('WANOTIFIER_WEBHOOK_SECRET'))).slice(7)))return reply(401);
 let body:any,event:any;
 try{
  body=JSON.parse(new TextDecoder().decode(raw));
  if(body.event!=='message.received'||req.headers.get('x-notifier-event')!==body.event)return reply(400);
  const m=body.data?.message;
  if(!m||m.direction!=='in'||normalizeIndianWhatsAppPhone(m.to).providerAddress!==sender)return reply(403);
  const from=normalizeIndianWhatsAppPhone(m.from).providerAddress;
  if(typeof m.wa_message_id!=='string'||!/^wamid\.[A-Za-z0-9._=+\/-]{1,230}$/.test(m.wa_message_id))return reply(400);
  if(!Number.isInteger(body.timestamp)||body.timestamp<=0||body.timestamp*1000>Date.now()+300000||body.timestamp*1000<Date.now()-30*86400000)return reply(400);
  const message:any={id:m.wa_message_id,from:from.slice(1),timestamp:String(body.timestamp),type:m.message_type};
  if(typeof m.context==='string'&&m.context)message.context={id:m.context};
  else if(m.context&&typeof m.context.id==='string')message.context={id:m.context.id};
  if(!m.message||typeof m.message!=='object'||Array.isArray(m.message))return reply(400);
  // Provider supplies the original message-type payload, not a full Meta envelope.
  if(['text','button','interactive'].includes(m.message_type))message[m.message_type]=m.message;
  const events=parseWhatsAppWebhook({object:'whatsapp_business_account',entry:[{changes:[{field:'messages',value:{messages:[message]}}]}]});
  if(events.length!==1)return reply(400);event=events[0];
 }catch{return reply(400);}
 try{
  const config=await rpc('console_sender_configuration',{});
  // Receiving remains available while sending is paused or its approval TTL expires.
  if(config?.phone_id!==get('WANOTIFIER_PHONE_NUMBER_ID')||config.account_id!==get('WANOTIFIER_BUSINESS_ACCOUNT_ID'))return reply(503);
  // Identical message identity is shared with canonical Meta ingress. Hash the
  // normalized event, excluding contact metadata and delivery-attempt identity.
  const hash=await sha256Hex(new TextEncoder().encode(JSON.stringify(event)));
  const webhookId=await rpc('accept_whatsapp_webhook_event',{p_provider_event_key:event.providerEventKey,p_payload_sha256:hash,p_event_category:event.category,p_redacted_payload:summarizeEvent(event)});
  if(typeof webhookId!=='string'||!webhookId)return reply(500);
  const contactId=await rpc('upsert_whatsapp_inbound_contact',{p_phone:event.phone});
  if(typeof contactId!=='string'||!contactId)return reply(500);
  const inboundId=await rpc('record_whatsapp_inbound_message',{p_webhook_event_id:webhookId,p_contact_id:contactId,p_provider_message_id:event.providerMessageId,p_provider_timestamp:event.providerTimestamp??null,p_message_type:event.messageType,p_safe_text:['text','button','list'].includes(event.messageType)?event.safeText??null:null,p_action_id:event.actionId??null,p_correlation_key:event.correlationKey??null,p_redacted_response:null});
  if(typeof inboundId!=='string'||!inboundId)return reply(500);
  const stop=['STOP','UNSUBSCRIBE','STOP_ALERTS'].includes((event.actionId||'').trim().toUpperCase())||(event.messageType==='text'&&['STOP','UNSUBSCRIBE'].includes((event.safeText||'').trim().toUpperCase()));
  if(stop&&await rpc('set_whatsapp_contact_suppression',{p_contact_id:contactId,p_suppressed:true,p_source:'whatsapp_inbound',p_reason_category:'user_stop'})!==true)return reply(500);
  return reply(200);
 }catch{return reply(500);}
}
const get=(name:string)=>(globalThis as any).Deno?.env.get(name)||'';
const handler={fetch:(req:Request)=>handleWANotifierWebhook(req,get,async(name,args)=>{
 const r=await fetch(get('SUPABASE_URL')+'/rest/v1/rpc/'+name,{method:'POST',headers:{...serverDatabaseHeaders(runtimeServerKey(get)),'content-type':'application/json'},body:JSON.stringify(args),redirect:'error',signal:AbortSignal.timeout(1500)});
 if(!r.ok)throw Error('Canonical persistence unconfirmed');return r.json();
})};
export default handler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(handler.fetch);
