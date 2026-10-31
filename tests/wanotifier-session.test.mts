import test from 'node:test';import assert from 'node:assert/strict';
import {wanotifierSessionTransport} from '../supabase/functions/_shared/whatsapp/wanotifier.ts';
import {sendSessionOutbox} from '../supabase/functions/_shared/whatsapp/registration-reply.ts';
const phone='1234567890123';
const payload={messaging_product:'whatsapp',to:'919876543210',type:'text',text:{body:'Synthetic test'}};
test('one transport call maps session payload and never forwards Meta authorization',async()=>{
 let calls=0;const send=wanotifierSessionTransport('synthetic-api-key',phone,async(url,init)=>{calls++;assert.equal(new URL(String(url)).origin,'https://app.wanotifier.com');assert.equal((init!.headers as any).authorization,undefined);assert.deepEqual(JSON.parse(String(init!.body)),{recipient:{whatsapp_number:'+919876543210'},message:{type:'text',text:{preview_url:false,body:'Synthetic test'}}});return Response.json({messages:[{id:'wamid.synthetic'}]});});
 const result=await send('https://graph.facebook.com/v25.0/'+phone+'/messages',{method:'POST',body:JSON.stringify(payload)});assert.equal((await result.json()).messages[0].id,'wamid.synthetic');assert.equal(calls,1);
});
for(const outcome of ['ack-without-id','timeout','server-error','rejected','receipt'])test('canonical outbox handles '+outcome+' without fallback or duplicate send',async()=>{
 let calls=0;const effects:any[]=[];
 const transport=wanotifierSessionTransport('synthetic',phone,async()=>{calls++;if(outcome==='timeout')throw Error('secret');if(outcome==='server-error')return Response.json({}, {status:503});if(outcome==='rejected')return Response.json({error:true});return Response.json(outcome==='receipt'?{messages:[{id:'wamid.synthetic'}]}:{error:false,message:'Message sent successfully.'});});
 const rpc=async(n:string,a:any)=>{effects.push([n,a]);if(n==='claim')return [{message_id:'synthetic'}];return true;};
 await sendSessionOutbox('synthetic',rpc,{ready:true,phone_id:phone,account_id:'9876543210123'},'synthetic',transport,'claim','p_id','boundary',()=>payload);
 assert.equal(calls,1);const sent=effects.find(x=>x[0]==='mark_whatsapp_outbound_sent');assert.equal(Boolean(sent),outcome==='receipt');if(outcome!=='receipt')assert.equal(effects.at(-1)[1].p_failure_kind,outcome==='rejected'?'permanent':'ambiguous');
});
test('unexpected URL or payload is rejected before provider call',async()=>{let calls=0;const send=wanotifierSessionTransport('synthetic',phone,async()=>{calls++;return Response.json({});});for(const url of ['https://evil.invalid/messages','https://graph.facebook.com/v25.0/9999999999999/messages'])await assert.rejects(send(url,{method:'POST',body:JSON.stringify(payload)}));await assert.rejects(send('https://graph.facebook.com/v25.0/'+phone+'/messages',{method:'POST',body:JSON.stringify({...payload,type:'template'})}));assert.equal(calls,0);});
