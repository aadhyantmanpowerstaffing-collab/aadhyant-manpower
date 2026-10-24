(function(root){
  'use strict';
  const normalize = text => String(text).replace(/\r\n?/g,'\n').replace(/[\t ]+/g,' ').replace(/\n{3,}/g,'\n\n').trim();
  const numbers = text => (String(text).replace(/[०-९]/g,c=>String(c.charCodeAt(0)-0x0966)).match(/\d[\d,.]*/g)||[]).map(x=>x.replace(/[,.]/g,''));
  const validNarration = text => text.length>=10 && text.length<=1800 && /[\u0900-\u097f]/.test(text);
  // Keep the OCR image independent of the smaller JPEG used as the video cover.
  const ocrSize=(width,height)=>{const scale=Math.min(3,3200/Math.max(width,height));return {width:Math.round(width*scale),height:Math.round(height*scale)};};
  function cleanLine(value){
    return normalize(value).replace(/^[^\p{L}\p{N}₹]+/u,'').replace(/[|{}<>_~]+/g,' ').replace(/ +/g,' ').trim();
  }
  function usableLine(value){
    const s=cleanLine(value),letters=(s.match(/[\p{L}\p{N}\p{M}]/gu)||[]).length;
    if(!/\p{L}/u.test(s)&&!/[\-/]/.test(s)&&numbers(s).join('').length<5)return false;
    return letters>=3 && letters/Math.max(s.length,1)>.55 && !/([=\\^])/.test(s);
  }
  function linesFrom(data){
    return (data.blocks||[]).flatMap(b=>(b.paragraphs||[]).flatMap(p=>(p.lines||[]))).map(line=>({
      text:cleanLine(line.text),confidence:line.confidence??data.confidence??0,bbox:line.bbox,verified:!!data.verified
    })).filter(line=>usableLine(line.text));
  }
  function overlap(a,b){
    if(!a||!b)return 0;
    const area=Math.max(0,Math.min(a.x1,b.x1)-Math.max(a.x0,b.x0))*Math.max(0,Math.min(a.y1,b.y1)-Math.max(a.y0,b.y0));
    return area/Math.max(1,Math.min((a.x1-a.x0)*(a.y1-a.y0),(b.x1-b.x0)*(b.y1-b.y0)));
  }
  function extractPoster(passes){
    const selected=[],all=[];let uncertain=0;
    for(const data of passes){
      let lines=linesFrom(data);
      // Text-only adapters still need a confidence score; missing confidence fails closed.
      if(!lines.length)lines=normalize(data.text||'').split('\n').filter(usableLine).map(text=>({text:cleanLine(text),confidence:data.confidence??0}));
      for(const line of lines){
        all.push(line);
        if(line.confidence<(line.verified?50:55)){uncertain++;continue;}
        const matches=selected.filter(x=>overlap(x.bbox,line.bbox)>.65||(!x.bbox&&!line.bbox&&x.text.toLowerCase()===line.text.toLowerCase()));
        if(!matches.length)selected.push(line);
        else if(matches.every(x=>(line.verified&&!x.verified)||(!x.verified&&line.confidence>x.confidence))){
          for(const match of matches)selected.splice(selected.indexOf(match),1);
          selected.push(line);
        }
      }
    }
    selected.sort((a,b)=>(a.bbox?.y0??0)-(b.bbox?.y0??0)||(a.bbox?.x0??0)-(b.bbox?.x0??0));
    const text=normalize(selected.map(x=>x.text).join('\n'));
    const confidence=selected.length?selected.reduce((sum,x)=>sum+x.confidence,0)/selected.length:0;
    const conflicts=selected.filter(line=>!line.verified&&all.some(other=>other!==line&&other.confidence>=55&&overlap(other.bbox,line.bbox)>.65&&numbers(other.text).length&&numbers(line.text).length&&JSON.stringify(numbers(other.text))!==JSON.stringify(numbers(line.text)))).length;
    return {text,confidence,uncertain,conflicts,reliable:selected.length>=3&&confidence>=65&&text.length>=30&&conflicts===0};
  }
  const sourceQuality=value=>{
    const rows=normalize(value).split('\n').filter(Boolean);
    return rows.length>0&&rows.filter(usableLine).length/rows.length>=.85&&!/[\\^=]{2}|[|{}]{2}/.test(value);
  };
  const api={normalize,numbers,validNarration,ocrSize,extractPoster,sourceQuality};
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
    let poster=null,requestId=null,busy=false,ocrReliable=false,extractedText='';
    raw.addEventListener('change',()=>{text.value='';changed();});
    const changed=()=>{review.checked=false;requestId=null;};
    const lock=value=>{busy=value;for(const el of [file,read,source,raw,text,title,translate,create,review])el.disabled=value;};
    for(const el of [text,title])el.addEventListener('input',changed);
    for(const el of [raw,source])el.addEventListener('input',()=>{text.value='';changed();});
    file.addEventListener('change',()=>{poster=null;image.removeAttribute('src');image.hidden=true;raw.value='';text.value='';changed();message.textContent='Choose Read poster to extract the text.';});
    read.addEventListener('click',async()=>{
      if(busy)return;
      const selected=file.files[0];
      if(!selected||!['image/jpeg','image/png'].includes(selected.type)||selected.size>6000000){message.textContent='Choose a JPG or PNG recruitment poster smaller than 6 MB.';return;}
      changed();poster=null;ocrReliable=false;lock(true);raw.value='';text.value='';let worker,timer,aborted=false;
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
          const dimensions=ocrSize(bitmap.width,bitmap.height),ocr=document.createElement('canvas');
          ocr.width=dimensions.width;ocr.height=dimensions.height;
          const oc=ocr.getContext('2d');oc.fillStyle='white';oc.fillRect(0,0,ocr.width,ocr.height);oc.drawImage(bitmap,0,0,ocr.width,ocr.height);
          const contrast=document.createElement('canvas');contrast.width=ocr.width;contrast.height=ocr.height;
          const cc=contrast.getContext('2d');cc.drawImage(ocr,0,0);
          const pixels=cc.getImageData(0,0,contrast.width,contrast.height);
          for(let i=0;i<pixels.data.length;i+=4){const v=(.299*pixels.data[i]+.587*pixels.data[i+1]+.114*pixels.data[i+2])>170?255:0;pixels.data[i]=pixels.data[i+1]=pixels.data[i+2]=v;}
          cc.putImageData(pixels,0,0);
          const engine=await loadOCR();
          const languages={en:'eng',hi:'eng+hin',gu:'eng+guj'};
          const task=(async()=>{
            worker=await engine.createWorker(languages[source.value],1,{
              workerPath:'https://cdn.jsdelivr.net/npm/tesseract.js@6.0.1/dist/worker.min.js',
              corePath:'https://cdn.jsdelivr.net/npm/tesseract.js-core@6.0.0',
              langPath:'https://tessdata.projectnaptha.com/4.0.0',
              logger:info=>{if(info.status==='recognizing text')message.textContent=`Reading poster: ${Math.round(info.progress*100)}%`;}
            });
            if(aborted){await worker.terminate();throw Error('Poster reading cancelled.');}
            await worker.setParameters({tessedit_pageseg_mode:'11',preserve_interword_spaces:'1',user_defined_dpi:'300'});
            const original=await worker.recognize(ocr,{}, {blocks:true});
            if(aborted)throw Error('Poster reading cancelled.');
            message.textContent='Checking coloured text, amounts and dates…';
            const enhanced=await worker.recognize(contrast,{}, {blocks:true});
            const passes=[original.data,enhanced.data];
            // A single page pass can interleave salary rows across poster columns.
            // Read each column as a block too, retaining absolute OCR coordinates.
            if(ocr.width/ocr.height>.45){
              await worker.setParameters({tessedit_pageseg_mode:'6'});
              const half=Math.floor(ocr.width/2);
              for(const left of [0,half]){
                if(aborted)throw Error('Poster reading cancelled.');
                message.textContent='Reading poster columns separately…';
                const column=await worker.recognize(ocr,{rectangle:{left,top:0,width:left?ocr.width-half:half,height:ocr.height}},{blocks:true});
                passes.push(column.data);
              }
            }
            // Isolate uncertain numeric lines: coloured backgrounds otherwise turn 19,000
            // into 719,000 or change a phone digit, even at a high page confidence.
            const candidates=[];
            for(const line of passes.flatMap(linesFrom)){
              if(!line.bbox||line.confidence>=90||!/[0-9०-९]/.test(line.text))continue;
              if(!candidates.some(x=>overlap(x.bbox,line.bbox)>.65))candidates.push(line);
            }
            await worker.reinitialize('eng');
            await worker.setParameters({tessedit_pageseg_mode:'7',user_defined_dpi:'300'});
            for(const line of candidates.sort((a,b)=>Number(/\d{4}/.test(b.text))-Number(/\d{4}/.test(a.text))).slice(0,24)){
              if(aborted)throw Error('Poster reading cancelled.');
              message.textContent='Rechecking individual amounts, dates and contact digits…';
              const b=line.bbox,left=Math.max(0,b.x0-10),top=Math.max(0,b.y0-10);
              const check=await worker.recognize(ocr,{rectangle:{left,top,width:Math.min(ocr.width,b.x1+10)-left,height:Math.min(ocr.height,b.y1+10)-top}},{blocks:true});
              const strong=passes.flatMap(linesFrom).filter(x=>x.bbox&&x.confidence>=90&&overlap(x.bbox,b)>.65&&numbers(x.text).length);
              const disagrees=strong.some(x=>JSON.stringify(numbers(x.text))!==JSON.stringify(numbers(check.data.text)));
              if(!disagrees&&check.data.confidence>=50&&usableLine(check.data.text))passes.push({verified:true,blocks:[{paragraphs:[{lines:[{text:check.data.text,confidence:check.data.confidence,bbox:b}]}]}]});
            }
            return extractPoster(passes);
          })();
          const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Reading took too long. Retry with a clearer, smaller poster.')),180000);});
          const result=await Promise.race([task,timeout]),found=result.text;
          ocrReliable=result.reliable;
          if(found.length<10)throw Error('Not enough text could be read. Try a sharper image.');
          if(found.length>12000)throw Error('Too much text in this image. Crop it to the recruitment announcement.');
          raw.value=found;extractedText=found;poster=cover.split(',')[1];image.src=cover;image.hidden=false;
          if(!ocrReliable)message.textContent='Some poster text could not be read reliably. Compare the extracted text with the preview before translating. Try a sharper original if details are missing.';
          else message.textContent=source.value==='gu'?'Text extracted. Enter the final Hindi narration below; automatic Gujarati translation is not available in this version.':'Poster read in two passes. Check the preview, especially amounts and dates, then create the Hindi draft. Low-confidence marks were excluded; verify that no detail is missing.';
        }finally{bitmap.close();}
      }catch(e){message.textContent=e.message||'Poster could not be read. Please retry.';}
      finally{aborted=true;clearTimeout(timer);if(worker)await worker.terminate().catch(()=>{});lock(false);}
    });
    translate.addEventListener('click',async()=>{
      if(busy)return;changed();
      const original=normalize(raw.value);
      if(original.length<10||original.length>6000){message.textContent='Keep the source announcement between 10 and 6000 characters before translating.';return;}
      text.value='';
      if(!sourceQuality(original)||(!ocrReliable&&original===extractedText)){message.textContent='The extracted text contains unreadable marks. Correct it against the poster before creating narration.';return;}
      if(!/[A-Za-z]{3}/.test(original)&&source.value==='hi'){text.value=original;message.textContent='Review the Hindi narration against the poster before confirming.';return;}
      if(source.value==='gu'||!root.Translator){message.textContent='Automatic translation needs a supported desktop Chrome browser and an English poster. You can enter the final Hindi narration below.';return;}
      lock(true);let translator;
      try{
        message.textContent='Preparing free Hindi translation. Chrome may download a language pack…';
        translator=await root.Translator.create({sourceLanguage:'en',targetLanguage:'hi'});
        // Translate clean lines; never feed decorative OCR marks into the voice draft.
        const paragraphs=[];
        for(const line of original.split('\n').filter(Boolean)){
          paragraphs.push(/[A-Za-z]{3}/.test(line)?await translator.translate(line):line);
        }
        const translated=normalize(paragraphs.join('\n'));
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
