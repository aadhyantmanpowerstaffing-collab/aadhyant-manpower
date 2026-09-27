import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {createHash,webcrypto} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {classifyRequest,isStorageDownload,assertPdfEvidence,assertTransportBody,observePdfBlobs,PDF_VIEWER_ID} from './browser_download_evidence.mjs';
const endpoints={frontend:'http://127.0.0.1:61431',backend:'http://127.0.0.1:61421',sdk:'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.4'};
const bytes=Buffer.from('%PDF-1.4\nSynthetic test PDF\n%%EOF\n');
const expected={pdfSize:bytes.length,pdfSha256:createHash('sha256').update(bytes).digest('hex')};
const sample={prefix:'%PDF-',type:'application/pdf',size:bytes.length,sha256:expected.pdfSha256};
test('only exact loopback origins and the exact pinned SDK are allowed',()=>{
 assert.equal(classifyRequest(endpoints.backend+'/rest/v1/rpc/example',endpoints,'POST','fetch'),'LOOPBACK');
 assert.equal(classifyRequest(endpoints.sdk,endpoints,'GET','script'),'PINNED_SDK');
 for(const u of ['https://wsuctjhbqiedttfnwjvf.supabase.co/storage/v1/object/a','http://127.0.0.1:54321/rest/v1/','https://example.com/storage/v1/object/a',endpoints.sdk+'/extra',endpoints.sdk+'?token=redacted'])assert.equal(classifyRequest(u,endpoints,'GET','script'),'BLOCKED');
 assert.equal(classifyRequest(endpoints.sdk,endpoints,'POST','fetch'),'BLOCKED');
});
test('built-in PDF viewer is internal and arbitrary extension requests remain blocked',()=>{
 assert.equal(classifyRequest(`chrome-extension://${PDF_VIEWER_ID}/index.html`,endpoints,'GET','document'),'BUILTIN_PDF_VIEWER');
 assert.equal(classifyRequest(`chrome-extension://${PDF_VIEWER_ID}/index.html`,endpoints,'POST','fetch'),'BLOCKED');
 assert.equal(classifyRequest('chrome-extension://other-extension/index.html',endpoints,'GET','document'),'BLOCKED');
 assert.equal(classifyRequest('file:///etc/passwd',endpoints,'GET','document'),'BLOCKED');
 assert.equal(classifyRequest('data:text/html,not-allowed',endpoints,'GET','document'),'BLOCKED');
});
test('Chrome PDF shared resources allow only internal GET scripts and styles',()=>{
 for(const type of ['script','stylesheet'])assert.equal(classifyRequest('chrome://resources/test',endpoints,'GET',type),'BUILTIN_CHROME_RESOURCE');
 for(const url of ['chrome://settings/test','chrome://resources.example.com/test','https://resources/test','chrome://user@resources/test','chrome://resources:1234/test'])assert.equal(classifyRequest(url,endpoints,'GET','script'),'BLOCKED');
 for(const type of ['fetch','xhr','document','image','other'])assert.equal(classifyRequest('chrome://resources/test',endpoints,'GET',type),'BLOCKED');
 assert.equal(classifyRequest('chrome://resources/test',endpoints,'POST','script'),'BLOCKED');
});
test('the ten supplied v2 browser-internal requests are not remote backend traffic',()=>{
 const records=Array.from({length:2},()=>['stylesheet','script','script','script','script']).flat();
 const classify=type=>classifyRequest('chrome://resources/',endpoints,'GET',type);
 assert.equal(records.filter(type=>classify(type)==='BUILTIN_CHROME_RESOURCE').length,10);
 assert.equal(records.filter(type=>classify(type)==='BLOCKED').length,0);
 // An additional actual remote request must still fail the zero-blocked-request gate.
 const blocked=[...records.map(classify),classifyRequest('https://example.com/rest/v1/',endpoints,'GET','fetch')].filter(kind=>kind==='BLOCKED').length;
 assert.equal(blocked,1);assert.throws(()=>assert.equal(blocked,0));
});
test('final network guard failure reports its own stage after successful Admin revocation',()=>{
 const source=readFileSync(new URL('./run_browser.mjs',import.meta.url),'utf8');
 const code=source.slice(source.indexOf(" stage='BACKEND_LOOPBACK_GUARD';"),source.indexOf('\n}catch(err)'));
 assert.ok(code.length>0);
 const passes=[],context={stage:'ADMIN_REVOCATION',results:{nonlocalBackendRequests:1},pass:n=>passes.push(n),expect:n=>({toBe:expected=>assert.equal(n,expected)}),console:{log(){}}};
 vm.createContext(context);
 assert.throws(()=>vm.runInContext(code,context));
 assert.equal(context.stage,'BACKEND_LOOPBACK_GUARD');assert.deepEqual(passes,[]);
 assert.equal(context.results.result,undefined);
 context.results.nonlocalBackendRequests=0;vm.runInContext(code,context);
 assert.deepEqual(passes,['BACKEND_LOOPBACK_GUARD']);assert.equal(context.results.result,'PASS');
});
test('only local browser Blob and exact blank navigation are allowed',()=>{
 assert.equal(classifyRequest('blob:'+endpoints.frontend+'/id',endpoints,'GET','document'),'LOCAL_BLOB');
 assert.equal(classifyRequest('blob:https://example.com/id',endpoints,'GET','document'),'BLOCKED');
 assert.equal(classifyRequest('about:blank',endpoints,'GET','document'),'LOCAL_BLANK');
});
const response=(url,type='fetch',method='GET',navigation=false)=>({url:()=>url,request:()=>({method:()=>method,resourceType:()=>type,isNavigationRequest:()=>navigation})});
test('Storage matcher excludes wrong-origin, wrong-object, preflight and viewer/navigation responses',()=>{
 const object='user/id/resume.pdf',url=endpoints.backend+'/storage/v1/object/authenticated/candidate-private/'+object;
 assert.equal(isStorageDownload(response(url),endpoints.backend,object),true);
 assert.equal(isStorageDownload(response(url.replace('127.0.0.1','example.com')),endpoints.backend,object),false);
 assert.equal(isStorageDownload(response(url),'http://127.0.0.1:9999',object),false);
 assert.equal(isStorageDownload(response(url),endpoints.backend,'another/resume.pdf'),false);
 assert.equal(isStorageDownload(response(url,'document','GET',true),endpoints.backend,object),false);
 assert.equal(isStorageDownload(response(url,'fetch','OPTIONS'),endpoints.backend,object),false);
 assert.equal(isStorageDownload(response('chrome-extension://'+PDF_VIEWER_ID+'/storage/v1/object/authenticated/candidate-private/'+object,'document'),endpoints.backend,object),false);
});
test('actual SDK PDF must match prefix, MIME, original byte size and SHA-256',()=>{
 assert.doesNotThrow(()=>assertPdfEvidence(sample,expected));
 for(const bad of [{prefix:''},{size:0},{sha256:'0'.repeat(64)},{type:'text/html'},{error:'probe-failed'},{size:10485761}])assert.throws(()=>assertPdfEvidence({...sample,...bad},expected));
});
test('nonempty captured HTTP body must match; empty transport capture cannot make a bad Blob pass',()=>{
 assert.doesNotThrow(()=>assertTransportBody(bytes,expected));
 assert.throws(()=>assertTransportBody(Buffer.from('wrong file'),expected));
 assert.doesNotThrow(()=>assertTransportBody(Buffer.alloc(0),expected));
 assert.throws(()=>assertPdfEvidence({...sample,size:0,prefix:''},expected));
});
test('Blob observation returns original URL and inspects original bytes without replacing fetch/RPC behavior',async()=>{
 const created=[],window={},native=value=>{created.push(value);return 'blob:local-original';};
 const URL={createObjectURL:native};
 const context={window,URL,Blob,TextDecoder,Uint8Array,crypto:webcrypto};vm.createContext(context);
 vm.runInContext('('+observePdfBlobs.toString()+')()',context);
 const blob=new Blob([bytes],{type:'application/pdf'});assert.equal(URL.createObjectURL(blob),'blob:local-original');assert.equal(created[0],blob);
 for(let i=0;i<50&&window.__resumePdfEvidence[0].pending;i++)await new Promise(r=>setTimeout(r,2));
 assertPdfEvidence(window.__resumePdfEvidence[0],expected);assert.equal(window.__resumePdfEvidence[0].pending,false);
 assert.equal(Object.hasOwn(window,'fetch'),false);assert.equal(Object.hasOwn(window,'client'),false);
});
test('empty actual Blob is observed as empty and remains a failure',async()=>{
 const window={},context={window,URL:{createObjectURL:()=> 'blob:empty'},Blob,TextDecoder,Uint8Array,crypto:webcrypto};vm.createContext(context);vm.runInContext('('+observePdfBlobs.toString()+')()',context);
 context.URL.createObjectURL(new Blob([],{type:'application/pdf'}));
 for(let i=0;i<50&&window.__resumePdfEvidence[0].pending;i++)await new Promise(r=>setTimeout(r,2));
 assert.equal(window.__resumePdfEvidence[0].size,0);assert.throws(()=>assertPdfEvidence(window.__resumePdfEvidence[0],expected));
});
