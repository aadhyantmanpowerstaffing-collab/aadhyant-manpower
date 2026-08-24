const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const vm = require('node:vm');

const page = fs.readFileSync('admin/index.html', 'utf8');
const styles = fs.readFileSync('admin/admin.css', 'utf8');
const admin = fs.readFileSync('admin/admin.js', 'utf8');
const recruitmentSource = fs.readFileSync('admin/recruitment-operations.js', 'utf8');
const campaignSource = fs.readFileSync('admin/whatsapp-campaigns.js', 'utf8');
const productSource = fs.readFileSync('admin/admin-product.js', 'utf8');
const phaseDocument = fs.readFileSync('POST_W7C_ADMIN_PRODUCT_PHASE.md', 'utf8');

const recruitmentWindow = {};
vm.runInNewContext(recruitmentSource, { window: recruitmentWindow, document: {}, crypto: { randomUUID: () => 'correlation' }, Date, String, Array, Object, Promise, Set });
const recruitment = recruitmentWindow.aadhyantRecruitmentOperations;
const productWindow = {};
vm.runInNewContext(productSource, { window: productWindow, document: {}, Date, String, Array, Object, Promise, Map, Boolean });
const product = productWindow.aadhyantAdminProduct;

test('product shell exposes grouped business navigation without duplicate primary modules', () => {
  for (const group of ['dashboard','recruitment','whatsapp','network','administration']) assert.match(page, new RegExp(`data-nav-group="${group}"`));
  for (const label of ['Companies','Contractors','Users / Roles']) assert.match(page, new RegExp(`>${label}<`));
  assert.match(page, /data-nav-group="compatibility" hidden/);
  assert.match(page, /admin-nav-toggle[^>]+aria-controls="admin-primary-navigation"/);
  assert.doesNotMatch(page, /role="tablist"/);
});

test('product navigation initializes after canonical recruitment and campaign modules', () => {
  assert.match(page, /admin-product\.js/);
  assert.match(admin, /aadhyantRecruitmentOperations\?\.initialize[\s\S]*aadhyantWhatsAppCampaigns\?\.initialize[\s\S]*aadhyantAdminProduct\?\.initialize/);
  assert.deepEqual(JSON.parse(JSON.stringify(product.operationsDefinitions)), [
    { key: 'whatsappInbound', label: 'Incoming / Replies', group: 'whatsapp' },
    { key: 'whatsappAttention', label: 'Failed / Attention', group: 'whatsapp' }
  ]);
  for (const source of [admin,recruitmentSource,campaignSource,productSource]) assert.match(source, /\[data-tab\],\[data-w3-tab\],\[data-product-tab\]/);
});

test('dashboard uses bounded safe projections and accurately labelled metrics', () => {
  for (const rpc of ['get_recruitment_dashboard','get_whatsapp_core_health','admin_list_whatsapp_campaigns','list_whatsapp_recent_inbound']) assert.match(recruitmentSource, new RegExp(rpc));
  for (const label of ['Open requirements','New candidates','Applications','Upcoming interviews','Active campaigns','Campaign audience','Queued','Sent','Delivered','Read','Failed','Recent replies']) assert.match(recruitmentSource, new RegExp(label));
  assert.match(recruitmentSource, /p_limit:6,p_offset:0/);
  const totals = recruitment.summarizeCampaigns([
    { campaign_status: 'approved', audience_count: 4, queued_count: 1, sent_count: 1 },
    { campaign_status: 'completed', audience_count: 3, delivered_count: 2, read_count: 1, failed_count: 1 }
  ]);
  assert.deepEqual(JSON.parse(JSON.stringify(totals)), { active_campaigns:1,campaign_audience:7,queued:1,sent:1,delivered:2,read:1,failed:1 });
});

test('dashboard quick actions target only supported canonical modules', () => {
  for (const key of ['recruitmentRequirements','recruitmentCandidates','recruitmentApplications','recruitmentInterviews','whatsappCampaigns']) assert.match(recruitmentSource, new RegExp(`'${key}'`));
  assert.match(productSource, /\[data-open-module\]/);
  assert.doesNotMatch(recruitmentSource, /Create Requirement/);
});

test('candidate, requirement and application filters map to bounded server RPC arguments', () => {
  assert.equal(recruitment.pageSize, 25);
  assert.deepEqual(JSON.parse(JSON.stringify(recruitment.argsFor('recruitmentCandidates', { search:'Asha',state:'Odisha',district:'Khordha',qualification:'ITI',candidateType:'Experienced',status:'shortlisted' }, 25))), {
    p_search:'Asha',p_state:'Odisha',p_district:'Khordha',p_qualification:'ITI',p_candidate_type:'Experienced',p_status:'shortlisted',p_limit:25,p_offset:25
  });
  assert.deepEqual(JSON.parse(JSON.stringify(recruitment.argsFor('recruitmentRequirements', { search:'fitter',stage:'open' }, 50))), { p_search:'fitter',p_stage:'open',p_limit:25,p_offset:50 });
  assert.deepEqual(JSON.parse(JSON.stringify(recruitment.argsFor('recruitmentApplications', { search:'REQ-1',stage:'screening' }, 0))), { p_stage:'screening',p_search:'REQ-1',p_limit:25,p_offset:0 });
  assert.match(recruitmentSource, /No actions available/);
});

test('interview filters derive upcoming, past and overdue attention from the bounded projection', () => {
  const now = new Date('2030-01-02T00:00:00Z').getTime();
  const rows = [
    { id:'past',status:'scheduled',scheduled_at:'2030-01-01T00:00:00Z' },
    { id:'future',status:'scheduled',scheduled_at:'2030-01-03T00:00:00Z' },
    { id:'done',status:'completed',scheduled_at:'2030-01-01T00:00:00Z' }
  ];
  assert.deepEqual(Array.from(recruitment.filterInterviewRows(rows,'upcoming',now), (row) => row.id), ['future']);
  assert.deepEqual(Array.from(recruitment.filterInterviewRows(rows,'past',now), (row) => row.id), ['past','done']);
  assert.deepEqual(Array.from(recruitment.filterInterviewRows(rows,'attention',now), (row) => row.id), ['past']);
});

test('requirements have a projected business detail with no invented schema fields', () => {
  const section = recruitmentSource.slice(recruitmentSource.indexOf('const openRequirementDetail'), recruitmentSource.indexOf('const renderList'));
  for (const label of ['Company','Job role / trade','Location','Openings','Filled','Remaining','Applications','Qualification','ITI trade','Experience','Salary','Shift','Working hours','Accommodation','Canteen','Transport']) assert.match(section, new RegExp(label));
  assert.doesNotMatch(section, /client\.from|\.rpc\(/);
});

test('application pipeline and recruitment lists preserve canonical server authority', () => {
  for (const stage of ['interested','applied','screening','shortlisted','interview','selected','rejected']) assert.match(recruitmentSource, new RegExp(`'${stage}'`));
  assert.match(recruitmentSource, /transition_recruitment_application/);
  assert.match(recruitmentSource, /await load\(\)/);
  assert.doesNotMatch(recruitmentSource, /(?:client|supabase)\.from\s*\(/);
});

test('campaign portfolio adds bounded status paging, cancellation and exact eight stages', () => {
  assert.match(campaignSource, /p_status:filter\.value\|\|null,p_limit:25,p_offset:offset/);
  assert.match(campaignSource, /admin_cancel_whatsapp_campaign/);
  assert.match(campaignSource, /responsive-table/);
  assert.deepEqual(Array.from(productWindow.aadhyantAdminProduct.operationsDefinitions).length, 2);
});

test('inbound and attention screens use only safe Admin RPC projections', () => {
  for (const rpc of ['list_whatsapp_recent_inbound','list_whatsapp_failed_outbound','admin_list_whatsapp_campaigns','list_recruitment_interviews']) assert.match(productSource, new RegExp(rpc));
  assert.doesNotMatch(productSource, /\.from\s*\(|raw_payload|payload_json|message_text|innerHTML|\b(?:alert|prompt|confirm)\s*\(/);
  for (const label of ['Masked contact','Structured action','Processing','Failure category','Interview attention']) assert.match(productSource, new RegExp(label));
});

test('attention derivation includes only overdue scheduled interviews', () => {
  const now = new Date('2030-01-02T00:00:00Z').getTime();
  const result = product.attentionFrom([{ id:'outbound' }],[{ id:'campaign' }],[
    { id:'overdue',status:'scheduled',scheduled_at:'2030-01-01T00:00:00Z' },
    { id:'future',status:'scheduled',scheduled_at:'2030-01-03T00:00:00Z' },
    { id:'complete',status:'completed',scheduled_at:'2030-01-01T00:00:00Z' }
  ],now);
  assert.deepEqual(Array.from(result.overdueInterviews, (row) => row.id), ['overdue']);
  assert.equal(result.failedOutbound.length,1);assert.equal(result.failedCampaigns.length,1);
});

test('loading empty error retry and double-submit protections are explicit', () => {
  for (const token of ['state-panel-loading','state-panel-error','Retry','No inbound replies are available','No failed outbound items']) assert.match(`${productSource}\n${recruitmentSource}\n${campaignSource}`, new RegExp(token));
  assert.match(recruitmentSource, /if\(loading\)return/);
  assert.match(productSource, /if\(loading\)return/);
  assert.match(campaignSource, /if\(loading\)return/);
  assert.match(campaignSource, /if\(state\.pendingFreeze\)return state\.pendingFreeze/);
});

test('mobile navigation and responsive table cards preserve actions', () => {
  assert.match(styles, /@media\(max-width:760px\)/);
  assert.match(styles, /\.admin-sidebar\.is-open/);
  assert.match(styles, /\.responsive-table td::before\{content:attr\(data-label\)/);
  assert.match(styles, /\.responsive-table \.table-actions/);
  assert.match(styles, /prefers-reduced-motion/);
});

test('unsupported audit and W7C conversion projections are documented rather than fabricated', () => {
  assert.doesNotMatch(page, />Audit(?:\s*\/\s*Activity)?</);
  assert.match(phaseDocument, /does not return the W7C recipient\/application foreign keys/);
  assert.match(phaseDocument, /No narrow Admin audit\/activity list projection currently exists/);
  assert.doesNotMatch(productSource, /candidate_application|application_id|campaign_recipient/);
});

test('product phase remains static and side-effect bounded', () => {
  const changedProductSource = `${productSource}\n${recruitmentSource}\n${campaignSource}`;
  assert.doesNotMatch(changedProductSource, /graph\.facebook|functions\.deploy|supabase\.functions|WHATSAPP_APP_SECRET|service_role|fetch\s*\(/i);
  assert.match(phaseDocument, /does not authorize a deployment, database mutation, Meta configuration change, WhatsApp message, real-Candidate contact, or production action/);
});
