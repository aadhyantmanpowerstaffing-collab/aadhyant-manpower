import vm from 'node:vm';
import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {handleSelectedVacancy as handle,selectedVacancyPayload} from '../supabase/functions/wanotifier-campaign/index.ts';
const campaign='00000000-0000-0000-0000-000000000081';
const fields={requirement_code:'AAD-2026-000023',company:'Factory',job_role:'Operator',job_location:'Sanand',qualification:'ITI',salary:'17000',take_home:'15000',overtime:'121 per hour',duty:'8 hours',benefits:'PF',template_contract:'registered_summary_v4',job_fingerprint:'a'.repeat(64),campaign_id:campaign};
const row={message_id:'synthetic-message',destination:'+919876543210',template_name:'aadhyant_registered_job_alert_v5',template_language:'en',template_version:'1',purpose:'vacancy_campaign',consent_class:'marketing',template_variables:fields};
const settings:any={SUPABASE_URL:'https://synthetic.supabase.co',SUPABASE_ANON_KEY:'synthetic-anon',SUPABASE_SERVICE_ROLE_KEY:'synthetic-service',WANOTIFIER_SELECTED_VACANCIES_ENABLED:'true',WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED:'true',WANOTIFIER_SENDER_NUMBER:'+919624453543',WANOTIFIER_PHONE_NUMBER_ID:'1415347881659158',WANOTIFIER_BUSINESS_ACCOUNT_ID:'1386833723249335',WANOTIFIER_SELECTED_VACANCY_EN_V5_URL:'https://app.wanotifier.com/api/v1/notifications/synthetic1?key=synthetic-private-key'};
const request=(body:any={campaign_id:campaign},origin='https://aadhyantmanpower.in')=>new Request('https://synthetic.invalid',{method:'POST',headers:{origin,authorization:'Bearer synthetic-admin','content-type':'application/json'},body:JSON.stringify(body)});
function fixture(options:any={}){const calls:any[]=[],state={sends:0,claims:0};const fetcher=async(input:any,init:any)=>{
 const u=new URL(String(input));assert.notEqual(u.hostname,'graph.facebook.com');const name=u.pathname.split('/').at(-1);const args=init.body?JSON.parse(init.body):{};calls.push([name,args]);
 if(u.origin==='https://app.wanotifier.com'){state.sends++;assert.deepEqual(args,selectedVacancyPayload(options.row??row));assert.equal(init.headers.authorization,undefined);if(options.timeout)throw Error('private-key');return Response.json(options.receipt??{wamid:'wamid.selected-vacancy'});}
 if(name==='admin_console_access')return Response.json(!options.denied);
 if(name==='admin_console_vacancy_route'){assert.equal(args.p_campaign_id,campaign);assert.equal(init.headers.authorization,'Bearer synthetic-admin');assert.equal(init.headers.apikey,settings.SUPABASE_ANON_KEY);return Response.json({id:campaign,template_name:options.template??row.template_name,template_language:options.row?.template_language??'en'});}
 if(name==='console_sender_configuration')return Response.json({ready:options.ready!==false,phone_id:settings.WANOTIFIER_PHONE_NUMBER_ID,account_id:settings.WANOTIFIER_BUSINESS_ACCOUNT_ID});
 if(name==='console_claim_campaign'){state.claims++;return Response.json(options.rows??[options.row??row]);}
 if(name==='console_provider_boundary')return Response.json(!options.stop);
 if(name==='mark_whatsapp_outbound_sent')return Response.json(!options.persistFail);
 if(name==='mark_whatsapp_outbound_failure')return Response.json(true);
 throw Error('Unexpected call '+name);
 };return {state,calls,fetcher:fetcher as typeof fetch};}
test('existing selected vacancy uses canonical snapshot, lease and final boundary through WANotifier only',async()=>{const f=fixture(),r=await handle(request(),k=>settings[k]||'',f.fetcher);assert.equal(r.status,200);assert.deepEqual(await r.json(),{processed:1,sent:1,failed:0,reconciliation_required:0});assert.equal(f.state.sends,1);assert.ok(f.calls.findIndex(c=>c[0]==='console_provider_boundary')<f.calls.findIndex(c=>c[0]==='synthetic1'));assert.equal(f.calls.at(-1)[0],'mark_whatsapp_outbound_sent');});
for(const name of ['aadhyant_registered_job_alert_v5','aadhyant_registered_job_alert_hi_v2'])test('registered variable order is preserved for '+name,()=>{const p=selectedVacancyPayload({...row,template_name:name,template_language:name.includes('_hi_')?'hi':'en'});assert.deepEqual(p.data.body_variables,['AAD-2026-000023','Factory','Operator','Sanand','ITI','17000','15000','121 per hour','8 hours','PF']);assert.deepEqual(p.data.button_variables,['AAD-2026-000023']);assert.deepEqual(p.recipients,[{whatsapp_number:row.destination}]);});
for(const key of ['WANOTIFIER_SELECTED_VACANCIES_ENABLED','WANOTIFIER_NOTIFICATION_RECEIPTS_VERIFIED','WANOTIFIER_SELECTED_VACANCY_EN_V5_URL','WANOTIFIER_SENDER_NUMBER'])test('missing '+key+' stops before claim',async()=>{const f=fixture();assert.equal((await handle(request(),k=>k===key?'':settings[k]||'',f.fetcher)).status,503);assert.equal(f.state.claims,0);assert.equal(f.state.sends,0);});
for(const options of [{denied:true},{ready:false},{template:'unsupported'}])test('unverified route/admin/readiness blocks '+JSON.stringify(options),async()=>{const f=fixture(options);assert.ok((await handle(request(),k=>settings[k]||'',f.fetcher)).status>=400);assert.equal(f.state.claims,0);assert.equal(f.state.sends,0);});
for(const options of [{stop:true},{row:{...row,template_variables:{...fields,campaign_id:'another'}}}])test('changed eligibility/campaign never sends '+JSON.stringify(options),async()=>{const f=fixture(options),r=await handle(request(),k=>settings[k]||'',f.fetcher);assert.equal((await r.json()).failed,1);assert.equal(f.state.sends,0);});
for(const options of [{timeout:true},{receipt:{error:false}},{receipt:{wamid:'wamid.a',messages:[{id:'wamid.b'}]}},{persistFail:true}])test('unconfirmed notification receipt never retries or reports sent '+JSON.stringify(options),async()=>{const f=fixture(options),r=await handle(request(),k=>settings[k]||'',f.fetcher);assert.equal((await r.json()).reconciliation_required,1);assert.equal(f.state.sends,1);assert.equal(f.calls.at(-1)[0],'mark_whatsapp_outbound_failure');assert.ok(!JSON.stringify(f.calls.at(-1)).includes('private-key'));});
test('browser delivery uses the canonical Meta worker without WANotifier or the removed composer',()=>{const ui=fs.readFileSync('admin/whatsapp-console.js','utf8');assert.match(ui,/invoke\('whatsapp-outbox-worker',\{campaign_id:id\}\)/);assert.doesNotMatch(ui,/invoke\('wanotifier-campaign'/);assert.doesNotMatch(ui,/'Job Message'|newJobMessage/);});
for(const lang of ['en','hi'])test(lang+' selected vacancy Interested templates send ten canonical fields and no URL-button variables',()=>{const p=selectedVacancyPayload({...row,template_name:'aadhyant_selected_vacancy_'+lang+'_v1',template_language:lang});assert.equal(p.data.body_variables.length,10);assert.deepEqual(Object.keys(p.data),['body_variables']);assert.equal(p.data.body_variables[0],fields.requirement_code);assert.equal(p.data.body_variables[2],fields.job_role);});

for(const lang of ['en','hi'])test(lang+' Interested route completes the same canonical boundary with no URL variables',async()=>{const name='aadhyant_selected_vacancy_'+lang+'_v1';const f=fixture({template:name,row:{...row,template_name:name,template_language:lang}});const config={...settings,WANOTIFIER_SELECTED_INTERESTED_EN_URL:settings.WANOTIFIER_SELECTED_VACANCY_EN_V5_URL,WANOTIFIER_SELECTED_INTERESTED_HI_URL:settings.WANOTIFIER_SELECTED_VACANCY_EN_V5_URL};const r=await handle(request(),k=>config[k]||'',f.fetcher);assert.equal((await r.json()).sent,1);assert.equal(f.state.sends,1);const payload=f.calls.find(c=>c[0]==='synthetic1')[1];assert.deepEqual(Object.keys(payload.data),['body_variables']);});

test('rich template placeholders never label the selected role as the company before canonical preview',()=>{const window:any={};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,Date});const job={requirement_code:'JOB123',job_role:'Operator'};assert.equal(window.AadhyantWhatsAppConsole.renderMessage({body:'Company {{2}} Role {{3}}'},job),'Company {{2}} Role {{3}}');assert.equal(window.AadhyantWhatsAppConsole.renderMessage({body:'Vacancy {{1}} Role {{2}}'},job),'Vacancy JOB123 Role Operator');});

test('campaign route never uses privileged direct-table reads',()=>{const src=fs.readFileSync('supabase/functions/wanotifier-campaign/index.ts','utf8');assert.doesNotMatch(src,/rest\/v1\/whatsapp_campaigns/);assert.match(src,/rpc\/admin_console_vacancy_route/);});

for(const template of ['aadhyant_registered_job_alert_v4','aadhyant_registered_job_alert_hi_v1'])test('retired endpoint cannot send the wrong template '+template,async()=>{const f=fixture({template});assert.equal((await handle(request(),k=>settings[k]||'',f.fetcher)).status,409);assert.equal(f.state.claims,0);assert.equal(f.state.sends,0);});

test('a slow vacancy notification does not consume the rest of the batch lease',async()=>{
 const rows=Array.from({length:10},(_,i)=>({...row,message_id:'synthetic-'+i}));const f=fixture({rows});
 let sends=0,release:any;const blocked=new Promise<void>(resolve=>{release=resolve});
 const fetcher:typeof fetch=async(input,init)=>{if(new URL(String(input)).origin==='https://app.wanotifier.com'){const number=++sends;if(number===1)await blocked;return Response.json({wamid:'wamid.selected-'+number});}return f.fetcher(input,init);};
 const work=handle(request(),k=>settings[k]||'',fetcher);
 try{for(let i=0;i<40&&sends<10;i++)await new Promise(resolve=>setImmediate(resolve));assert.equal(sends,10);assert.equal(f.calls.filter(c=>c[0]==='console_provider_boundary').length,10);}finally{release();}
 assert.deepEqual(await (await work).json(),{processed:10,sent:10,failed:0,reconciliation_required:0});
});

test('a failed result write waits for other in-flight recipients and reports an uncertain batch',async()=>{
 const rows=[row,{...row,message_id:'synthetic-second'}],f=fixture({rows});let sends=0,release:any;
 const blocked=new Promise<void>(resolve=>{release=resolve});
 const fetcher:typeof fetch=async(input,init)=>{const name=new URL(String(input)).pathname.split('/').at(-1);
  if(name==='console_provider_boundary'&&JSON.parse(String(init?.body)).p_message_id===row.message_id)return Response.json(false);
  if(name==='mark_whatsapp_outbound_failure')throw Error('synthetic persistence failure');
  if(new URL(String(input)).origin==='https://app.wanotifier.com'){sends++;await blocked;return Response.json({wamid:'wamid.second'});}
  return f.fetcher(input,init);
 };
 let settled=false;const work=handle(request(),k=>settings[k]||'',fetcher).then(r=>{settled=true;return r;});
 try{for(let i=0;i<40&&sends<1;i++)await new Promise(resolve=>setImmediate(resolve));assert.equal(sends,1);assert.equal(settled,false);}finally{release();}
 const response=await work;assert.equal(response.status,503);assert.match((await response.json()).error,/Outcome unconfirmed/);assert.equal(sends,1);assert.equal(f.calls.filter(c=>c[0]==='mark_whatsapp_outbound_sent').length,1);
});
