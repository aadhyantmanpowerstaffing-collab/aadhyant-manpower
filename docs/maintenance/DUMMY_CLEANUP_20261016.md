# Dummy dataset removal — 16 October 2026

User first requested removal of all testing data at 21:06:37 IST. After a concrete inventory, the user explicitly confirmed at 21:09:34 IST that every candidate, company, contractor, vacancy and login was their own dummy creation and authorized clearing all of them. Admin access and working sender/template configuration were retained.

## Completed production operation

Applied the Supabase-CLI-created `20261016154054_dummy_cleanup_archive.sql`, installing only one private recovery table (production ledger `20261016154301 / dummy_cleanup_archive`). The archive has RLS and no anon/authenticated/service_role table grants. It is not exposed by an RPC. No data, credentials or snapshot contents were exported into source, tool output or a user file.

`supabase/production/clear_dummy_data_20261016/cleanup.sql` is the exact one-shot transaction. It locks the complete affected relation set, checks every reviewed count, rejects in-flight sends and protects Admin/staff identities. It snapshots 35 relations inside the same transaction, including the seven removed Auth accounts/identities and protected configuration for invariant comparison. Auth snapshots remain restricted inside the production database; never export them into Git or logs. Active sessions are invalidated by the Auth deletion cascade and are not restored as part of account recovery.

The full operation first passed with ROLLBACK. The identical transaction then passed with COMMIT. No foreign-key constraint, trigger, authentication guard or RPC grant was disabled; no TRUNCATE/CASCADE or broad schema reset was used. Only nullable registration cycle links were broken after backup, and the corresponding temporary row shape was kept valid before deletion. Every affected relation was checked empty before commit. The archive prevents replay.

Removed business records: 5 vacancies, 4 candidate profiles, 2 companies, 1 contractor, 5 platform profiles, their company/contractor memberships, 6 applications, 4 interviews, 2 joinings, 2 document metadata records, 4 resume-share records and all associated preferences/onboarding/stage/idempotency records. Removed WhatsApp data: 10 campaigns, 11 campaign recipients, 5 contacts, 31 incoming messages, 40 outgoing messages, 109 status events, 140 webhook events, registration sessions/capabilities, publication records and 30 personal read markers. All **30 affected business/message relations are empty** in the postcheck. Seven non-admin Auth accounts and seven Auth identities were removed; the single real Admin Auth account and Admin membership remain.

Protected configuration and template catalog were compared byte-for-byte as sorted JSON with their snapshots before commit. Sender ready=true, employer Post Job replies=true, candidate automatic alerts=false remain unchanged. Existing security/audit records, application-stage/source vocabularies, code, Edge functions, approved/pending template setup and deployment history were preserved. The two former document binary objects remain private recovery assets; their portal metadata and share links were removed. They were not deleted by direct manipulation of Storage metadata. This is a portal-data reset with a recovery copy, not physical erasure of every backup object.

## Verification and recovery limits

Postcheck confirms all 30 target relations empty, one Auth/Admin account, 35 recovery relations and denied browser/service archive access. Fresh signed-in Admin dashboard shows every recruitment counter at zero. No message was sent and no fake replacement record was created. No frontend or Edge publication was required.

Snapshots are logical recovery material for a privileged, reviewed restoration. They do not constitute a tested automated restore tool. Reinstating records would need explicit authorization, dependency-aware inserts and new sessions; do not restore old active session tokens. Existing schema-migration history is retained. Vacancy/reference sequences were deliberately not rewound, preventing reused references in old sent links.
