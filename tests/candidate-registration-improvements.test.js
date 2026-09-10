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
