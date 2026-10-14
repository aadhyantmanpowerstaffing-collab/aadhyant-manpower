import test from 'node:test';
import assert from 'node:assert/strict';
import {registrationChatPayload,sendRegistrationChat} from '../supabase/functions/_shared/whatsapp/registration-chat.ts';
import {createSupabaseWebhookPersistence,handleWhatsAppWebhook} from '../supabase/functions/whatsapp-webhook/index.ts';
import {calculateMetaSignature} from '../supabase/functions/_shared/whatsapp/signature.ts';
const sid='00000000-0000-0000-0000-000000000001';
const row:any={message_id:sid,destination:'+919876543210',message_type:'session_text',purpose:'registration_chat',consent_class:'transactional',template_variables:{session_id:sid,step:0,kind:'question',invalid:false,requirement_code:'TEST_JOB',job_alerts_selected:null}};
test('English questions use provider-supported buttons/lists with exact session-step IDs and no private profile echo',()=>{
 for(let step=0;step<12;step++){
  const payload:any=registrationChatPayload({...row,template_variables:{...row.template_variables,step}});
  const body=payload.interactive?.body.text||payload.text?.body;
  assert.ok(body.length<1024);assert.match(body,/CANCEL/);assert.match(body,/RESUME/);assert.equal(body.includes('9876543210'),false);assert.doesNotMatch(body,/[\u0a80-\u0aff]/);
  if(payload.interactive?.type==='button')for(const b of payload.interactive.action.buttons){assert.ok(b.reply.title.length<=20);assert.match(b.reply.id,new RegExp('^REGCHAT\\|'+sid+'\\|'+step+'\\|[1-3]$'));}
  if(step===4){assert.equal(payload.interactive.type,'list');assert.equal(payload.interactive.action.sections[0].rows.length,8);}
 }
 const alerts:any=registrationChatPayload({...row,template_variables:{...row.template_variables,step:11}});
 assert.match(alerts.interactive.body.text,/ALL Aadhyant job alerts/);assert.match(alerts.interactive.body.text,/optional/);
 assert.throws(()=>registrationChatPayload({...row,purpose:'vacancy_campaign'}));
 assert.throws(()=>registrationChatPayload({...row,template_variables:{...row.template_variables,step:12}}));
});
test('completion text reports the explicit alert decision; malformed receipts cannot send',()=>{
 for(const alerts of [true,false]){const payload:any=registrationChatPayload({...row,template_variables:{...row.template_variables,step:12,kind:'complete',job_alerts_selected:alerts}});assert.match(payload.text.body,/Registration complete/);assert.ok(payload.text.body.includes(alerts?'subscribed to all':'not subscribed'));}
 assert.throws(()=>registrationChatPayload({...row,template_variables:{...row.template_variables,step:12,kind:'complete',job_alerts_selected:'true'}}));
});
for(const failure of ['none','boundary','timeout','rejection','receipt'])test('chat sender honors once-only canonical claim and provider reconciliation: '+failure,async()=>{
 const calls:string[]=[],bodies:any[]=[];
 const rpc=async(name:string,body:any)=>{calls.push(name);bodies.push(body);if(name==='console_claim_registration_chat')return [row];if(name==='console_registration_chat_boundary'&&failure==='boundary')throw Error('STOP');return true;};
 const fetcher:typeof fetch=async()=>{calls.push('provider');if(failure==='timeout')throw Error('timeout');return Response.json(failure==='rejection'?{error:{code:131047,message:'private'}}:failure==='receipt'?{}:{messages:[{id:'wamid.chat'}]},{status:failure==='rejection'?400:200});};
 await sendRegistrationChat(sid,rpc,{ready:true,phone_id:'1234567891',account_id:'1234567890'},'fixture',fetcher);
 assert.equal(calls[0],'console_claim_registration_chat');assert.equal(calls[1],'console_registration_chat_boundary');assert.equal(calls.filter(x=>x==='provider').length,failure==='boundary'?0:1);
 if(['timeout','receipt'].includes(failure))assert.equal(bodies.at(-1).p_failure_kind,'ambiguous');if(failure==='none')assert.equal(calls.at(-1),'mark_whatsapp_outbound_sent');assert.equal(JSON.stringify(bodies).includes('private'),false);
});
function signed(body:string){return calculateMetaSignature(new TextEncoder().encode(body),'fixture-secret').then(signature=>new Request('https://fixture.invalid',{method:'POST',headers:{'content-type':'application/json','x-hub-signature-256':signature},body}));}
for(const scenario of ['interested','answer','STOP'])test('signed ingress persists first then routes '+scenario+' to private chat processing without raw-text retention',async()=>{
 const calls:string[]=[],bodies:any[]=[];const environment={appSecret:'fixture-secret',verifyToken:'fixture',supabaseUrl:'https://fixture.invalid',supabaseSecretKey:'fixture-key',accessToken:'fixture-meta',businessAccountId:'1234567890',phoneNumberId:'1234567891'};
 const fetcher:typeof fetch=async(input,init)=>{
  const name=String(input).split('/').at(-1)!;calls.push(name);const args=JSON.parse(String(init?.body||'{}'));bodies.push(args);
  const values:any={accept_whatsapp_webhook_event:sid,upsert_whatsapp_inbound_contact:sid,record_whatsapp_inbound_message:sid,console_process_interested:{status:'registration_required'},console_process_registration_chat:{handled:true,outbound_id:sid},console_sender_configuration:{ready:true,phone_id:'1234567891',account_id:'1234567890'},console_claim_registration_chat:[row],console_registration_chat_boundary:true,mark_whatsapp_outbound_sent:true,set_whatsapp_contact_suppression:true,console_cancel_registration_chat:true,messages:{messages:[{id:'wamid.chat'}]}};
  assert.ok(name in values,'unexpected call '+name);return Response.json(values[name]);
 };
 const message:any={id:'wamid.inbound',from:'919876543210',timestamp:String(Math.floor(Date.now()/1000)),type:scenario==='interested'?'button':'text'};
 if(scenario==='interested'){message.button={payload:'INTERESTED',text:'Interested'};message.context={id:'wamid.original'};}else message.text={body:scenario==='STOP'?'STOP':'Synthetic Name'};
 const body=JSON.stringify({object:'whatsapp_business_account',entry:[{id:environment.businessAccountId,changes:[{value:{metadata:{phone_number_id:environment.phoneNumberId},messages:[message]}}]}]});
 const persistence=createSupabaseWebhookPersistence(environment,fetcher);
 assert.equal((await handleWhatsAppWebhook(await signed(body),environment,persistence.acceptEvent,persistence.processEvent)).status,200);
 assert.equal(bodies[calls.indexOf('record_whatsapp_inbound_message')].p_safe_text,null);
 if(scenario==='STOP'){assert.equal(calls.at(-1),'console_cancel_registration_chat');assert.equal(calls.includes('messages'),false);}
 else {assert.ok(calls.indexOf('record_whatsapp_inbound_message')<calls.indexOf('console_process_registration_chat'));assert.equal(calls.includes('console_claim_registration_reply'),false);assert.equal(calls.filter(x=>x==='messages').length,1);}
 const before=calls.length;assert.equal((await handleWhatsAppWebhook(new Request('https://fixture.invalid',{method:'POST',headers:{'content-type':'application/json'},body}),environment,persistence.acceptEvent,persistence.processEvent)).status,403);assert.equal(calls.length,before);
});
