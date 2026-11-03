import test from 'node:test';import assert from 'node:assert/strict';
import {recruitmentPayload,dispatchRecruitmentNotifications,recruitmentRoutes} from '../supabase/functions/_shared/whatsapp/recruitment-dispatch.ts';
const row={message_id:'synthetic',destination:'+919876543210',template_name:'aadhyant_interview_confirmation_hi_v1',template_language:'hi',template_variables:{requirement_code:'AAD-2026-000023',job_role:'Operator',event_date:'02 Jan 2099',event_time:'10:00 AM IST',venue:'Gate 1',instructions:'Review portal'}};
const endpoint='https://app.wanotifier.com/api/v1/notifications/synthetic123?key=synthetic-private-key';
function fixture({boundary=true,receipt={wamid:'wamid.synthetic'},persist=true}={}){const calls:any[]=[];let sends=0;const rpc=async(name:string,args:any)=>{calls.push({name,args});if(name==='console_claim_recruitment_notifications')return [row];if(name==='console_recruitment_provider_boundary')return boundary;if(name==='mark_whatsapp_outbound_sent')return persist;return true;};const fetcher:any=async()=>{sends++;return Response.json(receipt)};return {calls,rpc,fetcher,get sends(){return sends}};}
const run=(f:any,get=(_k:string)=>endpoint)=>dispatchRecruitmentNotifications('worker','1415347881659158','1386833723249335',get,f.rpc,f.fetcher);
test('all six exact routes map to six safe body variables',()=>{assert.equal(Object.keys(recruitmentRoutes).length,6);for(const template_name of Object.keys(recruitmentRoutes)){const payload=recruitmentPayload({...row,template_name,template_language:template_name.includes('_hi_')?'hi':'en'});assert.equal(payload.data.body_variables.length,6);assert.deepEqual(payload.recipients,[{whatsapp_number:row.destination}]);}assert.throws(()=>recruitmentPayload({...row,template_variables:{...row.template_variables,bank_account:'private'}}));});
test('route validation precedes any prep or claim',async()=>{const f=fixture();await assert.rejects(()=>run(f,()=>''));assert.equal(f.calls.length,0);assert.equal(f.sends,0);});
test('exact boundary precedes one send and receipt persistence',async()=>{const f=fixture();assert.deepEqual(await run(f),{processed:1,sent:1,blocked:0,reconciliation_required:0});assert.equal(f.sends,1);assert.deepEqual(f.calls.map(x=>x.name),['prepare_recruitment_notifications','console_claim_recruitment_notifications','console_recruitment_provider_boundary','mark_whatsapp_outbound_sent']);});
test('changed eligibility blocks provider',async()=>{const f=fixture({boundary:false});assert.equal((await run(f)).blocked,1);assert.equal(f.sends,0);});
for(const receipt of [{error:false},{wamid:'not-a-wa-id'},{wamid:'wamid.one',messages:[{id:'wamid.other'}]}])test('uncertain receipt never retries',async()=>{const f=fixture({receipt:receipt as any});assert.equal((await run(f)).reconciliation_required,1);assert.equal(f.sends,1);assert.ok(!f.calls.some(x=>x.name==='mark_whatsapp_outbound_sent'));});
test('receipt persistence failure is not success and never resends',async()=>{const f=fixture({persist:false});assert.equal((await run(f)).reconciliation_required,1);assert.equal(f.sends,1);});
test('a slow recipient does not prevent the rest of a bounded batch crossing their valid leases',async()=>{
 const rows=Array.from({length:10},(_,i)=>({...row,message_id:'synthetic-'+i}));let sends=0,boundaries=0,release:any;const blocked=new Promise<void>(resolve=>{release=resolve});
 const rpc=async(n:string,_a:any)=>{if(n==='console_claim_recruitment_notifications')return rows;if(n==='console_recruitment_provider_boundary')boundaries++;return true;};
 const fetcher:any=async()=>{const number=++sends;if(number===1)await blocked;return Response.json({wamid:'wamid.synthetic-'+number});};
 const work=dispatchRecruitmentNotifications('worker','1415347881659158','1386833723249335',()=>endpoint,rpc,fetcher);
 try{for(let i=0;i<30&&sends<10;i++)await new Promise(resolve=>setImmediate(resolve));assert.equal(boundaries,10);assert.equal(sends,10);}finally{release();}
 assert.deepEqual(await work,{processed:10,sent:10,blocked:0,reconciliation_required:0});
});
test('unconfirmed failure persistence cannot report a completed recruitment batch',async()=>{const f=fixture({boundary:false});const rpc=async(n:string,a:any)=>{if(n==='mark_whatsapp_outbound_failure')throw Error('synthetic persistence failure');return f.rpc(n,a);};await assert.rejects(()=>dispatchRecruitmentNotifications('worker','1415347881659158','1386833723249335',()=>endpoint,rpc,f.fetcher),/persistence unconfirmed/);assert.equal(f.sends,0);});

test('direct Meta definite rejection records the numeric reason without private provider text or retry',async()=>{
 const f=fixture();let sends=0;const result=await dispatchRecruitmentNotifications('worker','1415347881659158','1386833723249335',()=>'',f.rpc,async()=>{sends++;return Response.json({error:{code:131048,message:'PRIVATE provider detail'}},{status:400});},{accessToken:'synthetic-meta-key'});
 assert.deepEqual(result,{processed:1,sent:0,blocked:1,reconciliation_required:0});assert.equal(sends,1);
 assert.equal(f.calls.at(-1).args.p_error_code,'131048');assert.equal(f.calls.at(-1).args.p_failure_kind,'permanent');assert.doesNotMatch(JSON.stringify(f.calls),/PRIVATE|synthetic-meta-key/);
});
