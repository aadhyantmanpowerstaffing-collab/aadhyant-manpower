(function(root){
  'use strict';
  const enc = new TextEncoder();
  const xml = value => String(value ?? '').replace(/[\x00-\x08\x0b\x0c\x0e-\x1f]/g,'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&apos;');
  function crc(bytes){let c=0xffffffff;for(const b of bytes){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;}
  function zip(files){
    const parts=[],central=[];let offset=0,size=0;
    const header=n=>{const b=new Uint8Array(n);return[b,new DataView(b.buffer)];};
    for(const [name,content] of Object.entries(files)){
      const n=enc.encode(name),data=enc.encode(content),checksum=crc(data);
      const [b,v]=header(30);v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x800,true);v.setUint16(12,33,true);v.setUint32(14,checksum,true);v.setUint32(18,data.length,true);v.setUint32(22,data.length,true);v.setUint16(26,n.length,true);
      parts.push(b,n,data);
      const [c,d]=header(46);d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint16(14,33,true);d.setUint32(16,checksum,true);d.setUint32(20,data.length,true);d.setUint32(24,data.length,true);d.setUint16(28,n.length,true);d.setUint32(42,offset,true);central.push(c,n);size+=c.length+n.length;offset+=b.length+n.length+data.length;
    }
    const [end,v]=header(22),count=Object.keys(files).length;v.setUint32(0,0x06054b50,true);v.setUint16(8,count,true);v.setUint16(10,count,true);v.setUint32(12,size,true);v.setUint32(16,offset,true);
    return new Blob([...parts,...central,end],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'});
  }
  function column(n){let s='';do{s=String.fromCharCode(65+n%26)+s;n=Math.floor(n/26)-1;}while(n>=0);return s;}
  function workbook(rows){
    if(rows.length>100001||rows.some(r=>r.length>100))throw new Error('Report is too large. Use a smaller page.');
    const sheet=rows.map((r,i)=>`<row r="${i+1}">${r.map((v,j)=>`<c r="${column(j)}${i+1}" t="inlineStr" s="${i===0?1:0}"><is><t xml:space="preserve">${xml(v)}</t></is></c>`).join('')}</row>`).join('');
    return zip({
      '[Content_Types].xml':'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Report" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml':'<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf fontId="0" fillId="0" borderId="0" xfId="0"/><xf fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
      'xl/worksheets/sheet1.xml':`<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>${(rows[0]||[]).map((_,j)=>`<col min="${j+1}" max="${j+1}" width="${Math.min(60,Math.max(14,...rows.map(r=>Math.min(60,String(r[j]??'').length+2))))}" customWidth="1"/>`).join('')}</cols><sheetData>${sheet}</sheetData></worksheet>`
    });
  }
  function download(name,rows){const blob=workbook(rows),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`Aadhyant-${String(name).replace(/[^a-z0-9]+/gi,'-').slice(0,70)}-${new Date().toISOString().slice(0,10)}.xlsx`;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),30000);}
  function visible(node){
    for(let n=node;n&&n.nodeType===1;n=n.parentElement){const style=root.getComputedStyle(n);if(n.hidden||n.getAttribute('aria-hidden')==='true'||style.display==='none'||style.visibility==='hidden')return false;}
    return !node.closest('dialog:not([open])');
  }
  function cellText(cell){
    function read(n){if(n.nodeType===3)return n.textContent;if(n.nodeType!==1||!visible(n)||n.matches('button,input,select,textarea,script,style'))return '';return Array.from(n.childNodes).map(read).join(' ');}
    return read(cell).replace(/\s+/g,' ').trim();
  }
  function tableRows(table){
    const heads=Array.from(table.querySelectorAll('thead tr:last-child th'));
    const indexes=heads.map((h,i)=>({i,text:cellText(h)||String(h.textContent??'').trim()})).filter(h=>h.text&&!/^actions?$/i.test(h.text));
    const rows=Array.from(table.querySelectorAll('tbody tr')).filter(r=>visible(r)&&r.cells.length===heads.length&&!Array.from(r.cells).some(c=>c.colSpan>1)).map(r=>indexes.map(h=>cellText(r.cells[h.i])));
    return [indexes.map(h=>h.text),...rows];
  }
  function cardRows(host){
    const cards=Array.from(host.querySelectorAll(':scope > article')).filter(visible);
    const labels=Array.from(new Set(cards.flatMap(c=>Array.from(c.querySelectorAll('dt')).map(cellText))));
    return [['Record',...labels,'Details'],...cards.map(c=>[c.querySelector('h3')?.textContent||'',...labels.map(label=>{const dt=Array.from(c.querySelectorAll('dt')).find(n=>cellText(n)===label);return dt?.nextElementSibling?cellText(dt.nextElementSibling):'';}),Array.from(c.children).filter(n=>n.matches('p,span')).map(cellText).join(' · ')])];
  }
  function mountCards(){
    document.querySelectorAll('[data-excel-cards]').forEach(host=>{
      if(host.dataset.excelMounted)return;host.dataset.excelMounted='true';
      const bar=document.createElement('div'),b=document.createElement('button'),note=document.createElement('small');bar.className='excel-export-toolbar';b.type='button';b.textContent='Export to Excel';note.textContent='Current page only · displayed information';bar.append(b,note);host.before(bar);
      b.addEventListener('click',()=>{const rows=cardRows(host);if(!visible(host)||rows.length<2){note.textContent='No rows on this page to export.';return;}download(host.dataset.excelCards,rows);note.textContent=`Exported ${rows.length-1} rows · current page only`;});
    });
  }
  function mount(){
    mountCards();
    document.querySelectorAll('.table-wrap > table,.responsive-table > table').forEach(table=>{
      if(table.dataset.excelMounted||table.closest('dialog'))return;
      table.dataset.excelMounted='true';const bar=document.createElement('div'),button=document.createElement('button'),note=document.createElement('small');
      bar.className='excel-export-toolbar';button.type='button';button.className='admin-button button secondary';button.textContent='Export to Excel';note.textContent='Current page only · applied filters · displayed columns';bar.append(button,note);table.parentElement.before(bar);
      button.addEventListener('click',()=>{const rows=tableRows(table);if(!visible(table)||rows.length<2){note.textContent='No rows on this page to export.';return;}const section=table.closest('section,main');const title=section?.querySelector('h2,h1,h3')?.textContent||document.title;download(title,rows);note.textContent=`Exported ${rows.length-1} rows · current page only`;});
    });
  }
  root.AadhyantExcel={workbook,download,tableRows,cardRows};
  if(typeof document!=='undefined'){
    const style=document.createElement('style');style.textContent='.excel-export-toolbar{display:flex;align-items:center;flex-wrap:wrap;gap:12px;margin:12px 0}.excel-export-toolbar button{cursor:pointer;padding:9px 14px;border:1px solid #1769aa;border-radius:6px;background:#fff;color:#12558b;font:inherit}.excel-export-toolbar small{color:#52647a}';document.head.append(style);
    let pending=false;const schedule=()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;mount();});};
    new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true});mount();
  }
})(typeof window==='undefined'?globalThis:window);
