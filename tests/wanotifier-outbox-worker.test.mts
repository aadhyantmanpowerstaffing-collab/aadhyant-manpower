import test from 'node:test';import assert from 'node:assert/strict';
import {handleWANotifierWorker as handle} from '../supabase/functions/wanotifier-outbox-worker/index.ts';
import {wanotifierNotificationTransport,wanotifierRegisteredNotificationPayload} from '../supabase/functions/_shared/whatsapp/wanotifier-notification.ts';
const workerKey='synthetic-worker-key-over-32-characters';
const endpoint='https://app.wanotifier.com/api/v1/notifications/synthetic1?key=synthetic-private-key';
const env:any={WHATSAPP_WORKER_SECRET:workerKey,WANOTIFIER_AUTOMATION_ENABLED:'true',WANOTIFIER_INTERVIEWS_ENABLED:'true',WANOTIFIER_REGISTERED_ALERTS_ENABLED:'true',WANOTIFIER_SENDER_NUMBER:'+919624453543',WANOTIFIER_PHONE_NUMBER_ID:'1415347881659158',WANOTIFIER_BUSINESS_ACCOUNT_ID:'1386833723249335',WANOTIFIER_INTERVIEW_EN_URL:endpoint,WANOTIFIER_INTERVIEW_HI_URL:endpoint,WANOTIFIER_REGISTERED_JOB_EN_URL:endpoint,SUPABASE_URL:'https://synthetic.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'synthetic-server-key'};
const variables={requirement_code:'AAD-2026-000023',job_role:'Operator',interview_date:'02 Jan 2099',interview_time:'10:30 AM',interview_mode:'onsite',interview_location:'Factory gate',candidate_instructions:'Review Candidate portal.'};
const row={message_id:'synthetic-message',destination:'+919876543210',template_language:'en',template_variables:variables};
const registered={...row,template_name:'aadhyant_registered_job_alert_v4',template_version:'1',purpose:'vacancy_campaign',consent_class:'marketing',template_variables:{requirement_code:'AAD-2026-000023',company:'Factory',job_role:'Operator',job_location:'Sanand',qualification:'ITI',salary:'17000',take_home:'15000',overtime:'As applicable',duty:'8 hours',benefits:'PF',template_contract:'registered_summary_v4',job_fingerprint:'a'.repeat(64),private_notes:'PRIVATE'}};
const request=(kind='interviews',key=workerKey)=>new Request('https://synthetic.invalid',{method:'POST',headers:{'content-type':'application/json','x-whatsapp-worker-key':key},body:JSON.stringify({kind})});
function fixture({rows=[row],boundary=true,receipt={messages:[{id:'wamid.synthetic'}]},configReady=true,failReceipt=false}={}){
 const calls:{name:string;args:any;headers:any}[]=[];let sends=0;
 const fetcher:typeof fetch=async(input,init)=>{const u=new URL(String(input));if(u.origin==='https://app.wanotifier.com'){
  sends++;calls.push({name:'provider',args:JSON.parse(String(init?.body)),headers:init?.headers});assert.equal(init?.redirect,'error');return Response.json(receipt);
 }
 assert.equal(u.origin,env.SUPABASE_URL,'no Meta or fallback host');const name=u.pathname.split('/').at(-1)!;const args=JSON.parse(String(init?.body));calls.push({name,args,headers:init?.headers});
 if(name==='console_sender_configuration')return Response.json({ready:configReady,phone_id:env.WANOTIFIER_PHONE_NUMBER_ID,account_id:env.WANOTIFIER_BUSINESS_ACCOUNT_ID});
 if(name.startsWith('console_claim_'))return Response.json(rows);
 if(name.includes('provider_boundary'))return Response.json(boundary);
 if(name==='mark_whatsapp_outbound_sent'&&failReceipt)return Response.json({error:'private'}, {status:500});return Response.json(true);
 };
 return {calls,fetcher,get sends(){return sends}};
}
test('worker uses canonical interview claim/boundary and one Notification POST without server credentials',async()=>{
 const f=fixture();const r=await handle(request(),k=>env[k]||'',f.fetcher);assert.equal(r.status,200);assert.deepEqual(await r.json(),{processed:1,sent:1,blocked:0,reconciliation_required:0});assert.equal(f.sends,1);
 assert.deepEqual(f.calls.map(c=>c.name),['console_sender_configuration','console_claim_interview_notifications','console_interview_provider_boundary','provider','mark_whatsapp_outbound_sent']);
 assert.deepEqual(f.calls[3].headers,{'content-type':'application/json'});assert.equal(f.calls[3].args.data.body_variables.length,7);
});
test('registered notification preserves ten variables and job URL suffix without copying private data',async()=>{
 const f=fixture({rows:[registered] as any});const r=await handle(request('registered_alerts'),k=>env[k]||'',f.fetcher);assert.equal(r.status,200);assert.equal(f.sends,1);
 assert.equal(f.calls[1].name,'console_claim_registered_alerts');assert.equal(f.calls[2].name,'console_provider_boundary');
 const payload=f.calls[3].args;assert.equal(payload.data.body_variables.length,10);assert.deepEqual(payload.data.button_variables,['AAD-2026-000023']);assert.ok(!JSON.stringify(payload).includes('PRIVATE'));
});
test('worker ack without wamid is never retried, fabricated as sent or forwarded to Meta',async()=>{
 const f=fixture({receipt:{error:false,message:'accepted'} as any});const r=await handle(request(),k=>env[k]||'',f.fetcher);assert.equal((await r.json()).reconciliation_required,1);assert.equal(f.sends,1);assert.equal(f.calls.at(-1)?.args.p_failure_kind,'ambiguous');assert.ok(!f.calls.some(c=>c.name==='mark_whatsapp_outbound_sent'));
});
test('final denial blocks sends, including a contact whose permission changed after claim',async()=>{const f=fixture({boundary:false});const r=await handle(request(),k=>env[k]||'',f.fetcher);assert.equal((await r.json()).blocked,1);assert.equal(f.sends,0);});
test('unconfirmed receipt persistence cannot become success or a second provider call',async()=>{const f=fixture({failReceipt:true});const r=await handle(request(),k=>env[k]||'',f.fetcher);assert.equal((await r.json()).reconciliation_required,1);assert.equal(f.sends,1);});
test('authentication, route, feature switches and endpoint checks run before any claim',async()=>{
 for(const patch of [{WANOTIFIER_AUTOMATION_ENABLED:'false'},{WANOTIFIER_INTERVIEWS_ENABLED:'false'},{WANOTIFIER_SENDER_NUMBER:'+919586785800'},{WANOTIFIER_PHONE_NUMBER_ID:'1234567890123'},{WANOTIFIER_INTERVIEW_EN_URL:'https://example.org/private'}]){
  const f=fixture();const r=await handle(request(),k=>({...env,...patch})[k]||'',f.fetcher);assert.ok(r.status>=400);assert.equal(f.calls.length,0);
 }
 const f=fixture();assert.equal((await handle(request('interviews','wrong'),k=>env[k]||'',f.fetcher)).status,401);assert.equal(f.calls.length,0);
 assert.equal((await handle(request('arbitrary'),k=>env[k]||'',f.fetcher)).status,400);
});
test('stale sender connection blocks claiming; requests cannot supply recipients or alternate URLs',async()=>{
 const f=fixture({configReady:false});assert.equal((await handle(request(),k=>env[k]||'',f.fetcher)).status,503);assert.equal(f.calls.length,1);
 const r=new Request('https://synthetic.invalid',{method:'POST',headers:{'content-type':'application/json','x-whatsapp-worker-key':workerKey},body:JSON.stringify({kind:'interviews',recipient:'+919876543210'})});assert.equal((await handle(r,k=>env[k]||'',f.fetcher)).status,400);
});
test('Notification transport pins HTTPS origin, exact route and a single recipient; errors never expose endpoint keys',async()=>{
 for(const url of ['http://app.wanotifier.com/api/v1/notifications/synthetic1?key=synthetic-private-key',endpoint+'&redirect=x',endpoint.replace('/notifications/','/messages/'),endpoint+'#secret','https://user:pass@app.wanotifier.com/api/v1/notifications/synthetic1?key=synthetic-private-key'])assert.throws(()=>wanotifierNotificationTransport(url));
 const transport=wanotifierNotificationTransport(endpoint,async()=>{throw Error(endpoint);});
 await assert.rejects(()=>transport(wanotifierRegisteredNotificationPayload(registered)),e=>!String(e).includes('synthetic-private-key'));
 await assert.rejects(()=>transport({data:{},recipients:[{whatsapp_number:'+919876543210'},{whatsapp_number:'+919876543211'}]}));
});
