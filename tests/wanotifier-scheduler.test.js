'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {run}=require('../scripts/whatsapp/run-wanotifier-alerts.cjs');
const env={WANOTIFIER_SCHEDULER_ENABLED:'true',WANOTIFIER_INTERVIEWS_ENABLED:'true',WANOTIFIER_REGISTERED_ALERTS_ENABLED:'true',GITHUB_REPOSITORY:'aadhyantmanpowerstaffing-collab/aadhyant-manpower',GITHUB_REF:'refs/heads/main',GITHUB_EVENT_NAME:'schedule',WANOTIFIER_SCHEDULER_APPROVED_SHA:'a'.repeat(40),CHECKED_OUT_SHA:'a'.repeat(40),WHATSAPP_WORKER_SECRET:'b'.repeat(64)};
test('scheduler is installation-locked and rejects unreviewed source, unexpected branch/event or missing credentials',async()=>{
 const workflow=fs.readFileSync('.github/workflows/wanotifier-approved-queue.yml','utf8');assert.match(workflow,/false &&/);assert.match(workflow,/persist-credentials: false/);
 let calls=0;for(const patch of [{WANOTIFIER_SCHEDULER_ENABLED:'false'},{CHECKED_OUT_SHA:'c'.repeat(40)},{GITHUB_REF:'refs/heads/other'},{GITHUB_EVENT_NAME:'workflow_dispatch'},{WHATSAPP_WORKER_SECRET:''},{WANOTIFIER_INTERVIEWS_ENABLED:'false',WANOTIFIER_REGISTERED_ALERTS_ENABLED:'false'}])await assert.rejects(()=>run({...env,...patch},async()=>{calls++;throw Error('No network expected');}));assert.equal(calls,0);
});
test('scheduler sends only fixed notification kinds to the pinned worker and returns safe counts',async()=>{
 const calls=[];const result=await run(env,async(url,init)=>{calls.push({url,init});return Response.json({processed:1,sent:1,blocked:0,reconciliation_required:0});});
 assert.deepEqual(Object.keys(result),['interviews','registered_alerts']);assert.equal(calls.length,2);
 assert.ok(calls.every(c=>c.url==='https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/wanotifier-outbox-worker'&&c.init.redirect==='error'));
 assert.deepEqual(calls.map(c=>JSON.parse(c.init.body)),[{kind:'interviews'},{kind:'registered_alerts'}]);assert.ok(!JSON.stringify(result).includes(env.WHATSAPP_WORKER_SECRET));
});
test('scheduler never retries a network timeout or leaks credentials from thrown network errors',async()=>{
 let calls=0;await assert.rejects(()=>run(env,async()=>{calls++;throw Error(env.WHATSAPP_WORKER_SECRET);}),error=>!error.message.includes(env.WHATSAPP_WORKER_SECRET));assert.equal(calls,1);
});
test('uncertain results stop the current run before the next kind, without resend or invented success',async()=>{
 let calls=0;await assert.rejects(()=>run(env,async()=>{calls++;return Response.json({processed:1,sent:0,blocked:0,reconciliation_required:1});}),/Review message results/);assert.equal(calls,1);
 for(const result of [{processed:1,sent:0,blocked:0,reconciliation_required:0},{processed:11,sent:11,blocked:0,reconciliation_required:0},{processed:0,sent:-1,blocked:1,reconciliation_required:0}])await assert.rejects(()=>run(env,async()=>Response.json(result)),/result unconfirmed/);
});
