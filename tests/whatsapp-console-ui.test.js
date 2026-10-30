'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const window={};vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,Date});const ui=window.AadhyantWhatsAppConsole;
test('message preview fills both actual template parameters without changing its text',()=>{assert.equal(ui.renderMessage({body:'Vacancy {{1}} / Role {{2}} / {{1}}'},{requirement_code:'JOB-42',job_role:'Fitter'}),'Vacancy JOB-42 / Role Fitter / JOB-42');});
test('only fresh compatible Meta approval is selectable; schedule cannot be invalid or past',()=>{const t={status:'APPROVED',compatible:true,synced_at:new Date().toISOString()};assert.equal(ui.availableTemplate(t),true);assert.equal(ui.availableTemplate({...t,status:'REJECTED'}),false);assert.equal(ui.availableTemplate({...t,name:'aadhyant_registered_job_alert_v1'}),false);assert.equal(ui.availableTemplate({...t,synced_at:'2000-01-01'}),false);assert.equal(ui.dueTime('now',''),null);assert.throws(()=>ui.dueTime('schedule','invalid'));assert.throws(()=>ui.dueTime('schedule','2000-01-01'));});
test('review excludes ineligible records and build ships one console with automatic alerts alongside manual workspaces',()=>{assert.deepEqual(Array.from(ui.selectedIds(new Map([['a',{contact_id:'a',eligible:true}],['b',{contact_id:'b',eligible:false}]]))),['a']);const src=fs.readFileSync('admin/whatsapp-console.js','utf8');assert.match(src,/\['Contacts','Templates','Campaigns','Automatic Alerts','Reports'\]/);assert.doesNotMatch(src,/innerHTML|graph\.facebook\.com|WHATSAPP_ACCESS_TOKEN/);const build=fs.readFileSync('scripts/build-production-artifact.js','utf8');assert.match(build,/'admin\/whatsapp-console\.js'/);assert.match(build,/'admin\/whatsapp-console\.css'/);});

test('recipient report Excel includes exact text numbers, campaign and canonical delivery timestamps',()=>{const rows=ui.reportExportRows({campaign_name:'Job alert'},[{mobile:'+919876543210',mobile_masked:'+91XXXXXX3210',status:'read',sent_at:'s',delivered_at:'d',read_at:'r'}]);assert.deepEqual(Array.from(rows[0]),['Campaign','WhatsApp Number','Status','Sent','Delivered','Read','Failure']);assert.deepEqual(Array.from(rows[1]),['Job alert','+919876543210','read','s','d','r','']);});

test('approved fresh Hindi summary is selectable and preview uses server-generated canonical job details',()=>{assert.equal(ui.availableTemplate({name:'aadhyant_registered_job_alert_hi_v2',status:'APPROVED',compatible:true,synced_at:new Date().toISOString()}),true);const src=fs.readFileSync('admin/whatsapp-console.js','utf8');assert.match(src,/admin_console_preview_hindi_job_alert/);assert.match(src,/messageCard\(d.template,d.job,d.preview\)/);});
test('Hindi campaigns retain the supported approved summary while replacement approval is pending',()=>{
const fresh=new Date().toISOString();assert.equal(ui.availableTemplate({name:'aadhyant_registered_job_alert_hi_v2',status:'APPROVED',compatible:true,synced_at:fresh}),true);assert.equal(ui.availableTemplate({name:'aadhyant_registered_job_alert_hi_v1',status:'APPROVED',compatible:true,synced_at:fresh}),true);
const src=fs.readFileSync('admin/whatsapp-console.js','utf8');assert.match(src,/admin_console_preview_hindi_contact_alert/);
});

test('manual video preview uses canonical server values and requires a ready reel',()=>{
  const source=fs.readFileSync('admin/whatsapp-console.js','utf8');
  assert.match(source,/admin_console_preview_manual_video/);
  assert.match(source,/if\(!preview\.reel_ready\)/);
});

test('delivery labels never call Sent delivered or leave a finished dispatch marked Queued',()=>{
 assert.equal(ui.deliveryLabel({campaign_status:'queued',delivery:{total:383,delivered:150,awaiting:67,failed:166,pending:0,review:0,not_sent:0}}),'Awaiting delivery');
 assert.equal(ui.deliveryLabel({campaign_status:'queued',delivery:{total:1,delivered:1,awaiting:0,failed:0,pending:0,review:0,not_sent:0}}),'Delivered');
 assert.equal(ui.deliveryLabel({campaign_status:'queued',delivery:{total:1,delivered:0,awaiting:0,failed:1,pending:0,review:0,not_sent:0}}),'Finished with issues');
 assert.equal(ui.failureReason({failure_code:'131048'}),'Meta spam/quality sending limit (131048)');
 assert.match(ui.failureReason({send_phase:'reconciliation_required'}),/review before retrying/);
});

test('campaign choices use the approved Hindi fallback until a fresh compatible replacement is ready',()=>{
 const fresh=new Date().toISOString(), old={id:'old',name:'aadhyant_registered_job_alert_hi_v1',status:'APPROVED',compatible:true,synced_at:fresh}, newer={...old,id:'new',name:'aadhyant_registered_job_alert_hi_v2'};
 const names=rows=>Array.from(ui.campaignTemplates(rows),t=>t.id);
 assert.deepEqual(names([old,{...newer,status:'PENDING'}]),['old']);
 assert.deepEqual(names([old,newer]),['new']);
 assert.deepEqual(names([old,{...newer,compatible:false}]),['old']);
 assert.deepEqual(names([old,{...newer,synced_at:'2000-01-01'}]),['old']);
 assert.deepEqual(names([{...old,status:'PENDING'},{...newer,status:'PENDING'}]),[]);
 assert.equal(ui.availableTemplate({...old,name:'aadhyant_registered_job_alert_v4'}),false);
});
