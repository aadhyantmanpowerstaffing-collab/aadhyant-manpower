(function (root) {
  'use strict';
  const headers = ['Name','Email','Mobile','Gender','Age','State','District'];
  const clean = value => String(value ?? '').trim();
  function mobile(value) {
    let result = clean(value).replace(/[\s()+-]/g,'');
    if (/^91[6-9]\d{9}$/.test(result)) result = result.slice(2);
    return /^[6-9]\d{9}$/.test(result) ? result : null;
  }
  function normalize(matrix) {
    if (!matrix.length) throw new Error('The file is empty.');
    const columns = matrix[0].map(v=>clean(v).replace(/^\uFEFF/,'').toLowerCase());
    if (headers.some(h=>columns.filter(v=>v===h.toLowerCase()).length!==1)) throw new Error('Required columns: '+headers.join(', '));
    const seen=new Map(),rows=[],errors=[],duplicates=[];
    matrix.slice(1).forEach((cells,index)=>{
      if (!cells.some(v=>clean(v))) return;
      const row=Object.fromEntries(headers.map(h=>[h,clean(cells[columns.indexOf(h.toLowerCase())])]));
      const phone=mobile(row.Mobile),gender=({male:'Male',female:'Female',other:'Other / Prefer not to say','other / prefer not to say':'Other / Prefer not to say'})[row.Gender.toLowerCase()];
      const age=Number(row.Age),reasons=[];
      if (!phone) reasons.push('invalid Indian mobile');
      if (!row.Name || row.Name.length>160) reasons.push('invalid name');
      if (!gender) reasons.push('invalid gender');
      if (!/^\d{1,2}$/.test(row.Age)||!Number.isInteger(age)||age<18||age>75) reasons.push('age must be 18–75');
      if (!row.State||row.State.length>160||!row.District||row.District.length>160) reasons.push('state and district required');
      if (row.Email && (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(row.Email)||row.Email.length>254)) reasons.push('invalid email');
      if (reasons.length) { errors.push({row:index+2,reasons});return; }
      row.Mobile=phone;row.Gender=gender;row.Age=age;
      if (seen.has(phone)) { duplicates.push({row:index+2,firstRow:seen.get(phone)});return; }
      seen.set(phone,index+2);rows.push(row);
    });
    if (rows.length>500) throw new Error('Import at most 500 contacts per file.');
    return {rows,errors,duplicates};
  }
  function csv(source) {
    const rows=[];let row=[],cell='',quoted=false;
    for(let i=0;i<source.length;i++) {
      const c=source[i];
      if(c==='"') { if(quoted&&source[i+1]==='"'){cell+='"';i++;}else if(!quoted&&cell){throw new Error('Invalid CSV quoting.');}else quoted=!quoted; }
      else if(c===','&&!quoted){row.push(cell);cell='';}
      else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&source[i+1]==='\n')i++;row.push(cell);rows.push(row);row=[];cell='';}
      else cell+=c;
    }
    if(quoted)throw new Error('Unclosed CSV quote.');
    if(cell||row.length){row.push(cell);rows.push(row);}
    return normalize(rows);
  }
  const decode=s=>s.replace(/&(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);/g,e=>{
    const named={'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"};
    if(named[e])return named[e];const code=e.startsWith('&#x')?parseInt(e.slice(3,-1),16):Number(e.slice(2,-1));
    if(code>0x10ffff)throw new Error('Invalid XML character.');return String.fromCodePoint(code);
  });
  const texts=s=>[...s.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)].map(m=>decode(m[1])).join('');
  async function unzip(buffer) {
    const bytes=new Uint8Array(buffer),v=new DataView(buffer),entries=new Map();let end=bytes.length-22;
    while(end>=Math.max(0,bytes.length-65557)&&v.getUint32(end,true)!==0x06054b50)end--;
    if(end<0||end<bytes.length-65557)throw new Error('Invalid XLSX archive.');
    const count=v.getUint16(end+10,true);let pos=v.getUint32(end+16,true),total=0;
    if(count>2000)throw new Error('XLSX archive is too large.');
    for(let i=0;i<count;i++){
      if(pos+46>bytes.length||v.getUint32(pos,true)!==0x02014b50)throw new Error('Invalid XLSX directory.');
      const flags=v.getUint16(pos+8,true),method=v.getUint16(pos+10,true),size=v.getUint32(pos+20,true),raw=v.getUint32(pos+24,true),nl=v.getUint16(pos+28,true),extra=v.getUint16(pos+30,true),comment=v.getUint16(pos+32,true),offset=v.getUint32(pos+42,true);
      const name=new TextDecoder().decode(bytes.slice(pos+46,pos+46+nl));pos+=46+nl+extra+comment;
      if(!/^xl\/(workbook\.xml|_rels\/workbook\.xml\.rels|sharedStrings\.xml|worksheets\/[^/]+\.xml)$/.test(name))continue;
      if(flags&1||raw>10000000||total+raw>20000000||offset+30>bytes.length||v.getUint32(offset,true)!==0x04034b50)throw new Error('Unsupported or oversized XLSX archive.');
      total+=raw;const start=offset+30+v.getUint16(offset+26,true)+v.getUint16(offset+28,true);
      if(start+size>bytes.length)throw new Error('Truncated XLSX archive.');
      let output;
      if(method===0)output=bytes.slice(start,start+size);
      else if(method===8){
        const reader=new Blob([bytes.slice(start,start+size)]).stream().pipeThrough(new DecompressionStream('deflate-raw')).getReader(),chunks=[];let length=0;
        try {for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>raw||length>10000000)throw new Error('Oversized XLSX entry.');chunks.push(value);}}
        catch(error){await reader.cancel();throw error;}
        output=new Uint8Array(length);let at=0;for(const chunk of chunks){output.set(chunk,at);at+=chunk.length;}
      }else throw new Error('Unsupported XLSX compression.');
      if(output.length!==raw||entries.has(name))throw new Error('Invalid XLSX entry.');
      const xml=new TextDecoder().decode(output);if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('Unsupported XML declarations.');entries.set(name,xml);
    }
    return entries;
  }
  async function xlsx(buffer) {
    const entries=await unzip(buffer),workbook=entries.get('xl/workbook.xml')||'',rels=entries.get('xl/_rels/workbook.xml.rels')||'';
    const sheet=workbook.match(/<sheet\s[^>]*r:id="([^"]+)"[^>]*\/?\s*>/);
    let target;
    for(const m of rels.matchAll(/<Relationship\s([^>]+)\/?\s*>/g)){
      if(m[1].match(/\bId="([^"]+)"/)?.[1]===sheet?.[1])target=m[1].match(/\bTarget="([^"]+)"/)?.[1];
    }
    if(!target||/\.\.|TargetMode="External"/.test(target))throw new Error('Worksheet not found.');
    const xml=entries.get(target.startsWith('/')?target.slice(1):'xl/'+target);
    if(!xml)throw new Error('Worksheet not found.');
    const strings=[...(entries.get('xl/sharedStrings.xml')||'').matchAll(/<si(?:\s[^>]*)?>([\s\S]*?)<\/si>/g)].map(m=>texts(m[1]));
    const matrix=[];
    for(const m of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)){
      const row=[];for(const c of m[1].matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)){
        const ref=c[1].match(/\br="([A-Z]+)\d+"/)?.[1];if(!ref)throw new Error('Cell reference missing.');
        let col=0;for(const ch of ref)col=col*26+ch.charCodeAt(0)-64;if(col>100)throw new Error('Too many columns.');
        if(/<f\b/.test(c[2]))throw new Error('Import values only; formulas are unsupported.');
        const type=c[1].match(/\bt="([^"]+)"/)?.[1],value=c[2].match(/<v(?:\s[^>]*)?>([\s\S]*?)<\/v>/)?.[1]||'';
        row[col-1]=type==='s'?strings[Number(value)]:type==='inlineStr'?texts(c[2]):decode(value);
      }
      matrix.push(row);if(matrix.length>501)throw new Error('Import at most 500 contacts per file.');
    }
    return normalize(matrix);
  }
  async function read(file){if(file.size>5000000)throw new Error('File must be under 5 MB.');if(/\.xlsx$/i.test(file.name))return xlsx(await file.arrayBuffer());if(/\.csv$/i.test(file.name))return csv(await file.text());throw new Error('Choose an XLSX or CSV file.');}
  root.AadhyantSharingImport=Object.freeze({headers,mobile,normalize,csv,xlsx,read});
})(typeof window==='undefined'?globalThis:window);
