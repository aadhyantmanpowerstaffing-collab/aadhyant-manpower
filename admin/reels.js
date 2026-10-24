(async()=>{'use strict';
const status=document.querySelector('#reel-status'),controls=document.querySelector('#reel-controls'),list=document.querySelector('#reel-list'),select=document.querySelector('#reel-job'),create=document.querySelector('#reel-create'),refresh=document.querySelector('#reel-refresh'),dialog=document.querySelector('#reel-preview'),video=document.querySelector('#reel-video');
const access=await window.aadhyantAdminAuth?.requireAccess();if(!access)return;
const studioTabs=['create','library'].map(key=>document.querySelector(`#studio-${key}-tab`));
function selectStudioTab(index,focus=false){
 for(const [i,key] of ['create','library'].entries()){
  studioTabs[i].setAttribute('aria-selected',String(i===index));studioTabs[i].tabIndex=i===index?0:-1;
  document.querySelector(`#studio-${key}-panel`).hidden=i!==index;
 }
 if(focus)studioTabs[index].focus();
}
for(const [i,tab] of studioTabs.entries()){
 tab.addEventListener('click',()=>selectStudioTab(i));
 tab.addEventListener('keydown',event=>{
  const next=event.key==='Home'?0:event.key==='End'?1:['ArrowLeft','ArrowRight'].includes(event.key)?1-i:null;
  if(next!==null){event.preventDefault();selectStudioTab(next,true);}
 });
}
const client=window.aadhyantSupabase.client;window.aadhyantAdminAuth.monitorAccess();
const rpc=async(name,args={})=>{const {data,error}=await client.rpc(name,args);if(error)throw Error('Reel service is unavailable. Refresh and try again.');return data;};
const make=(tag,text)=>{const el=document.createElement(tag);el.textContent=text;return el;};
async function preview(id){status.textContent='Preparing your private video preview…';try{const {data,error}=await client.functions.invoke('recruitment-reels',{body:{id}});if(error||!data?.url)throw Error('The video is not ready, or the job details have changed. Refresh the list.');const url=new URL(data.url);if(url.origin!==window.AADHYANT_CONFIG.supabaseUrl||!url.pathname.startsWith('/storage/v1/object/sign/recruitment-reels/'))throw Error('Invalid preview link.');video.src=url.href;const link=document.querySelector('#reel-download');link.href=url.href;dialog.showModal();status.textContent='Check the video before sharing. The preview link lasts five minutes.';}catch(e){status.textContent=e.message;}}
async function load(){refresh.disabled=true;try{const [data,jobs]=await Promise.all([rpc('admin_reels'),rpc('admin_reel_jobs')]);controls.hidden=false;select.replaceChildren(make('option','Choose an open job'));select.options[0].value='';for(const j of jobs){const o=make('option',`${j.requirement_code} · ${j.job_role} · ${j.job_location}`);o.value=j.id;select.append(o);}create.disabled=!data.enabled;status.textContent=data.enabled?'Automatic videos are on. New posts enter the queue; generation time depends on queue and worker availability.':'Reel generation is paused.';list.replaceChildren();
const groups={};
for(const [key,title,description] of [
 ['announcements','Job details Reels','Videos created from the details you entered in this studio.'],
 ['jobs','Portal job Reels','Videos linked to approved public jobs on the portal.']
]){
 const section=make('section','');section.className='reel-library-group';
 const heading=make('h3',title);heading.id=`reel-group-${key}`;section.setAttribute('aria-labelledby',heading.id);
 const items=make('div','');items.className='reel-group-grid';
 section.append(heading,make('p',description),items);list.append(section);groups[key]=items;
}
for(const j of data.jobs){const card=make('article','');card.className='reel-card';card.append(make('h4',`${j.is_poster?'ANNOUNCEMENT':j.requirement_code} · ${j.job_role}`),make('p',`${j.is_poster?'Job announcement':j.company_name}${j.job_location?' · '+j.job_location:''}`),make('p',`Status: ${j.state} · Attempts: ${j.attempts}`));if(j.state==='ready'){const b=make('button','Preview / download');b.type='button';b.className='admin-button admin-button-primary';b.addEventListener('click',()=>preview(j.id));card.append(b);}if(j.state==='failed'&&j.is_poster){const retry=make('button','Retry poster video');retry.type='button';retry.className='admin-button';retry.addEventListener('click',async()=>{retry.disabled=true;try{await rpc('admin_retry_poster_reel',{p_id:j.id});await load();}catch(e){status.textContent=e.message;retry.disabled=false;}});card.append(retry);}else if(j.state==='failed')card.append(make('p','Choose this job above and retry.'));groups[j.is_poster?'announcements':'jobs'].append(card);}
for(const [key,items] of Object.entries(groups))if(!items.children.length)items.append(make('p',key==='announcements'?'No job details Reels yet. Open Create a Reel to make one.':'No portal job Reels yet. Choose an open job above to create one.'));}catch(e){status.textContent=e.message;}finally{refresh.disabled=false;}}
document.querySelector('#reel-form').addEventListener('submit',async e=>{e.preventDefault();create.disabled=true;try{await rpc('admin_queue_reel',{p_requirement_id:select.value});await load();status.textContent='Video queued. Refresh this page to see when it is ready.';}catch(e){status.textContent=e.message;}finally{create.disabled=false;}});
refresh.addEventListener('click',load);document.querySelector('#reel-close').addEventListener('click',()=>dialog.close());dialog.addEventListener('close',()=>{video.pause();video.removeAttribute('src');video.load();});window.aadhyantJobReelForm?.init({client,onQueued:async()=>{await load();selectStudioTab(1);document.querySelector('.studio-tabs').scrollIntoView({block:'start'});}});await load();
})();
