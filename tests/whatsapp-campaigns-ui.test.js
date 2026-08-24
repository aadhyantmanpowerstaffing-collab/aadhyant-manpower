const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const page = fs.readFileSync('admin/index.html', 'utf8');
const admin = fs.readFileSync('admin/admin.js', 'utf8');
const source = fs.readFileSync('admin/whatsapp-campaigns.js', 'utf8');
const styles = fs.readFileSync('admin/admin.css', 'utf8');
const migration = fs.readFileSync('supabase/migrations/028_whatsapp_vacancy_campaigns.sql', 'utf8');
const sandbox = {window:{},document:{},crypto:{randomUUID:()=> 'stable-operation-id'},Set,Object,String,Error,Promise};
vm.runInNewContext(source, sandbox, {filename:'admin/whatsapp-campaigns.js'});
const controller = sandbox.window.aadhyantWhatsAppCampaigns;

const campaignState = (overrides={}) => ({
  requirement:{id:'requirement-1'}, operationKey:'operation-1', campaignId:null,
  campaign:{campaignName:'Fitter intake',templateName:'vacancy_interest',templateLanguage:'en',templateVersion:'1'},
  criteria:{avoid_existing_application:true}, included:new Set(['candidate-1']), excluded:new Set(), pendingFreeze:null,
  ...overrides
});
const clientWith = (handler) => ({rpc:handler});

// Source/static security and integration checks (6).
test('static: module is integrated and exposes the eight controlled stages', () => {
  assert.match(page, /whatsapp-campaigns\.js/); assert.match(admin, /aadhyantWhatsAppCampaigns\?\.initialize/);
  assert.deepEqual(Array.from(controller.steps), ['Select Vacancy','Matching Criteria','Candidate Preview','Include / Exclude','Template Preview','Review Campaign','Approve','Queue']);
});

test('static: campaign UI is RPC-only and has no blocking browser dialogs', () => {
  for (const rpc of ['admin_preview_whatsapp_campaign_audience','admin_create_whatsapp_campaign','admin_freeze_whatsapp_campaign_audience','admin_approve_whatsapp_campaign','admin_queue_whatsapp_campaign','admin_list_whatsapp_campaigns','admin_get_whatsapp_campaign']) assert.match(source,new RegExp(rpc));
  assert.doesNotMatch(source,/client\.from\s*\(/); assert.doesNotMatch(source,/\b(?:alert|prompt|confirm)\s*\(/);
});

test('static: matching remains requirement-derived and avoids sensitive filters', () => {
  for (const field of ['req.qualification','req.iti_trade','req.experience_requirement','req.job_location']) assert.match(migration,new RegExp(field.replace('.','\\.')));
  assert.match(source,/Age and gender are intentionally not available/); assert.doesNotMatch(source,/\[['"](?:age|gender)['"]/);
});

test('static: list, detail, counts and responsive controls remain present', () => {
  for (const label of ['Campaign Portfolio','Masked Contact','Audience','Queued','Sent','Delivered','Read','Failed']) assert.match(source,new RegExp(label));
  assert.match(styles,/campaign-stepper/); assert.match(styles,/campaign-preview-table/); assert.match(styles,/@media\(max-width:640px\)/);
});

test('static: W7B prepares correlation without implementing W7C', () => {
  assert.match(source,/INTERESTED prepared; no application action in W7B/);
  assert.doesNotMatch(source,/create_candidate_application|interested_response|registration_flow/i);
});

test('static: resumed template and mutation controls are visibly immutable', () => {
  assert.match(source,/input\.disabled=Boolean\(state\.campaignId\)/); assert.match(source,/state\.step>0&&!state\.campaignId/);
  assert.match(source,/Stored campaign and template metadata is authoritative and read-only/);
});

// Executed controller behavior checks (11).
test('behavior: new campaign starts at vacancy selection and resumed draft starts at criteria', () => {
  assert.equal(controller.initialStep(null),0); assert.equal(controller.initialStep({id:'campaign-1'}),1);
});

test('behavior: vacancy selection resolves only a server-returned open requirement', () => {
  const requirements=[{id:'requirement-1',requirement_stage:'open'}];
  assert.equal(controller.selectRequirement(requirements,'requirement-1'),requirements[0]); assert.equal(controller.selectRequirement(requirements,'unrelated'),null);
});

test('behavior: lifecycle actions are derived from canonical server status', () => {
  assert.equal(controller.detailAction('draft'),'resume'); assert.equal(controller.detailAction('audience_ready'),'approve'); assert.equal(controller.detailAction('approved'),'queue');
  assert.equal(controller.detailAction('queued'),'reconcile'); assert.equal(controller.detailAction('sending'),'reconcile');
  for (const status of ['completed','failed','cancelled','unknown']) assert.equal(controller.detailAction(status),null);
});

test('behavior: resumed draft uses stored template metadata in review', () => {
  const stored=controller.storedTemplate({campaign_name:'Canonical',template_name:'vacancy_interest',template_language:'en',template_version:'7'});
  const reviewed=controller.reviewTemplate({campaignId:'campaign-1',campaign:stored},[{name:'templateName',value:'browser_only'}]);
  assert.deepEqual(JSON.parse(JSON.stringify(stored)),{campaignName:'Canonical',templateName:'vacancy_interest',templateLanguage:'en',templateVersion:'7'}); assert.equal(reviewed.templateName,'vacancy_interest');
});

test('behavior: new campaign review accepts entered template values', () => {
  const inputs=[{name:'campaignName',value:'  New intake  '},{name:'templateName',value:' vacancy_interest '},{name:'templateLanguage',value:' en '},{name:'templateVersion',value:' 1 '}];
  assert.deepEqual(JSON.parse(JSON.stringify(controller.reviewTemplate({campaignId:null,campaign:null},inputs))),{campaignName:'New intake',templateName:'vacancy_interest',templateLanguage:'en',templateVersion:'1'});
});

test('behavior: create and freeze uses one stable operation identity and canonical returned ID', async () => {
  const calls=[]; const state=campaignState();
  const client=clientWith(async(name,args)=>{calls.push([name,args]);return {data:name==='admin_create_whatsapp_campaign'?'campaign-1':name==='admin_get_whatsapp_campaign'?{id:'campaign-1',campaign_status:'audience_ready'}:1,error:null};});
  const detail=await controller.createAndFreeze(client,state);
  assert.equal(state.campaignId,'campaign-1'); assert.equal(detail.campaign_status,'audience_ready'); assert.equal(calls[0][1].p_operation_key,'operation-1');
  assert.deepEqual(calls.map(([name])=>name),['admin_create_whatsapp_campaign','admin_freeze_whatsapp_campaign_audience','admin_get_whatsapp_campaign']);
});

test('behavior: concurrent double submit shares one create/freeze RPC sequence', async () => {
  const calls=[]; let release; const gate=new Promise(resolve=>{release=resolve;}); const state=campaignState();
  const client=clientWith(async(name)=>{calls.push(name);if(name==='admin_create_whatsapp_campaign')await gate;return {data:name==='admin_create_whatsapp_campaign'?'campaign-1':{},error:null};});
  const first=controller.createAndFreeze(client,state); const second=controller.createAndFreeze(client,state); release(); await Promise.all([first,second]);
  assert.equal(calls.filter(name=>name==='admin_create_whatsapp_campaign').length,1); assert.equal(calls.filter(name=>name==='admin_freeze_whatsapp_campaign_audience').length,1);
});

test('behavior: failed create retries with the same stable operation identity', async () => {
  const operationKeys=[]; let fail=true; const state=campaignState();
  const client=clientWith(async(name,args)=>{if(name==='admin_create_whatsapp_campaign'){operationKeys.push(args.p_operation_key);if(fail){fail=false;return {data:null,error:{message:'temporary'}};}return {data:'campaign-1',error:null};}return {data:{id:'campaign-1'},error:null};});
  await assert.rejects(controller.createAndFreeze(client,state),(error)=>error.message==='temporary'); await controller.createAndFreeze(client,state);
  assert.deepEqual(operationKeys,['operation-1','operation-1']); assert.equal(state.campaignId,'campaign-1');
});

test('behavior: resumed campaign retry never creates a duplicate draft', async () => {
  const calls=[]; const state=campaignState({campaignId:'campaign-existing'});
  const client=clientWith(async(name)=>{calls.push(name);return {data:name==='admin_get_whatsapp_campaign'?{id:'campaign-existing',campaign_status:'audience_ready'}:1,error:null};});
  await controller.createAndFreeze(client,state);
  assert.doesNotMatch(calls.join(','),/admin_create_whatsapp_campaign/); assert.equal(calls.filter(name=>name==='admin_freeze_whatsapp_campaign_audience').length,1);
});

test('behavior: successful mutation reloads canonical campaign detail', async () => {
  const calls=[]; const state=campaignState();
  const client=clientWith(async(name)=>{calls.push(name);return {data:name==='admin_create_whatsapp_campaign'?'campaign-1':name==='admin_get_whatsapp_campaign'?{id:'campaign-1',campaign_status:'approved',audience_count:1}:1,error:null};});
  const canonical=await controller.createAndFreeze(client,state);
  assert.equal(calls.at(-1),'admin_get_whatsapp_campaign'); assert.equal(canonical.campaign_status,'approved'); assert.equal(canonical.audience_count,1);
});

test('behavior: terminal and preapproval states never expose queue', () => {
  for (const status of ['draft','audience_ready','queued','sending','completed','failed','cancelled']) assert.notEqual(controller.detailAction(status),'queue');
  assert.equal(controller.detailAction('approved'),'queue');
});
