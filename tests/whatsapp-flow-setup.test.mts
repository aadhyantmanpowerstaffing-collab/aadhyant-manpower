import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {handleFlowSetup} from '../supabase/functions/whatsapp-flow-setup/index.ts';
import {registrationFlow} from '../supabase/functions/_shared/whatsapp/registration-flow-definition.ts';
import {registrationPayload} from '../supabase/functions/_shared/whatsapp/registration-reply.ts';
import {parseWhatsAppWebhook} from '../supabase/functions/_shared/whatsapp/parser.ts';
const env:any={SUPABASE_URL:'https://fixture.invalid',SUPABASE_ANON_KEY:'fixture',SUPABASE_SERVICE_ROLE_KEY:'server-fixture',WHATSAPP_BUSINESS_ACCOUNT_ID:'1234567890',WHATSAPP_ACCESS_TOKEN:'meta-fixture'};
const req=(publish=true)=>new Request('https://fixture.invalid',{method:'POST',headers:{origin:'https://aadhyantmanpower.in',authorization:'Bearer admin'},body:JSON.stringify({publish})});
function network(options:any={}){const calls:string[]=[];let draft=true;
 const fetcher:typeof fetch=async(input,init)=>{const u=String(input);calls.push(u);
  if(u.endsWith('admin_console_access'))return Response.json(options.admin??true);
  if(u.endsWith('console_sender_configuration'))return Response.json({ready:true,account_id:env.WHATSAPP_BUSINESS_ACCOUNT_ID});
  if(u.includes('/flows?'))return Response.json({data:options.existing?[{id:'1234567899',name:'aadhyant_registration_alerts_v1',status:options.draft?'DRAFT':'PUBLISHED'}]:[]});
  if(u.endsWith('/flows'))return Response.json({id:'1234567899'});
  if(u.endsWith('/assets')&&init?.method==='POST')return Response.json({success:true,validation_errors:options.invalid?[{error:'fixture-invalid'}]:[]});
  if(u.endsWith('/publish')){if(options.blocked)return Response.json({error:{code:139000,error_subcode:4233020,message:'private provider error'}},{status:400});draft=false;return Response.json({success:true});}
  if(u.includes('?fields=validation_errors'))return Response.json({validation_errors:options.draftInvalid?[{error:'INVALID_PROPERTY_KEY',message:'Static form property is invalid.'}]:[],health_status:{entities:[]}});
  if(u.includes('?fields=id,name,status'))return Response.json({id:'1234567899',name:'aadhyant_registration_alerts_v1',status:draft&&!options.existing?'DRAFT':'PUBLISHED'});
  if(u.endsWith('/assets'))return Response.json({data:[{asset_type:'FLOW_JSON',download_url:'https://scontent.xx.fbcdn.net/fixture-flow'}]});
  if(u.includes('fbcdn.net'))return Response.json(options.different?{version:'3.1',screens:[]}:registrationFlow);
  if(u.endsWith('console_verify_registration_flow')){assert.match(JSON.parse(String(init?.body)).p_flow_hash,/^[a-f0-9]{64}$/);return Response.json(true);}
  throw Error('Unexpected fixture URL');
 };return {calls,fetcher};}
test('review JSON matches the deployed definition; marketing consent is optional and unchecked',()=>{
 assert.deepEqual(JSON.parse(fs.readFileSync('docs/whatsapp/flows/aadhyant-registration-v1.json','utf8')),registrationFlow);
 const fields=registrationFlow.screens.flatMap(s=>s.layout.children.flatMap(x=>(x as any).children||[]));
 const alerts:any=fields.find((x:any)=>x.name==='job_alert_consent');assert.equal(alerts.required,false);assert.equal('init-value' in alerts,false);const form:any=registrationFlow.screens[1].layout.children.find((x:any)=>x.type==='Form');assert.equal(form['init-values'].job_alert_consent,false);assert.equal(form['init-values'].registration_consent,false);
 const registration:any=fields.find((x:any)=>x.name==='registration_consent');assert.equal(registration.required,true);
 assert.equal(fields.some((x:any)=>['aadhaar','bank_account','password','mobile'].includes(x.name)),false);
});
test('publication validates Meta JSON before publishing and verifies immutable asset before activation; never sends',async()=>{const n=network();const r=await handleFlowSetup(req(),k=>env[k]||'',n.fetcher);assert.equal(r.status,200);assert.equal((await r.json()).ready,true);assert.ok(n.calls.findIndex(x=>x.endsWith('/publish'))>n.calls.findIndex(x=>x.endsWith('/assets')));assert.equal(n.calls.some(x=>x.endsWith('/messages')),false);});
test('Meta validation errors prevent publication and activation',async()=>{const n=network({invalid:true});assert.equal((await handleFlowSetup(req(),k=>env[k]||'',n.fetcher)).status,502);assert.equal(n.calls.some(x=>x.endsWith('/publish')),false);assert.equal(n.calls.some(x=>x.endsWith('console_verify_registration_flow')),false);});
test('read-only verification never creates a Flow; existing published assets must match',async()=>{let n=network();assert.equal((await handleFlowSetup(req(false),k=>env[k]||'',n.fetcher)).status,200);assert.equal(n.calls.some(x=>x.endsWith('/flows')),false);n=network({existing:true,different:true});assert.equal((await handleFlowSetup(req(false),k=>env[k]||'',n.fetcher)).status,502);assert.equal(n.calls.some(x=>x.endsWith('console_verify_registration_flow')),false);});
test('non-admin cannot reach Meta',async()=>{const n=network({admin:false});assert.equal((await handleFlowSetup(req(),k=>env[k]||'',n.fetcher)).status,403);assert.equal(n.calls.length,1);});
test('interactive registration uses a bound opaque token and native WhatsApp button',()=>{const p:any=registrationPayload({purpose:'interested_registration',consent_class:'transactional',message_type:'session_text',destination:'+919876543210',template_variables:{requirement_code:'AAD-2026-000003'},flow_id:'1234567899',flow_token:'a'.repeat(64)});assert.equal(p.type,'interactive');assert.equal(p.interactive.type,'flow');assert.equal(p.interactive.action.parameters.flow_message_version,'3');assert.equal(p.interactive.action.parameters.flow_action_payload.data.requirement_code,'AAD-2026-000003');});
test('Flow response retains exact boolean consent and ignores secrets/foreign mobile fields',()=>{
 const envelope=(response:any)=>({object:'whatsapp_business_account',entry:[{changes:[{value:{messages:[{id:'wamid.flow',from:'919876543210',type:'interactive',interactive:{type:'nfm_reply',nfm_reply:{name:'flow',response_json:JSON.stringify(response)}}}]}}]}]});
 let e=parseWhatsAppWebhook(envelope({form_kind:'aadhyant_registration_v1',flow_token:'a'.repeat(64),age:25,registration_consent:true,job_alert_consent:false,consent_policy_version:'wa-registration-alerts-v1',mobile:'9999999999',aadhaar:'private',access_token:'private'}))[0];
 assert.equal(e.actionId,'REGISTRATION_SUBMIT');assert.equal(e.redactedResponse?.age,'25');assert.equal(e.redactedResponse?.job_alert_consent,false);assert.equal(e.redactedResponse?.registration_consent,true);assert.equal('mobile' in e.redactedResponse!,false);assert.equal('aadhaar' in e.redactedResponse!,false);
 e=parseWhatsAppWebhook(envelope({form_kind:'aadhyant_registration_v1',job_alert_consent:'true'}))[0];assert.equal('job_alert_consent' in e.redactedResponse!,false);
});

test('Meta integrity rejection reports safe codes and never activates or retries publication',async()=>{const n=network({blocked:true});const r=await handleFlowSetup(req(),k=>env[k]||'',n.fetcher);assert.equal(r.status,502);const data=await r.json();assert.match(data.error,/139000\/4233020/);assert.equal(data.error.includes('private provider error'),false);assert.equal(n.calls.filter(x=>x.endsWith('/publish')).length,1);assert.equal(n.calls.some(x=>x.endsWith('console_verify_registration_flow')),false);});
test('draft diagnostics read validation without uploading or publishing',async()=>{const n=network({existing:true,draft:true,draftInvalid:true});const r=await handleFlowSetup(req(false),k=>env[k]||'',n.fetcher);assert.equal(r.status,502);assert.match((await r.json()).error,/INVALID_PROPERTY_KEY/);assert.equal(n.calls.some(x=>x.endsWith('/publish')||x.endsWith('/assets')),false);});
