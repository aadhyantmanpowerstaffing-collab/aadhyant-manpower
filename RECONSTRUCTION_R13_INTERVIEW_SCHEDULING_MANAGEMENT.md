# Reconstruction R13 — Interview Scheduling and Management

## Operator-reported production state

Migration 014 was manually applied and production structural verification was reported by the operator. The operator reported that `public.interviews`, RLS, compatible M7 Admin policies/constraints, all three SECURITY DEFINER R13 RPCs, authenticated-only execute grants, and the required application/status/supersession indexes and constraint are present. Production contained no interview rows before migration. Codex did not access production or execute production SQL.

Frontend implementation and validation are separate from that operator-reported production state. The Admin frontend uses the exact migration 014 RPC names and named parameters, reads only `public.interviews` rows for the selected `candidate_applications.id`, and performs no direct interview insert or update.

## 1. Scope

R13 adds Admin-only interview scheduling, audit-preserving rescheduling, controlled interview outcomes, and bounded interview history to the existing Candidate Application management dialog. It does not add Candidate authentication, joining, messaging automation, or Company/Staffing Partner access.

## 2. Existing model reuse

Milestone 7 already created `public.interviews` with `application_id`, `scheduled_at`, `location`, controlled `mode`, controlled `status`, result/notes fields, creator/timestamps, RLS, Admin policies, and the shared `private.set_updated_at()` trigger. R13 reuses and narrowly extends this table. No duplicate interview table is created.

## 3. Data model

`candidate_applications.id` remains the sole scheduling parent supplied by the Admin UI. R13 adds `interview_round`, `supersedes_interview_id`, `meeting_link`, `contact_person`, `contact_phone`, `instructions`, and `result_notes`. Existing rows receive deterministic rounds ordered by schedule/creation/ID while the timestamp trigger is temporarily disabled, preserving their prior `updated_at` values.

At most one `scheduled` interview may exist per application. `supersedes_interview_id` is unique and self-reference is rejected. Existing application, Candidate, Requirement, Company, assignment, and Staffing Partner identities are never supplied separately to an interview RPC.

## 4. Interview status model

The existing compatible allowlist is retained:

`scheduled`, `attended`, `absent`, `rescheduled`, `completed`, `cancelled`.

The UI labels `absent` as “No-show.” R13 does not alter the existing table constraint.

## 5. Interview mode model

The existing compatible allowlist is retained:

`onsite`, `phone`, `video`, `other`.

The UI presents On-site, Telephonic, Video, and Other / Walk-in labels while persisting canonical values.

## 6. Application-status interaction

Scheduling is allowed only when the application is `interested`, `applied`, `screening`, `shortlisted`, or `interview`. The first four advance to `interview`; an existing `interview` status remains unchanged. Scheduling and rescheduling reject `selected`, `rejected`, `joining_pending`, `joined`, `left`, and `cancelled`, so a more advanced or incompatible application is never downgraded.

Interview completion does not automatically select or reject a Candidate. Hiring decisions remain in the existing R12 application-status control.

## 7. Admin security and RLS

The existing M7 interview RLS and `private.is_admin()` policies remain authoritative. Anonymous and ordinary authenticated users receive no interview rows. R13 revokes direct authenticated `INSERT` and `UPDATE` table privileges and exposes only three narrow authenticated RPCs, each of which independently requires `auth.uid()` and `private.is_admin()`.

No delete grant or policy is introduced. Company, Staffing Partner, Candidate, and public users receive no interview access.

## 8. RPC design

- `public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)` creates the next round, records the Admin creator, and safely advances an eligible application to `interview`.
- `public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)` marks the prior scheduled event `rescheduled` and creates a replacement linked through `supersedes_interview_id` with the same round number.
- `public.admin_update_candidate_interview(uuid,text,text,text)` permits only scheduled → attended/completed/absent/cancelled and attended → completed, with the existing result allowlist and bounded result notes.

All are `SECURITY DEFINER`, have empty `search_path`, use schema-qualified objects, contain no dynamic SQL, revoke PUBLIC/anon execution, and grant execution only to `authenticated` with internal Admin verification.

## 9. UI design and interview history

The existing Candidate Application dialog retains Opportunity, Candidate Profile, and Application Management. A new Interview Management section contains:

- Latest interview summary
- Schedule/reschedule form
- Controlled outcome form
- Newest-first history capped at 50 events
- Round, schedule, mode, status, update time, and applicable actions

Candidate and Requirement details remain read-only. Values are rendered with text nodes through existing helpers; no untrusted `innerHTML` is used.

## 10. Duplicate scheduling protection

The browser uses single-flight form state and disabled buttons. The database is authoritative: scheduling locks the Candidate Application row and a partial unique index permits only one `scheduled` interview per application. Reschedule locks the previous event and application. Unique conflicts return a controlled failure. Network retry or duplicate event dispatch cannot create two current schedules.

## 11. Reschedule model

R13 uses an audit-preserving event model. The prior event remains with status `rescheduled`; the replacement points to it through `supersedes_interview_id` and retains the same interview round. A genuinely new round is created only after no current scheduled event remains and receives `max(interview_round) + 1` server-side.

## 12. Validation bounds

- Future `timestamptz` is required for schedule/reschedule.
- Location: 500 characters.
- Meeting link: 1,000 characters.
- Contact person: 200 characters.
- Contact phone: 30 characters.
- Instructions and result notes: 4,000 characters each.

Optional fields remain optional. Date/time is converted to ISO UTC for RPC persistence and displayed in the Admin browser’s local timezone.

## 13. SQL tests

`supabase/tests/014_interview_scheduling_management_test.sql` transactionally covers Admin scheduling, application advancement, creator/round/details, duplicate-current prevention, reschedule lineage, absent/completed outcomes, second round, invalid status, oversized notes, terminal application rejection, Candidate/Requirement/application identity immutability, anon/Company/Partner denial, direct-mutation revocation, R10/R11 existence, R12 RPC persistence, and unique-constraint preservation. Fixtures roll back.

Schema and migrations 007–014 were applied to a disposable local Supabase PostgreSQL 17 container from an already cached image. The transactional R13 suite passed and rolled back all fixtures. The exact disposable container was removed afterward; no production system was contacted.

## 14. Browser tests

Isolated Chrome/Selenium harnesses loaded the real Admin HTML/JavaScript with local mock Supabase clients and no production calls. They verified the empty state; delayed Application A → Application B load isolation; schedule/reschedule/update error recovery; single-flight schedule; full fresh-history verification; predecessor reschedule history; application-status re-read; attended, completed, absent, and cancelled statuses; pending, selected, rejected, and on-hold results; result-note persistence; post-save read failure without false success; R12.1 status/note single-flight regression; and zero direct interview table writes. Unexplained console errors were zero.

## 15. Responsive and accessibility

The Admin dialog passed 360, 390, 768, 1024, and 1440px without page-level overflow. Forms stack on mobile and the history table scrolls within its wrapper. Controls have explicit labels, live status regions, keyboard-native buttons/selects, visible focus, a semantic section heading, and textual status labels. Existing Escape-close and focus-restoration behavior remains intact.

## 16. R10, R11, and R12/R12.1 regression

Migration 014 does not replace or change the R10 public Jobs or R11 public interest functions. No interview field is added to either output/input. R12’s Admin application RPC remains unchanged. The R12.1 load-version and verified single-flight Save paths remain in `admin/admin.js` and are reused conceptually for interview history/mutations.

## 17. Production preflight — SELECT only

Run manually before migration 014. Do not proceed if a prerequisite is absent, a collision is present, more than one scheduled interview exists per application, existing values fall outside the M7 constraints, length violations exist, RLS/Admin policies are missing, or grants differ unexpectedly.

```sql
select
  to_regclass('public.interviews') as interviews_table,
  to_regclass('public.candidate_applications') as candidate_applications_table,
  to_regprocedure('private.is_admin()') as admin_helper,
  to_regprocedure('private.set_updated_at()') as updated_at_helper,
  to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_function,
  to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as r11_function,
  to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') as r12_function;

select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name in ('candidate_applications','interviews')
order by table_name, ordinal_position;

select conname, contype, pg_get_constraintdef(oid, true) as definition, convalidated
from pg_constraint
where conrelid in ('public.candidate_applications'::regclass, 'public.interviews'::regclass)
order by conrelid::regclass::text, conname;

select mode, count(*) as row_count from public.interviews group by mode order by mode;
select status, count(*) as row_count from public.interviews group by status order by status;
select result, count(*) as row_count from public.interviews group by result order by result;

select application_id, count(*) as scheduled_count, array_agg(id order by created_at, id) as interview_ids
from public.interviews
where status = 'scheduled'
group by application_id
having count(*) > 1;

select id, length(location) as location_length, length(remarks) as remarks_length, length(internal_notes) as internal_notes_length
from public.interviews
where length(coalesce(location,'')) > 500;

select column_name
from information_schema.columns
where table_schema='public' and table_name='interviews'
  and column_name in ('interview_round','supersedes_interview_id','meeting_link','contact_person','contact_phone','instructions','result_notes')
order by column_name;

select
  to_regprocedure('public.admin_schedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') as schedule_collision,
  to_regprocedure('public.admin_reschedule_candidate_interview(uuid,timestamp with time zone,text,text,text,text,text,text)') as reschedule_collision,
  to_regprocedure('public.admin_update_candidate_interview(uuid,text,text,text)') as update_collision;

select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'public.interviews'::regclass;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname='public' and tablename='interviews'
order by policyname;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='interviews'
order by grantee, privilege_type;

select tgname, tgenabled, pg_get_triggerdef(oid, true) as definition
from pg_trigger
where tgrelid='public.interviews'::regclass and not tgisinternal
order by tgname;

select indexname, indexdef
from pg_indexes
where schemaname='public' and tablename='interviews'
order by indexname;
```

Expected: prerequisite objects are non-null; existing M7 interview columns/constraints match the repository; the duplicate-scheduled and length-violation queries return zero rows; all R13 column/function collision results are absent/null; RLS is enabled; only M7 Admin policies exist; the updated-at trigger is enabled.

## 18. Migration fingerprint

- File: `supabase/migrations/014_interview_scheduling_management.sql`
- SHA-256: `c2a5dab691be2cbbc8c52f346e54d27fa18d8604324812f944e4c90118ddbd7b`
- Size: 12,673 bytes
- Lines: 259
- First executable statement: `begin;`
- Last executable statement: `commit;`

## 19. Production postflight — SELECT only

```sql
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema='public' and table_name='interviews'
  and column_name in ('interview_round','supersedes_interview_id','meeting_link','contact_person','contact_phone','instructions','result_notes')
order by column_name;

select relrowsecurity, relforcerowsecurity
from pg_class where oid='public.interviews'::regclass;

select conname, contype, pg_get_constraintdef(oid, true) as definition, convalidated
from pg_constraint
where conrelid='public.interviews'::regclass
order by conname;

select indexname, indexdef
from pg_indexes
where schemaname='public' and tablename='interviews'
order by indexname;

select p.oid::regprocedure as function_signature, p.prosecdef as security_definer, p.proconfig
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'admin_schedule_candidate_interview','admin_reschedule_candidate_interview','admin_update_candidate_interview'
)
order by p.proname;

select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where specific_schema='public' and routine_name in (
  'admin_schedule_candidate_interview','admin_reschedule_candidate_interview','admin_update_candidate_interview'
)
order by routine_name, grantee;

select
  has_function_privilege('anon','public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE') as anon_schedule,
  has_function_privilege('anon','public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE') as anon_reschedule,
  has_function_privilege('anon','public.admin_update_candidate_interview(uuid,text,text,text)','EXECUTE') as anon_update,
  has_function_privilege('authenticated','public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE') as authenticated_schedule,
  has_function_privilege('authenticated','public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text)','EXECUTE') as authenticated_reschedule,
  has_function_privilege('authenticated','public.admin_update_candidate_interview(uuid,text,text,text)','EXECUTE') as authenticated_update;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema='public' and table_name='interviews'
order by grantee, privilege_type;

select
  to_regprocedure('public.get_public_job_requirements(integer,integer)') as r10_function,
  to_regprocedure('public.register_candidate_requirement_interest(text,jsonb)') as r11_function,
  to_regprocedure('public.admin_update_candidate_application(uuid,text,text)') as r12_function;
```

Expected: seven R13 columns exist; RLS remains enabled; constraints and indexes exist; all three functions are SECURITY DEFINER with `search_path` set to an empty string; anon execute values are false; authenticated execute values are true; authenticated has SELECT but no direct INSERT/UPDATE on interviews; R10-R12 functions remain present.

## 20. Rollback

Prefer this non-destructive rollback, which disables R13 mutation RPCs while retaining interview records and additive columns:

```sql
begin;
revoke all on function public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text) from public, anon, authenticated;
revoke all on function public.admin_update_candidate_interview(uuid,text,text,text) from public, anon, authenticated;
drop function public.admin_schedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text);
drop function public.admin_reschedule_candidate_interview(uuid,timestamptz,text,text,text,text,text,text);
drop function public.admin_update_candidate_interview(uuid,text,text,text);
grant insert, update on public.interviews to authenticated;
commit;
```

This restores the pre-R13 M7 direct Admin table privilege model but intentionally retains columns, indexes, constraints, and interview history. Dropping those columns would destroy R13 data and requires a separately reviewed data-loss operation. Candidate/Application/Requirement data and R10-R12 objects are untouched.

## 21. Known limitations

- Production migration remains a separate manual operator step after preflight and review.
- No Candidate notification, confirmation, calendar integration, Company sharing, Staffing Partner sharing, or WhatsApp automation exists.
- History is bounded to 50 events in the Admin dialog; server pagination can be added if operational volume requires it.
- Interview result and application hiring decision remain deliberately separate.

## 22. Recommended next phase

After local SQL and production migration review, the next explicit milestone should cover controlled Candidate communication/interview confirmation or joining management—not public interview access.
