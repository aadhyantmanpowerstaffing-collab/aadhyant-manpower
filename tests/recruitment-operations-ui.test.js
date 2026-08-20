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

test('candidate matching uses an accessible picker instead of UUID entry', () => {
  assert.doesNotMatch(source, /Candidate UUID to match|prompt\([^)]*UUID/i);
  assert.match(source, /candidate-picker-dialog/);
  assert.match(source, /dialog\.showModal\(\)/);
  assert.match(source, /Search candidates/);
  assert.doesNotMatch(source, /name=['"]candidateId|type=['"]text['"][^>]*candidate.*id/i);
});

test('candidate picker searches through the projected W3 candidate RPC', () => {
  assert.deepEqual({ ...moduleApi.candidateSearchArgs('  W3 Candidate  ') }, {
    p_search: 'W3 Candidate', p_status: null, p_limit: 50, p_offset: 0
  });
  assert.match(source, /list_recruitment_candidates',candidateSearchArgs/);
  assert.doesNotMatch(source, /\.from\s*\(/);
});

test('only open requirements and eligible candidates are actionable', () => {
  assert.equal(moduleApi.isRequirementMatchable({ requirement_stage: 'open' }), true);
  ['draft','closed','filled','cancelled','on_hold'].forEach((stage) => assert.equal(moduleApi.isRequirementMatchable({ requirement_stage: stage }), false));
  assert.equal(moduleApi.isCandidateMatchable({ status: 'new' }), true);
  assert.equal(moduleApi.isCandidateMatchable({ status: 'active' }), true);
  assert.equal(moduleApi.isCandidateMatchable({ status: 'inactive' }), false);
  assert.equal(moduleApi.canMatchRequirement({ requirement_stage: 'open' }, { application_mutation: true }), true);
  assert.equal(moduleApi.canMatchRequirement({ requirement_stage: 'open' }, { application_mutation: false }), false);
  assert.equal(moduleApi.canMatchRequirement({ requirement_stage: 'draft' }, { application_mutation: true }), false);
  assert.match(source, /canMatchRequirement\(row,permissions\)/);
});

test('matching confirmation uses the existing application RPC and refreshes the requirement list', () => {
  assert.match(source, /Confirm Match/);
  assert.match(source, /create_recruitment_application/);
  assert.match(source, /p_candidate_id:selected\.id/);
  assert.match(source, /p_requirement_id:requirement\.id/);
  assert.match(source, /if\(matched\)\{await load\(\)/);
  assert.match(source, /Applications and Dashboard will refresh when opened/);
});

test('candidate picker maps duplicate, eligibility, requirement, authorization, and network errors', () => {
  assert.match(moduleApi.friendlyMatchError({ message: 'Candidate already has an application for this requirement' }), /already matched/i);
  assert.match(moduleApi.friendlyMatchError({ message: 'Active candidate was not found' }), /no longer eligible/i);
  assert.match(moduleApi.friendlyMatchError({ message: 'Open requirement was not found' }), /no longer open/i);
  assert.match(moduleApi.friendlyMatchError({ message: 'Application management access is required' }), /not authorized/i);
  assert.match(moduleApi.friendlyMatchError({ message: 'Failed to fetch' }), /connection/i);
});

test('application stages use a controlled transition dialog without free-text stage entry', () => {
  assert.doesNotMatch(source, /Enter validated next stage|prompt\([^)]*(?:stage|Current:)/i);
  assert.match(source, /application-transition-dialog/);
  assert.match(source, /Current stage/);
  assert.match(source, /Confirm Change/);
});

test('application transition graph exactly mirrors migration 018 generic transitions', () => {
  const graph=JSON.parse(JSON.stringify(moduleApi.applicationTransitionGraph));
  assert.deepEqual(Object.fromEntries(Object.entries(graph).map(([stage,items])=>[stage,items.map((item)=>item.value)])), {
    interested:['applied'],applied:['screening'],screening:['shortlisted'],shortlisted:['interview'],interview:['selected','rejected'],selected:['rejected']
  });
  ['rejected','joining_pending','joined','left'].forEach((stage)=>assert.deepEqual(Array.from(moduleApi.getApplicationTransitions(stage)),[]));
});

test('transition action follows application permission and terminal-stage rules', () => {
  const recruiter={application_mutation:true};const viewer={application_mutation:false};
  assert.equal(moduleApi.canTransitionApplication({application_status:'applied'},recruiter),true);
  assert.equal(moduleApi.canTransitionApplication({application_status:'applied'},viewer),false);
  assert.equal(moduleApi.canTransitionApplication({application_status:'rejected'},recruiter),false);
  assert.equal(moduleApi.canTransitionApplication({application_status:'joining_pending'},recruiter),false);
  assert.match(source,/No further stage changes are available/);
});

test('transition confirmation uses only the existing W3 RPC and refreshes applications', () => {
  assert.match(source,/transition_recruitment_application/);
  assert.match(source,/p_to_stage:select\.value/);
  assert.match(source,/transitions\.some\(\(item\)=>item\.value===select\.value\)/);
  assert.match(source,/if\(changed\)\{await load\(\)/);
  assert.match(source,/Dashboard will refresh when opened/);
  assert.match(source,/cancel\.addEventListener\('click',\(\)=>finish\(false\)\)/);
});

test('transition dialog maps stale, authorization, missing, validation, and server errors', () => {
  assert.match(moduleApi.friendlyTransitionError({message:'Unsupported application stage transition'}),/changed elsewhere/i);
  assert.match(moduleApi.friendlyTransitionError({message:'Application management access is required'}),/not authorized/i);
  assert.match(moduleApi.friendlyTransitionError({message:'Application was not found'}),/no longer available/i);
  assert.match(moduleApi.friendlyTransitionError({message:'Application note is too long'}),/too long/i);
  assert.match(moduleApi.friendlyTransitionError({message:'Failed to fetch'}),/connection/i);
});
