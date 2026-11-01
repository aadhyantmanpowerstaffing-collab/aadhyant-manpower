import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {handleJobMessage} from '../supabase/functions/wanotifier-job-message/index.ts';
import {jobMessageNotificationPayload,jobMessageFields,jobMessageBodies,wanotifierMessageId} from '../supabase/functions/_shared/whatsapp/job-message.ts';
const campaign='00000000-0000-0000-0000-000000000081',recipient='00000000-0000-0000-0000-000000000082';
const fields={qualification:'10th / 12th / ITI',group_1:'10th / 12th',ctc_1:'₹17,174',take_home_1:'₹15,326',ot_1:'₹121/hour',group_2:'ITI',ctc_2:'₹17,495',take_home_2:'₹15,602',ot_2:'₹122/hour',benefits:'PF & ESIC; bus; canteen; 8 hours duty'};
const row={message_id:'message-1',destination:'+919876543210',template_name:'aadhyant_job_salary_details_en_v2',template_language:'en',template_version:'1',purpose:'vacancy_campaign',consent_class:'marketing',correlation_id:recipient,template_variables:{...fields,template_contract:'salary_details_v2',campaign_id:campaign,recipient_id:recipient,requirement_code:'AAD-2026-000023',job_fingerprint:'a'.repeat(64)}};
const settings:any={SUPABASE_URL:'https://synthetic.supabase.co',SUPABASE_ANON_KEY:'synthetic',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service',WANOTIFIER_JOB_MESSAGES_ENABLED:'true',WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED:'true',WANOTIFIER_SENDER_NUMBER:'+919624453543',WANOTIFIER_PHONE_NUMBER_ID:'1415347881659158',WANOTIFIER_BUSINESS_ACCOUNT_ID:'1386833723249335',WANOTIFIER_JOB_MESSAGE_EN_URL:'https://app.wanotifier.com/api/v1/notifications/ABCDEF123?key=synthetic-secret'};
const request=(body:any={campaign_id:campaign},origin='https://aadhyantmanpower.in')=>new Request('https://example.invalid/job-message',{method:'POST',headers:{origin,authorization:'Bearer synthetic-admin','content-type':'application/json'},body:JSON.stringify(body)});
function provider(options:any={}){const calls:any[]=[],state={sends:0,claims:0,failures:[] as any[],receipts:[] as any[]};const fetcher=async(input:any,init:any)=>{
 const url=new URL(String(input));assert.notEqual(url.hostname,'graph.facebook.com');const name=url.pathname.split('/').at(-1),body=JSON.parse(init.body);calls.push([name,body]);
 if(url.origin==='https://app.wanotifier.com'){state.sends++;assert.equal((init.headers as any).authorization,undefined);assert.deepEqual(body,jobMessageNotificationPayload(row));if(options.timeout)throw Error('private-secret');return Response.json(options.receipt??{wamid:'wamid.job-message'});}
 if(name==='admin_console_access')return Response.json(options.denied?false:true);
 if(name==='admin_console_job_message_route')return Response.json({template_name:options.route??row.template_name,language:'en'});
 if(name==='console_sender_configuration')return Response.json({ready:true,phone_id:settings.WANOTIFIER_PHONE_NUMBER_ID,account_id:settings.WANOTIFIER_BUSINESS_ACCOUNT_ID});
 if(name==='console_claim_job_message_campaign'){state.claims++;return Response.json([options.row??row]);}
 if(name==='console_provider_boundary')return Response.json(options.stop?false:true);
 if(name==='mark_whatsapp_outbound_sent'){state.receipts.push(body);return Response.json(true);}
 if(name==='mark_whatsapp_outbound_failure'){state.failures.push(body);return Response.json(true);}
 throw Error('Unexpected request '+name);
 };return {fetcher:fetcher as typeof fetch,calls,state};}
test('both templates preserve exact language/body/variable ordering and only the fixed Interested button',()=>{
 for(const l of ['en','hi']){const doc=JSON.parse(fs.readFileSync('docs/whatsapp/job-salary-details-'+l+'-v2.json','utf8'));assert.equal(doc.components[0].text,jobMessageBodies[l]);assert.deepEqual(doc.components[1].buttons,[{type:'QUICK_REPLY',text:'Interested'}]);const p=jobMessageNotificationPayload({...row,template_name:doc.name,template_language:l});assert.deepEqual(p.data.body_variables,jobMessageFields.map(k=>(fields as any)[k]));assert.deepEqual(Object.keys(p.data),['body_variables']);}
 for(const patch of [{template_language:'hi'},{template_name:'aadhyant_job_salary_details_en_v1'},{correlation_id:'bad'},{template_variables:{...row.template_variables,ctc_1:''}},{template_variables:{...row.template_variables,bank_details:'private'}}])assert.throws(()=>jobMessageNotificationPayload({...row,...patch}));
});
test('new worker sends one WANotifier request only after Admin authorization, exact route and canonical boundary',async()=>{
 const p=provider();const r=await handleJobMessage(request(),k=>settings[k]||'',p.fetcher);assert.equal(r.status,200);assert.deepEqual(await r.json(),{processed:1,sent:1,failed:0,reconciliation_required:0});assert.equal(p.state.sends,1);assert.equal(p.state.receipts[0].p_provider_message_id,'wamid.job-message');
 assert.ok(p.calls.findIndex(x=>x[0]==='console_provider_boundary')<p.calls.findIndex(x=>x[0]==='ABCDEF123'));
});
for(const scenario of ['disabled','receipt-unverified','not-admin','wrong-origin','wrong-route','bad-url','recipient-override','stop'])test('Job Message guard prevents provider sends: '+scenario,async()=>{
 const e={...settings};if(scenario==='disabled')e.WANOTIFIER_JOB_MESSAGES_ENABLED='false';if(scenario==='receipt-unverified')e.WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED='false';if(scenario==='bad-url')e.WANOTIFIER_JOB_MESSAGE_EN_URL='https://evil.invalid/';
 const p=provider({denied:scenario==='not-admin',stop:scenario==='stop',route:scenario==='wrong-route'?'old_template':undefined});
 const r=await handleJobMessage(request(scenario==='recipient-override'?{campaign_id:campaign,recipients:['private']}:{campaign_id:campaign},scenario==='wrong-origin'?'https://evil.invalid':'https://aadhyantmanpower.in'),k=>e[k]||'',p.fetcher);
 assert.equal(p.state.sends,0);if(scenario!=='stop')assert.equal(p.state.claims,0);else assert.equal(p.state.failures[0].p_failure_kind,'permanent');assert.ok(r.status>=400||scenario==='stop');
});
for(const receipt of [{error:false,message:'Sent successfully'},{wamid:'numeric-ui-id'},{wamid:'wamid.a',messages:[{id:'wamid.b'}]}])test('uncertain acknowledgement cannot create a fake receipt or retry: '+JSON.stringify(receipt),async()=>{
 const p=provider({receipt});const r=await handleJobMessage(request(),k=>settings[k]||'',p.fetcher);assert.equal(r.status,200);assert.equal((await r.json()).reconciliation_required,1);assert.equal(p.state.sends,1);assert.equal(p.state.receipts.length,0);assert.equal(p.state.failures[0].p_failure_kind,'ambiguous');
});
test('receipt parser accepts deployed top-level wamid and legacy genuine ID only',()=>{
 assert.equal(wanotifierMessageId({wamid:'wamid.real'}),'wamid.real');assert.equal(wanotifierMessageId({messages:[{id:'wamid.real'}]}),'wamid.real');assert.throws(()=>wanotifierMessageId({wamid:'not-wamid'}));
});
