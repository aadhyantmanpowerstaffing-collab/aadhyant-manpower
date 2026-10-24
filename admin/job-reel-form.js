(function(root){
  'use strict';
  const normalize=value=>String(value??'').replace(/\r\n?/g,'\n').trim();
  const CONTACT='9586785800',PART_LIMIT=1800,MAX_TEXT=12000;
  const ROLE_OPTIONS=[['helper','Helper','हेल्पर'],['operator','Machine Operator','मशीन ऑपरेटर'],['cnc','CNC Operator','सीएनसी ऑपरेटर'],['hpdc','HPDC Operator','एचपीडीसी ऑपरेटर'],['quality','Quality Department','क्वालिटी विभाग'],['ppc','PPC','पीपीसी'],['fitter','ITI Fitter / Tool Room','आईटीआई फिटर / टूल रूम'],['guard','Security Guard','सिक्योरिटी गार्ड'],['supervisor','Security Supervisor','सिक्योरिटी सुपरवाइज़र'],['custom','Other / custom role','']];
  const QUALIFICATIONS=[['','Not specified',''],['5','5th pass','पाँचवीं पास'],['10','10th pass','दसवीं पास'],['12','12th pass','बारहवीं पास'],['iti','ITI','आईटीआई'],['diploma','Diploma','डिप्लोमा'],['degree','B.E. / B.Tech','बीई / बीटेक'],['10-12-iti','10th / 12th / ITI','दसवीं, बारहवीं या आईटीआई'],['any','Any qualification','किसी भी शैक्षणिक योग्यता वाले उम्मीदवार'],['custom','Other / custom qualification','']];
  const PERIODS={month:'प्रति माह',day:'प्रतिदिन',shift:'प्रति शिफ्ट',hour:'प्रति घंटा'};
  const SHIFTS={abc:'ए, बी और सी तीन शिफ्ट',day:'दिन की शिफ्ट',night:'रात की शिफ्ट',rotational:'रोटेशनल शिफ्ट'};
  const FACILITIES={pf:{yes:'पीएफ उपलब्ध है',no:'पीएफ उपलब्ध नहीं है'},esic:{yes:'ईएसआईसी उपलब्ध है',no:'ईएसआईसी उपलब्ध नहीं है'},bus:{free:'मुफ्त बस सुविधा है',paid:'बस सुविधा शुल्क के साथ है',yes:'बस सुविधा उपलब्ध है',no:'बस सुविधा उपलब्ध नहीं है'},canteen:{free:'मुफ्त कैंटीन है',paid:'कैंटीन शुल्क के साथ है',yes:'कैंटीन उपलब्ध है',no:'कैंटीन उपलब्ध नहीं है'},room:{free:'रहने की सुविधा मुफ्त है',paid:'रूम या पीजी का खर्च उम्मीदवार को देना होगा',yes:'रहने की सुविधा उपलब्ध है',no:'रहने की सुविधा उपलब्ध नहीं है'},uniform:{free:'यूनिफॉर्म मुफ्त मिलेगी',paid:'यूनिफॉर्म का शुल्क देना होगा',yes:'यूनिफॉर्म उपलब्ध है',no:'यूनिफॉर्म उपलब्ध नहीं है'},shoes:{free:'सेफ्टी शूज मुफ्त मिलेंगे',paid:'सेफ्टी शूज का शुल्क देना होगा',yes:'सेफ्टी शूज उपलब्ध हैं',no:'सेफ्टी शूज उपलब्ध नहीं हैं'}};
  function money(value,label){const s=normalize(value);if(!s)return '';const n=Number(s);if(!Number.isFinite(n)||n<0||n>10000000)throw Error(`Enter a valid ${label}.`);return new Intl.NumberFormat('en-IN',{maximumFractionDigits:2}).format(n);}
  function salaryRange(start,end,label){const a=money(start,label),b=money(end,label);if(b&&!a)throw Error(`Enter the starting ${label} before its upper amount.`);if(b&&Number(end)<Number(start))throw Error(`The upper ${label} must not be below its starting amount.`);return a?(b?`${a} से ₹${b}`:a):'';}
  function dateHindi(value){if(!value)return '';if(!/^\d{4}-\d{2}-\d{2}$/.test(value))throw Error('Choose a valid interview date.');const [y,m,d]=value.split('-').map(Number),dt=new Date(Date.UTC(y,m-1,d));if(dt.getUTCFullYear()!==y||dt.getUTCMonth()!==m-1||dt.getUTCDate()!==d)throw Error('Choose a valid interview date.');return `${d} ${['जनवरी','फ़रवरी','मार्च','अप्रैल','मई','जून','जुलाई','अगस्त','सितंबर','अक्टूबर','नवंबर','दिसंबर'][m-1]} ${y}`;}
  function timeHindi(value){if(!value)return '';const match=/^(\d{2}):(\d{2})$/.exec(value);if(!match||+match[1]>23||+match[2]>59)throw Error('Choose a valid interview time.');const h=+match[1],m=+match[2],period=h<12&&h>0?'सुबह':h>=12&&h<16?'दोपहर':h>=16&&h<20?'शाम':'रात';return `${period} ${h%12||12} बजे${m?` ${m} मिनट`:''}`;}
  function buildNarration(data){
    const company=normalize(data.company),location=normalize(data.location),roles=data.roles||[];
    if(!company||!location)throw Error('Enter the company and job location.');
    if(!roles.length||roles.length>10)throw Error('Add between 1 and 10 job roles.');
    const paragraphs=[`${company} में भर्ती है। नौकरी का स्थान ${location} है।`];
    for(const role of roles){
      const option=ROLE_OPTIONS.find(x=>x[0]===role.type);if(!option)throw Error('Choose a job role.');
      const custom=normalize(role.name),name=option[2]?option[2]+(custom?` — ${custom}`:''):custom;
      if(!name)throw Error('Enter the custom job role.');
      const lines=[`${name} के लिए भर्ती।`],vacancies=normalize(role.vacancies);
      if(vacancies){if(!/^\d+$/.test(vacancies)||+vacancies<1||+vacancies>100000)throw Error('Enter a valid number of vacancies.');lines.push(`कुल ${vacancies} पद।`);}
      const qualification=QUALIFICATIONS.find(x=>x[0]===(role.qualification||''));if(!qualification)throw Error('Choose a qualification.');
      const extra=normalize(role.trade);if(role.qualification==='custom'&&!extra)throw Error('Enter the custom qualification.');
      if(qualification[2]||extra)lines.push(`योग्यता: ${[qualification[2],extra].filter(Boolean).join('। ')}।`);
      const ctc=salaryRange(role.ctc,role.ctcMax,'CTC'),takeHome=salaryRange(role.takeHome,role.takeHomeMax,'in-hand salary'),overtime=money(role.overtime,'overtime rate');
      if((ctc||takeHome)&&!PERIODS[role.period])throw Error('Choose the salary period.');
      if(ctc)lines.push(`सीटीसी ₹${ctc} ${PERIODS[role.period]}।`);
      if(takeHome)lines.push(`हाथ में वेतन ₹${takeHome} ${PERIODS[role.period]}।`);
      const duty=normalize(role.duty);if(duty){if(!Number.isFinite(Number(duty))||+duty<=0||+duty>24)throw Error('Duty must be between 0 and 24 hours.');lines.push(`ड्यूटी ${duty} घंटे।`);}
      if(overtime)lines.push(`ओवरटाइम ₹${overtime} प्रति घंटा।`);
      if(normalize(role.remarks))lines.push(`पद से जुड़ी अन्य जानकारी: ${normalize(role.remarks)}`);
      paragraphs.push(lines.join(' '));
    }
    if(normalize(data.age))paragraphs.push(`उम्र: ${normalize(data.age)}।`);
    if(data.shift){if(!SHIFTS[data.shift])throw Error('Choose a valid shift.');paragraphs.push(`शिफ्ट: ${SHIFTS[data.shift]}।`);}
    const facilities=[];for(const key of Object.keys(FACILITIES)){if(data[key]){if(!FACILITIES[key][data[key]])throw Error('Choose a valid facility.');facilities.push(FACILITIES[key][data[key]]);}}
    if(facilities.length)paragraphs.push(`सुविधाएँ: ${facilities.join('। ')}।`);
    if(normalize(data.benefits))paragraphs.push(`अन्य सुविधाएँ: ${normalize(data.benefits)}`);
    const start=dateHindi(data.startDate),end=dateHindi(data.endDate),time=timeHindi(data.time);
    if(data.startDate&&data.endDate&&data.endDate<data.startDate)throw Error('Interview end date must be on or after the start date.');
    if(start||end)paragraphs.push(start&&end?`इंटरव्यू ${start} से ${end} तक।`:start?`इंटरव्यू की तारीख ${start}।`:`इंटरव्यू ${end} तक।`);
    if(time)paragraphs.push(`इंटरव्यू का समय ${time} है।`);
    if(normalize(data.address))paragraphs.push(`इंटरव्यू का पता: ${normalize(data.address)}`);
    if(normalize(data.documents))paragraphs.push(`साथ लाने वाले दस्तावेज: ${normalize(data.documents)}`);
    if(normalize(data.other))paragraphs.push(`अन्य जरूरी जानकारी: ${normalize(data.other)}`);
    const text=paragraphs.join('\n\n');if(text.length>MAX_TEXT)throw Error('This announcement is too long. Keep the complete narration under 12,000 characters.');return text;
  }
  function splitNarration(value){
    const text=normalize(value);if(text.length<10||text.length>MAX_TEXT||!/[\u0900-\u097f]/.test(text))throw Error('Enter 10–12,000 characters of reviewed Hindi narration.');
    const parts=[];let remaining=text;const bodyLimit=PART_LIMIT-32;
    while(remaining.length>bodyLimit){
      const slice=remaining.slice(0,bodyLimit);let cut=slice.lastIndexOf('\n\n');
      if(cut<Math.floor(bodyLimit/2)){const sentence=Math.max(slice.lastIndexOf('। '),slice.lastIndexOf('. '));cut=sentence<0?-1:sentence+1;}
      if(cut<Math.floor(bodyLimit/2))cut=slice.lastIndexOf(' ');
      if(cut<1)cut=bodyLimit;
      if(remaining.length-cut<10)cut=remaining.length-10;
      if(/[\uD800-\uDBFF]/.test(remaining[cut-1]))cut--;
      parts.push(remaining.slice(0,cut).trim());remaining=remaining.slice(cut).trim();
    }
    if(remaining)parts.push(remaining);
    for(let i=0;i<parts.length;i++)if(!/[\u0900-\u097f]/.test(parts[i]))parts[i]='अन्य जानकारी: '+parts[i];
    if(parts.some(x=>x.length<10||x.length>PART_LIMIT))throw Error('Adjust the narration spacing before creating the video parts.');
    return parts;
  }
  const api={buildNarration,splitNarration,dateHindi,timeHindi,CONTACT};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  root.aadhyantJobReelForm=api;
  if(!root.document)return;
  api.init=({client,onQueued})=>{
    const $=id=>document.getElementById(id),form=$('announcement-form'),roles=$('announcement-roles'),draft=$('announcement-draft'),review=$('announcement-reviewed'),heading=$('announcement-title'),file=$('announcement-file'),preview=$('announcement-image'),status=$('announcement-status'),create=$('announcement-create');
    const COMMON=['company','location','age','shift','pf','esic','bus','canteen','room','uniform','shoes','benefits','startDate','endDate','time','address','documents','other'];
    let rows=[],serial=0,busy=false,batch=null,coverPromise=null;
    const partial=()=>batch&&batch.next>0&&batch.next<batch.parts.length;
    const controls=()=>Array.from(form.querySelectorAll('input,select,textarea,button'));
    function lock(value){busy=value;for(const el of controls())el.disabled=value||!!partial();create.disabled=value;}
    function count(){try{const parts=splitNarration(draft.value);$('announcement-count').textContent=`${draft.value.length} characters · ${parts.length} video ${parts.length===1?'part':'parts'}. All narration is included. Contact ${CONTACT} is added to every part.`;}catch{$('announcement-count').textContent='Create the Hindi narration, review all details, then confirm.';}}
    function changed(){if(partial())return;review.checked=false;batch=null;count();}
    function detailsChanged(){if(partial())return;draft.value='';coverPromise=null;changed();status.textContent='Details changed. Select Create Hindi narration again.';}
    function field(row,key,label,type='text',options=null){
      const wrapper=document.createElement('label');wrapper.textContent=label;const input=document.createElement(options?'select':'input');input.id=`role-${row.serial}-${key}`;input.dataset.field=key;
      if(options)for(const [value,name] of options){const option=document.createElement('option');option.value=value;option.textContent=name;input.append(option);}else{input.type=type;input.maxLength=500;if(type==='number'){input.min=key==='vacancies'?'1':'0';input.step=key==='vacancies'?'1':'0.01';}}
      input.value=key==='period'?'month':'';
      wrapper.append(input);row.grid.append(wrapper);row.fields[key]=input;input.addEventListener('input',detailsChanged);return input;
    }
    function addRole(){
      if(busy||partial())return;if(rows.length>=10){status.textContent='You can include up to 10 job roles.';return;}
      const row={serial:++serial,fields:{},card:document.createElement('fieldset'),grid:document.createElement('div')};row.card.className='announcement-role';row.grid.className='announcement-grid';
      const legend=document.createElement('legend');legend.textContent=`Job role ${serial}`;row.card.append(legend,row.grid);
      field(row,'type','Role', 'text',[['','Choose a role'],...ROLE_OPTIONS]);field(row,'name','Custom role / specialization (Hindi recommended)');
      field(row,'takeHome','In-hand salary — from (₹)','number');field(row,'takeHomeMax','In-hand salary — to (₹, optional)','number');field(row,'period','Salary period','text',[['month','Per month'],['day','Per day'],['shift','Per shift'],['hour','Per hour']]);field(row,'duty','Duty hours','number');field(row,'overtime','Overtime (₹ per hour)','number');
      const advanced=document.createElement('details'),summary=document.createElement('summary');summary.textContent='Qualification, vacancies, CTC and other role conditions';advanced.append(summary);const primary=row.grid;row.grid=document.createElement('div');row.grid.className='announcement-grid';advanced.append(row.grid);row.card.append(advanced);
      field(row,'qualification','Qualification','text',QUALIFICATIONS);field(row,'trade','Trade / additional qualification (Hindi recommended)');field(row,'vacancies','Number of vacancies','number');field(row,'ctc','CTC — from (₹)','number');field(row,'ctcMax','CTC — to (₹, optional)','number');field(row,'remarks','Other role conditions (Hindi recommended)');row.grid=primary;
      const remove=document.createElement('button');remove.type='button';remove.className='admin-button';remove.textContent='Remove this role';remove.addEventListener('click',()=>{if(busy||partial())return;if(rows.length===1){status.textContent='Keep at least one job role.';return;}rows=rows.filter(x=>x!==row);row.card.remove();detailsChanged();});row.card.append(remove);rows.push(row);roles.append(row.card);detailsChanged();
    }
    function values(){const data={roles:rows.map(row=>Object.fromEntries(Object.entries(row.fields).map(([key,el])=>[key,el.value])))};for(const key of COMMON)data[key]=$(`announcement-${key}`).value;return data;}
    for(const key of COMMON)$(`announcement-${key}`).addEventListener('input',detailsChanged);
    draft.addEventListener('input',changed);heading.addEventListener('input',()=>{heading.dataset.auto='no';coverPromise=null;changed();});file.addEventListener('change',()=>{coverPromise=null;preview.hidden=true;preview.removeAttribute('src');changed();});
    $('announcement-add-role').addEventListener('click',addRole);
    $('announcement-generate').addEventListener('click',()=>{if(busy||partial())return;try{draft.value=buildNarration(values());if(heading.value==='नौकरी का नया अवसर'||heading.dataset.auto==='yes'){const title=normalize($('announcement-company').value)+' — भर्ती';heading.value=title.length>60?title.slice(0,58).replace(/[\uD800-\uDBFF]$/,'')+'…':title;heading.dataset.auto='yes';}changed();status.textContent='Complete Hindi narration is ready below. Custom names and descriptions stay exactly as entered; use Hindi for Hindi wording. Review every detail before creating.';}catch(e){status.textContent=e.message;}});
    function wrap(ctx,value,y,size,width){ctx.font=`bold ${size}px sans-serif`;let line='';for(const word of String(value).split(/\s+/)){const next=line?line+' '+word:word;if(ctx.measureText(next).width>width&&line){ctx.fillText(line,80,y);y+=size*1.4;line=word;}else line=next;}if(line)ctx.fillText(line,80,y);return y+size*1.6;}
    async function cover(){
      if(coverPromise)return coverPromise;
      coverPromise=(async()=>{
        const canvas=document.createElement('canvas'),ctx=canvas.getContext('2d'),selected=file.files[0];
        if(selected){
          if(!['image/jpeg','image/png'].includes(selected.type)||selected.size>6000000)throw Error('Choose a JPG or PNG cover smaller than 6 MB.');
          const bitmap=await createImageBitmap(selected);try{if(bitmap.width*bitmap.height>20000000)throw Error('Choose a cover under 20 megapixels.');const scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height));canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);}finally{bitmap.close();}
        }else{
          canvas.width=1080;canvas.height=1440;ctx.fillStyle='#092945';ctx.fillRect(0,0,1080,1440);ctx.fillStyle='#d8ef73';wrap(ctx,'AADHYANT',130,62,920);wrap(ctx,'MANPOWER & STAFFING',215,37,920);ctx.fillStyle='white';let y=wrap(ctx,heading.value,420,54,920);y=wrap(ctx,$('announcement-company').value,y+40,48,920);wrap(ctx,$('announcement-location').value,y+35,40,920);ctx.fillStyle='#d8ef73';wrap(ctx,'WhatsApp: '+CONTACT,1280,48,920);
        }
        const data=canvas.toDataURL('image/jpeg',.72);if(data.length>900023)throw Error('Cover is too detailed. Use a smaller image.');preview.src=data;preview.hidden=false;return data.split(',')[1];
      })();try{return await coverPromise;}catch(e){coverPromise=null;throw e;}
    }
    form.addEventListener('submit',async event=>{
      event.preventDefault();if(busy)return;
      const title=normalize(heading.value),text=normalize(draft.value);let parts;
      try{if(!title||title.length>60)throw Error('Enter a video heading of 1–60 characters.');if(!review.checked)throw Error('Review and confirm the complete narration first.');parts=splitNarration(text);if(!normalize($('announcement-company').value)||!normalize($('announcement-location').value))throw Error('Enter the company and job location.');}
      catch(e){status.textContent=e.message;return;}
      const signature=JSON.stringify([title,text]);
      if(batch&&batch.signature!==signature){status.textContent='Finish retrying the remaining video parts before changing this announcement.';return;}
      lock(true);
      try{
        const poster=await cover();
        if(!batch)batch={signature,poster,next:0,parts:parts.map((part,i)=>({id:crypto.randomUUID(),text:part,title:parts.length===1?title:`${title} (${i+1}/${parts.length})`}))};
        for(;batch.next<batch.parts.length;batch.next++){
          const part=batch.parts[batch.next];status.textContent=`Queueing video part ${batch.next+1} of ${batch.parts.length}…`;
          const {data,error}=await client.rpc('admin_queue_poster_reel',{p_request_id:part.id,p_title:part.title,p_text:part.text,p_poster:batch.poster,p_reviewed:true});
          if(error||!data)throw Error('Could not queue this part. Check that video generation is on and the daily limit is not reached, then retry.');
        }
        status.textContent=`${batch.parts.length} video ${batch.parts.length===1?'part is':'parts are'} queued with the existing Hindi voice and music. Refresh videos below to preview and download.`;
        await onQueued();
      }catch(e){status.textContent=(batch?.next?`${batch.next} of ${batch.parts.length} parts queued. Retry remaining parts on this page. `:'')+e.message;}
      finally{lock(false);}
    });
    addRole();status.textContent='Enter the job details, create the Hindi narration, review it and create your video.';
  };
})(typeof window!=='undefined'?window:globalThis);
