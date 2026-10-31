import test from 'node:test';import assert from 'node:assert/strict';
import {dispatchInterviewNotifications as dispatch} from '../supabase/functions/_shared/whatsapp/interview-dispatch.ts';
const row={message_id:'synthetic',destination:'+919876543210',template_language:'en',template_variables:{requirement_code:'AAD-2026-000023',job_role:'Operator',interview_date:'02 Jan 2099',interview_time:'10:30 AM',interview_mode:'onsite',interview_location:'Factory',candidate_instructions:'Review your account.'}};
function fixture({boundary=true,receipt={messages:[{id:'wamid.synthetic'}]},networkError=false,persistenceError=false}={}){
 const calls:any[]=[];let sends=0;
 const deps={rpc:async(name:string,args:any)=>{calls.push({name,args});if(name==='console_claim_interview_notifications')return [row];if(name==='console_interview_provider_boundary')return boundary;if(name==='mark_whatsapp_outbound_sent'&&persistenceError)throw Error('synthetic persistence failure');return true;},
 send:async(language:any,payload:any)=>{sends++;calls.push({name:'provider',language,payload});if(networkError)throw Error('synthetic network error');return receipt;}};
 return {calls,deps,get sends(){return sends;}};
}
const run=(f:ReturnType<typeof fixture>)=>dispatch('test-worker','1415347881659158','1386833723249335',f.deps);
test('interview dispatcher crosses final boundary before exactly one send, then persists genuine receipt',async()=>{const f=fixture();assert.equal((await run(f))[0].outcome,'sent');assert.equal(f.sends,1);assert.deepEqual(f.calls.map(c=>c.name),['console_claim_interview_notifications','console_interview_provider_boundary','provider','mark_whatsapp_outbound_sent']);assert.equal(f.calls[2].payload.recipients.length,1);});
test('denied final boundary sends nothing and records permanent failure',async()=>{const f=fixture({boundary:false});assert.equal((await run(f))[0].outcome,'blocked');assert.equal(f.sends,0);assert.equal(f.calls.at(-1).args.p_failure_kind,'permanent');});
for(const scenario of ['ack-only','numeric-id','network-error','persistence-error'])test('interview '+scenario+' never retries or fabricates successful delivery',async()=>{
 const f=fixture({receipt:scenario==='ack-only'?{error:false} as any:scenario==='numeric-id'?{messages:[{id:'173912015'}]}:{messages:[{id:'wamid.synthetic'}]},networkError:scenario==='network-error',persistenceError:scenario==='persistence-error'});
 assert.equal((await run(f))[0].outcome,'reconciliation_required');assert.equal(f.sends,1);assert.equal(f.calls.at(-1).name,'mark_whatsapp_outbound_failure');assert.equal(f.calls.at(-1).args.p_failure_kind,'ambiguous');
 if(scenario!=='persistence-error')assert.equal(f.calls.filter(c=>c.name==='mark_whatsapp_outbound_sent').length,0);
});
