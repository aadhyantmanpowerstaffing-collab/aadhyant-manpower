'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const api=require('../admin/job-reel-form.js');
const code=fs.readFileSync('admin/job-reel-form.js','utf8');
const role={type:'helper',qualification:'10-12-iti',vacancies:'30',ctc:'21000',takeHome:'18000',period:'month',duty:'8',overtime:'130',remarks:'अनुभव आवश्यक नहीं है।'};
const details={company:'FCC CLUTCH',location:'साणंद जीआईडीसी',roles:[role,{type:'cnc',takeHome:'20000',period:'month',duty:'8',overtime:'150'},{type:'custom',name:'मैकेनिकल डिप्लोमा / बीई / बीटेक',takeHome:'19000',takeHomeMax:'20000',period:'month',overtime:'170'}],age:'18–40 वर्ष',shift:'abc',pf:'yes',esic:'yes',bus:'free',canteen:'paid',room:'paid',uniform:'free',shoes:'free',benefits:'उपस्थिति बोनस शर्तों के अनुसार।',startDate:'2026-10-24',endDate:'2026-11-01',time:'09:00',address:'कंपनी गेट, कोका कोला के पास',documents:'आधार, PAN, मार्कशीट, बैंक पासबुक और 2 फोटो',other:'इंटरव्यू के अनुसार अंतिम वेतन तय होगा।'};
function ui({failAt=0}={}){
  const elements={},calls=[];let seq=0,refreshed=0,failed=false;
  class El{
    constructor(tag='div'){this.tag=tag;this.value='';this.checked=false;this.disabled=false;this.hidden=false;this.files=[];this.children=[];this.dataset={};this.listeners={};this.textContent='';}
    append(...els){for(const el of els){el.parent=this;this.children.push(el);}}
    remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
    removeAttribute(key){delete this[key];}
    addEventListener(name,fn){this.listeners[name]=fn;}
    async emit(name){return this.listeners[name]?.({preventDefault(){}});}
    querySelectorAll(selector){const tags=selector.split(',');return this.children.flatMap(x=>[...(tags.includes(x.tag)?[x]:[]),...x.querySelectorAll(selector)]);}
    getContext(){return {fillRect(){},drawImage(){},fillText(){},measureText:t=>({width:t.length*25})};}
    toDataURL(){return 'data:image/jpeg;base64,/9j/'+'A'.repeat(200);}
  }
  const el=id=>elements[id]||(elements[id]=new El(id.includes('form')?'form':'input'));
  const document={getElementById:el,createElement:tag=>new El(tag)};
  const form=el('announcement-form');for(const id of ['announcement-roles','announcement-draft','announcement-reviewed','announcement-title','announcement-file','announcement-add-role','announcement-generate','announcement-create'])form.append(el(id));
  el('announcement-title').value='नौकरी का नया अवसर';
  const window={document};vm.runInNewContext(code,{window,document,Intl,Date,console,createImageBitmap:async()=>({width:800,height:1200,close(){}}),crypto:{randomUUID:()=>`request-${++seq}`}});
  window.aadhyantJobReelForm.init({client:{async rpc(name,args){calls.push({name,args});if(failAt&&calls.length===failAt&&!failed){failed=true;return {error:{message:'temporary'}};}return {data:'queued'};}},onQueued:async()=>{refreshed++;}});
  el('announcement-company').value='FCC CLUTCH';el('announcement-location').value='साणंद';el('announcement-roles').children[0].querySelectorAll('select').find(x=>x.dataset.field==='type').value='helper';
  return {el,calls,stats:()=>({refreshed}),roles:()=>el('announcement-roles').children};
}
const field=(row,key)=>row.querySelectorAll('input,select').find(x=>x.dataset.field===key);
test('complete deterministic Hindi narration includes every supplied role and shared fact',()=>{
  const text=api.buildNarration(details);
  for(const token of ['FCC CLUTCH','साणंद','हेल्पर','30','सीएनसी','₹18,000','₹20,000','₹19,000 से ₹20,000','₹21,000','₹130','₹150','₹170','8 घंटे','18–40','ए, बी और सी','पीएफ','ईएसआईसी','मुफ्त बस','कैंटीन शुल्क','रूम या पीजी','यूनिफॉर्म मुफ्त','सेफ्टी शूज मुफ्त',details.benefits,'24 अक्टूबर 2026','1 नवंबर 2026','सुबह 9 बजे',details.address,details.documents,details.other,role.remarks])assert.ok(text.includes(token),token);
});
test('missing optional facts are never invented and custom descriptions are retained verbatim',()=>{
  const extra='भोजन का ₹45 शुल्क। कंपनी की अलग शर्त लागू है।';const text=api.buildNarration({company:'Firm',location:'Town',roles:[{type:'custom',name:'कस्टम पद',remarks:extra}],other:extra});
  assert.ok(text.includes(extra));assert.doesNotMatch(text,/पीएफ|ईएसआईसी|वेतन|ड्यूटी|इंटरव्यू/);
});
test('invalid amounts, salary ranges, dates and incomplete roles fail before queueing',()=>{
  for(const changed of [{company:''},{roles:[]},{roles:[{...role,type:'unknown'}]},{roles:[{...role,takeHome:'bad'}]},{roles:[{...role,takeHomeMax:'100'}]},{roles:[{...role,ctc:'',ctcMax:'20000'}]},{endDate:'2026-01-01'},{time:'25:00'},{startDate:'2026-02-30'}])assert.throws(()=>api.buildNarration({...details,...changed}));
});
test('all long narration is retained across bounded video parts, including Other details',()=>{
  const full=api.buildNarration({...details,other:'जरूरी शर्त और सभी सुविधाएँ। '.repeat(100)}),parts=api.splitNarration(full);
  assert.ok(parts.length>1);assert.ok(parts.every(p=>p.length>=10&&p.length<=1800));
  assert.equal(parts.join(' ').replace(/\s+/g,''),full.replace(/\s+/g,''));
  const boundary=api.splitNarration('अ'.repeat(1801));assert.equal(boundary.join(''),'अ'.repeat(1801));
  assert.throws(()=>api.splitNarration('अ'.repeat(12001)));assert.throws(()=>api.splitNarration('English only announcement'));
});
test('form creates a Hindi draft without OCR, Chrome Translator or a microphone',async()=>{
  const u=ui();field(u.roles()[0],'takeHome').value='18000';await u.el('announcement-generate').emit('click');
  assert.match(u.el('announcement-draft').value,/हेल्पर/);assert.match(u.el('announcement-draft').value,/18,000/);assert.equal(u.calls.length,0);
  await u.el('announcement-form').emit('submit');assert.equal(u.calls.length,0);
  u.el('announcement-reviewed').checked=true;await u.el('announcement-form').emit('submit');
  assert.equal(u.calls.length,1);assert.equal(u.calls[0].name,'admin_queue_poster_reel');assert.match(u.calls[0].args.p_poster,/^\/9j\//);assert.equal(u.calls[0].args.p_reviewed,true);assert.equal(u.stats().refreshed,1);
});
test('adding separate roles preserves each salary and editing a detail invalidates the old narration',async()=>{
  const u=ui();field(u.roles()[0],'takeHome').value='18000';await u.el('announcement-add-role').emit('click');field(u.roles()[1],'type').value='cnc';field(u.roles()[1],'takeHome').value='20000';
  await u.el('announcement-generate').emit('click');assert.match(u.el('announcement-draft').value,/18,000/);assert.match(u.el('announcement-draft').value,/20,000/);
  u.el('announcement-reviewed').checked=true;await field(u.roles()[1],'takeHome').emit('input');assert.equal(u.el('announcement-reviewed').checked,false);assert.equal(u.el('announcement-draft').value,'');
});
test('ambiguous network retries reuse request IDs and successful resubmission creates no duplicates',async()=>{
  const u=ui({failAt:1});await u.el('announcement-generate').emit('click');u.el('announcement-reviewed').checked=true;
  await u.el('announcement-form').emit('submit');await u.el('announcement-form').emit('submit');
  assert.equal(u.calls[0].args.p_request_id,u.calls[1].args.p_request_id);await u.el('announcement-form').emit('submit');assert.equal(u.calls.length,2);
});
test('multipart partial failures retry only the remaining reviewed parts with stable IDs',async()=>{
  const u=ui({failAt:2});u.el('announcement-draft').value='भर्ती की जरूरी जानकारी और पूरी शर्तें। '.repeat(100);u.el('announcement-reviewed').checked=true;
  await u.el('announcement-form').emit('submit');assert.equal(u.calls.length,2);assert.match(u.el('announcement-status').textContent,/1 of/);
  assert.equal(u.el('announcement-draft').disabled,true);assert.equal(u.el('announcement-create').disabled,false);
  const firstId=u.calls[0].args.p_request_id,failedId=u.calls[1].args.p_request_id;
  await u.el('announcement-form').emit('submit');assert.equal(u.calls[2].args.p_request_id,failedId);assert.equal(u.calls.filter(c=>c.args.p_request_id===firstId).length,1);
  assert.ok(u.calls.every(c=>c.args.p_text.length<=1800));assert.equal(u.el('announcement-draft').disabled,false);
});
test('bad covers do not queue and changing a cover revokes final review',async()=>{
  const u=ui();await u.el('announcement-generate').emit('click');u.el('announcement-file').files=[{type:'application/pdf',size:1000}];u.el('announcement-reviewed').checked=true;
  await u.el('announcement-form').emit('submit');assert.equal(u.calls.length,0);assert.match(u.el('announcement-status').textContent,/JPG or PNG/);
  await u.el('announcement-file').emit('change');assert.equal(u.el('announcement-reviewed').checked,false);
});
test('published form removes the old OCR/translation flow and keeps existing Admin-only video integration',()=>{
  const html=fs.readFileSync('admin/reels.html','utf8'),reels=fs.readFileSync('admin/reels.js','utf8'),builder=fs.readFileSync('scripts/build-production-artifact.js','utf8');
  assert.doesNotMatch(html+code,/Tesseract|\.Translator|Read poster|poster-raw|wasm-unsafe-eval|tessdata|innerHTML|getUserMedia/);
  assert.ok(html.includes('Other details / conditions'));assert.ok(html.includes('Long announcements are split'));assert.ok(html.includes('9586785800'));
  assert.ok(reels.indexOf('requireAccess()')<reels.indexOf('aadhyantJobReelForm?.init'));assert.match(builder,/admin\/job-reel-form\.js/);assert.doesNotMatch(builder,/admin\/poster-reel\.js/);
  assert.match(code,/admin_queue_poster_reel/);assert.doesNotMatch(code,/client\.from\(|\.schema\(|api\.openai|fetch\(/);
});

test('English custom descriptions split into Hindi-compatible server payloads without losing their text',()=>{
  const text='भर्ती की जानकारी। '+('Custom condition 1234. '.repeat(200)),parts=api.splitNarration(text);
  assert.ok(parts.length>1);assert.ok(parts.every(x=>/[\u0900-\u097f]/.test(x)&&x.length<=1800));
  assert.equal(parts.map(x=>x.replace(/^अन्य जानकारी: /,'')).join(' ').replace(/\s+/g,''),text.replace(/\s+/g,''));
});

test('a role must be selected explicitly before a Hindi announcement is generated',async()=>{const u=ui();field(u.roles()[0],'type').value='';await u.el('announcement-generate').emit('click');assert.equal(u.el('announcement-draft').value,'');assert.match(u.el('announcement-status').textContent,/Choose a job role/);assert.equal(u.calls.length,0);});
