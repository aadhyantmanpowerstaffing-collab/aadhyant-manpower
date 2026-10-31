import test from 'node:test';import assert from 'node:assert/strict';
import {handleWANotifierWebhook} from '../supabase/functions/wanotifier-webhook/index.ts';
import {calculateMetaSignature} from '../supabase/functions/_shared/whatsapp/signature.ts';
const secret='synthetic-webhook-secret-32-characters-only';
const env:any={WANOTIFIER_INGRESS_ENABLED:'true',WANOTIFIER_SENDER_NUMBER:'+919624453543',WANOTIFIER_WEBHOOK_SECRET:secret,WANOTIFIER_PHONE_NUMBER_ID:'1234567890123',WANOTIFIER_BUSINESS_ACCOUNT_ID:'9876543210123'};
const payload=(text='Hello')=>({event:'message.received',timestamp:Math.floor(Date.now()/1000),data:{message:{to:'+919624453543',from:'+919876543210',direction:'in',wa_message_id:'wamid.synthetic',message:{body:text},message_type:'text'}}});
async function request(body:any,signature=true){const raw=JSON.stringify(body);return new Request('https://example.invalid',{method:'POST',headers:{'content-type':'application/json','x-notifier-event':'message.received','x-notifier-signature':signature?(await calculateMetaSignature(new TextEncoder().encode(raw),secret)).slice(7):'0'.repeat(64)},body:raw});}
test('signed inbound uses canonical persistence, with summary-only ledger and no provider sends',async()=>{
 const calls:any[]=[];const rpc=async(name:string,args:any)=>{calls.push([name,args]);return name==='console_sender_configuration'?{ready:true,phone_id:env.WANOTIFIER_PHONE_NUMBER_ID,account_id:env.WANOTIFIER_BUSINESS_ACCOUNT_ID}:name==='set_whatsapp_contact_suppression'?true:'synthetic-id';};
 assert.equal((await handleWANotifierWebhook(await request(payload('Gujarati નોકરી')),k=>env[k]||'',rpc)).status,200);
 assert.deepEqual(calls.map(x=>x[0]),['console_sender_configuration','accept_whatsapp_webhook_event','upsert_whatsapp_inbound_contact','record_whatsapp_inbound_message']);
 assert.equal(calls[3][1].p_safe_text,'Gujarati નોકરી');assert.ok(!JSON.stringify(calls[1]).includes('Gujarati'));assert.equal(calls[1][1].p_provider_event_key,'message:wamid.synthetic');
});
test('retries use stable identity and ignore changing contact/delivery metadata',async()=>{
 const events:any[]=[];const rpc=async(n:string,a:any)=>{if(n==='accept_whatsapp_webhook_event')events.push(a);return n==='console_sender_configuration'?{ready:true,phone_id:env.WANOTIFIER_PHONE_NUMBER_ID,account_id:env.WANOTIFIER_BUSINESS_ACCOUNT_ID}:'id';};
 const p:any=payload();await handleWANotifierWebhook(await request(p),k=>env[k]||'',rpc);p.data.contact={first_name:'changed'};await handleWANotifierWebhook(await request(p),k=>env[k]||'',rpc);assert.deepEqual(events[0],events[1]);
});
test('STOP suppresses canonical contact and never creates an opt-in',async()=>{const calls:any[]=[];assert.equal((await handleWANotifierWebhook(await request(payload('STOP')),k=>env[k]||'',async(n,a)=>{calls.push([n,a]);return n==='console_sender_configuration'?{ready:true,phone_id:env.WANOTIFIER_PHONE_NUMBER_ID,account_id:env.WANOTIFIER_BUSINESS_ACCOUNT_ID}:n==='set_whatsapp_contact_suppression'?true:'id';})).status,200);assert.equal(calls.at(-1)[1].p_suppressed,true);});
test('invalid signature, sender, direction, body, and disabled configuration cause zero writes',async()=>{
 for(const mutation of ['signature','sender','direction','future','id','event','disabled','secret','config']){
 const p=payload();const e={...env};if(mutation==='sender')p.data.message.to='+919586785800';if(mutation==='direction')p.data.message.direction='out';if(mutation==='future')p.timestamp+=86400;if(mutation==='id')p.data.message.wa_message_id='bad';if(mutation==='event')p.event='contact.created';if(mutation==='disabled')e.WANOTIFIER_INGRESS_ENABLED='false';if(mutation==='secret')e.WANOTIFIER_WEBHOOK_SECRET='';if(mutation==='config')e.WANOTIFIER_SENDER_NUMBER='';
 let writes=0;assert.ok((await handleWANotifierWebhook(await request(p,mutation!=='signature'),k=>e[k]||'',async()=>{writes++;return 'id';})).status>=400,mutation);assert.equal(writes,0,mutation);
 }
});
test('persistence failure requests retry without leaking private data',async()=>{const r=await handleWANotifierWebhook(await request(payload()),k=>env[k]||'',async()=>{throw Error('private raw content');});assert.equal(r.status,500);assert.ok(!(await r.text()).includes('private'));});
test('large stream is rejected before database writes',async()=>{let calls=0;const r=await handleWANotifierWebhook(await request(payload('x'.repeat(70000))),k=>env[k]||'',async()=>{calls++;return 'id';});assert.equal(r.status,413);assert.equal(calls,0);});

test('sender configuration mismatch blocks canonical writes',async()=>{const calls:string[]=[];const r=await handleWANotifierWebhook(await request(payload()),k=>env[k]||'',async n=>{calls.push(n);return {ready:true,phone_id:'0000000000000',account_id:env.WANOTIFIER_BUSINESS_ACCOUNT_ID};});assert.equal(r.status,503);assert.deepEqual(calls,['console_sender_configuration']);});
