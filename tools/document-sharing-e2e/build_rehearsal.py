from pathlib import Path
import shutil,json,hashlib,re
R=Path.cwd();S=R/'tools/resume-sharing-e2e';D=R/'tools/document-sharing-e2e';D.mkdir(exist_ok=True)
for n in ['package.json','package-lock.json','configure_local_stack.mjs','synthetic_mapping.mjs','exercise_local_api.mjs','browser_download_evidence.mjs']:
 shutil.copyfile(S/n,D/n)
pkg='supabase/production/admin_document_sharing_20260927'
bootstrap=(S/'bootstrap_local_supabase.sql').read_text()+'\nBEGIN;\n'+(R/pkg/'fixture_onboarding.sql').read_text()+"COMMIT;\nSELECT 'DOCUMENT_FIXTURE_ONBOARDING=PASS';\n"
bootstrap=re.sub(r'(?m)^(GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects[^\n]*?)[ \t]+$',r'\1',bootstrap)
(D/'bootstrap_local_supabase.sql').write_text(bootstrap)
s=(S/'START_LOCAL_TEST.ps1').read_text().replace('61421','62421')
s=s.replace("$stage='GENUINE_RESUME_UPLOAD'", """$stage='DOCUMENT_UPGRADE_PREFLIGHT'
  Run-Sql $stage (Join-Path $repo 'supabase/production/admin_document_sharing_20260927/preflight_read_only.sql') 'ADMIN_DOCUMENT_PREFLIGHT=PASS'
  $stage='DOCUMENT_UPGRADE'
  Run-Sql $stage (Join-Path $repo 'supabase/production/admin_document_sharing_20260927/forward_proposed.sql') 'ADMIN_DOCUMENT_REPAIR=COMMITTED'
  $stage='DOCUMENT_UPGRADE_POSTCHECK'
  Run-Sql $stage (Join-Path $repo 'supabase/production/admin_document_sharing_20260927/postcheck_read_only.sql') 'ADMIN_DOCUMENT_POSTCHECK=PASS'
  $stage='GENUINE_RESUME_UPLOAD'""")
s=s.replace("$stage='RESUME_BROWSER_COMPONENT_FLOW'","$stage='DOCUMENT_BROWSER_COMPONENT_FLOW'")
s=s.replace("LOCAL_RESUME_BROWSER_REHEARSAL=PASS","LOCAL_DOCUMENT_BROWSER_REHEARSAL=PASS").replace("scope='Fresh local resume-sharing Auth/Storage and browser component rehearsal'","scope='Fresh local Admin documents, bank, UAN, ESIC sharing through genuine Auth/Storage and browser components'")
(D/'START_LOCAL_TEST.ps1').write_text(s)
s=(S/'browser_download_evidence.mjs').read_text().replace("name:'View Resume'","name:'View document'").replace('Resume opened. Use it only for this application.','Document opened. Use it only for this application.').replace('Resume downloaded. Use the link to open it.','Document opened. Use it only for this application.')

s=s.replace("assert.equal(sample?.prefix,'%PDF-','SDK_BLOB_IS_NOT_PDF');","if((expected.mimeType||'application/pdf')==='application/pdf')assert.equal(sample?.prefix,'%PDF-','SDK_BLOB_IS_NOT_PDF');else assert.equal(sample?.headerHex,'89504e470d0a1a0a','SDK_BLOB_IS_NOT_PNG');")
s=s.replace("assert.equal(sample?.type,'application/pdf','SDK_BLOB_MIME_MISMATCH');","assert.equal(sample?.type,expected.mimeType||'application/pdf','SDK_BLOB_MIME_MISMATCH');")
s=s.replace("value.type==='application/pdf'","['application/pdf','image/png','image/jpeg'].includes(value.type)")
s=s.replace("sample.prefix=new TextDecoder().decode(buffer.slice(0,5));","sample.prefix=new TextDecoder().decode(buffer.slice(0,5));sample.headerHex=Array.from(new Uint8Array(buffer.slice(0,8)),n=>n.toString(16).padStart(2,'0')).join('');")
s=s.replace("page.getByRole('button',{name:'View document',exact:true})","page.locator('[data-sharing-item=\"'+expected.document+'\"]').getByRole('button',{name:'View document',exact:true})")
s=s.replace("assert.match(record.contentType||'',/^application\\/pdf(?:;|$)/i,'STORAGE_HTTP_NOT_PDF');","assert.equal((record.contentType||'').split(';')[0],expected.mimeType||'application/pdf','STORAGE_HTTP_MIME_MISMATCH');")
(D/'browser_download_evidence.mjs').write_text(s)
s=(S/'exercise_local_api.mjs').read_text()
s=s.replace("schema.paths?.['/rpc/get_shared_application_resume']","schema.paths?.['/rpc/get_shared_application_items']&&schema.paths?.['/rpc/admin_set_application_document_share']")
# Materialize canonical onboarding data through the genuine Candidate-JWT RPC, not a database insert.
s=s.replace("console.log('UNSHARED_COMPANY_RESUME_DENIED=PASS');", """console.log('UNSHARED_COMPANY_RESUME_DENIED=PASS');
 assert.equal(await request('/rest/v1/rpc/update_candidate_onboarding_details',candidate,{p_account_holder_name:'Synthetic Holder',p_bank_name:'Synthetic Bank',p_bank_account_number:'123456789012',p_ifsc:'TEST0123456',p_has_existing_uan:true,p_uan_number:'123456789012',p_has_existing_esic_ip:true,p_esic_ip_number:'12345678901234567'}),true);
 console.log('GENUINE_CANDIDATE_JOINING_DETAILS_SAVE=PASS');""")

s=s.replace("console.log('GENUINE_CANDIDATE_JOINING_DETAILS_SAVE=PASS');", """console.log('GENUINE_CANDIDATE_JOINING_DETAILS_SAVE=PASS');
 const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=','base64');
 const imageName=actors.candidate.id+'/'+crypto.randomUUID()+'/synthetic-pan.png';
 await request('/storage/v1/object/candidate-private/'+imageName,candidate,png,'POST','image/png');
 const imageDoc=await request('/rest/v1/rpc/register_candidate_document',candidate,{p_document_type:'pan',p_storage_object_name:imageName,p_display_file_name:'synthetic-pan.png',p_mime_type:'image/png',p_file_size_bytes:png.length});
 for(const state of ['under_verification','verified'])assert.equal(await request('/rest/v1/rpc/admin_review_candidate_document',admin,{p_document_id:imageDoc,p_status:state,p_feedback:null}),true);
 const fixture=JSON.parse(await readFile(join(evidence,'fixture-state.json'),'utf8'));fixture.image={document:imageDoc,objectName:imageName,pdfSize:png.length,pdfSha256:createHash('sha256').update(png).digest('hex'),mimeType:'image/png'};
 await writeFile(join(evidence,'fixture-state.json'),JSON.stringify(fixture,null,2)+'\\n');
 console.log('GENUINE_PNG_UPLOAD_REGISTRATION_VERIFICATION=PASS');""")
(D/'exercise_local_api.mjs').write_text(s)
s=(S/'run_browser.mjs').read_text();start=s.index(" stage='CANDIDATE_EXPLICIT_CONSENT'");end=s.index(" stage='BACKEND_LOOPBACK_GUARD'",start)
s=s[:start]+''' const card=(page,key)=>page.locator('[data-sharing-item="'+key+'"]');
 stage='CANDIDATE_NO_CONSENT_ACTION_REQUIRED';await candidateView(a,'E2E-SHARE-1');await expect(a.getByRole('checkbox')).toHaveCount(0);await expect(a.getByRole('button',{name:'Allow Admin to share'})).toHaveCount(0);pass(stage);
 stage='UNSHARED_DOCUMENTS_AND_DETAILS_DENIED';await tenantView(company,state.app,'company');await expect(company.getByRole('button',{name:'View document'})).toHaveCount(0);await expect(company.getByRole('button',{name:'View details'})).toHaveCount(0);pass(stage);
 stage='ADMIN_EXPLICIT_DOCUMENT_SHARE';await adminView(state.app);await card(admin,state.document).getByRole('button',{name:'Share item',exact:true}).click();await expect(card(admin,state.document).getByRole('button',{name:'Stop sharing'})).toBeVisible();pass(stage);
 stage='COMPANY_GENUINE_DOCUMENT_DOWNLOAD';await tenantView(company,state.app,'company');results.downloads.company={};await verifyBrowserDownload(company,state,back.origin,results.downloads.company);pass(stage);
 stage='ADMIN_SEPARATE_BANK_UAN_ESIC_SHARES';for(const key of ['bank','uan','esic']){await card(admin,key).getByRole('button',{name:'Share item',exact:true}).click();await expect(card(admin,key).getByRole('button',{name:'Stop sharing'})).toBeVisible();}pass(stage);
 stage='COMPANY_JOINING_DETAILS_ON_DEMAND';await tenantView(company,state.app,'company');await expect(company.locator('#sharing')).not.toContainText('123456789012');for(const key of ['bank','uan','esic']){const c=card(company,key);await c.getByRole('button',{name:'View details'}).click();await expect(c).toContainText(key==='esic'?'12345678901234567':'123456789012');await c.getByRole('button',{name:'Hide details'}).click();await expect(c).not.toContainText('123456789012');}pass(stage);
 stage='ADMIN_PNG_SHARE_AND_GENUINE_DOWNLOAD';await card(admin,state.image.document).getByRole('button',{name:'Share item',exact:true}).click();await expect(card(admin,state.image.document).getByRole('button',{name:'Stop sharing'})).toBeVisible();await tenantView(company,state.app,'company');results.downloads.image={};await verifyBrowserDownload(company,state.image,back.origin,results.downloads.image);pass(stage);
 stage='OTHER_COMPANY_DOCUMENT_AND_DETAILS_DENIED';await tenantView(other,state.app,'company');await expect(other.getByRole('button',{name:'View document'})).toHaveCount(0);await expect(other.getByRole('button',{name:'View details'})).toHaveCount(0);const blocked=await other.evaluate(async path=>Boolean((await window.client.storage.from('candidate-private').download(path)).error),state.objectName);expect(blocked).toBe(true);pass(stage);
 stage='CONTRACTOR_ADMIN_SHARE_WITHOUT_CANDIDATE_ACTION';await adminView(state.contractorApp);await card(admin,state.document).getByRole('button',{name:'Share item',exact:true}).click();await expect(card(admin,state.document).getByRole('button',{name:'Stop sharing'})).toBeVisible();await tenantView(contractor,state.contractorApp,'contractor');results.downloads.contractor={};await verifyBrowserDownload(contractor,state,back.origin,results.downloads.contractor);pass(stage);
 stage='ADMIN_REVOCATION';await card(admin,state.document).getByRole('button',{name:'Stop sharing'}).click();await expect(card(admin,state.document).getByRole('button',{name:'Share item',exact:true})).toBeVisible();await tenantView(contractor,state.contractorApp,'contractor');await expect(contractor.getByRole('button',{name:'View document'})).toHaveCount(0);pass(stage);
 stage='JOINING_EDIT_REQUIRES_FRESH_ADMIN_SHARE';const saved=await a.evaluate(async()=>{const r=await window.client.rpc('update_candidate_onboarding_details',{p_account_holder_name:'Synthetic Holder',p_bank_name:'Synthetic Bank',p_bank_account_number:'123456789099',p_ifsc:'TEST0123456',p_has_existing_uan:true,p_uan_number:'123456789099',p_has_existing_esic_ip:false,p_esic_ip_number:''});return !r.error&&r.data===true;});expect(saved).toBe(true);await tenantView(company,state.app,'company');await expect(company.getByRole('button',{name:'View details'})).toHaveCount(0);await expect(company.getByRole('button',{name:'View document'})).toHaveCount(2);pass(stage);
''' +s[end:]
s=s.replace('RESUME_BROWSER_COMPONENT_FLOW=PASS','DOCUMENT_BROWSER_COMPONENT_FLOW=PASS').replace('Actual new resume-sharing browser component','Actual Admin documents and joining details browser component')
(D/'run_browser.mjs').write_text(s)
files=['assets/js/resume-sharing.js']
files += [str(p.relative_to(R)) for p in sorted(D.iterdir()) if p.is_file() and p.name not in ['local_manifest.json','README.md']]
for d in [R/'supabase/production/tenant_resume_access_20260926',R/pkg]:
 files += [str(p.relative_to(R)) for p in sorted(d.iterdir()) if p.name in ['preflight_read_only.sql','forward_proposed.sql','postcheck_read_only.sql','fixture_onboarding.sql']]
(D/'local_manifest.json').write_text(json.dumps({'scope':'Local-only new upgrade rehearsal; no Production dispatch','files':[{'path':n,'sha256':hashlib.sha256((R/n).read_bytes()).hexdigest()} for n in files]},indent=2)+'\n')
