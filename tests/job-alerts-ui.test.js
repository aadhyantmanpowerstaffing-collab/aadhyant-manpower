'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync('admin/job-alerts.js','utf8'),sandbox={window:{},document:{},Object,Map,Set,encodeURIComponent};vm.runInNewContext(source,sandbox);const controller=sandbox.window.AadhyantJobAlerts;
test('manual selection accepts eligible nonmatches, never accepts suppressed rows',()=>{
 const selected=new Map();assert.equal(controller.choose(selected,{contact_id:'other',eligible:true,suggested:false},true),true);
 assert.equal(controller.choose(selected,{contact_id:'stopped',eligible:false,suggested:true},true),false);
 assert.equal(selected.size,1);assert.equal(controller.choose(selected,{contact_id:'other',eligible:true},false),true);assert.equal(selected.size,0);
});
test('selection cap permits deselection and rechecking already selected recipients',()=>{
 const selected=new Map(Array.from({length:500},(_,i)=>['id'+i,{}]));assert.equal(controller.choose(selected,{contact_id:'extra',eligible:true},true),false);
 assert.equal(controller.choose(selected,{contact_id:'id0',eligible:true},true),true);assert.equal(controller.choose(selected,{contact_id:'id0',eligible:true},false),true);assert.equal(selected.size,499);
});
test('preview links use canonical public requirement route, not candidate portal bypass',()=>{
 const preview=controller.previewData({requirement_code:'AAD-2026-000001',job_role:'Helper',job_location:'Sanand'});
 assert.equal(preview.url,'https://aadhyantmanpower.in/jobs/?requirement=AAD-2026-000001');assert.equal(preview.location,'Sanand');
 assert.match(source,/preview of the job details/);assert.match(source,/exact wording is configured in Meta/);
});
test('four steps retain separate server approval and queue actions, no direct sends',()=>{
 assert.equal(controller.steps.length,4);assert.match(source,/admin_prepare_selected_job_campaign/);assert.match(source,/admin_approve_selected_job_campaign/);assert.match(source,/admin_queue_selected_job_campaign/);
 assert.doesNotMatch(source,/client\.from\(|graph\.facebook|localStorage|sendTemplate\(/);
 assert.match(source,/crypto\.randomUUID\(\)/);
});
class Element{
 constructor(tag){this.tagName=tag.toUpperCase();this.children=[];this.dataset={};this.attrs={};this.events={};this.textContent='';this.value='';this.disabled=false;this.hidden=false;this.classList={toggle:()=>{}};}
 append(...items){this.children.push(...items);}prepend(...items){this.children.unshift(...items);}replaceChildren(...items){this.children=[...items];}
 setAttribute(k,v){this.attrs[k]=v;}addEventListener(k,f){this.events[k]=f;}scrollIntoView(){}
 get options(){return this.children;}
 querySelectorAll(selector){return walk(this).filter(n=>selector.split(',').some(s=>matches(n,s)));}
}
const walk=root=>root.children.flatMap(n=>[n,...walk(n)]);
const matches=(n,selector)=>{
 const s=selector.trim();if(s==='.admin-main')return n.className==='admin-main';
 const m=s.match(/^\[data-([\w-]+)(?:="([^"]*)")?\]$/);if(m){const k=m[1].replace(/-([a-z])/g,(_,c)=>c.toUpperCase());return k in n.dataset&&(m[2]===undefined||n.dataset[k]===m[2]);}
 return n.tagName.toLowerCase()===s;
};
test('executed wizard keeps consent eligibility, selects nonmatches, previews and separately approves then queues',async()=>{
 const root=new Element('div'),group=new Element('nav'),main=new Element('main');group.dataset.navGroup='whatsapp';main.className='admin-main';root.append(group,main);
 const document={createElement:t=>new Element(t),querySelector:s=>walk(root).find(n=>matches(n,s)),querySelectorAll:s=>walk(root).filter(n=>s.split(',').some(x=>matches(n,x)))};
 const rows=[{contact_id:'eligible',name_masked:'S•••',mobile_masked:'+91XXXXXX3210',candidate_id:'candidate',eligible:true,suggested:false,match_reasons:['Location differs'],status:'Can select'},{contact_id:'unknown',name_masked:'U•••',mobile_masked:'+91XXXXXX1111',eligible:false,suggested:true,status:'Consent required'}];let campaign=null;const calls=[];
 const client={rpc:async(name,args)=>{calls.push(name);const data={list_recruitment_requirements:[{id:'job',requirement_stage:'open',requirement_code:'AAD-1',job_role:'Helper',job_location:'Sanand'}],get_public_job_requirements:[{requirement_code:'AAD-1'}],admin_preview_selected_job_contacts:rows,admin_list_selected_job_campaigns:campaign?[campaign]:[]};
  if(name==='admin_prepare_selected_job_campaign'){assert.deepEqual(Array.from(args.p_contact_ids),['eligible']);campaign={id:'campaign',requirement_code:'AAD-1',campaign_name:'Test',campaign_status:'audience_ready',audience_count:1};return{data:'campaign'};}
  if(name==='admin_approve_selected_job_campaign')campaign.campaign_status='approved';if(name==='admin_queue_selected_job_campaign')campaign.campaign_status='queued';return{data:data[name]??true};}};
 const env={window:{AadhyantSharingContacts:{selectPublishedVacancies:(a)=>a}},document,Object,Map,Set,encodeURIComponent,crypto:{randomUUID:()=> 'operation'},Option:function(text,value){const n=new Element('option');n.textContent=text;n.value=value;return n;}};vm.runInNewContext(source,env);
 await env.window.AadhyantJobAlerts.initialize({client,authorization:{bootstrap_admin:true}});
 const button=text=>walk(main).find(n=>n.tagName==='BUTTON'&&n.textContent===text);
 await group.children[0].events.click();walk(main).find(n=>n.tagName==='SELECT').value='job';await button('Choose Audience').events.click();
 const checks=walk(main).filter(n=>n.type==='checkbox');assert.equal(checks[1].disabled,true);checks[0].checked=true;checks[0].events.change();await button('Preview Selected Audience').events.click();
 const inputs=walk(main).filter(n=>n.tagName==='INPUT');inputs[1].value='approved_template';inputs[2].value='en';inputs[3].value='1';await button('Save Audience for Approval').events.click();
 assert.equal(calls.includes('admin_queue_selected_job_campaign'),false);await button('Approve Reviewed Campaign').events.click();assert.equal(calls.includes('admin_queue_selected_job_campaign'),false);
 await button('Queue Approved Campaign').events.click();assert.equal(campaign.campaign_status,'queued');
});
