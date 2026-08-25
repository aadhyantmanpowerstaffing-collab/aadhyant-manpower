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
| Point-in-Time Recovery | Paid-plan add-on; at least Small compute required | 7 days: $100/month; 14 days: $200/month; 28 days: $400/month; billed hourly and outside Spend Cap | Recommend 7 days for launch |
| Small compute | Available add-on/current paid-project prerequisite for PITR | Read-only inventory: approximately $15/month | Required with PITR unless checkout proves an equivalent or larger active compute |
| Restore to a New Project | Paid plan with physical backups enabled; currently documented as Beta | New project mirrors source compute/disk attributes and incurs separate project costs | Use for the isolated drill |
| Manual logical dump | Supabase CLI or `pg_dump` | Operator-managed storage, encryption, retention, and restore burden | Defense in depth only; not the sole P0-B proof |

Paid daily backups are provider-scheduled; the reviewed capability exposes no customer-selected daily schedule or safe manual physical-snapshot trigger. Enabling PITR replaces daily backups because PITR provides the finer-grained recovery chain. The valid recovery interval is the earliest/latest recovery point displayed by the provider, not the add-on enablement time. A selected timestamp is usable only after the provider exposes it inside that interval.

The supported isolated recovery path is **Restore to a New Project** from a physical backup or PITR point. No evidence establishes that a Supabase preview branch is an eligible substitute for this provider backup restore, so a branch is not accepted as the P0-B recovery target.

The organization plan currently costs nothing. Moving to Pro, selecting Small compute, and enabling 7-day PITR creates paid recurring usage. Supabase's current example is approximately $25/month for Pro, $15/month for Small compute, $100/month for 7-day PITR, less the plan's applicable compute credit. That example is not an Aadhyant quote. The organization already has production and NONPROD projects, and the drill creates another temporary billed project, so the Dashboard checkout estimate, taxes, disk, compute, and all active-project charges require human acceptance before any change.

Current provider references, reviewed 25 August 2026:

- Database backups: <https://supabase.com/docs/guides/platform/backups>
- Database-backup feature/RPO summary: <https://supabase.com/features/database-backups>
- PITR usage and pricing: <https://supabase.com/docs/guides/platform/manage-your-usage/point-in-time-recovery>
- Restore to a new project: <https://supabase.com/docs/guides/platform/clone-project>
- Production checklist: <https://supabase.com/docs/guides/deployment/going-into-prod>
- Pricing: <https://supabase.com/pricing>

Provider capability, prices, and Beta behavior must be rechecked in the Dashboard immediately before approval; this document is not a price guarantee or provider SLA.

## Required target posture

Before migration 016 can be considered, P0-B requires all of the following:

1. The organization is on an approved paid plan and production uses at least Small compute.
2. Production has 7-day PITR enabled and the provider shows a valid earliest/latest recovery interval.
3. A recovery timestamp immediately before the migration window is recorded inside that interval.
4. A provider-managed restore from that source point has completed into a separate project, never over production.
5. The restored catalog, security objects, aggregate data posture, and Auth linkage match the source fingerprint captured at the recovery timestamp.
6. Storage scope is recorded separately. A database restore does not restore Storage files or operational configuration.
7. A named backup operator, rollback decision owner, alternate owner, and incident communication channel are recorded.
8. The measured drill establishes an accepted RPO/RTO and a usable recovery runbook.

A daily physical backup plus a successful clone would prove basic recoverability, but it can be nearly a day old. That is not the recommended launch posture for real account and recruitment data. Seven-day PITR is the minimum recommended production posture for this release. Fourteen or 28 days may be selected only after the business owner accepts the higher retention and cost.

## Approval and execution sequence

Every mutation below requires an explicit approval that names the target and exact action.

### Gate 1 — billing and ownership

1. Record the billing owner and accept the complete organization checkout estimate, including existing projects and the temporary drill project.
2. Approve Pro (or a higher plan), at least Small production compute, and the chosen PITR retention.
3. Approve the data-retention implications of the recovery window.
4. Name the backup operator, rollback decision owner, alternate, and incident channel.
5. Record launch-time RPO and RTO acceptance.

Stop if any owner, cost, retention decision, or authority is missing.

### Gate 2 — backup/PITR mutation

Under a separate production-infrastructure mutation approval:

1. Reverify exact organization, production project ref, region, PostgreSQL version, and current add-ons.
2. Capture the current billing/add-on settings without secret values.
3. Upgrade the organization and compute only as explicitly approved.
4. Enable only the approved PITR retention on `wsuctjhbqiedttfnwjvf`.
5. Do not migrate, deploy, change Auth/Storage/network/DNS/Meta, or send messages.
6. Wait until the provider exposes a valid recovery interval. Record earliest/latest points and a candidate source timestamp without private row data.

Stop if the project identity differs, checkout differs materially, PITR cannot be enabled cleanly, the recovery interval is absent, or project health degrades.

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

### Gate 4 — isolated restore mutation

Under a separate restore-drill approval, use Dashboard **Restore to a New Project**:

1. Source: exact production project `wsuctjhbqiedttfnwjvf` and an approved timestamp inside the recorded PITR interval.
2. Target: a new disposable project named for the drill, in the provider-selected same region. Never select in-place restore.
3. Record the source ref, source timestamp/timezone, recovery interval, target ref, operator, start/end times, compute/disk posture, and displayed cost in an ignored sanitized evidence manifest.
4. Do not bind the target to Aadhyant domains, GitHub Pages, production applications, Meta, WhatsApp, SMTP, webhooks, workers, or any real-user workflow.
5. Treat the target as production-sensitive from creation. Limit Dashboard and database access to the named drill operators.
6. The clone inherits source compute/disk, SSL-enforcement, and database network-restriction settings. Because the current source has SSL enforcement off and open database CIDRs, the drill approval must include immediate target-only TLS/network containment before verification. This does not authorize changing production.
7. Do not publish generated API keys or URLs. Disable external signup/recovery/email behavior on the target before any Auth testing; do not sign in as a real user.
8. Before verification, identify and disable target-side `pg_net`, `pg_cron`, wrappers, database webhooks, or other external-operation mechanisms if any exist. Edge Functions are not copied and must remain undeployed.
9. Use only server-enforced read-only catalog and aggregate queries for the drill verification.

The provider describes this clone as database-only. It includes database schemas/data, roles/permissions, Auth schema records, and the database encryption root key. It does **not** copy Storage objects/settings, Edge Functions, Auth settings/API keys, Realtime settings, or read replicas. These omissions are part of the recovery result and must not be silently treated as restored services.

### Gate 5 — read-only verification

The drill passes only when all checks succeed:

1. Provider operation reports success and the target is healthy.
2. Target PostgreSQL major version is compatible with the source PostgreSQL 17.6 posture.
3. Recorded source timestamp is inside the provider recovery interval and is the exact source used.
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

### Recommended launch RPO: five minutes

Supabase describes PITR recovery selection with second-level granularity and documents a worst-case RPO of approximately two minutes. Aadhyant should use a more conservative **five-minute operational RPO** for launch. This is a target, not a contractual SLA. The actual earliest/latest recovery interval must be observed before every migration, and a quiet-database latest point can appear behind wall-clock time without omitting a transaction.

Daily backups alone imply an RPO of up to approximately 24 hours and therefore do not meet this recommendation without explicit risk acceptance, a write freeze, and an additional approved immediate backup mechanism.

### Recommended launch RTO: four hours

Use **four hours from recovery declaration to a verified isolated database** as the initial internal RTO for the current small production dataset. Supabase does not guarantee that duration; provisioning and restore time depend on data size and platform conditions. The first drill must measure:

- time from restore submission to healthy target;
- time from healthy target to completed verification; and
- operator decision/coordination time.

If the measured drill exceeds four hours, the RTO must be revised and explicitly accepted, or the recovery process must be improved before launch. This database RTO excludes DNS, frontend, Edge, Auth-setting, Storage-object, Meta, and messaging recovery.

## Migration gate

**NO migration 016–029 may be applied unless every condition below is PASS at the same approved release boundary:**

- paid backup posture and selected PITR retention are active;
- a usable provider recovery interval and exact pre-migration recovery timestamp are recorded;
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
| Paid plan/compute | BLOCKED | Approved plan and at least Small compute active |
| PITR | BLOCKED | Approved retention active with valid recovery interval |
| Usable recovery point | BLOCKED | Exact source point recorded and selectable |
| Restore target | BLOCKED | Separately approved isolated target created and contained |
| Restore verification | BLOCKED | All catalog/data/Auth aggregate checks pass |
| Privacy controls | MANUAL | Named access list and evidence location approved |
| RPO/RTO | MANUAL | Human owner accepts values after measured drill |
| Rollback ownership | MANUAL | Primary, alternate, authority, and channel named |
| Migration gate | PASS | Explicit fail-closed rule documented above |

## Human decisions required

Before requesting any P0-B mutation, humans must decide and record:

1. billing owner and maximum approved monthly/temporary drill spend;
2. Pro versus a higher organization plan;
3. production compute size, at least Small;
4. PITR retention: recommended 7 days, or approved 14/28 days;
5. privacy/legal acceptance of the recovery retention window;
6. five-minute RPO and four-hour initial RTO, subject to drill measurement;
7. backup operator, rollback decision owner, alternate, and incident channel;
8. exact isolated restore-project naming, access list, and cost approval;
9. authorization for target-only isolation/configuration changes required immediately after cloning;
10. sanitized evidence location and retention period;
11. separate restore-drill execution authority; and
12. later separate destructive cleanup authority for the exact drill target.

## Exact next approval boundary

After human acceptance of the decisions above, request a narrowly bounded **P0-B Gate 2 production-infrastructure mutation authorization** to upgrade the organization/compute as approved and enable only the selected PITR retention on `wsuctjhbqiedttfnwjvf`. Stop again after a valid recovery interval is proven. Creating and containing the isolated restore target remains a second, separately authorized mutation boundary. No migration, deployment, Auth/Storage/network production change, DNS/Meta action, or message is included.
