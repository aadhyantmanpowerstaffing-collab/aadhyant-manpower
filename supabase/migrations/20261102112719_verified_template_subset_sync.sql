-- Match the current approved business-number contracts observed in both Meta and WANotifier.
-- Existing campaign snapshots are not rewritten or replayed.
create or replace function private.english_contact_alert_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$Hello,

*Aadhyant Manpower & Staffing* has a new job opening. Review the summary below and share this opportunity with someone looking for work.

*Job details*
• Vacancy: {{1}}
• Company: {{2}}
• Role: {{3}}
• Location: {{4}}

*Qualification*
{{5}}

*Salary & duty*
• CTC / Salary: {{6}}
• Approx. take home: {{7}}
• Overtime: {{8}}
• Duty: {{9}}

*Benefits*
{{10}}

Tap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.

For more information or to apply for a job, call 9624453543.

To stop WhatsApp job alerts, tap Stop alerts or reply STOP.$body$ $verified_body$;
create or replace function private.video_job_alert_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$Hello,

*Aadhyant Manpower & Staffing* has a new job opening. Watch the video and review the details below.

*Job details*
• Vacancy: {{1}}
• Company: {{2}}
• Role: {{3}}
• Location: {{4}}

*Qualification*
{{5}}

*Salary & duty*
• CTC / Salary: {{6}}
• Approx. take home: {{7}}
• Overtime: {{8}}
• Duty: {{9}}

*Benefits*
{{10}}

Tap View Job & Apply for complete eligibility, salary breakup, deductions, facilities, conditions and application.
For more information or to apply, call 9624453543.
To stop WhatsApp job alerts, tap Stop alerts or reply STOP.$body$ $verified_body$;
create or replace function private.hindi_contact_alert_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$नमस्ते,
*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। नीचे विवरण देखें और काम ढूँढ रहे लोगों के साथ साझा करें।

*नौकरी का विवरण*
• भर्ती संदर्भ: {{1}}
• कंपनी: {{2}}
• पद: {{3}}
• स्थान: {{4}}

*योग्यता*
{{5}}

*वेतन और ड्यूटी*
• CTC / वेतन: {{6}}
• अनुमानित हाथ में वेतन: {{7}}
• ओवरटाइम: {{8}}
• ड्यूटी: {{9}}

*सुविधाएँ*
{{10}}

पूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे नौकरी देखें बटन दबाएँ।

अधिक जानकारी या नौकरी के लिए आवेदन करने हेतु 9624453543 पर कॉल करें।

WhatsApp नौकरी अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।$body$ $verified_body$;
create or replace function private.same_day_contact_alert_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$*रोकड़ी काम — उसी शाम भुगतान*
*Aadhyant Manpower & Staffing*

📍 *स्थान:* {{1}}
🛠️ *काम:* {{2}}
📅 *तारीख:* {{3}}
🕗 *समय:* {{4}}
👥 *ज़रूरत:* {{5}} लोग
💵 *मेहनताना:* {{6}} प्रति व्यक्ति, पूरी शिफ्ट का
✅ *भुगतान:* उसी दिन {{7}}

काम के लिए उपलब्ध हैं? नीचे बटन दबाकर आवेदन करें। कंपनी/ठेकेदार आपकी जगह की पुष्टि करेगा।

अधिक जानकारी या नौकरी के लिए आवेदन करने हेतु 9624453543 पर कॉल करें।

अलर्ट बंद करने के लिए *Stop alerts* दबाएँ या *STOP* लिखें।$body$ $verified_body$;
create or replace function private.registration_video_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$*Aadhyant Manpower & Staffing*

साणंद GIDC और आसपास नौकरी ढूंढ रहे हैं?
उपलब्ध नौकरियों के WhatsApp Job Alerts पाने के लिए आज ही रजिस्टर करें।

रजिस्ट्रेशन निःशुल्क है। नौकरी के लिए उम्मीदवारों से कोई फीस नहीं ली जाती।

नीचे Register Now बटन दबाएँ या https://aadhyantmanpower.in/ खोलें।
जानकारी के लिए कॉल करें: 9624453543

अलर्ट बंद करने के लिए Stop alerts दबाएँ या STOP लिखें।$body$ $verified_body$;
create or replace function private.hindi_video_job_alert_body() returns text language sql immutable set search_path='' as $verified_body$ select $body$नमस्ते,
*Aadhyant Manpower & Staffing* की ओर से नौकरी का नया अवसर है। हिंदी वीडियो देखें और नीचे जानकारी पढ़ें।

*नौकरी का विवरण*
• भर्ती संदर्भ: {{1}}
• कंपनी: {{2}}
• पद: {{3}}
• स्थान: {{4}}

*योग्यता*
{{5}}

*वेतन और ड्यूटी*
• CTC / वेतन: {{6}}
• अनुमानित हाथ में वेतन: {{7}}
• ओवरटाइम: {{8}}
• ड्यूटी: {{9}}

*सुविधाएँ*
{{10}}

पूरी पात्रता, वेतन विवरण, कटौती, सुविधाएँ, शर्तें और आवेदन के लिए नीचे बटन दबाएँ।
अधिक जानकारी या आवेदन के लिए 9624453543 पर कॉल करें।
अलर्ट बंद करने के लिए अलर्ट बंद करें दबाएँ या STOP लिखें।$body$ $verified_body$;

-- Partial provider verification must never renew or invalidate unseen templates.
create function public.console_sync_verified_template_subset(p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare preserved jsonb;n integer;
begin
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 100
 or (select count(distinct r->>'id') from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows)
 or (select count(distinct (r->>'name',r->>'language')) from jsonb_array_elements(p_rows) r)<>jsonb_array_length(p_rows)
 then raise exception 'Verified distinct template subset required';end if;
 lock table public.whatsapp_template_catalog in share row exclusive mode;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'status',t.status,'compatible',t.compatible,'synced_at',t.synced_at,'buttons',t.buttons)),'[]') into preserved
 from public.whatsapp_template_catalog t where not exists(select 1 from jsonb_array_elements(p_rows) r where r->>'id'=t.meta_id);
 n:=public.console_sync_templates(p_rows);
 update public.whatsapp_template_catalog t set status=p.status,compatible=p.compatible,synced_at=p.synced_at,buttons=p.buttons
 from jsonb_to_recordset(preserved) as p(id uuid,status text,compatible boolean,synced_at timestamptz,buttons jsonb) where t.id=p.id;
 return n;
end;$$;
revoke all on function public.console_sync_verified_template_subset(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.console_sync_verified_template_subset(jsonb) to service_role;
