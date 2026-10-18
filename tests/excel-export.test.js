'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const context={TextEncoder,Blob};vm.runInNewContext(fs.readFileSync('assets/js/excel-export.js','utf8'),context);
async function entries(blob){const b=Buffer.from(await blob.arrayBuffer()),out={};let p=0;while(b.readUInt32LE(p)===0x04034b50){const n=b.readUInt16LE(p+26),x=b.readUInt16LE(p+28),size=b.readUInt32LE(p+18);out[b.subarray(p+30,p+30+n).toString()]=b.subarray(p+30+n+x,p+30+n+x+size).toString();p+=30+n+x+size;}assert.equal(b.readUInt32LE(p),0x02014b50);assert.equal(b.readUInt32LE(b.length-22),0x06054b50);return out;}
test('genuine XLSX archive preserves Gujarati, leading zeroes and untrusted values as text',async()=>{const files=await entries(context.AadhyantExcel.workbook([['Name','Phone','Text'],['હિતેશ','0012345678','=HYPERLINK("evil")'],['<>&','+123','@SUM(1)']]));assert.equal(Object.keys(files).length,6);assert.match(files['xl/worksheets/sheet1.xml'],/હિતેશ/);assert.match(files['xl/worksheets/sheet1.xml'],/0012345678/);assert.match(files['xl/worksheets/sheet1.xml'],/&lt;&gt;&amp;/);assert.match(files['xl/worksheets/sheet1.xml'],/t="inlineStr"/);assert.doesNotMatch(files['xl/worksheets/sheet1.xml'],/<f[ >]/);assert.match(files['xl/worksheets/sheet1.xml'],/state="frozen"/);});
test('Excel column names support reports wider than Z',async()=>{const row=Array.from({length:28},(_,i)=>String(i)),files=await entries(context.AadhyantExcel.workbook([row]));assert.match(files['xl/worksheets/sheet1.xml'],/r="AA1"/);assert.match(files['xl/worksheets/sheet1.xml'],/r="AB1"/);});
test('export is local and keeps server authorization intact',()=>{const src=fs.readFileSync('assets/js/excel-export.js','utf8');assert.doesNotMatch(src,/fetch\(|\.rpc\(|localStorage|sessionStorage|innerHTML|client\.from\(/);assert.match(src,/Current page only/);assert.match(src,/aria-hidden/);assert.match(src,/colSpan>1/);});
test('reporting pages load the shared exporter and production packages it',()=>{for(const file of ['admin/index.html','company/applications.html','company/requirements.html','company/interviews.html','company/joinings.html','contractor/applications.html','contractor/vacancies.html','contractor/assignments.html','contractor/interviews.html','contractor/joinings.html','same-day-pay/index.html'])assert.match(fs.readFileSync(file,'utf8'),/excel-export\.js/);assert.match(fs.readFileSync('scripts/build-production-artifact.js','utf8'),/'assets\/js\/excel-export\.js'/);});
test('table export excludes hidden rows, action columns, controls and placeholder rows',()=>{
 context.getComputedStyle=n=>({display:n.display||'block',visibility:'visible'});
 function element(text='',props={}){const e={nodeType:1,hidden:false,parentElement:null,colSpan:1,getAttribute:()=>null,closest:()=>null,matches:()=>false,childNodes:[],...props};e.childNodes=[{nodeType:3,textContent:text},...(props.children||[])];return e;}
 const hidden=element('private',{hidden:true}),control=element('Send message',{matches:s=>s.includes('button')});
 const name=element('હિતેશ',{children:[hidden,control]});
 const headers=['Name','Mobile','Action'].map(t=>element(t));
 const record={...element(),cells:[name,element('00123'),element('Approve')]};
 const hiddenRow={...record,hidden:true};
 const placeholder={...element(),cells:[element('Loading',{colSpan:3})]};
 const table={querySelectorAll:s=>s.startsWith('thead')?headers:[record,hiddenRow,placeholder]};
 const rows=context.AadhyantExcel.tableRows(table);
 assert.deepEqual(JSON.parse(JSON.stringify(rows)),[['Name','Mobile'],['હિતેશ','00123']]);
});
