'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
require('../assets/js/sharing-contact-import.js');
const api=globalThis.AadhyantSharingImport;
const header=['Name','Email','Mobile','Gender','Age','State','District'];
const row=['Sample Person','person@example.invalid','+91 98765 43210','male','25','Gujarat','Ahmedabad'];
test('import normalizes Indian phones, gender and age without inferred consent',()=>{
  const out=api.normalize([header,row]);assert.equal(out.rows.length,1);assert.equal(out.rows[0].Mobile,'9876543210');assert.equal(out.rows[0].Gender,'Male');assert.equal(out.rows[0].Age,25);assert.equal('consent' in out.rows[0],false);
});
test('duplicates normalize before deduplication',()=>{const out=api.normalize([header,row,[...row.slice(0,2),'9876543210',...row.slice(3)]]);assert.equal(out.rows.length,1);assert.equal(out.duplicates.length,1);});
test('invalid numbers and incomplete demographics are held for correction',()=>{
  const out=api.normalize([header,['Sample','','1234','','17','','']]);assert.equal(out.rows.length,0);assert.equal(out.errors.length,1);
});
test('CSV supports quoted commas, escaped quotes and CRLF',()=>{
  const out=api.csv('Name,Email,Mobile,Gender,Age,State,District\r\n"Sample, ""Person""",,9876543210,Male,25,Gujarat,Ahmedabad\r\n');assert.equal(out.rows[0].Name,'Sample, "Person"');assert.equal(out.rows[0].Email,'');
});
test('missing/duplicate headers and malformed quotes fail clearly',()=>{
  assert.throws(()=>api.normalize([['Name','Mobile']]),/Required columns/);assert.throws(()=>api.normalize([[...header,'Mobile'],row]),/Required columns/);assert.throws(()=>api.csv('"unclosed'),/Unclosed/);
});
test('row/file limits and invalid spreadsheet archives fail before import',async()=>{
  assert.throws(()=>api.normalize([header,...Array.from({length:501},(_,i)=>{const r=[...row];r[2]=String(9000000000+i);return r;})]),/500/);
  await assert.rejects(api.read({name:'large.xlsx',size:5000001}),/5 MB/);
  await assert.rejects(api.xlsx(new Uint8Array(30).buffer),/Invalid XLSX/);
});
