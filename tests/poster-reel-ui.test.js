'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const api=require('../admin/poster-reel.js');
const code=fs.readFileSync('admin/poster-reel.js','utf8');
function ui({ocr='Company: Test\nSalary 20000\nDuty 8 hours',translated='कंपनी टेस्ट। वेतन 20000। ड्यूटी 8 घंटे।',translation=true,failFirst=false}={}){
  const elements={},calls=[],voices=[];let refreshed=0,terminated=0,translations=0,seq=0;
  const el=id=>elements[id]||(elements[id]={value:'',checked:false,disabled:false,hidden:false,files:[],listeners:{},textContent:'',addEventListener(name,fn){this.listeners[name]=fn;},removeAttribute(name){delete this[name];},async emit(name){return this.listeners[name]?.({preventDefault(){}});}});
  const document={getElementById:el,createElement:tag=>tag==='canvas'?{getContext:()=>({fillRect(){},drawImage(){}}),toDataURL:()=>('data:image/jpeg;base64,/9j/'+ 'A'.repeat(200))}:null};
  const window={document,Tesseract:{async createWorker(language){voices.push(language);return{async recognize(){return{data:{text:ocr}};},async terminate(){terminated++;}};}}};
  if(translation)window.Translator={async create(){return{async translate(){translations++;return translated;},destroy(){}};}};
  vm.runInNewContext(code,{window,document,console,setTimeout,clearTimeout,crypto:{randomUUID:()=>`request-${++seq}`},createImageBitmap:async()=>({width:800,height:1000,close(){}})});
  el('poster-source').value='en';el('poster-title').value='नौकरी का अवसर';el('poster-file').files=[{type:'image/jpeg',size:1000}];
  window.aadhyantPosterReel.init({client:{async rpc(name,args){calls.push({name,args});return failFirst&&calls.length===1?{error:{message:'temporary'}}:{data:'queued-id'};}},onQueued:async()=>{refreshed++;}});
  return{el,calls,voices,stats:()=>({refreshed,terminated,translations})};
}
test('poster number comparison preserves decimal and Indian formatted values and normalizes Hindi digits',()=>{
  assert.deepEqual(api.numbers('₹20,000.50; phone 9586785800; 8h'),api.numbers('२०,०००.५०; ९५८६७८५८००; ८ घंटे'));
  assert.equal(api.validNarration('English announcement'),false);assert.equal(api.validNarration('साणंद में नई भर्ती का अवसर।'),true);
});
test('poster OCR, translation and explicit review queue the same poster and reviewed text through the Admin RPC',async()=>{
  const u=ui();await u.el('poster-read').emit('click');assert.equal(u.stats().terminated,1);assert.equal(u.voices[0],'eng');assert.match(u.el('poster-raw').value,/20000/);
  await u.el('poster-translate').emit('click');assert.equal(u.stats().translations,1);
  await u.el('poster-form').emit('submit');assert.equal(u.calls.length,0);
  u.el('poster-reviewed').checked=true;await u.el('poster-form').emit('submit');
  assert.equal(u.calls.length,1);assert.equal(u.calls[0].name,'admin_queue_poster_reel');assert.equal(u.calls[0].args.p_reviewed,true);assert.match(u.calls[0].args.p_poster,/^\/9j\//);assert.equal(u.calls[0].args.p_text,u.el('poster-hindi').value);assert.equal(u.stats().refreshed,1);
});
test('translation cannot silently replace an extracted salary or phone number',async()=>{
  const u=ui({translated:'कंपनी टेस्ट। वेतन 30000। ड्यूटी 8 घंटे।'});await u.el('poster-read').emit('click');await u.el('poster-translate').emit('click');assert.equal(u.el('poster-hindi').value,'');assert.match(u.el('poster-status').textContent,/changed a number/);assert.equal(u.calls.length,0);
});
test('unsupported translation stays editable and never claims an English draft is Hindi',async()=>{
  const u=ui({translation:false});await u.el('poster-read').emit('click');await u.el('poster-translate').emit('click');assert.match(u.el('poster-status').textContent,/desktop Chrome/);assert.equal(u.el('poster-hindi').value,'');assert.equal(u.calls.length,0);
});
test('editing narration revokes review and generates a new idempotency request; network retry reuses its request',async()=>{
  const u=ui({failFirst:true});await u.el('poster-read').emit('click');await u.el('poster-translate').emit('click');u.el('poster-reviewed').checked=true;
  await u.el('poster-form').emit('submit');await u.el('poster-form').emit('submit');assert.equal(u.calls[0].args.p_request_id,u.calls[1].args.p_request_id);
  u.el('poster-hindi').value+=' स्थान साणंद।';await u.el('poster-hindi').emit('input');assert.equal(u.el('poster-reviewed').checked,false);await u.el('poster-form').emit('submit');assert.equal(u.calls.length,2);
  u.el('poster-reviewed').checked=true;await u.el('poster-form').emit('submit');assert.notEqual(u.calls[1].args.p_request_id,u.calls[2].args.p_request_id);
});
test('Hindi and Gujarati OCR choose their models and invalid files do not start work',async()=>{
  const u=ui({ocr:'साणंद में भर्ती। वेतन 20000 रुपये।'});u.el('poster-source').value='hi';await u.el('poster-read').emit('click');assert.equal(u.voices[0],'hin+eng');assert.match(u.el('poster-hindi').value,/साणंद/);
  u.el('poster-source').value='gu';await u.el('poster-read').emit('click');assert.equal(u.voices[1],'guj+eng');assert.equal(u.el('poster-hindi').value,'');assert.match(u.el('poster-status').textContent,/Gujarati/);
  u.el('poster-file').files=[{type:'application/pdf',size:100}];await u.el('poster-read').emit('click');assert.equal(u.voices.length,2);
});
test('poster page confines OCR permissions to its own route, pins OCR, and initializes only after Admin access',()=>{
  const html=fs.readFileSync('admin/reels.html','utf8'),reels=fs.readFileSync('admin/reels.js','utf8');
  assert.match(code,/tesseract\.js@6\.0\.1/);assert.match(code,/script\.integrity='sha384-/);assert.match(html,/wasm-unsafe-eval/);assert.match(html,/worker-src/);assert.match(html,/media-src/);
  assert.ok(reels.indexOf('requireAccess()')<reels.indexOf('aadhyantPosterReel?.init'));
  assert.equal((reels.match(/aadhyantPosterReel\?\.init/g)||[]).length,1);
  assert.doesNotMatch(code,/innerHTML|api\.openai|translate\.googleapis/);
});
