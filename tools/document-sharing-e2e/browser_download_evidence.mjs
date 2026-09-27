import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';

export const PDF_VIEWER_ID='mhjfbmdgcfjbbpaeojofohoefgiehjai';
// These are browser-local resources, not remote origins. Never allow arbitrary extensions/hosts.
export function classifyRequest(raw,{frontend,backend,sdk},method='GET',type='other'){
 let u;try{u=new URL(raw);}catch{return 'BLOCKED';}
 if(['http:','https:'].includes(u.protocol)&&[frontend,backend].includes(u.origin))return 'LOOPBACK';
 if(u.href===sdk&&method==='GET'&&type==='script')return 'PINNED_SDK';
 if(u.protocol==='blob:'&&u.origin===frontend&&method==='GET')return 'LOCAL_BLOB';
 if(u.href==='about:blank'&&method==='GET'&&type==='document')return 'LOCAL_BLANK';
 if(u.protocol==='chrome-extension:'&&u.hostname===PDF_VIEWER_ID&&method==='GET'
   &&['document','script','stylesheet','image','font','other'].includes(type))return 'BUILTIN_PDF_VIEWER';
 // Chrome's PDF viewer loads shared scripts/styles from this browser-internal host.
 // Keep the exception limited to the observed resource types; no HTTP(S), fetch or navigation exception.
 if(u.protocol==='chrome:'&&u.hostname==='resources'&&!u.port&&!u.username&&!u.password
   &&method==='GET'&&['script','stylesheet'].includes(type))return 'BUILTIN_CHROME_RESOURCE';
 return 'BLOCKED';
}
export function isStorageDownload(response,backend,objectName){
 const u=new URL(response.url()),r=response.request();
 const object=objectName.split('/').map(encodeURIComponent).join('/');
 return u.origin===backend&&r.method()==='GET'&&!r.isNavigationRequest()
  &&['fetch','xhr'].includes(r.resourceType())
  &&['/storage/v1/object/authenticated/candidate-private/','/storage/v1/object/candidate-private/'].some(p=>u.pathname===p+object);
}
export function assertPdfEvidence(sample,expected){
 assert.equal(sample?.error,undefined,'PDF_BLOB_OBSERVATION_FAILED');
 if((expected.mimeType||'application/pdf')==='application/pdf')assert.equal(sample?.prefix,'%PDF-','SDK_BLOB_IS_NOT_PDF');else assert.equal(sample?.headerHex,'89504e470d0a1a0a','SDK_BLOB_IS_NOT_PNG');
 assert.equal(sample?.type,expected.mimeType||'application/pdf','SDK_BLOB_MIME_MISMATCH');
 assert.ok(Number.isSafeInteger(sample?.size)&&sample.size>0&&sample.size<=10485760,'SDK_BLOB_SIZE_INVALID');
 assert.equal(sample.size,expected.pdfSize,'SDK_BLOB_SIZE_MISMATCH');
 assert.equal(sample.sha256,expected.pdfSha256,'SDK_BLOB_HASH_MISMATCH');
}
export function assertTransportBody(body,expected){
 // CDP response capture is diagnostic. The real SDK Blob must ALWAYS match the original upload.
 if(body.length)assert.equal(createHash('sha256').update(body).digest('hex'),expected.pdfSha256,'CAPTURED_HTTP_BODY_HASH_MISMATCH');
}
// Installed by addInitScript: observes actual generated Blob bytes without mocking fetch, RPCs or sessions.
export function observePdfBlobs(){
 const native=URL.createObjectURL.bind(URL);
 window.__resumePdfEvidence=[];
 URL.createObjectURL=function(value){
  const url=native(value);
  if(value instanceof Blob&&['application/pdf','image/png','image/jpeg'].includes(value.type)){
   const sample={size:value.size,type:value.type,pending:true};window.__resumePdfEvidence.push(sample);
   value.arrayBuffer().then(async buffer=>{
    sample.prefix=new TextDecoder().decode(buffer.slice(0,5));sample.headerHex=Array.from(new Uint8Array(buffer.slice(0,8)),n=>n.toString(16).padStart(2,'0')).join('');
    sample.sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',buffer)),v=>v.toString(16).padStart(2,'0')).join('');
    sample.pending=false;
   }).catch(()=>{sample.error='BLOB_OBSERVATION_FAILED';sample.pending=false;});
  }
  return url;
 };
}
export async function verifyBrowserDownload(page,expected,backend,record){
 record.step='WAIT_FOR_VIEW_CONTROL';
 const before=await page.evaluate(()=>window.__resumePdfEvidence.length);
 const responsePromise=page.waitForResponse(r=>isStorageDownload(r,backend,expected.objectName),{timeout:30000});
 // Register before click; attach a handler immediately so click failure cannot create an unhandled timeout.
 responsePromise.catch(()=>{});
 record.step='CLICK_VIEW';await page.locator('[data-sharing-item="'+expected.document+'"]').getByRole('button',{name:'View document',exact:true}).click();
 record.step='STORAGE_HTTP_RESPONSE';const response=await responsePromise;
 record.status=response.status();record.contentType=await response.headerValue('content-type');record.resourceType=response.request().resourceType();
 assert.equal(response.status(),200,'STORAGE_HTTP_NOT_200');
 assert.equal((record.contentType||'').split(';')[0],expected.mimeType||'application/pdf','STORAGE_HTTP_MIME_MISMATCH');
 let captureError;
 const capture=response.body().then(body=>{
  record.capturedBodyBytes=body.length;
  try{assertTransportBody(body,expected);}catch(error){captureError=error;}
 }).catch(()=>{record.transportCapture='UNAVAILABLE';});
 try{
  record.step='SDK_BLOB';
  await page.waitForFunction(index=>window.__resumePdfEvidence[index]?.pending===false,before,{timeout:15000});
  const sample=await page.evaluate(index=>window.__resumePdfEvidence[index],before);
  record.blob=sample;assertPdfEvidence(sample,expected);
  record.step='TRANSPORT_CAPTURE';await capture;if(captureError)throw captureError;
  record.step='UI_COMPLETION';
  await page.waitForFunction(()=>Array.from(document.querySelectorAll('[role="status"]')).some(n=>n.textContent==='Document opened. Use it only for this application.'||n.textContent==='Document opened. Use it only for this application.'),null,{timeout:15000});
  record.step='PASS';
 }finally{
  record.uiStatus=await page.locator('[role="status"]').allTextContents().catch(()=>['UNAVAILABLE']);
 }
}
