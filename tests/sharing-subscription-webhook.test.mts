import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSharingSubscription, createSupabaseWebhookPersistence, handleWhatsAppWebhook } from '../supabase/functions/whatsapp-webhook/index.ts';
import { calculateMetaSignature } from '../supabase/functions/_shared/whatsapp/signature.ts';
import type { NormalizedWebhookEvent } from '../supabase/functions/_shared/whatsapp/types.ts';
const make = (safeText: string): NormalizedWebhookEvent => ({ category:'message', providerEventKey:'message:test',providerMessageId:'test',phone:'919876543210',messageType:'text',safeText,providerTimestamp:new Date().toISOString() });
test('only exact valid subscriber commands opt into sharing updates',()=>{
  const p={scope:'all',locations:[],trades:[]};assert.deepEqual(parseSharingSubscription(make('SUBSCRIBE JOB UPDATES '+JSON.stringify(p))),p);
  for(const s of ['INTERESTED','START','STOP','SUBSCRIBE JOB UPDATES {}','SUBSCRIBE JOB UPDATES {"scope":"all","locations":["Sanand"],"trades":[]}','SUBSCRIBE JOB UPDATES {"scope":"filtered","locations":[],"trades":[]}'])assert.equal(parseSharingSubscription(make(s)),null);
});
test('signed subscription persists an inbound event before service-only consent RPC and never sends',async()=>{
  const calls:string[]=[],env={appSecret:'fixture-secret',verifyToken:'fixture',supabaseUrl:'https://nonprod.invalid',supabaseSecretKey:'fixture-key'};
  const persist=createSupabaseWebhookPersistence(env,async(input,init)=>{const name=new URL(String(input)).pathname.split('/').pop()!;calls.push(name);const body=JSON.parse(String(init?.body||'{}'));if(name==='record_whatsapp_inbound_message')assert.equal(body.p_action_id,'SUBSCRIBE_JOB_UPDATES');return Response.json(name==='accept_whatsapp_webhook_event'?'event-id':name==='upsert_whatsapp_inbound_contact'?'contact-id':name==='record_whatsapp_inbound_message'?'inbound-id':true);});
  const body=JSON.stringify({object:'whatsapp_business_account',entry:[{changes:[{value:{messages:[{id:'fixture-message',from:'919876543210',type:'text',timestamp:String(Math.floor(Date.now()/1000)),text:{body:'SUBSCRIBE JOB UPDATES '+JSON.stringify({scope:'all',locations:[],trades:[]})}}]}}]}]});
  const signature=await calculateMetaSignature(new TextEncoder().encode(body),env.appSecret);
  const response=await handleWhatsAppWebhook(new Request('https://nonprod.invalid/whatsapp-webhook',{method:'POST',headers:{'content-type':'application/json','x-hub-signature-256':signature},body}),env,persist.acceptEvent,persist.processEvent);
  assert.equal(response.status,200);assert.deepEqual(calls,['accept_whatsapp_webhook_event','upsert_whatsapp_inbound_contact','record_whatsapp_inbound_message','subscribe_whatsapp_sharing_updates']);
});
test('unsigned subscription cannot reach persistence or change consent',async()=>{
  let calls=0;const response=await handleWhatsAppWebhook(new Request('https://nonprod.invalid/whatsapp-webhook',{method:'POST',headers:{'content-type':'application/json'},body:'{}'}),{appSecret:'fixture',verifyToken:'fixture',supabaseUrl:'',supabaseSecretKey:''},async()=>{calls++;return 'id';});assert.equal(response.status,403);assert.equal(calls,0);
});
test('signed events from another business account or phone are rejected before persistence',async()=>{let calls=0;const environment={appSecret:'fixture',verifyToken:'fixture',supabaseUrl:'',supabaseSecretKey:'',businessAccountId:'1234567890',phoneNumberId:'1234567891'};const body=JSON.stringify({object:'whatsapp_business_account',entry:[{id:'other-account',changes:[{value:{metadata:{phone_number_id:'1234567891'},messages:[{id:'fixture',from:'919876543210',type:'text',timestamp:'1700000000',text:{body:'STOP'}}]}}]}]});const signature=await calculateMetaSignature(new TextEncoder().encode(body),environment.appSecret);const r=await handleWhatsAppWebhook(new Request('https://fixture.invalid',{method:'POST',headers:{'content-type':'application/json','x-hub-signature-256':signature},body}),environment,async()=>{calls++;return 'id';});assert.equal(r.status,403);assert.equal(calls,0);});
