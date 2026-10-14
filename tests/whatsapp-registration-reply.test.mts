import test from 'node:test';
import assert from 'node:assert/strict';
import {registrationPayload,sendRegistrationReply} from '../supabase/functions/_shared/whatsapp/registration-reply.ts';
const row={message_id:'00000000-0000-0000-0000-000000000001',destination:'+919876543210',message_type:'session_text',purpose:'interested_registration',consent_class:'transactional',template_variables:{requirement_code:'AAD-2026-000003'}};
const config={ready:true,phone_id:'1234567891',account_id:'1234567890'};
function network(options:any={}){
 const calls:string[]=[],bodies:any[]=[];
 const rpc=async(name:string,body:any)=>{calls.push(name);bodies.push(body);if(name==='console_claim_registration_reply')return options.empty?[]:[row];if(name==='console_registration_boundary'&&options.boundary===false)throw Error('suppressed');return true;};
 const fetcher:typeof fetch=async()=>{calls.push('provider');if(options.timeout)throw Error('timeout');return Response.json(options.badReceipt?{}:options.rejected?{error:{code:131047,message:'private'}}:{messages:[{id:'wamid.reply'}]},{status:options.rejected?400:200});};
 return {calls,bodies,rpc,fetcher};
}
test('registration link retains the selected job; fixed text contains no PII or invented subscription',()=>{
 const p=registrationPayload(row);assert.equal(p.type,'text');assert.match(p.text.body,/register\.html\?requirement=AAD-2026-000003/);assert.equal(p.text.body.includes('9876543210'),false);assert.equal(p.text.preview_url,false);
 assert.throws(()=>registrationPayload({...row,purpose:'vacancy_campaign'}));assert.throws(()=>registrationPayload({...row,template_variables:{requirement_code:'../../evil?phone=123'}}));
});
test('durable claim and final boundary precede exactly one send and receipt',async()=>{const n=network();await sendRegistrationReply('inbound',n.rpc,config,'fixture',n.fetcher);assert.deepEqual(n.calls,['console_claim_registration_reply','console_registration_boundary','provider','mark_whatsapp_outbound_sent']);});
test('no claim, missing sender configuration or boundary rejection sends nothing',async()=>{let n=network({empty:true});await sendRegistrationReply('inbound',n.rpc,config,'fixture',n.fetcher);assert.deepEqual(n.calls,['console_claim_registration_reply']);n=network();await sendRegistrationReply('inbound',n.rpc,{...config,ready:false},'fixture',n.fetcher);assert.equal(n.calls.length,0);n=network({boundary:false});await sendRegistrationReply('inbound',n.rpc,config,'fixture',n.fetcher);assert.equal(n.calls.includes('provider'),false);assert.equal(n.bodies.at(-1).p_failure_kind,'permanent');});
for(const failure of ['timeout','badReceipt'])test(failure+' requires reconciliation with no retry',async()=>{const n=network({[failure]:true});await sendRegistrationReply('inbound',n.rpc,config,'fixture',n.fetcher);assert.equal(n.calls.filter(x=>x==='provider').length,1);assert.equal(n.bodies.at(-1).p_failure_kind,'ambiguous');});
test('provider rejection is terminal and never exposes the raw provider error',async()=>{const n=network({rejected:true});await sendRegistrationReply('inbound',n.rpc,config,'fixture',n.fetcher);assert.equal(n.bodies.at(-1).p_error_code,'131047');assert.equal(n.bodies.at(-1).p_failure_kind,'permanent');assert.equal(JSON.stringify(n.bodies).includes('private'),false);});
