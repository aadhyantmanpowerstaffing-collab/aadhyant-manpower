const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const source = fs.readFileSync(path.join(__dirname, '..', 'admin', 'recruitment-operations.js'), 'utf8');
const adminSource = fs.readFileSync(path.join(__dirname, '..', 'admin', 'admin.js'), 'utf8');
const adminHtml = fs.readFileSync(path.join(__dirname, '..', 'admin', 'index.html'), 'utf8');
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

test('interview scheduling uses date and time controls without ISO or mode prompts', () => {
  assert.doesNotMatch(source,/Interview date\/time \(ISO 8601\)|prompt\([^)]*(?:Interview date|Mode: onsite)/i);
  assert.match(source,/date\.type='date'/);
  assert.match(source,/time\.type='time'/);
  assert.match(source,/mode\.name='interviewMode'/);
  ['onsite','phone','video','other'].forEach((mode)=>assert.match(source,new RegExp(`\\['${mode}'`)));
});

test('local interview date and time are converted internally to an RPC timestamp', () => {
  const timestamp=moduleApi.localInterviewTimestamp('2030-06-15','14:30');
  assert.equal(new Date(timestamp).getTime(),new Date('2030-06-15T14:30').getTime());
  assert.equal(moduleApi.localInterviewTimestamp('','14:30'),null);
  assert.equal(moduleApi.localInterviewTimestamp('2030-06-15',''),null);
  assert.equal(moduleApi.localInterviewTimestamp('invalid','14:30'),null);
  assert.match(source,/new Date\(timestamp\)\.getTime\(\)<=Date\.now\(\)/);
});

test('schedule action follows interview permission and application eligibility', () => {
  const recruiter={interview_mutation:true};const viewer={interview_mutation:false};
  ['interested','applied','screening','shortlisted','interview'].forEach((stage)=>assert.equal(moduleApi.canScheduleInterview({application_status:stage},recruiter),true));
  ['selected','rejected','joining_pending','joined','left'].forEach((stage)=>assert.equal(moduleApi.canScheduleInterview({application_status:stage},recruiter),false));
  assert.equal(moduleApi.canScheduleInterview({application_status:'screening'},viewer),false);
  assert.match(source,/canScheduleInterview\(row,permissions\)/);
});

test('schedule modal validates fields, checks current interview, and requires confirmation', () => {
  assert.match(source,/A current interview is already scheduled/);
  assert.match(source,/interview\.status==='scheduled'/);
  assert.match(source,/mode\.value==='onsite'&&!location\.value\.trim\(\)/);
  assert.match(source,/Confirm Schedule/);
  assert.match(source,/Review interview schedule/);
  assert.match(source,/cancel\.addEventListener\('click',\(\)=>finish\(false\)\)/);
});

test('schedule confirmation calls the existing RPC and refreshes related modules', () => {
  assert.match(source,/schedule_recruitment_interview/);
  assert.match(source,/p_scheduled_at:timestamp/);
  assert.match(source,/p_mode:mode\.value/);
  assert.match(source,/p_location:location\.value\.trim\(\)\|\|null/);
  assert.match(source,/p_instructions:instructions\.value\.trim\(\)\|\|null/);
  assert.match(source,/if\(scheduled\)\{await load\(\)/);
  assert.match(source,/Interviews and Dashboard will refresh when opened/);
});

test('schedule errors are business-friendly', () => {
  assert.match(moduleApi.friendlyScheduleError({message:'A current interview is already scheduled'}),/already scheduled/i);
  assert.match(moduleApi.friendlyScheduleError({message:'Application is not eligible for interview scheduling'}),/no longer eligible/i);
  assert.match(moduleApi.friendlyScheduleError({message:'Interview management access is required'}),/not authorized/i);
  assert.match(moduleApi.friendlyScheduleError({message:'Valid future interview details are required'}),/valid future/i);
  assert.match(moduleApi.friendlyScheduleError({message:'Application was not found'}),/no longer available/i);
  assert.match(moduleApi.friendlyScheduleError({message:'Failed to fetch'}),/connection/i);
});

test('interview management replaces raw status, result, and reschedule prompts', () => {
  assert.doesNotMatch(source,/prompt\([^)]*(?:Interview status|Result: pending|reschedul|ISO 8601)/i);
  assert.match(source,/interview-management-dialog/);
  assert.match(source,/Manage Interview/);
  assert.match(source,/Reschedule Interview/);
  assert.match(source,/Record Completed Outcome/);
  assert.match(source,/Cancel Interview/);
});

test('scheduled and attended interviews expose only supported management states', () => {
  const manager={interview_mutation:true};const viewer={interview_mutation:false};
  assert.equal(moduleApi.canManageInterview({status:'scheduled'},manager),true);
  assert.equal(moduleApi.canManageInterview({status:'attended'},manager),true);
  ['completed','absent','cancelled','rescheduled'].forEach((status)=>assert.equal(moduleApi.canManageInterview({status},manager),false));
  assert.equal(moduleApi.canManageInterview({status:'scheduled'},viewer),false);
  assert.deepEqual(Array.from(moduleApi.interviewFinalStatuses),['completed','absent','cancelled','rescheduled']);
});

test('interview outcome choices exactly match the W3 backend vocabulary', () => {
  assert.deepEqual(JSON.parse(JSON.stringify(moduleApi.interviewResultChoices)),[
    {value:'pending',label:'Pending Decision'},{value:'selected',label:'Selected'},
    {value:'rejected',label:'Rejected'},{value:'on_hold',label:'On Hold'}
  ]);
  assert.match(source,/submitUpdate\('completed',result\.value/);
  assert.match(source,/renderSimpleConfirmation\('cancelled','Cancel Interview'\)/);
  assert.doesNotMatch(source,/submitUpdate\('(?:scheduled|rescheduled)'/);
});

test('reschedule uses business controls, internal timestamp conversion, and confirmation', () => {
  assert.match(source,/date\.type='date'/);
  assert.match(source,/time\.type='time'/);
  assert.match(source,/Confirm Reschedule/);
  assert.match(source,/Old schedule:/);
  assert.match(source,/New schedule:/);
  assert.match(source,/reschedule_recruitment_interview/);
  assert.match(source,/p_scheduled_at:timestamp/);
  assert.match(source,/p_mode:mode\.value/);
});

test('cancellation and completion require explicit confirmation without internal identifiers', () => {
  assert.match(source,/`Confirm \$\{label\}`/);
  assert.match(source,/renderSimpleConfirmation\('cancelled','Cancel Interview'\)/);
  assert.match(source,/Confirm Completed Outcome/);
  assert.match(source,/cancel\.addEventListener\('click',back\)/);
  assert.doesNotMatch(source,/Interview UUID|Application UUID|name=['"]interviewId/i);
});

test('finalized interviews are non-actionable and refresh messages cover related modules', () => {
  assert.match(source,/Interview finalized\. No further changes are available/);
  assert.match(source,/if\(changed\)\{await load\(\)/);
  assert.match(source,/Applications and Dashboard will refresh when opened/);
  assert.match(source,/canManageInterview\(row,permissions\)/);
});

test('interview management maps stale, finalized, conflict, authorization, validation, and network errors', () => {
  assert.match(moduleApi.friendlyInterviewError({message:'Interview outcome is already final'}),/already finalized/i);
  assert.match(moduleApi.friendlyInterviewError({message:'A scheduled interview was not found'}),/changed elsewhere/i);
  assert.match(moduleApi.friendlyInterviewError({message:'Interview rescheduling conflicted with another update'}),/conflicted/i);
  assert.match(moduleApi.friendlyInterviewError({message:'Interview management access is required'}),/not authorized/i);
  assert.match(moduleApi.friendlyInterviewError({message:'Completed interview requires a result'}),/not valid/i);
  assert.match(moduleApi.friendlyInterviewError({message:'Failed to fetch'}),/connection/i);
});

test('joining workflow removes raw prompts and uses date controls with confirmation', () => {
  assert.doesNotMatch(source,/Expected joining date \(YYYY-MM-DD\)|Joining status: pending/);
  assert.match(source,/expected\.type='date'/);
  assert.match(source,/input\.name='actualJoiningDate'/);
  assert.match(source,/input\.type='date'/);
  assert.match(source,/Confirm Start Joining/);
  assert.match(source,/Review joining setup/);
  assert.match(source,/Resulting state: Joining Pending/);
  assert.match(source,/cancel\.addEventListener\('click',\(\)=>finish\(false\)\)/);
});

test('joining actions are constrained by the backend state machine', () => {
  assert.equal(JSON.stringify(moduleApi.getJoiningActions('pending').map(({value})=>value)),JSON.stringify(['update_expected','confirmed','joined','no_show','deferred','cancelled']));
  assert.equal(JSON.stringify(moduleApi.getJoiningActions('confirmed').map(({value})=>value)),JSON.stringify(['update_expected','joined','no_show','deferred','cancelled']));
  assert.equal(JSON.stringify(moduleApi.getJoiningActions('deferred').map(({value})=>value)),JSON.stringify(['update_expected','confirmed','joined','no_show','cancelled']));
  assert.equal(JSON.stringify(moduleApi.getJoiningActions('joined').map(({value})=>value)),JSON.stringify(['left']));
  for (const status of ['left','no_show','cancelled']) assert.equal(moduleApi.getJoiningActions(status).length,0);
  assert.match(source,/Joining workflow finalized\. No further changes are available/);
});

test('joining permissions expose management only to approved roles', () => {
  const manager={joining_mutation:true};
  const readOnly={joining_mutation:false};
  assert.equal(moduleApi.canStartJoining({application_status:'selected'},manager),true);
  assert.equal(moduleApi.canStartJoining({application_status:'interview'},manager),false);
  assert.equal(moduleApi.canStartJoining({application_status:'selected'},readOnly),false);
  assert.equal(moduleApi.canManageJoining({joining_status:'confirmed'},manager),true);
  assert.equal(moduleApi.canManageJoining({joining_status:'confirmed'},readOnly),false);
  assert.equal(moduleApi.canManageJoining({joining_status:'left'},manager),false);
});

test('joining dialogs use only the existing RPC and preserve server synchronization', () => {
  assert.match(source,/call\(client,'upsert_recruitment_joining',joiningRpcArgs/);
  assert.doesNotMatch(source,/client\.from\(['"]candidate_joinings|client\.from\(['"]candidate_applications/);
  assert.match(source,/p_application_id:row\.application_id\|\|row\.id/);
  assert.match(source,/const nextStatus=action\.value==='update_expected'\?joining\.joining_status:action\.value/);
  assert.doesNotMatch(source,/joining_pending.*transition_recruitment_application|transition_recruitment_application.*joining_pending/);
});

test('mark joined requires an actual date and joined can only move to left', () => {
  assert.match(source,/action\.value==='joined'&&!actualDate/);
  assert.match(source,/Enter the candidate\\'s actual joining date/);
  assert.equal(JSON.stringify(moduleApi.getJoiningActions('joined')),JSON.stringify([{value:'left',label:'Mark Left'}]));
  assert.match(source,/joiningRpcArgs\(joining,status,expectedDate,actualDate\)/);
});

test('joining errors are business-facing and success refreshes related workspaces', () => {
  assert.match(moduleApi.friendlyJoiningError({message:'new joining requires a selected application'}),/no longer selected|already exists/i);
  assert.match(moduleApi.friendlyJoiningError({message:'joined status requires an actual joining date'}),/actual joining date/i);
  assert.match(moduleApi.friendlyJoiningError({message:'terminal joining status cannot change'}),/already final/i);
  assert.match(moduleApi.friendlyJoiningError({message:'joining management access is required'}),/not authorized/i);
  assert.match(moduleApi.friendlyJoiningError({message:'Failed to fetch'}),/connection/i);
  assert.match(source,/Joining \/ Placement refreshed; Applications, Dashboard, and Candidate context will refresh when opened/);
  assert.match(source,/Joining started\. Applications refreshed; Joining \/ Placement, Dashboard, and Candidate context will refresh when opened/);
});

test('joining UI does not present UUIDs or candidate contact PII', () => {
  assert.doesNotMatch(source,/Application UUID|Candidate UUID|name=['"]applicationId/i);
  const joiningSection=source.slice(source.indexOf('const joiningActionGraph'),source.indexOf('const renderDashboard'));
  assert.doesNotMatch(joiningSection,/mobile|phone|whatsapp|email/i);
  assert.match(joiningSection,/Candidate.*Requirement.*Company/);
});

test('candidate update uses constrained business controls instead of prompts', () => {
  assert.doesNotMatch(source,/prompt\(['"]Candidate status|prompt\(['"]Interview available/i);
  assert.equal(JSON.stringify(moduleApi.candidateStatusChoices),JSON.stringify(['new','contacted','shortlisted','interview','selected','joined','inactive']));
  assert.equal(JSON.stringify(moduleApi.candidateAvailabilityChoices),JSON.stringify(['Yes','No']));
  assert.match(source,/candidate-update-dialog/);
  assert.match(source,/Internal operational note/);
  assert.match(source,/Confirm Update/);
  assert.match(source,/cancel\.addEventListener\('click',\(\)=>finish\(false\)\)/);
});

test('candidate update reuses the projected detail and mutation RPCs with permission-gated controls', () => {
  const updateSection=source.slice(source.indexOf('const openCandidateUpdate'),source.indexOf('const formatDateTime'));
  assert.match(source,/get_recruitment_candidate'.*p_candidate_id:candidate\.id/);
  assert.match(source,/update_recruitment_candidate'.*p_status:status\.value.*p_interview_available:availability\.value.*p_internal_notes:notes\.value/);
  assert.match(source,/key==='recruitmentCandidates'&&canMutate\(key,permissions\)/);
  assert.doesNotMatch(source,/\.from\s*\(/);
  assert.doesNotMatch(updateSection,/Auth|auth_user|whatsapp_number|mobile|phone/i);
});

test('candidate update errors are business-facing', () => {
  assert.match(moduleApi.friendlyCandidateUpdateError({message:'Unsupported candidate workflow value'}),/changed elsewhere/i);
  assert.match(moduleApi.friendlyCandidateUpdateError({message:'Candidate note is too long'}),/too long/i);
  assert.match(moduleApi.friendlyCandidateUpdateError({message:'Candidate management access is required'}),/not authorized/i);
  assert.match(moduleApi.friendlyCandidateUpdateError({message:'Candidate was not found'}),/no longer available/i);
  assert.match(moduleApi.friendlyCandidateUpdateError({message:'Failed to fetch'}),/connection/i);
});

test('application view uses a projected read-only modal instead of an alert summary', () => {
  assert.match(source,/application-detail-dialog/);
  assert.match(source,/get_recruitment_application'.*p_application_id:application\.id/);
  assert.match(source,/Application Detail/);
  assert.match(source,/Current stage/);
  assert.match(source,/Stage History/);
  assert.match(source,/Interview History/);
  assert.match(source,/detail\.stage_history\|\|\[\]/);
  assert.doesNotMatch(source,/History: \$\{detail\.stage_history|if \(key === 'recruitmentApplications'\).*window\.alert/);
});

test('application detail remains read-only and excludes internal identifiers', () => {
  const detailSection=source.slice(source.indexOf('const openApplicationDetail'),source.indexOf('const viewRecord'));
  assert.doesNotMatch(detailSection,/Confirm|Save|p_to_stage|transition_recruitment_application|update_recruitment/);
  assert.doesNotMatch(detailSection,/make\(['"][^'"]+['"],[^\n]*['"](?:Application|Candidate|Requirement) (?:UUID|ID)['"]|detail\.(?:id|candidate_id|requirement_id)/i);
  assert.match(detailSection,/Close application detail/);
  assert.match(detailSection,/Applied.*Last updated/);
});

test('W3 tab activation hides every unrelated legacy and W3 panel', () => {
  assert.match(source,/querySelectorAll\('\[data-panel\]'\).*panel\.hidden=panel!==item\.panel/);
  assert.match(source,/querySelectorAll\('\[data-tab\],\[data-w3-tab\]'\)/);
  for (const key of ['recruitmentCandidates','recruitmentApplications','recruitmentInterviews','recruitmentJoinings']) assert.match(source,new RegExp(key));
  assert.match(adminHtml,/data-panel="employers"/);
  assert.match(adminHtml,/data-panel="candidates"/);
});

test('legacy tab activation clears W3 selection and shows only its own legacy panel', () => {
  assert.match(adminSource,/querySelectorAll\('\[data-tab\],\[data-w3-tab\]'\)/);
  assert.match(adminSource,/panel\.hidden = panel\.dataset\.panel !== tab\.dataset\.tab/);
  for (const label of ['Employer Requirements','Candidate Interests','Company Accounts','Company Requirements','Staffing Partners']) assert.match(adminHtml,new RegExp(label));
});

test('W3 missing values use a UTF-8-safe em dash without mojibake', () => {
  assert.equal(moduleApi.displayValue(null),'—');
  assert.equal(moduleApi.displayValue(undefined),'—');
  assert.equal(moduleApi.displayValue(''),'—');
  assert.equal(moduleApi.displayValue('Joined'),'Joined');
  assert.doesNotMatch(source,/â€“|â€”|â€¦|Ã—/);
  assert.match(source,/displayValue\(value\)/);
});

test('candidate view uses an accessible projected detail modal instead of alert', () => {
  assert.doesNotMatch(source,/window\.alert|alert\s*\(/);
  assert.match(source,/candidate-detail-dialog/);
  assert.match(source,/aria-labelledby','candidate-detail-title/);
  assert.match(source,/get_recruitment_candidate'.*p_candidate_id:candidate\.id/);
  assert.match(source,/if \(key === 'recruitmentCandidates'\) await openCandidateDetail/);
  assert.match(source,/Close candidate detail/);
});

test('candidate detail renders projected core fields and related histories', () => {
  const detailSection=source.slice(source.indexOf('const openCandidateDetail'),source.indexOf('const openApplicationDetail'));
  for (const label of ['Candidate','Location','District','State','Qualification','Trade / specialization','Candidate type','Status','Interview availability']) assert.match(detailSection,new RegExp(label));
  assert.match(detailSection,/Application History/);
  assert.match(detailSection,/Interview History/);
  assert.match(detailSection,/detail\.applications\|\|\[\]/);
  assert.match(detailSection,/detail\.interviews\|\|\[\]/);
  assert.match(detailSection,/Requirement.*Company.*Role.*Stage.*Applied/);
  assert.match(detailSection,/Scheduled.*Mode.*Status.*Result/);
});

test('candidate detail preserves projected PII and internal-note suppression', () => {
  const detailSection=source.slice(source.indexOf('const openCandidateDetail'),source.indexOf('const openApplicationDetail'));
  assert.match(detailSection,/if\(detail\.mobile\|\|detail\.whatsapp_number\)/);
  assert.match(detailSection,/if\(detail\.mobile\)/);
  assert.match(detailSection,/if\(detail\.whatsapp_number\)/);
  assert.match(detailSection,/detail\.internal_notes!==null&&detail\.internal_notes!==undefined/);
  assert.match(detailSection,/Contact details are not available for this view/);
  assert.doesNotMatch(detailSection,/email|auth_user|Auth linkage/i);
});

test('candidate detail has safe empty states and no identifier presentation', () => {
  const detailSection=source.slice(source.indexOf('const openCandidateDetail'),source.indexOf('const openApplicationDetail'));
  assert.match(detailSection,/No applications yet\./);
  assert.match(detailSection,/No interviews yet\./);
  assert.doesNotMatch(detailSection,/make\(['"][^'"]+['"],[^\n]*['"](?:Candidate|Application|Requirement) (?:UUID|ID)['"]|detail\.(?:id|candidate_id|application_id|requirement_id)/i);
  assert.doesNotMatch(detailSection,/\.from\s*\(/);
  assert.match(detailSection,/returnFocus\?\.focus\?\.\(\)/);
});
