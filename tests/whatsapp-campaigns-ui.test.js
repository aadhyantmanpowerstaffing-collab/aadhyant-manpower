const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const page = fs.readFileSync('admin/index.html', 'utf8');
const admin = fs.readFileSync('admin/admin.js', 'utf8');
const source = fs.readFileSync('admin/whatsapp-campaigns.js', 'utf8');
const styles = fs.readFileSync('admin/admin.css', 'utf8');

test('campaign module is integrated into the Admin shell', () => {
  assert.match(page, /whatsapp-campaigns\.js/);
  assert.match(admin, /aadhyantWhatsAppCampaigns\?\.initialize/);
});

test('campaign builder exposes all eight controlled stages', () => {
  for (const label of ['Select Vacancy','Matching Criteria','Preview Candidates','Include / Exclude','Message Template','Review Campaign','Approve','Queue']) assert.match(source, new RegExp(label.replace('/', '\\/')));
  assert.match(source, /choice\.type='checkbox'/);
  assert.match(source, /Approve Campaign/);
  assert.match(source, /Queue Approved Audience/);
});

test('campaign UI uses RPCs without base-table access', () => {
  for (const rpc of ['admin_preview_whatsapp_campaign_audience','admin_create_whatsapp_campaign','admin_freeze_whatsapp_campaign_audience','admin_approve_whatsapp_campaign','admin_queue_whatsapp_campaign','admin_list_whatsapp_campaigns','admin_get_whatsapp_campaign']) assert.match(source, new RegExp(rpc));
  assert.doesNotMatch(source, /client\.from\s*\(/);
});

test('matching controls avoid sensitive filters', () => {
  assert.match(source, /Age and gender are intentionally not available/);
  assert.doesNotMatch(source, /\[['"](?:age|gender)['"]/);
});

test('list, detail, states and delivery counts are rendered', () => {
  for (const label of ['Campaign Portfolio','Masked Contact','Audience','Queued','Sent','Delivered','Read','Failed']) assert.match(source, new RegExp(label));
  assert.match(source, /aria-live/);
});

test('campaign UI is responsive and has no blocking browser dialogs', () => {
  assert.match(styles, /campaign-stepper/);
  assert.match(styles, /campaign-preview-table/);
  assert.match(styles, /@media\(max-width:640px\)/);
  assert.doesNotMatch(source, /\b(?:alert|prompt|confirm)\s*\(/);
});

test('W7B prepares INTERESTED metadata but no response workflow', () => {
  assert.match(source, /INTERESTED prepared; no application action in W7B/);
  assert.doesNotMatch(source, /create_candidate_application|interested_response|registration_flow/i);
});
