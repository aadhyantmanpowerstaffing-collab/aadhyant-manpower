import {createHash} from 'node:crypto';
import {buildSyntheticMapping} from './synthetic_mapping.mjs';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const env=process.env,url=new URL(env.RESUME_E2E_BACKEND||''),key=env.RESUME_E2E_ANON_KEY,password=env.RESUME_E2E_PASSWORD,evidence=env.RESUME_E2E_EVIDENCE_DIR;
if(url.protocol!=='http:'||url.hostname!=='127.0.0.1'||!url.port||url.pathname!=='/'||url.username||url.password||url.search||url.hash||!key||!password||!evidence)throw Error('EXPLICIT_LOCAL_INPUTS_REQUIRED');
const api=url.origin;
async function request(path,token,body,method='POST',type='application/json'){
 const r=await fetch(api+path,{method,headers:{apikey:key,Authorization:'Bearer '+(token||key),'Content-Type':type},body:body===undefined?undefined:type==='application/json'?JSON.stringify(body):body,redirect:'error',signal:AbortSignal.timeout(30000)});
 if(!r.ok)throw Error('LOCAL_REQUEST_FAILED:'+path.split('?')[0]+':HTTP_'+r.status);
 return r.headers.get('content-type')?.includes('json')?r.json():r.arrayBuffer();
}
const uid=n=>'e1000000-0000-0000-0000-'+String(n).padStart(12,'0');
if(process.argv[2]==='prepare'){
 const actors={};for(const name of ['candidate','otherCandidate','admin','company','otherCompany','contractor']){
  const email=env.RESUME_E2E_EMAIL_A.replace('-a@','-'+name.toLowerCase()+'@');
  const data=await request('/auth/v1/signup',null,{email,password});assert.match(data.user.id,/^[a-f0-9-]{36}$/);actors[name]={id:data.user.id,email};
 }
 const mapping=buildSyntheticMapping(actors);
 await writeFile(join(evidence,'synthetic-resume-mapping.sql'),mapping);await writeFile(join(evidence,'synthetic-actors.json'),JSON.stringify(actors,null,2)+'\n');console.log('GENUINE_LOCAL_AUTH_ACCOUNTS=PASS');
}else if(process.argv[2]==='verify'){
 const actors=JSON.parse(await readFile(join(evidence,'synthetic-actors.json'),'utf8'));
 const login=async n=>(await request('/auth/v1/token?grant_type=password',null,{email:actors[n].email,password})).access_token;
 const candidate=await login('candidate'),admin=await login('admin');
 let ready=false;for(let i=0;i<20;i++){const schema=await request('/rest/v1/',admin,undefined,'GET');if(schema.paths?.['/rpc/get_shared_application_resume']&&schema.paths?.['/rpc/register_candidate_document']&&schema.paths?.['/rpc/admin_review_candidate_document']){ready=true;break;}await new Promise(r=>setTimeout(r,500));}assert.equal(ready,true,'LOCAL_RPC_SCHEMA_NOT_READY');console.log('LOCAL_RPC_SCHEMA_READY=PASS');
 const name=actors.candidate.id+'/'+crypto.randomUUID()+'/resume.pdf';
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R >>','<< /Length 0 >>\nstream\n\nendstream'];
 let pdf='%PDF-1.4\n',offsets=[0];objects.forEach((o,i)=>{offsets.push(Buffer.byteLength(pdf));pdf+=`${i+1} 0 obj\n${o}\nendobj\n`;});const xref=Buffer.byteLength(pdf);pdf+='xref\n0 5\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+`trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
 const bytes=Buffer.from(pdf);await request('/storage/v1/object/candidate-private/'+name,candidate,bytes,'POST','application/pdf');
 const stored=Buffer.from(await request('/storage/v1/object/authenticated/candidate-private/'+name,candidate,undefined,'GET'));assert.deepEqual(stored,bytes,'CANDIDATE_STORAGE_ROUNDTRIP_MISMATCH');console.log('GENUINE_STORAGE_PDF_ROUNDTRIP=PASS');
 const doc=await request('/rest/v1/rpc/register_candidate_document',candidate,{p_document_type:'resume',p_storage_object_name:name,p_display_file_name:'synthetic-resume.pdf',p_mime_type:'application/pdf',p_file_size_bytes:bytes.length});
 for(const state of ['under_verification','verified'])assert.equal(await request('/rest/v1/rpc/admin_review_candidate_document',admin,{p_document_id:doc,p_status:state,p_feedback:null}),true);
 const before=await request('/rest/v1/rpc/get_shared_application_resume',await login('company'),{p_application_id:uid(61),p_portal:'company'});assert.deepEqual(before,[]);
 await writeFile(join(evidence,'fixture-state.json'),JSON.stringify({app:uid(61),contractorApp:uid(62),document:doc,objectName:name,pdfSize:bytes.length,pdfSha256:createHash('sha256').update(bytes).digest('hex')},null,2)+'\n');console.log('GENUINE_CANDIDATE_STORAGE_UPLOAD_REGISTRATION=PASS');console.log('GENUINE_ADMIN_VERIFICATION=PASS');console.log('UNSHARED_COMPANY_RESUME_DENIED=PASS');
}else throw Error('Unknown local phase');
