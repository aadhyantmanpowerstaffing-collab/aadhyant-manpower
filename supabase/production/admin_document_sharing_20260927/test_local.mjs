// Local SQL engine + synthetic SQL principals. No genuine Auth JWT/Storage-service proof.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {pathToFileURL,fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {createHash} from 'node:crypto';
const storageSchema=process.env.DOCUMENT_STORAGE_SCHEMA||'versioned';if(!['versioned','standard'].includes(storageSchema))throw Error('Invalid test storage schema');
const toolsRoot=process.env.RESUME_SQL_TOOLS;if(!toolsRoot)throw Error('RESUME_SQL_TOOLS required');
const {PGlite}=await import(pathToFileURL(join(toolsRoot,'protocol_tools/node_modules/@electric-sql/pglite/dist/index.js')));
const {PGLiteSocketServer}=await import(pathToFileURL(join(toolsRoot,'protocol_tools/node_modules/@electric-sql/pglite-socket/dist/index.js')));
const here=fileURLToPath(new URL('.',import.meta.url));const read=n=>readFile(join(here,n),'utf8');const exec=promisify(execFile);
const db=new PGlite(),server=new PGLiteSocketServer({db,host:'127.0.0.1',port:0,maxConnections:1});
const query=async(s,p=[])=>(await db.query(s,p)).rows,sql=s=>db.exec(s);
const proof={storageSchema,scope:'Native psql 17 -> local PostgreSQL17/PGlite. Exact captured SQL constraints/helpers; synthetic SQL principals. Not genuine Auth/Storage or full browser E2E.',checks:{}};
const pass=n=>{proof.checks[n]='PASS';console.log(n+'=PASS');};
const psql=join(toolsRoot,'psql17/files/usr/lib/postgresql/17/bin/psql'),lib=join(toolsRoot,'psql17/files/usr/lib/x86_64-linux-gnu');
async function run(file,marker,code=0){let r;try{r=await exec(psql,['-X','-A','-t','--no-password','-v','ON_ERROR_STOP=1','-f',join(here,file)],{env:{...process.env,LD_LIBRARY_PATH:lib,PGHOST:'127.0.0.1',PGPORT:server.getServerConn().split(':').at(-1),PGUSER:'postgres',PGDATABASE:'template1',PGSSLMODE:'disable',PGOPTIONS:'',PGPASSWORD:'local-only'},timeout:60000,maxBuffer:2*1024*1024});r.code=0;}catch(e){r=e;}
 assert.equal(r.code,code,(r.stderr||'')+'\n'+r.stdout);if(marker)assert.ok(r.stdout.split(/\r?\n/).includes(marker),r.stdout);return r;}
const uid=n=>'e0000000-0000-0000-0000-'+String(n).padStart(12,'0');
const user={admin:uid(1),a:uid(2),b:uid(3),coA:uid(4),coB:uid(5),coViewer:uid(6),ctA:uid(7),ctB:uid(8),ctViewer:uid(9),staff:uid(10)};
const co=uid(21),coB=uid(22),ct=uid(23),ctB=uid(24),cand=uid(31),candB=uid(32),doc=uid(41),pan=uid(42),replacement=uid(43),app=uid(61),ctApp=uid(62),otherApp=uid(63);
const req=uid(51),ctReq=uid(52),otherReq=uid(53),obj=uid(71);const objectName=user.a+'/'+doc+'/synthetic.pdf';
async function as(u='',role='authenticated'){await sql('RESET ROLE');await query("SELECT set_config('request.jwt.claim.sub',$1,false)",[u]);await sql('SET ROLE '+role);}
async function denied(s,p=[],code='P0001'){let e;try{await query(s,p);}catch(err){e=err;}assert.ok(e,'Expected failure '+s);assert.equal(e.code,code,e.message);}
try {
 await sql(await read('../tenant_resume_access_20260926/fixture_sql_engine_only.sql'));
 if(storageSchema==='standard')await sql('ALTER TABLE storage.objects DROP COLUMN is_delete_marker');
 await server.start();
 await run('../tenant_resume_access_20260926/forward_proposed.sql','TENANT_RESUME_REPAIR=COMMITTED');
 await sql(await read('fixture_onboarding.sql'));
 await run('preflight_read_only.sql','ADMIN_DOCUMENT_PREFLIGHT=PASS');pass('NATIVE_PSQL_PREFLIGHT');
 for(const [name,id] of Object.entries(user))await query('INSERT INTO auth.users(id,email) VALUES($1,$2)',[id,name+'@example.invalid']);
 for(const [name,id] of Object.entries(user))if(!['admin','staff'].includes(name))await query('INSERT INTO public.platform_users(user_id,account_type,display_name,email,account_status) VALUES($1,$2,$3,$4,$5)',[id,name.startsWith('co')?'company':name.startsWith('ct')?'contractor':'candidate','Synthetic '+name,name+'@example.invalid','active']);
 for(const name of ['admin','staff']){await query('INSERT INTO public.staff_profiles(user_id,display_name) VALUES($1,$2)',[user[name],'Synthetic '+name]);await query('INSERT INTO public.staff_roles(user_id,role) VALUES($1,$2)',[user[name],name==='admin'?'admin':'recruiter']);}
 for(const id of [co,coB])await query("INSERT INTO public.companies(id,legal_name,account_status) VALUES($1,'Synthetic Company','active')",[id]);
 for(const id of [ct,ctB])await query("INSERT INTO public.contractors(id,agency_name,account_status) VALUES($1,'Synthetic Contractor','active')",[id]);
 for(const [name,id,role] of [['coA',co,'owner'],['coB',coB,'owner'],['coViewer',co,'viewer']])await query("INSERT INTO public.company_users(company_id,user_id,role,status) VALUES($1,$2,$3,'active')",[id,user[name],role]);
 for(const [name,id,role] of [['ctA',ct,'owner'],['ctB',ctB,'owner'],['ctViewer',ct,'coordinator']])await query("INSERT INTO public.contractor_users(contractor_id,user_id,role,status) VALUES($1,$2,$3,'active')",[id,user[name],role]);
 for(const [id,u,phone] of [[cand,user.a,'9876549811'],[candB,user.b,'9876549812']])await query("INSERT INTO public.candidates(id,user_id,full_name,age,gender,mobile,current_location,district,state,highest_qualification,candidate_type,interview_available,consent,profile_status,profile_completion_status) VALUES($1,$2,'Synthetic Candidate',25,'Male',$3,'Sanand','Ahmedabad','Gujarat','ITI','Fresher','Yes',true,'active','complete')",[id,u,phone]);
 for(const [id,company,code] of [[req,co,'E2E-SHARE-1'],[ctReq,null,'E2E-SHARE-2'],[otherReq,coB,'E2E-SHARE-3']])await query("INSERT INTO public.employer_requirements(id,company_id,company_name,contact_person,mobile,company_location,job_role,required_headcount,consent,requirement_code) VALUES($1,$2,'Synthetic','Synthetic','9876549813','Sanand','Operator',2,true,$3)",[id,company,code]);
 await query("INSERT INTO public.requirement_contractors(requirement_id,contractor_id,assigned_headcount,origin_type,submission_status,assignment_status) VALUES($1,$2,2,'contractor_submission','approved','active')",[ctReq,ct]);
 for(const [id,c,r] of [[app,cand,req],[ctApp,cand,ctReq],[otherApp,candB,otherReq]])await query('INSERT INTO public.candidate_applications(id,candidate_id,requirement_id) VALUES($1,$2,$3)',[id,c,r]);
 await query("INSERT INTO storage.objects(id,bucket_id,name,owner,version) VALUES($1,'candidate-private',$2,$3,'v1')",[obj,objectName,user.a]);
 for(const [id,type,path] of [[doc,'resume',objectName],[pan,'pan',user.a+'/'+pan+'/pan.pdf']])await query("INSERT INTO public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes) VALUES($1,$2,$3,$4,'synthetic.pdf','application/pdf',128)",[id,cand,type,path]);

 // Retain one legacy active grant and one revoked consent: never silently broaden either.
 await as(user.a); await query('SELECT public.set_candidate_resume_consent($1,$2,$3,$4,true)',[app,doc,'company',co]);
 await as(user.admin);await query('SELECT public.admin_review_candidate_document($1,$2,NULL)',[doc,'under_verification']);await query('SELECT public.admin_review_candidate_document($1,$2,NULL)',[doc,'verified']);
 const legacy=(await query('SELECT public.admin_list_application_resume_sharing($1) data',[app]))[0].data.recipients[0];
 await query('SELECT public.admin_set_application_resume_share($1,$2,true)',[legacy.consent_id,legacy.revision]);
 await as(user.a);await query('SELECT public.set_candidate_resume_consent($1,$2,$3,$4,true)',[ctApp,doc,'contractor',ct]);await query('SELECT public.set_candidate_resume_consent($1,$2,$3,$4,false)',[ctApp,doc,'contractor',ct]);
 await sql('RESET ROLE');
 await query("INSERT INTO public.candidate_onboarding_details(candidate_id,account_holder_name,bank_name,bank_account_fingerprint,bank_account_last4,ifsc,has_existing_uan,uan_number,has_existing_esic_ip,esic_ip_number) VALUES($1,'Synthetic Holder','Synthetic Bank',encode(sha256(convert_to('123456789012','UTF8')),'hex'),'9012','TEST0123456',true,'123456789012',true,'12345678901234567')",[cand]);
 await run('forward_proposed.sql','ADMIN_DOCUMENT_REPAIR=COMMITTED');await run('postcheck_read_only.sql','ADMIN_DOCUMENT_POSTCHECK=PASS');pass('NATIVE_FORWARD_AND_POSTCHECK');
 await run('forward_proposed.sql',null,3);await sql('ROLLBACK');pass('REPLAY_FAILS_CLOSED');
 const listing=async(id=app,portal='company')=>query('SELECT * FROM public.get_shared_application_items($1,$2)',[id,portal]);
 const context=async(id=app)=>(await query('SELECT public.admin_list_application_document_sharing($1) data',[id]))[0].data;
 const item=async(key,id=app)=>(await context(id)).items.find(r=>r.item_key===key);
 const share=(r,yes=true,id=app)=>query('SELECT public.admin_set_application_document_share($1,$2,$3,$4,$5,$6,$7)',[id,r.item_key,r.recipient_type,r.recipient_id,r.source_token,r.revision,yes]);
 const detail=(key,id=app,portal='company')=>query('SELECT public.get_shared_application_joining_detail($1,$2,$3) data',[id,key,portal]);
 await as(user.coA);assert.equal((await listing()).length,1);await as(user.ctA);assert.equal((await listing(ctApp,'contractor')).length,0);pass('LEGACY_ACTIVE_AND_REVOKED_GRANTS_PRESERVED');
 await as(user.admin);assert.equal((await item('bank')).available,false);assert.equal((await query('SELECT public.admin_get_application_joining_detail($1,$2) data',[app,'bank']))[0].data.full_account_available,false);pass('HISTORICAL_HASH_NOT_FABRICATED_AS_FULL_ACCOUNT');
 const saveArgs=['Synthetic Holder','Synthetic Bank','123456789012','TEST0123456',true,'123456789012',true,'12345678901234567'];
 await as(user.a);await query('SELECT public.update_candidate_onboarding_details($1,$2,$3,$4,$5,$6,$7,$8)',saveArgs);
 await query('SELECT public.update_candidate_onboarding_details($1,$2,$3,$4,$5,$6,$7,$8)',['Synthetic Holder','Synthetic Bank','','TEST0123456',true,'',true,'']);
 const masked=(await query('SELECT * FROM public.get_candidate_onboarding_details()'))[0];assert.equal(masked.bank_account_masked,'XXXX XXXX 9012');assert.equal(masked.uan_masked,'XXXXXXXX9012');
 await denied('SELECT public.set_candidate_resume_consent($1,$2,$3,$4,true)',[app,doc,'company',co]);
 const status=(await query('SELECT public.get_candidate_document_sharing($1) data',['E2E-SHARE-1']))[0].data;assert.ok(status.items.length>=4);assert.doesNotMatch(JSON.stringify(status),/123456789012/);pass('CANDIDATE_SAVE_PRESERVES_BLANKS_MASKED_GETTER_NO_CONSENT_MUTATION');
 await as(user.coA);await denied('SELECT public.get_shared_application_joining_detail($1,$2,$3)',[app,'bank','company']);
 await sql('RESET ROLE');await query("INSERT INTO storage.objects(id,bucket_id,name,owner,version) VALUES($1,'candidate-private',$2,$3,'v1')",[uid(72),user.a+'/'+pan+'/pan.pdf',user.a]);
 await as(user.admin);await query('SELECT public.admin_review_candidate_document($1,$2,NULL)',[pan,'under_verification']);await query('SELECT public.admin_review_candidate_document($1,$2,NULL)',[pan,'verified']);
 let panRow=await item(pan);await share(panRow);for(const key of ['bank','uan','esic'])await share(await item(key));
 await as(user.coA);assert.equal((await listing()).length,5);assert.equal((await detail('bank'))[0].data.bank_account_number,'123456789012');assert.equal((await detail('uan'))[0].data.uan_number,'123456789012');assert.equal((await detail('esic'))[0].data.esic_ip_number,'12345678901234567');
 assert.equal((await query('SELECT * FROM public.get_shared_application_resume($1,$2)',[app,'company'])).length,1);
 assert.equal((await query('SELECT * FROM public.get_shared_application_document_access($1,$2,$3)',[app,pan,'company'])).length,1);pass('ADMIN_WITHOUT_CONSENT_SHARES_SELECTED_DOCUMENT_AND_BANK_UAN_ESIC');
 if(storageSchema==='versioned'){
  await sql('RESET ROLE');await query('UPDATE storage.objects SET is_delete_marker=true WHERE id=$1',[uid(72)]);
  await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===pan),false);
  assert.equal((await query('SELECT name FROM storage.objects WHERE name=$1',[user.a+'/'+pan+'/pan.pdf'])).length,0);
  await as(user.admin);assert.equal((await item(pan)).available,false);
  await sql('RESET ROLE');await query('UPDATE storage.objects SET is_delete_marker=false WHERE id=$1',[uid(72)]);
  await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===pan),true);
  pass('PRESENT_TRUE_DELETE_MARKER_DENIES_RPC_AND_STORAGE_ACCESS');
 }else{await sql('RESET ROLE');assert.equal((await query("SELECT count(*) n FROM pg_attribute WHERE attrelid='storage.objects'::regclass AND attname='is_delete_marker' AND NOT attisdropped"))[0].n,0);await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===pan),true);pass('ABSENT_DELETE_MARKER_NATIVE_UPGRADE_AND_AUTHORIZED_ACCESS');}

 for(const actor of ['coB','b','coViewer','staff']){await as(user[actor]);await denied('SELECT public.admin_get_application_joining_detail($1,$2)',[app,'bank']);await denied('SELECT public.get_shared_application_joining_detail($1,$2,$3)',[app,'bank','company']);}
 await as('','anon');await denied('SELECT * FROM public.get_shared_application_items($1,$2)',[app,'company'],'42501');
 await as(user.coA);await denied('SELECT * FROM public.candidate_onboarding_details',[],'42501');await denied('SELECT private.application_joining_detail($1,$2)',[app,'bank'],'42501');await denied('SELECT * FROM private.candidate_resume_shares',[],'42501');pass('NO_CROSS_TENANT_NONADMIN_ANON_TABLE_OR_INTERNAL_DETAIL_ACCESS');
 await as(user.admin);let bank=await item('bank');await share(bank,false);await as(user.coA);await denied('SELECT public.get_shared_application_joining_detail($1,$2,$3)',[app,'bank','company']);assert.equal((await detail('uan'))[0].data.uan_number,'123456789012');pass('REVOKE_ONE_ITEM_PRESERVES_OTHER_EXPLICIT_GRANTS');
 await as(user.admin);await denied('SELECT public.admin_set_application_document_share($1,$2,$3,$4,$5,$6,true)',[app,'bank','company',co,bank.source_token,bank.revision]);bank=await item('bank');await share(bank);await share(await item('bank'));pass('STALE_REVISION_REJECTED_CURRENT_REPEAT_IDEMPOTENT');
 await as(user.a);await query('SELECT public.update_candidate_onboarding_details($1,$2,$3,$4,$5,$6,$7,$8)',['Synthetic Holder','Synthetic Bank','123456789099','TEST0123456',true,'123456789099',false,'']);
 await as(user.coA);for(const key of ['bank','uan','esic'])await denied('SELECT public.get_shared_application_joining_detail($1,$2,$3)',[app,key,'company']);assert.equal((await listing()).length,2);pass('EDITED_JOINING_DETAILS_REQUIRE_FRESH_ADMIN_SHARE');
 await as(user.admin);const ctDoc=await item(doc,ctApp);await share(ctDoc,true,ctApp);await share(await item('uan',ctApp),true,ctApp);await as(user.ctA);assert.equal((await listing(ctApp,'contractor')).length,2);assert.equal((await detail('uan',ctApp,'contractor'))[0].data.uan_number,'123456789099');await as(user.ctB);assert.equal((await listing(ctApp,'contractor')).length,0);pass('CONTRACTOR_ONLY_MATCHING_APPLICATION_AND_SELECTED_ITEMS');
 await sql('RESET ROLE');await query("UPDATE storage.objects SET version='v2',updated_at=now() WHERE id=$1",[uid(72)]);await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===pan),false);await as(user.admin);panRow=await item(pan);await share(panRow);await sql('RESET ROLE');await query('UPDATE public.candidate_documents SET active=false,replaced_at=now() WHERE id=$1',[pan]);await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===pan),false);pass('STORAGE_REPLACEMENT_AND_INACTIVE_DOCUMENT_REVOKE_FUTURE_ACCESS');
 await sql('RESET ROLE');await query("UPDATE public.company_users SET status='suspended' WHERE user_id=$1",[user.coA]);await as(user.coA);await denied('SELECT * FROM public.get_shared_application_items($1,$2)',[app,'company']);await sql('RESET ROLE');await query("UPDATE public.company_users SET status='active' WHERE user_id=$1",[user.coA]);await query("UPDATE public.candidates SET status='inactive' WHERE id=$1",[cand]);await as(user.coA);assert.equal((await listing()).length,0);await sql('RESET ROLE');await query("UPDATE public.candidates SET status='new' WHERE id=$1",[cand]);pass('SUSPENDED_MEMBERSHIP_AND_CANDIDATE_DENIED');
 await query("UPDATE public.requirement_contractors SET submission_status='closed' WHERE requirement_id=$1",[ctReq]);await as(user.ctA);assert.equal((await listing(ctApp,'contractor')).length,0);await sql('RESET ROLE');await query("UPDATE public.requirement_contractors SET submission_status='approved' WHERE requirement_id=$1",[ctReq]);await query("UPDATE public.candidate_applications SET application_status='cancelled' WHERE id=$1",[app]);await as(user.coA);assert.equal((await listing()).length,0);await sql('RESET ROLE');await query("UPDATE public.candidate_applications SET application_status='applied' WHERE id=$1",[app]);pass('CLOSED_ASSIGNMENT_CANCELLED_APPLICATION_DENIED');
 const audits=await query("SELECT metadata FROM public.audit_logs WHERE entity_type='candidate_item_share'");assert.ok(audits.length>0);for(const a of audits)assert.deepEqual(Object.keys(a.metadata),['shared']);assert.equal((await query("SELECT count(*) n FROM private.candidate_resume_shares WHERE consent_by IS NULL AND authorization_mode='admin_v2'"))[0].n,5);pass('AUDITS_OMIT_RAW_VALUES_ADMIN_NEVER_IMPERSONATES_CANDIDATE');

 const kinds=['aadhaar','aadhaar_front','aadhaar_back','candidate_photo','10th_certificate','12th_certificate','iti_certificate','iti_marksheet','diploma_certificate','degree_certificate','education_other','experience_certificate','previous_employment','bank_proof','bank_passbook','cancelled_cheque','driving_licence','passport','other'];
 for(let index=0;index<kinds.length;index++){
  const id=uid(200+index),path=user.a+'/'+id+'/synthetic.png';await sql('RESET ROLE');
  await query("INSERT INTO storage.objects(id,bucket_id,name,owner,version) VALUES($1,'candidate-private',$2,$3,'v1')",[uid(300+index),path,user.a]);
  await query("INSERT INTO public.candidate_documents(id,candidate_id,document_type,storage_object_name,display_file_name,mime_type,file_size_bytes) VALUES($1,$2,$3,$4,'synthetic.png','image/png',68)",[id,cand,kinds[index],path]);
  await as(user.admin);await denied('SELECT public.admin_set_application_document_share($1,$2,$3,$4,$5,$6,true)',[app,id,'company',co,(await item(id)).source_token,null]);
  for(const state of ['under_verification','verified'])await query('SELECT public.admin_review_candidate_document($1,$2,NULL)',[id,state]);
  await share(await item(id));await as(user.coA);assert.equal((await listing()).some(r=>r.document_id===id),true);
  assert.equal((await query('SELECT * FROM public.get_shared_application_document_access($1,$2,$3)',[app,id,'company']))[0].mime_type,'image/png');
 }
 pass('ALL_21_DOCUMENT_CATEGORIES_REQUIRE_VERIFICATION_AND_EXPLICIT_ADMIN_SHARE');
 await as(user.coA);assert.equal((await query('UPDATE storage.objects SET name=$1 WHERE name=$2 RETURNING name',['bad',objectName])).length,0);assert.equal((await query('DELETE FROM storage.objects WHERE name=$1 RETURNING name',[objectName])).length,0);pass('RECIPIENT_CANNOT_OVERWRITE_OR_DELETE');
 await sql('RESET ROLE');await query("INSERT INTO auth.users(id,email) VALUES($1,'rebound@example.invalid')",[uid(11)]);await query("INSERT INTO public.platform_users(user_id,account_type,display_name,email,account_status) VALUES($1,'candidate','Synthetic Rebound','rebound@example.invalid','active')",[uid(11)]);await query('UPDATE public.candidates SET user_id=$1 WHERE id=$2',[uid(11),cand]);await as(user.coA);assert.equal((await listing()).length,0);await sql('RESET ROLE');await query('UPDATE public.candidates SET user_id=$1 WHERE id=$2',[user.a,cand]);pass('CANDIDATE_AUTH_REBIND_DOES_NOT_INHERIT_SHARES');
 await run('postcheck_read_only.sql','ADMIN_DOCUMENT_POSTCHECK=PASS');pass('FINAL_CATALOG_POSTCHECK');
 const documentCount=(await query('SELECT count(*) n FROM public.candidate_documents'))[0].n;
 await run('pause_sharing_guarded.sql','ADMIN_DOCUMENT_SHARING_PAUSED=COMMITTED');
 await as(user.coA);assert.equal((await listing()).length,0);await as(user.ctA);assert.equal((await listing(ctApp,'contractor')).length,0);
 await as(user.admin);const paused=await item(doc);await denied('SELECT public.admin_set_application_document_share($1,$2,$3,$4,$5,$6,true)',[app,doc,'company',co,paused.source_token,paused.revision],'42501');
 await sql('RESET ROLE');assert.equal((await query('SELECT count(*) n FROM public.candidate_documents'))[0].n,documentCount);assert.equal((await query('SELECT bank_account_number FROM public.candidate_onboarding_details WHERE candidate_id=$1',[cand]))[0].bank_account_number,'123456789099');pass('GUARDED_PAUSE_STOPS_SHARES_PRESERVES_DOCUMENTS_AND_JOINING_DATA');proof.result='PASS';

}catch(e){proof.result='FAIL';proof.error={message:e.message.slice(0,3000),code:e.code,where:e.where};console.error(JSON.stringify(proof.error));process.exitCode=1;}
finally{await server.stop();await db.close();await writeFile(join(here,'local_validation_'+storageSchema+'.json'),JSON.stringify(proof,null,2)+'\n');}
