const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'admin', 'recruitment-operations.js'), 'utf8');
const window = {};
vm.runInNewContext(source, { window, document: {}, crypto: { randomUUID: () => 'correlation' }, Date, String, Array, Object });
const moduleApi = window.aadhyantRecruitmentOperations;

test('W3 navigation exposes the six approved recruitment modules', () => {
  assert.deepEqual(Array.from(moduleApi.definitions, (item) => Array.from(item).slice(0, 2)), [
    ['recruitmentDashboard','Dashboard'],['recruitmentCandidates','Candidates'],
    ['recruitmentRequirements','Requirements'],['recruitmentApplications','Applications'],
    ['recruitmentInterviews','Interviews'],['recruitmentJoinings','Joining / Placement']
  ]);
});

test('recruiter permissions enable candidate, application, and interview controls only', () => {
  const p={candidate_mutation:true,application_mutation:true,interview_mutation:true,joining_mutation:false};
  assert.equal(moduleApi.canMutate('recruitmentCandidates',p),true);
  assert.equal(moduleApi.canMutate('recruitmentApplications',p),true);
  assert.equal(moduleApi.canMutate('recruitmentInterviews',p),true);
  assert.equal(moduleApi.canMutate('recruitmentJoinings',p),false);
});

test('operations permissions enable joining controls only', () => {
  const p={candidate_mutation:false,application_mutation:false,interview_mutation:false,joining_mutation:true};
  assert.equal(moduleApi.canMutate('recruitmentCandidates',p),false);
  assert.equal(moduleApi.canMutate('recruitmentApplications',p),false);
  assert.equal(moduleApi.canMutate('recruitmentInterviews',p),false);
  assert.equal(moduleApi.canMutate('recruitmentJoinings',p),true);
});

test('viewer permissions keep every mutation control unavailable', () => {
  const p={candidate_mutation:false,application_mutation:false,interview_mutation:false,joining_mutation:false};
  ['recruitmentCandidates','recruitmentApplications','recruitmentInterviews','recruitmentJoinings'].forEach((key)=>assert.equal(moduleApi.canMutate(key,p),false));
});

test('browser module uses only projected W3 RPCs, never direct tables', () => {
  assert.doesNotMatch(source,/\.from\s*\(/);
  ['get_recruitment_permissions','list_recruitment_candidates','list_recruitment_requirements','list_recruitment_applications','list_recruitment_interviews','list_recruitment_joinings'].forEach((rpc)=>assert.match(source,new RegExp(rpc)));
});

test('operations UI includes a selected-application joining action', () => {
  assert.match(source,/Start Joining/);
  assert.match(source,/upsert_recruitment_joining/);
  assert.match(source,/permissions\.joining_mutation/);
});
