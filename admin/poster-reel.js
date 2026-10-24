(function(root){
  'use strict';
  const normalize = text => String(text).replace(/\r\n?/g,'\n').replace(/[\t ]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();
  const numbers = text => (String(text).replace(/[०-९]/g,c=>String(c.charCodeAt(0)-0x0966)).match(/\d[\d,.]*/g)||[]).map(x=>x.replace(/[,.]/g,''));
  const validNarration = text => text.length>=10 && text.length<=1800 && /[\u0900-\u097f]/.test(text);
  const api={normalize,numbers,validNarration};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  if(!root.document)return;
  let loadingOCR;
  function loadOCR(){
    if(root.Tesseract)return Promise.resolve(root.Tesseract);
    if(!loadingOCR)loadingOCR=new Promise((resolve,reject)=>{
      const script=document.createElement('script');
      script.src='https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/tesseract.min.js';
      script.integrity='sha384-r1ru3tcf6FhnCFR4B7pIFG+BhFF9LlFtz/P1y4pblWn3AGs9y3lBx5SKLNf4+rED';script.crossOrigin='anonymous';
      const timeout=setTimeout(()=>{script.remove();loadingOCR=null;reject(Error('OCR could not load. Check your connection and retry.'));},30000);
      script.onload=()=>{clearTimeout(timeout);resolve(root.Tesseract);};
      script.onerror=()=>{clearTimeout(timeout);script.remove();loadingOCR=null;reject(Error('OCR could not load. Check your connection and retry.'));};
      document.head.append(script);
    });
    return loadingOCR;
  }
  api.init=({client,onQueued})=>{
    const $=id=>document.getElementById(id),file=$('poster-file'),read=$('poster-read'),source=$('poster-source'),raw=$('poster-raw'),text=$('poster-hindi'),title=$('poster-title'),review=$('poster-reviewed'),translate=$('poster-translate'),create=$('poster-create'),message=$('poster-status'),image=$('poster-image');
    let poster=null,requestId=null,busy=false;
    const changed=()=>{review.checked=false;requestId=null;};
    const lock=value=>{busy=value;for(const el of [file,read,source,raw,text,title,translate,create,review])el.disabled=value;};
    for(const el of [raw,text,title,source])el.addEventListener('input',changed);
    file.addEventListener('change',()=>{poster=null;image.removeAttribute('src');image.hidden=true;raw.value='';text.value='';changed();message.textContent='Choose Read poster to extract the text.';});
    read.addEventListener('click',async()=>{
      if(busy)return;
      const selected=file.files[0];
      if(!selected||!['image/jpeg','image/png'].includes(selected.type)||selected.size>6000000){message.textContent='Choose a JPG or PNG recruitment poster smaller than 6 MB.';return;}
      changed();poster=null;lock(true);raw.value='';text.value='';let worker,timer,aborted=false;
      try{
        message.textContent='Reading the poster on this device. The first use downloads language files…';
        const bitmap=await createImageBitmap(selected);
        try{
          if(bitmap.width*bitmap.height>20000000)throw Error('Poster is too large. Use an image under 20 megapixels.');
          const canvas=document.createElement('canvas'),scale=Math.min(1,1600/Math.max(bitmap.width,bitmap.height));
          canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);
          const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);
          const cover=canvas.toDataURL('image/jpeg',0.72);
          if(cover.length>900023)throw Error('Poster is too detailed. Resize it and retry.');
          const engine=await loadOCR();
          const languages={en:'eng',hi:'hin+eng',gu:'guj+eng'};
          const task=(async()=>{
            worker=await engine.createWorker(languages[source.value],1,{
              workerPath:'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/worker.min.js',
              corePath:'https://cdn.jsdelivr.net/npm/tesseract.js-core@6.0.0',
              langPath:'https://tessdata.projectnaptha.com/4.0.0',
              logger:info=>{if(info.status==='recognizing text')message.textContent=`Reading poster: ${Math.round(info.progress*100)}%`;}
            });
            if(aborted){await worker.terminate();throw Error('Poster reading cancelled.');}
            const result=await worker.recognize(canvas);
            return normalize(result.data.text);
          })();
          const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Reading took too long. Retry with a clearer, smaller poster.')),180000);});
          const found=await Promise.race([task,timeout]);
          if(found.length<10)throw Error('Not enough text could be read. Try a sharper image.');
          if(found.length>12000)throw Error('Too much text in this image. Crop it to the recruitment announcement.');
          raw.value=found;poster=cover.split(',')[1];image.src=cover;image.hidden=false;
          if(source.value==='hi'&&found.length<=1800){text.value=found;message.textContent='Hindi draft is ready. Check the poster, salary, dates and contact numbers before confirming.';}
          else message.textContent=source.value==='en'?'Text extracted. Correct reading errors, then select Translate to Hindi.':'Text extracted. Enter the final Hindi narration below; automatic Gujarati translation is not available in this version.';
        }finally{bitmap.close();}
      }catch(e){message.textContent=e.message||'Poster could not be read. Please retry.';}
      finally{aborted=true;clearTimeout(timer);if(worker)await worker.terminate().catch(()=>{});lock(false);}
    });
    translate.addEventListener('click',async()=>{
      if(busy)return;changed();
      const original=normalize(raw.value);
      if(original.length<10||original.length>6000){message.textContent='Keep the source announcement between 10 and 6000 characters before translating.';return;}
      if(source.value==='hi'){text.value=original;message.textContent='Review and shorten the Hindi narration to 1800 characters if needed.';return;}
      if(source.value!=='en'||!root.Translator){message.textContent='Automatic translation needs a supported desktop Chrome browser and an English poster. You can enter the final Hindi narration below.';return;}
      lock(true);let translator;
      try{
        message.textContent='Preparing free Hindi translation. Chrome may download a language pack…';
        translator=await root.Translator.create({sourceLanguage:'en',targetLanguage:'hi'});
        const translated=normalize(await translator.translate(original));
        if(JSON.stringify(numbers(original))!==JSON.stringify(numbers(translated)))throw Error('Translation changed a number. Enter or correct the Hindi narration using the source text.');
        text.value=translated;
        message.textContent=translated.length>1800?'Hindi translation is ready. Shorten it to 1800 characters and verify every detail.':'Hindi draft is ready. Check names, salary, dates, duty and phone numbers before confirming.';
      }catch(e){message.textContent=e.message||'Translation is unavailable. Enter the Hindi narration manually.';}
      finally{translator?.destroy();lock(false);}
    });
    $('poster-form').addEventListener('submit',async event=>{
      event.preventDefault();if(busy)return;
      if(!poster){message.textContent='Read a recruitment poster first.';return;}
      const narration=normalize(text.value),heading=normalize(title.value);
      if(!validNarration(narration)||heading.length<1||heading.length>80){message.textContent='Enter a heading and 10–1800 characters of final Hindi narration.';return;}
      if(!review.checked){message.textContent='Confirm that you checked all details against the poster.';return;}
      requestId=requestId||crypto.randomUUID();lock(true);
      try{
        message.textContent='Saving the reviewed poster video…';
        const {data,error}=await client.rpc('admin_queue_poster_reel',{p_request_id:requestId,p_title:heading,p_text:narration,p_poster:poster,p_reviewed:true});
        if(error||!data)throw Error('The poster video could not be queued. Check that Reel generation is on and the daily limit is not reached, then retry.');
        message.textContent='Poster video queued. Refresh videos below until it is Ready, then preview and download.';
        await onQueued();
      }catch(e){message.textContent=e.message;}
      finally{lock(false);}
    });
  };
  root.aadhyantPosterReel=api;
})(typeof window!=='undefined'?window:globalThis);
