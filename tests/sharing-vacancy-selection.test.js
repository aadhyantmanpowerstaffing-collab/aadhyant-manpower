'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const window={};vm.runInNewContext(fs.readFileSync(require('node:path').join(__dirname,'../admin/sharing-contacts.js'),'utf8'),{window});
const select=window.AadhyantSharingContacts.selectPublishedVacancies;
test('published vacancies resolve to canonical Admin IDs without an unprojected visibility field',()=>{
 const admin=[{id:'canonical-id',requirement_code:'JOB_1',requirement_stage:'open',job_role:'Fitter'},{id:'private-id',requirement_code:'JOB_2',requirement_stage:'open'}];
 const out=select(admin,[{requirement_code:'JOB_1',job_role:'Fitter'}]);assert.equal(out.length,1);assert.equal(out[0],admin[0]);
});
test('unknown/closed vacancies and missing canonical IDs cannot be selected',()=>{
 const out=select([{id:'closed',requirement_code:'JOB_1',requirement_stage:'closed'},{requirement_code:'JOB_2',requirement_stage:'open'}],[{requirement_code:'JOB_1'},{requirement_code:'JOB_2'},{requirement_code:'UNKNOWN'}]);assert.equal(out.length,0);
});
