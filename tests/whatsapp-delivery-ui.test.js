'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{constructor(tag){this.tag=tag;this.textContent='';this.children=[];this.dataset={};this.attrs={};this.handlers={};this.classList={toggle(){}};}append(...n){this.children.push(...n);}replaceChildren(...n){this.children=n;}setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,v){this.handlers[k]=v;}querySelectorAll(){return [];}scrollIntoView(){}}
const walk=n=>[n,...n.children.flatMap(walk)];
async function setup({approved=false}={}){
 const main=new Element('main'),group=new Element('nav'),rpcCalls=[],httpCalls=[],timers=[];let status=approved?'approved':'queued';let summary={total:3,delivered:1,read:0,awaiting:1,failed:1,pending:0,sending:0,review:0,not_sent:0,checked_at:'2026-10-28T07:00:00Z'};
 const campaign=()=>({id:'00000000-0000-0000-0000-000000000001',campaign_name:'Sample',requirement_code:'JOB-1',campaign_status:status,template_name:'current',delivery:summary,audience_count:3,sent:1,delivered:1,read:0,failed:1});
 const client={auth:{getSession:async()=>({data:{session:{access_token:'fixture'}}})},rpc:async(name,args)=>{rpcCalls.push([name,args]);if(name==='admin_console_inbox')return{data:[]};if(name==='admin_console_templates')return{data:{templates:[],sender_ready:true}};if(name==='admin_console_registration_flow')return{data:{ready:true}};if(name==='admin_console_campaigns')return{data:[campaign()]};if(name==='admin_console_queue'){status='queued';return{data:3};}if(name==='admin_console_report')return{data:[{mobile_masked:'+91XXXXXX0000',status:'failed',failure_code:'131048'}]};if(name==='admin_console_campaign_delivery')return{data:summary};throw Error(name);}};
 const window={AADHYANT_CONFIG:{supabaseUrl:'https://fixture.invalid',supabasePublishableKey:'fixture'},setTimeout:fn=>{timers.push(fn);return timers.length;},clearTimeout:()=>{}};
 const document={hidden:false,createElement:t=>new Element(t),querySelector:s=>s==='.admin-main'?main:group,querySelectorAll:s=>s==='[data-panel]'?main.children.filter(n=>n.dataset.panel):[]};
 vm.runInNewContext(fs.readFileSync('admin/whatsapp-console.js','utf8'),{window,document,Date,crypto:{randomUUID:()=> 'fixture'},Option:class extends Element{constructor(text,value){super('option');this.textContent=text;this.value=value;}},fetch:async(url)=>{httpCalls.push(url);return Response.json({error:'Sending paused while preparing the next batch.'},{status:503});}});
 await window.AadhyantWhatsAppConsole.initialize({client,authorization:{bootstrap_admin:true}});await group.children[0].handlers.click();
 const find=text=>walk(main).find(n=>n.tag==='button'&&n.textContent===text);
 const click=async text=>{await find(text).handlers.click();await new Promise(r=>setImmediate(r));};await click('Campaigns');
 return{main,find,click,rpcCalls,httpCalls,timers,setSummary:v=>{summary={...summary,...v};}};
}
test('worker preparation failure refreshes durable campaign status and removes stale Send Now / empty Process Pending actions',async()=>{
 const f=await setup({approved:true});await f.click('Send Now');assert.equal(f.httpCalls.length,1);assert.ok(!f.find('Send Now'));assert.ok(!f.find('Process Pending'));assert.ok(walk(f.main).some(n=>n.textContent==='Awaiting delivery'));assert.ok(walk(f.main).some(n=>n.textContent==='Sending paused while preparing the next batch.'));
});
test('report shows English provider reason and full summary; automatic refresh reads receipts without sending',async()=>{
 const f=await setup();await f.click('View Report');assert.ok(walk(f.main).some(n=>n.textContent==='Meta spam/quality sending limit (131048)'));assert.ok(walk(f.main).some(n=>n.textContent==='Delivered (incl. Read)'));assert.ok(walk(f.main).some(n=>n.textContent.includes('Sent is not proof of delivery')));
 f.setSummary({delivered:2,read:1,awaiting:0,checked_at:'2026-10-28T07:01:00Z'});await f.timers.at(-1)();assert.ok(walk(f.main).some(n=>n.textContent.startsWith('Read: 1')));assert.equal(f.httpCalls.length,0);
 const staleTimer=f.timers.at(-1);await f.click('Campaigns');const count=f.rpcCalls.length;await staleTimer();assert.equal(f.rpcCalls.length,count);
});
