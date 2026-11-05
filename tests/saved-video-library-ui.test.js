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

test('saved MP4 in a job video campaign is read-only until backend sending is approved',()=>{
 assert.match(source,/Load Saved MP4s/);
 assert.match(source,/admin_console_preview_saved_job_video/);
 assert.match(source,/Preview Saved Video & Job Message/);
 assert.match(source,/Uploaded MP4 job sending is not yet enabled/);
 assert.match(source,/if\(!preview\.reel_ready\)/);
});
test('job video preview SQL checks Admin, private VIDEO metadata, published vacancy and template freshness',()=>{
 const sql=fs.readFileSync('supabase/migrations/20261105043000_saved_video_job_preview.sql','utf8');
 for(const required of ['public.admin_console_access()','auth.uid()','private.whatsapp_console_media',"media_format='VIDEO'",'private.vacancy_is_application_eligible','private.manual_video_render','private.whatsapp_safe_flat_json',"status='APPROVED'",'compatible','synced_at>clock_timestamp()'])assert.ok(sql.includes(required),required);
 assert.match(sql,/ready_for_sending',false/);
 assert.doesNotMatch(sql,/insert\s+into\s+public\.whatsapp_campaign|enqueue_whatsapp_outbound_message|graph\.facebook\.com/i);
 assert.match(sql,/grant execute on function public\.admin_console_preview_saved_job_video\(uuid,uuid,uuid\) to authenticated/);
});
