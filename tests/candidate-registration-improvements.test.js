const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');

const root=path.resolve(__dirname,'..');
const read=file=>fs.readFileSync(path.join(root,...file),'utf8');
const onboarding=read(['candidate','portal','onboarding.html']);
const registration=read(['candidate','portal','register.html']);
const documents=read(['candidate','portal','documents.html']);
const candidate=read(['candidate','portal','candidate.js']);
const migration=read(['supabase','migrations','023_candidate_portal_foundation.sql']);
const apply=read(['supabase','migrations','042_fix_candidate_apply_ambiguity.sql']);
const login=read(['candidate','portal','login.html']);
const mapper=(name,next)=>vm.runInNewContext(`(${candidate.slice(candidate.indexOf(`function ${name}`),candidate.indexOf(next,candidate.indexOf(`function ${name}`)))})`);

test('registration collects a required canonical Resume/CV before profile submission',()=>{
  assert.match(onboarding,/Personal Details · Location · Education · Experience · Resume\/CV · Review/);
  assert.match(onboarding,/name="resume"[^>]*type="file"[^>]*required/);
  assert.match(onboarding,/accept="\.pdf,application\/pdf"/);
  assert.match(onboarding,/Required to complete Candidate registration\. Upload a PDF up to 10 MB\./);
  assert.match(onboarding,/data-resume-file-name[^>]*aria-live="polite"/);
  assert.match(onboarding,/data-resume-upload-state[^>]*aria-live="polite"/);
  assert.ok(onboarding.indexOf('<legend>Resume / CV</legend>')<onboarding.indexOf('<legend>Review / Create Profile</legend>'));
});

test('Resume uses the existing private document contract only after canonical profile creation',()=>{
  const create=candidate.indexOf('await call(rpc.create');
  const update=candidate.indexOf('await call(rpc.update,a)',create);
  const upload=candidate.indexOf("await uploadCandidateDocument(file,'resume')",update);
  assert.ok(create>=0&&update>create&&upload>update);
  assert.match(candidate,/client\.storage\.from\('candidate-private'\)\.upload/);
  assert.match(candidate,/p_document_type:type/);
  assert.match(candidate,/p_storage_object_name:object/);
  assert.match(candidate,/p_display_file_name:file\.name\.replace/);
  assert.doesNotMatch(candidate,/\.from\s*\(\s*['"](?:candidates|candidate_documents)['"]/);
  assert.match(migration,/create function public\.register_candidate_document/);
  assert.match(migration,/p_document_type='resume' and p_mime_type<>'application\/pdf'/);
  assert.match(migration,/candidate-private','candidate-private',false,10485760/);
});

test('Resume validation and upload failure preserve a recoverable non-duplicate profile state',()=>{
  assert.match(candidate,/function resumeValidation\(file\)/);
  assert.match(candidate,/Upload your Resume\/CV to complete registration\./);
  assert.match(candidate,/Choose a Resume\/CV PDF file\./);
  assert.match(candidate,/no larger than 10 MB/);
  assert.match(candidate,/let profileCreated=false/);
  assert.match(candidate,/showExistingCandidateAccount\(\{resumePending:true\}\)/);
  assert.match(candidate,/Your Candidate profile is saved\. Upload your Resume\/CV to complete your Candidate registration\./);
  assert.match(candidate,/Upload Resume \/ CV/);
  assert.match(candidate,/documents\.html/);
});

test('existing authenticated accounts are resolved server-side without unauthenticated email enumeration',()=>{
  for(const page of [registration,onboarding]){
    assert.match(page,/Your Candidate account already exists\./);
    assert.match(page,/Go to Candidate Portal/);
    assert.match(page,/Sign In/);
    assert.match(page,/Forgot Password/);
  }
  assert.match(candidate,/async function routeAuthenticatedCandidate/);
  assert.match(candidate,/await call\(rpc\.context\)/);
  assert.match(candidate,/await call\(rpc\.eligibility\)/);
  assert.match(candidate,/registrationSessionState\(\)/);
  assert.doesNotMatch(candidate,/from\s*\(\s*['"]auth\.users/);
  assert.doesNotMatch(candidate,/check.*email.*exist|email.*exist.*check/i);
});

test('safe actionable registration and document errors do not render raw backend details',()=>{
  ['A Candidate profile already exists for this account.','This mobile number or Aadhaar number is already linked to another Candidate profile.','Your session has expired. Please sign in again.','Your Resume could not be uploaded. Please try again.','Your Candidate profile could not be created. Review the details and try again.'].forEach(copy=>assert.match(candidate,new RegExp(copy.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))));
  assert.match(candidate,/button\.disabled=true/);
  assert.match(candidate,/finally\{button\.disabled=false\}/);
  assert.doesNotMatch(candidate,/message\(\s*(?:error|_error)\?\.message/);
  assert.doesNotMatch(candidate,/message\(\s*(?:error|_error)\.message/);
  assert.doesNotMatch(candidate,/event\.reason\?\.message/);
});

test('Step 1 maps Auth signup failures without Candidate-profile wording or raw Auth details',()=>{
  const signupError=mapper('signupError','function registrationError');
  assert.equal(signupError({status:429,code:'over_email_send_rate_limit',message:'raw upstream rate limit detail'}),'Too many attempts. Please wait and try again.');
  assert.equal(signupError({code:'email_address_invalid',message:'raw email validation detail'}),'Enter a valid email address.');
  assert.equal(signupError({code:'weak_password',message:'raw password policy detail'}),'Choose a stronger password of at least 10 characters.');
  assert.equal(signupError({message:'Failed to fetch internal endpoint'}),'We could not create your account securely. Please try again.');
  assert.equal(signupError({code:'unexpected_failure',message:'raw Supabase internal detail'}),'Your account could not be created. Please try again or contact Aadhyant.');
  assert.doesNotMatch(signupError({message:'raw Supabase internal detail'}),/Candidate profile|raw Supabase/i);
  assert.match(candidate,/catch\(error\)\{message\(signupError\(error\),'error'\)\}/);
  assert.match(candidate,/if\(!client\?\.auth\?\.signUp\)\{message\('We could not create your account securely\. Please try again\.'/);
});

test('Step 1 uses identical neutral session-null signup wording and persistent account actions',()=>{
  const neutral='Check your email for the next step. If you already have an account, sign in instead.';
  assert.match(candidate,new RegExp(`data\\.session\\?'Account created\\. Continue to required profile setup\\.'\\s*:\\s*'${neutral.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')}'`));
  assert.equal((candidate.match(new RegExp(neutral.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'),'g'))||[]).length,1);
  assert.doesNotMatch(candidate,/Check your email to confirm the account, then sign in to complete your profile\./);
  assert.match(registration,/data-registration-account-actions/);
  assert.match(registration,/Already registered\?\s*<a href="login\.html">Sign In<\/a>/);
  assert.match(registration,/<a href="login\.html">Forgot Password<\/a>/);
  assert.doesNotMatch(registration,/<[^>]+data-registration-account-actions[^>]*hidden/);
  assert.match(candidate,/emailRedirectTo:new URL\(withRequirement\('onboarding\.html'\),location\.href\)\.href/);
  assert.match(candidate,/function registrationError\(error\)/);
  assert.match(candidate,/else message\(registrationError\(error\),'error'\)/);
  assert.doesNotMatch(candidate,/auth\.users|check.*email.*exist|email.*exist.*check/i);
});

test('Documents remains the canonical Resume surface and Apply still requires an active Resume',()=>{
  assert.match(documents,/<option value="resume">Resume \/ CV<\/option>/);
  assert.match(candidate,/type==='resume'&&resumeValidation\(file\)/);
  assert.match(candidate,/Resume\/CV uploaded for secure review\./);
  assert.match(apply,/d\.candidate_id=v_candidate_id/);
  assert.match(apply,/d\.document_type='resume'/);
  assert.match(apply,/d\.active/);
});

test('Candidate password recovery remains isolated from registration improvements',()=>{
  assert.match(login,/data-password-recovery-portal="candidate"/);
  assert.match(login,/data-recovery-set-password/);
  assert.match(login,/This password reset link has expired or was already used\./);
  assert.doesNotMatch(candidate,/service_role|SUPABASE_SERVICE/i);
});

test('profile reports STOP separately after a confirmed profile save, retains entries and allows No retry',async()=>{
 const button={disabled:false},fields={aadhaar:{value:''},immediate_joining:{type:'checkbox',checked:true}},form={elements:fields,querySelector:()=>button};
 const messages=[],writes=[];let stop=true;
 const sandbox={document:{querySelector:()=>form},gate:async()=>true,session:async()=>({user:{id:'candidate-a'}}),rpc:{profile:'profile',update:'update'},first:x=>x,options:undefined,loadAlertChoices:async()=>{},validateCandidateForm:()=>true,alertChoiceArgs:()=>({}),profileArgs:()=>({}),message:(text)=>messages.push(text),setTimeout:()=>{},location:{reload(){}},call:async name=>{if(name==='profile')return{immediate_joining:false};writes.push(name);return true},saveAlertChoices:async()=>{writes.push('alerts');if(stop)throw new Error('WhatsApp STOP is active; contact Aadhyant to review re-enrolment')}};
 vm.createContext(sandbox);vm.runInContext(candidate.slice(candidate.indexOf('function profileSaveFeedback('),candidate.indexOf('async function jobs(){')),sandbox);
 await sandbox.profile();assert.equal(fields.immediate_joining.checked,false);fields.aadhaar.value='synthetic';
 await form.onsubmit({preventDefault(){}});assert.deepEqual(writes,['update','alerts']);assert.match(messages.at(-1),/Your profile was saved.*WhatsApp STOP is active/);assert.match(messages.at(-1),/Select No for both/);assert.equal(button.disabled,false);assert.equal(fields.aadhaar.value,'synthetic');
 stop=false;await form.onsubmit({preventDefault(){}});assert.match(messages.at(-1),/Candidate profile updated/);assert.equal(fields.aadhaar.value,'');
});

test('profile prevents a changed login from saving and does not claim failed updates succeeded',async()=>{
 for(const scenario of ['changed-before-save','changed-before-alerts','update-failed']){
  const button={disabled:false},form={elements:{aadhaar:{value:''}},querySelector:()=>button},messages=[],writes=[];let checks=0;
  const sandbox={document:{querySelector:()=>form},gate:async()=>true,session:async()=>({user:{id:++checks> (scenario==='changed-before-alerts'?2:1)&&scenario!=='update-failed'?'admin-b':'candidate-a'}}),rpc:{profile:'profile',update:'update'},first:x=>x,options:undefined,loadAlertChoices:async()=>{},validateCandidateForm:()=>true,alertChoiceArgs:()=>({}),profileArgs:()=>({}),message:text=>messages.push(text),setTimeout:()=>{},call:async name=>{if(name==='profile')return{};writes.push(name);if(scenario==='update-failed')throw new Error('Profile details are invalid or already in use');return true},saveAlertChoices:async()=>{writes.push('alerts')}};
  vm.createContext(sandbox);vm.runInContext(candidate.slice(candidate.indexOf('function profileSaveFeedback('),candidate.indexOf('async function jobs(){')),sandbox);
  await sandbox.profile();form.elements.aadhaar.value='synthetic';await form.onsubmit({preventDefault(){}});
  assert.equal(writes.includes('alerts'),false);assert.equal(button.disabled,false);
  if(scenario==='changed-before-save'){assert.deepEqual(writes,[]);assert.match(messages.at(-1),/login changed or expired/)}
  if(scenario==='changed-before-alerts')assert.match(messages.at(-1),/Your profile was saved.*login changed or expired/);
  if(scenario==='update-failed'){assert.match(messages.at(-1),/Your profile update was not confirmed/);assert.doesNotMatch(messages.at(-1),/profile was saved/)}
 }
});

test('alert restart requires a separate unchecked confirmation, freezes selected choices and checks Candidate session',async()=>{
 function node(){return{hidden:false,disabled:false,checked:false,textContent:'',addEventListener(){},showModal(){this.open=true},close(){this.open=false}}}
 const panel=node(),dialog=node(),open=node(),confirm=node(),cancel=node(),consent=node(),error=node(),status=node(),summary=node();
 panel.querySelector=s=>s==='[data-alert-restart-open]'?open:status;
 const controls={'[data-alert-restart-confirm]':confirm,'[data-alert-restart-cancel]':cancel,'[data-alert-restart-consent]':consent,'[data-alert-restart-error]':error,'[data-alert-restart-summary]':summary};dialog.querySelector=s=>controls[s];
 let choices={p_general:false,p_same_day:true,p_current_job_location:'Sanand'},deny=false;const calls=[],messages=[];
 const sandbox={document:{querySelector:s=>s==='[data-alert-restart]'?panel:dialog},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},alertChoiceArgs:()=>({...choices}),call:async(name,args)=>{calls.push({name,args});return{saved:true}},loadAlertChoices:async()=>({can_restart_alerts:false}),message:text=>messages.push(text)};
 vm.createContext(sandbox);vm.runInContext(candidate.slice(candidate.indexOf('function setupAlertRestart('),candidate.indexOf('function profileSaveFeedback(')),sandbox);
 sandbox.setupAlertRestart({}, {can_restart_alerts:true},async()=>{if(deny)throw new Error('Candidate session changed');return 'candidate-a'});
 open.onclick();assert.equal(dialog.open,true);assert.equal(consent.checked,false);assert.equal(confirm.disabled,true);assert.match(summary.textContent,/Job Alerts: No.*Same-Day Pay Alerts: Yes/);
 await confirm.onclick();assert.equal(calls.length,0);cancel.onclick();assert.equal(dialog.open,false);
 open.onclick();consent.checked=true;consent.onchange();assert.equal(confirm.disabled,false);deny=true;await confirm.onclick();assert.equal(calls.length,0);assert.match(error.textContent,/login changed or expired/);
 deny=false;choices={p_general:true,p_same_day:false,p_current_job_location:'Kadi'};await confirm.onclick();assert.equal(calls.length,1);assert.equal(calls[0].name,'restart_candidate_whatsapp_alerts');assert.equal(calls[0].args.p_general,false);assert.equal(calls[0].args.p_same_day,true);assert.equal(calls[0].args.p_current_job_location,'Sanand');assert.equal(calls[0].args.p_confirmed,true);assert.equal(calls[0].args.p_expected_user_id,'candidate-a');assert.equal(panel.hidden,true);assert.equal(dialog.open,false);assert.match(messages.at(-1),/new permission/);
});
