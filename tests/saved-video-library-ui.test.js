'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const source=fs.readFileSync('admin/whatsapp-console.js','utf8');
test('Campaigns exposes Saved Videos without creating or sending a campaign on upload',()=>{
 assert.match(source,/button\('Saved Videos',newMediaLibrary\)/);
 assert.match(source,/draft=\{kind:'media-library'/);
 const media=source.slice(source.indexOf('const newMediaLibrary='),source.indexOf('const renderPromotion='));
 assert.match(media,/uploadSavedVideo\(d\.file\)/);
 assert.match(media,/previewPromotion\(d\.media\)/);
 assert.doesNotMatch(media,/admin_console_prepare|admin_console_queue|whatsapp-outbox-worker/);
});
test('private uploads use the existing authenticated bounded MP4 endpoint',()=>{
 const media=source.slice(source.indexOf('const uploadSavedVideo='),source.indexOf('const newMediaLibrary='));
 assert.match(media,/file\.type!=='video\/mp4'/);
 assert.match(media,/file\.size>16000000/);
 assert.match(media,/client\.auth\.getSession\(\)/);
 assert.match(media,/functions\/v1\/whatsapp-campaign-media/);
 assert.match(media,/authorization:'Bearer '/);
 assert.doesNotMatch(media,/service_role|SUPABASE_SERVICE_ROLE_KEY|graph\.facebook\.com/);
});
test('existing registration upload reuses the authenticated media helper and job campaign guard stays intact',()=>{
 assert.match(source,/const id=await uploadSavedVideo\(d\.file\)/);
 assert.match(source,/if\(!preview\.reel_ready\)throw new Error\('A current job video is required/);
 assert.match(source,/admin_console_prepare_job_image/);
 assert.match(source,/await call\(client,'admin_console_prepare',args\)/);
});
