# Aadhyant Production Backup and Restore Plan

Plan date: 25 August 2026 (Asia/Kolkata)

Release HEAD reviewed: `1f466475967b71f37ca962074963e63a4031f02b`

Production project: `wsuctjhbqiedttfnwjvf` (`Aadhyant Manpower`, `ap-northeast-1`)

Status: **P0-B planning PASS; backup, PITR, restore, and recovery proof remain BLOCKED.**

This document is a pre-mutation plan. Its preparation used authenticated read-only management requests only. It does not authorize a plan purchase, add-on, backup, restore, project creation/deletion, SQL write, migration, deployment, or production configuration change.

## Current verified state

The 25 August 2026 read-only check established:

- the Supabase organization `Aadhyant Manpower & Staffing` is on the **Free** plan;
- production is `ACTIVE_HEALTHY`, PostgreSQL 17.6 (platform build 17.6.1.155), and object-equivalent through repository migration 015;
- the project has no selected billing add-ons;
- WAL-G capability reports enabled, but PITR reports disabled;
- the physical-backup list is empty (`backups: null`, empty physical-backup metadata);
- no backup identifier, recovery window, downloadable dump, or restorable point is proven;
- no isolated restore has been attempted; and
- production currently has zero Storage buckets and zero Storage object policies. Database backup still must not be treated as a future Storage-object backup.

Result: there is currently no acceptable recovery point for migrations 016–029. WAL-G capability alone is not backup evidence.

## Current Supabase options

Official Supabase documentation and the project's read-only add-on inventory establish the following current options:

| Capability | Current availability | Retention or cost posture | Project decision |
| --- | --- | --- | --- |
| Automatic daily physical backup | Pro, Team, and Enterprise | Pro: 7 days; Team: 14 days; Enterprise: up to 30 days | Free does not meet the gate |
| Point-in-Time Recovery | Paid-plan add-on; at least Small compute required | 7 days: $100/month; 14 days: $200/month; 28 days: $400/month; billed hourly and outside Spend Cap | Enhanced Option B; not required if conditional Option A passes |
| Small compute | Available add-on/current paid-project prerequisite for PITR | Read-only inventory: approximately $15/month | Required with PITR unless checkout proves an equivalent or larger active compute |
| Restore to a New Project | Paid plan with physical backups enabled; currently documented as Beta | New project mirrors source compute/disk attributes and incurs separate project costs | Use for the isolated drill |
| Manual logical dump | Supabase CLI `db dump` roles/schema/data bundle, with separate `auth,storage` schema-change capture | Operator-managed storage, encryption, retention, and restore burden | Accepted for the cost-minimized gate only after an exact isolated restore drill and enforced write freeze |

Paid daily backups are provider-scheduled; the reviewed capability exposes no customer-selected daily schedule or safe manual physical-snapshot trigger. Enabling PITR replaces daily backups because PITR provides the finer-grained recovery chain. The valid recovery interval is the earliest/latest recovery point displayed by the provider, not the add-on enablement time. A selected timestamp is usable only after the provider exposes it inside that interval.

The supported isolated recovery path is **Restore to a New Project** from a physical backup or PITR point. No evidence establishes that a Supabase preview branch is an eligible substitute for this provider backup restore, so a branch is not accepted as the P0-B recovery target.

The organization plan currently costs nothing. Option A is expected to cost approximately $35/month for the current two active projects: $25 Pro plus about $20 total Micro/Nano-billed-as-Micro compute, less one $10 compute credit. Option B is expected to cost approximately $140/month: the same organization, production Small compute, the other active Micro/Nano project, the compute credit, and $100 seven-day PITR. These are not Aadhyant quotes. The temporary drill project, taxes, disk, compute, egress, storage, and all actual active-project charges require human acceptance of the Dashboard estimate before any change.

Current provider references, reviewed 25 August 2026:

- Database backups: <https://supabase.com/docs/guides/platform/backups>
- Database-backup feature/RPO summary: <https://supabase.com/features/database-backups>
- PITR usage and pricing: <https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery>
- Restore to a new project: <https://supabase.com/docs/guides/platform/clone-project>
- CLI backup/restore: <https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore>
- Compute billing: <https://supabase.com/docs/guides/platform/manage-your-usage/compute>
- Production checklist: <https://supabase.com/docs/guides/deployment/going-into-prod>
- Pricing: <https://supabase.com/pricing>

Provider capability, prices, and Beta behavior must be rechecked in the Dashboard immediately before approval; this document is not a price guarantee or provider SLA.

## Cost-minimized recovery alternative review

### Option A — Pro daily backup plus tested logical export

1. **Mechanism:** upgrade the organization to Pro, wait for a provider daily physical backup, and create an explicit pre-migration bundle with the version-pinned Supabase CLI: `roles.sql` (`--role-only`), `schema.sql`, and `data.sql` (`--data-only --use-copy`). Capture custom `auth`/`storage` schema changes separately through Supabase's documented `db diff --schema auth,storage` procedure from an explicitly production-bound, production-through-015 baseline—not the current NONPROD-linked workspace. Production currently has no migration ledger, so no historic migration rows may be fabricated.
2. **Database/Auth recovery:** provider daily physical clone includes database schemas/data, roles, permissions, Auth users/hashed passwords, and the encryption root key. The CLI bundle preserves application schema/data/roles and Auth user data under the supported restore procedure, but managed `auth`/`storage` schema definitions come from the target; custom changes require the separate diff. Auth settings/API keys are not restored. Custom login-role passwords are not retained. Vault/encrypted-column use must be proven absent or its provider key-copy procedure separately approved.
3. **Storage:** neither database mechanism restores Storage objects/settings. Current production has zero buckets, but this ceases to be sufficient once document storage is enabled.
4. **Isolated target:** supported. A daily physical backup can use Dashboard Restore to a New Project. The exact logical bundle must be tested through the documented CLI/`psql --single-transaction --variable ON_ERROR_STOP=1` restore into a separately created fresh Supabase project.
5. **RPO:** daily physical fallback can lose up to about 24 hours. For the migration itself, the tested logical bundle can provide zero data loss relative to its captured snapshot only when an enforceable all-writer maintenance freeze begins before export and remains through migration/postflight. Without that freeze, the logical path has an unbounded write-after-dump gap and fails this gate.
6. **RTO:** initial internal objective eight hours because target creation, manual roles/schema/data restore, custom Auth/Storage change application, fingerprinting, and service reconfiguration are operator-run. The drill must replace this estimate with measured evidence.
7. **Rollback confidence:** high for the database at the frozen export boundary after the exact bundle restores cleanly; lower than PITR for writes outside that boundary and for non-database configuration. Committed migrations still prefer forward-fix unless incident authority selects restore.
8. **Recurring cost:** expected current-organization baseline is approximately $35/month before tax/overage: $25 Pro plus two active Micro/Nano-billed-as-Micro projects at about $10 each, less one $10 monthly compute credit. No $100 PITR line item.
9. **Drill cost:** a temporary Micro target is about $0.01344/hour (roughly $0.11 for eight billed hours), plus disk/usage and secure-runner/encrypted-backup storage costs. Actual cost continues until the exact target is separately approved for deletion.
10. **Complexity:** high. It requires a pinned CLI/PostgreSQL toolchain, secure non-laptop artifact storage, checksums, a write freeze, target bootstrap, ordered restore, special Auth/Storage handling, and sanitized evidence.
11. **Privacy:** higher exposure surface because roles/schema/data files contain production data and Auth records outside the managed source project. Artifacts must be encrypted in an approved restricted server-side location, never committed, never placed on a local laptop, and destroyed only under the approved retention schedule.
12. **P0-B result:** **PASS-capable, conditionally.** It satisfies the pre-migration gate only after a paid daily backup exists, the exact logical bundle has been restored and verified in isolation, the freeze control is proven, fingerprints match, owners/RPO/RTO are accepted, and the bundle remains available for the migration window.

### Option B — Pro, Small compute, and seven-day PITR

1. **Mechanism:** upgrade to Pro or higher, move production to at least Small compute, enable seven-day PITR, and use the provider's physical backup plus WAL chain.
2. **Database/Auth recovery:** Restore to a New Project includes database schema/data/indexes, roles/permissions/users, Auth users/hashed passwords, and the encryption root key. Auth settings/API keys still require manual reconfiguration.
3. **Storage:** Storage objects/settings are not included, exactly as in Option A.
4. **Isolated target:** supported directly from a selected timestamp through Dashboard Restore to a New Project.
5. **RPO:** provider documentation describes about two minutes worst case; use five minutes as the conservative internal operational objective. No export-to-migration writer freeze is required to preserve a recovery point, although a migration maintenance window is still required.
6. **RTO:** initial internal objective four hours; the drill must measure it.
7. **Rollback confidence:** highest of the two database options because a precise pre-incident timestamp can be selected from the active recovery interval and the restore is provider-managed.
8. **Recurring cost:** expected current-organization baseline is approximately $140/month before tax/overage: $25 Pro, $15 production Small, about $10 for the other active project, minus $10 compute credit, plus $100 seven-day PITR. PITR is billed hourly.
9. **Drill cost:** a temporary Small target is about $0.0206/hour (roughly $0.08 for four billed hours), plus disk/usage until separately deleted.
10. **Complexity:** medium. Recovery is provider-managed, but target containment, fingerprints, non-database configuration, owner/runbook, and deletion approval remain manual.
11. **Privacy:** lower export exposure than Option A because production rows stay inside provider-managed projects; the restored project still contains real database/Auth data and must be tightly isolated.
12. **P0-B result:** **PASS-capable.** It satisfies the gate after PITR exposes a valid interval and an exact isolated restore/fingerprint drill passes.

### Cost-minimized recommendation

Choose **Option A** for the current small, pre-launch dataset, provided the business accepts a controlled write outage and the security owner approves encrypted server-side handling of the logical bundle. It saves approximately $105/month under the current two-project organization posture while still producing a genuinely tested recovery path.

PITR is not technically required solely to apply migrations 016–029. It becomes required if Aadhyant cannot enforce the all-writer freeze, cannot securely retain/restore the logical bundle, needs continuous recovery between daily backups, needs the five-minute operational RPO outside the maintenance window, or the logical drill exposes an Auth/Vault/extension restoration gap.

## Required target posture

Before migration 016 can be considered, P0-B requires all of the following:

1. The organization is on an approved paid plan and a provider daily physical backup is present.
2. One recovery posture is explicitly selected: Option A with Micro-or-higher compute and an exact tested logical bundle, or Option B with Small-or-higher compute and an active PITR interval.
3. The exact pre-migration recovery boundary is recorded: the write-frozen logical snapshot/manifest for Option A or a selectable PITR timestamp for Option B.
4. The selected recovery path has completed successfully into a separate project, never over production.
5. The restored catalog, security objects, aggregate data posture, and Auth linkage match the source fingerprint captured at the recovery timestamp.
6. Storage scope is recorded separately. A database restore does not restore Storage files or operational configuration.
7. A named backup operator, rollback decision owner, alternate owner, and incident communication channel are recorded.
8. The measured drill establishes an accepted RPO/RTO and a usable recovery runbook.

For this pre-launch dataset, the approved cost-minimized posture is Option A only with a proven writer freeze and exact logical restore drill. A daily backup without that explicit tested export remains insufficient because it can be nearly a day old. Seven-day PITR remains the safer operational posture and is mandatory if the Option A conditions cannot be satisfied.

## Approval and execution sequence

Every mutation below requires an explicit approval that names the target and exact action.

### Gate 1 — billing and ownership

1. Record the billing owner and accept the complete organization checkout estimate, including existing projects and the temporary drill project.
2. Select Option A or Option B. Approve Pro (or higher), the resulting compute posture, and PITR retention only if Option B is selected.
3. Approve the data-retention implications of the recovery window.
4. Name the backup operator, rollback decision owner, alternate, and incident channel.
5. Record launch-time RPO and RTO acceptance.

Stop if any owner, cost, retention decision, or authority is missing.

### Gate 2 — paid backup activation

Under a separate production-infrastructure mutation approval:

1. Reverify exact organization, production project ref, region, PostgreSQL version, and current add-ons.
2. Capture the current billing/add-on settings without secret values.
3. Upgrade the organization and compute only as explicitly approved. Option A does not require Small compute; the existing Nano may remain but is billed at the Micro rate on a paid organization.
4. Under Option A, do not enable PITR. Wait until a production daily physical backup is listed and selectable. Under Option B, enable only the approved PITR retention on `wsuctjhbqiedttfnwjvf` and wait for a valid recovery interval.
5. Do not migrate, deploy, change Auth/Storage/network/DNS/Meta, or send messages.
6. Record the daily backup identifier/time for Option A or earliest/latest PITR points and a candidate timestamp for Option B, without private row data.

Stop if the project identity differs, checkout differs materially, the selected backup mechanism does not become usable, or project health degrades.

### Gate 3 — source fingerprint

Before the drill and again immediately before migrations, capture through a server-enforced read-only channel:

- project/database identity, PostgreSQL version, and transaction read-only state;
- application schema, table, column, constraint, index, trigger, RLS, policy, grant, function, owner, `SECURITY DEFINER`, and `search_path` fingerprints;
- migration-object boundary and the absence of migration 016+ objects;
- per-table row counts and server-side whole-row digests, returning only counts and digests;
- aggregate Auth user count, Admin linkage count, Company linkage count, and orphan counts without emails, UUIDs, or metadata;
- Storage bucket/object metadata counts only; and
- current sendable campaign/outbox counts, expected to remain zero.

Raw application rows, Auth identities, credentials, and private fields must not enter logs or evidence files.

For Option A, create the exact export only through a separately authorized, pinned, non-interactive runner after the writer freeze is proven:

```text
supabase db dump --db-url "$PRODUCTION_DB_URL" -f roles.sql --role-only
supabase db dump --db-url "$PRODUCTION_DB_URL" -f schema.sql
supabase db dump --db-url "$PRODUCTION_DB_URL" -f data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
```

The current workspace is linked to approved NONPROD and its migrations extend beyond production, so it must **not** use `--linked` to capture production `auth`/`storage` changes. Build that adjunct from a separately reviewed production-through-015 baseline worktree with an explicit production DB URL, following Supabase's documented `db diff --schema auth,storage` procedure, and compare it to the existing read-only production catalog fingerprint before acceptance.

The connection material must remain in a secret manager/in-memory environment and never enter output. Pin the Supabase CLI and compatible PostgreSQL image/client, normalize a manifest containing tool versions, file byte counts, SHA-256 values, source database identity, freeze start, export start/end, and source fingerprints, then store the bundle encrypted in the approved restricted server-side location. Recheck source fingerprints after export; any write or schema drift invalidates the bundle and stops the migration.

### Gate 4 — isolated restore mutation

Under a separate restore-drill approval, use the selected supported isolated restore path:

1. Source: exact production project `wsuctjhbqiedttfnwjvf`; use the exact Option A logical-bundle manifest or an approved Option B timestamp inside the recorded PITR interval.
2. Target: a new disposable project named for the drill in the same region. Under Option A, create a clean target and use the documented single-transaction CLI/`psql` restore. Under Option B, use Dashboard Restore to a New Project. Never select in-place restore.
3. Record the source ref, export or PITR timestamp/timezone, bundle/interval identity, target ref, operator, start/end times, compute/disk posture, and displayed cost in an ignored sanitized evidence manifest.
4. Do not bind the target to Aadhyant domains, GitHub Pages, production applications, Meta, WhatsApp, SMTP, webhooks, workers, or any real-user workflow.
5. Treat the target as production-sensitive from creation. Limit Dashboard and database access to the named drill operators.
6. A physical clone inherits source compute/disk, SSL-enforcement, and database network-restriction settings; a manually created Option A target has its own initial settings. In either case, the drill approval must include immediate target-only TLS/network containment before verification. This does not authorize changing production.
7. Do not publish generated API keys or URLs. Disable external signup/recovery/email behavior on the target before any Auth testing; do not sign in as a real user.
8. Before verification, identify and disable target-side `pg_net`, `pg_cron`, wrappers, database webhooks, or other external-operation mechanisms if any exist. Edge Functions are not copied and must remain undeployed.
9. Use only server-enforced read-only catalog and aggregate queries for the drill verification.

The provider describes the physical clone as database-only. It includes database schemas/data, roles/permissions, Auth schema records, and the database encryption root key. It does **not** copy Storage objects/settings, Edge Functions, Auth settings/API keys, Realtime settings, or read replicas. The Option A logical restore is more manual: managed target schemas/settings are not replaced wholesale, custom `auth`/`storage` changes need the separate reviewed diff, and encryption-key handling must fail closed if Vault/encrypted columns are present. These omissions are part of the recovery result and must not be silently treated as restored services.

### Gate 5 — read-only verification

The drill passes only when all checks succeed:

1. Provider operation reports success and the target is healthy.
2. Target PostgreSQL major version is compatible with the source PostgreSQL 17.6 posture.
3. The exact Option A export manifest/freeze boundary or Option B provider recovery timestamp is recorded and is the source actually restored.
4. Expected production-through-015 surface exists: twelve public application tables, 40 public policies, 43 public indexes, 12 application triggers, 26 repository application functions, and the migration-011/015 projections.
5. Migration-016 and later application objects remain absent.
6. Catalog/security fingerprints match the source capture, including RLS, policies, grants, function security, and `search_path`.
7. Per-table counts and server-side digests match the source point, with a documented explanation for any provider-managed operational difference.
8. Aggregate Auth counts and Admin/Company linkage/orphan checks match; no credential or identity is printed and no real-user login occurs.
9. Storage remains explicitly incomplete: current source has zero buckets, but the drill records that future Storage files require their own backup/restore procedure.
10. No Edge Function, external callback, outbound worker, email, Meta call, WhatsApp send, or real-user action occurs.
11. Start-to-healthy and start-to-verified durations are recorded for RTO evidence.

Any mismatch, missing recovery metadata, unexpected external mechanism, broad target exposure, private-data leakage, or inability to verify read-only status fails the drill.

### Gate 6 — evidence retention and cleanup

Retain only sanitized evidence: source/target refs, timestamps, version, counts, digests, PASS/FAIL results, duration, cost estimate, and operator/approval identifiers. Store no credentials, connection strings, API keys, emails, phone numbers, UUID lists, raw rows, document contents, or screenshots containing private data.

Deletion of the drill project is destructive and is **not** implicit in restore authorization. After evidence is accepted, request separate deletion approval for the exact target ref, verify it is not production/NONPROD, confirm no continuing diagnostic need, then delete through the Dashboard. Record completion and billing cessation. Until deletion is authorized, keep the target isolated and monitored.

## Privacy and access controls

- Do not export real production data to a laptop. The preferred provider clone remains in the source region.
- Do not download Candidate documents or Storage objects. Current production has none, and database restore would not recover future files.
- Do not capture screenshots of tables, Auth users, logs, or secrets.
- Do not print or store passwords, tokens, keys, connection strings, email addresses, phone numbers, Aadhaar, bank, UAN, ESIC, document, or free-text data.
- Use aggregate counts, orphan counts, catalog fingerprints, and server-side data digests. Evidence must contain only the resulting count/digest, never the digested row material.
- Use named least-privilege operators and server-enforced read-only queries. No browser application is pointed at the target.
- Keep the target non-public operationally: no domain, deployment, Edge, worker, Meta callback, external email, or shared credentials.
- Access ends when verification ends. Project deletion still requires a separate exact-target approval.

## RPO and RTO

### Option A migration RPO: frozen export boundary

Option A can target **zero loss relative to the accepted write-freeze/export snapshot**, not zero continuous data loss. All external and operator writers must remain blocked from before the export until migration/postflight releases the freeze. The daily physical fallback alone can lose up to approximately 24 hours. If the freeze cannot be made enforceable, Option A fails and Option B is required.

### Option B operational RPO: five minutes

Supabase describes PITR recovery selection with second-level granularity and documents a worst-case RPO of approximately two minutes. Use a more conservative **five-minute operational RPO** for Option B. This is an internal target, not a contractual SLA. The actual earliest/latest recovery interval must be observed before every migration.

### RTO objectives

Use **eight hours for Option A** and **four hours for Option B**, measured from recovery declaration to a verified isolated database, as the initial internal objectives for the current small dataset. Supabase does not guarantee either duration; provisioning, manual logical restore work, and data size affect completion. The selected drill must measure:

- time from restore submission to healthy target;
- time from healthy target to completed verification; and
- operator decision/coordination time.

If the measured drill exceeds the selected objective, the RTO must be revised and explicitly accepted, or the recovery process must be improved before launch. These database RTOs exclude DNS, frontend, Edge, Auth-setting, Storage-object, Meta, and messaging recovery.

## Migration gate

**NO migration 016–029 may be applied unless every condition below is PASS at the same approved release boundary:**

- Option A has at least one listed daily physical backup, or Option B has an active provider recovery interval;
- Option A has an enforced writer freeze, a complete checksum-manifested encrypted bundle, and an exact successful restore of that mechanism, or Option B has active PITR and a selectable pre-migration timestamp;
- isolated restore proof has passed against that backup mechanism;
- backup operator, rollback decision owner, alternate, and incident channel are named;
- RPO/RTO are accepted and the drill measurement is recorded;
- the fresh production catalog/data/Auth/Storage aggregate fingerprint is captured read-only;
- P0-C, P0-D, P0-E, P0-H, and P0-I prerequisites are satisfied as required by the ordered remediation plan;
- exact migration checksums and the contiguous 016–029 suffix are independently approved; and
- the production mutation approval names the migration/checkpoint sequence and stop conditions.

PITR is recovery protection, not permission to run a migration. An in-progress transactional failure rolls back; a committed additive migration normally requires a reviewed forward-fix. In-place PITR restoration is incident authority only and must never be used casually to undo a deployment.

## Pass/fail status

| Item | Current status | Pass condition |
| --- | --- | --- |
| Current plan/add-on inventory | PASS | Authenticated read-only evidence recorded without secrets |
| Backup/PITR design | PASS | Document complete and internally reviewed; listed human choices remain MANUAL |
| Paid plan/compute | BLOCKED | Pro or higher active; Micro-or-higher for Option A or Small-or-higher for Option B |
| Recovery mode | MANUAL | Human selects conditional Option A or enhanced Option B |
| PITR decision | MANUAL | Not required for accepted Option A; approved interval required for Option B |
| Usable recovery point | BLOCKED | Option A bundle/freeze or Option B timestamp recorded and restorable |
| Restore target | BLOCKED | Separately approved isolated target created and contained |
| Restore verification | BLOCKED | All catalog/data/Auth aggregate checks pass |
| Privacy controls | MANUAL | Named access list and evidence location approved |
| RPO/RTO | MANUAL | Human accepts Option A frozen-boundary/eight-hour or Option B five-minute/four-hour targets after drill |
| Rollback ownership | MANUAL | Primary, alternate, authority, and channel named |
| Migration gate | PASS | Explicit fail-closed rule documented above |

## Human decisions required

Before requesting any P0-B mutation, humans must decide and record:

1. billing owner and maximum approved monthly/temporary drill spend;
2. Option A or Option B, with explicit acceptance that Option A requires a complete all-writer freeze and higher manual/privacy burden;
3. Pro versus a higher organization plan and production compute: Micro-or-higher for Option A, at least Small for Option B;
4. no PITR for Option A, or PITR retention of 7/14/28 days for Option B;
5. privacy/legal acceptance of the recovery retention window;
6. Option A frozen-snapshot RPO/eight-hour initial RTO or Option B five-minute RPO/four-hour initial RTO, subject to drill measurement;
7. backup operator, rollback decision owner, alternate, and incident channel;
8. exact isolated restore-project naming, access list, and cost approval;
9. authorization for the Option A writer freeze and encrypted server-side export location, if selected;
10. authorization for target-only isolation/configuration changes and the sanitized evidence location/retention period;
11. separate restore-drill execution authority; and
12. later separate destructive cleanup authority for the exact drill target.

## Exact next approval boundary

The cost-minimized next boundary is human selection of **Option A**, acceptance of the expected approximately $35/month current-organization baseline, approval of the all-writer freeze and encrypted export handling, and naming of recovery owners. After that decision, request a narrowly bounded P0-B production-infrastructure mutation authorization to upgrade the organization to Pro without PITR and wait for one listed daily physical backup. The exact logical export/write freeze and isolated restore drill remain separately authorized boundaries. If the Option A controls are rejected, request Option B authorization for Pro, production Small compute, and seven-day PITR instead. No migration, deployment, Auth/Storage/network production change, DNS/Meta action, or message is included.
