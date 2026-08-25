# Aadhyant Web Platform — Production Readiness Audit

Audit date: 24 August 2026 (Asia/Kolkata)
Audited branch: `web-platform-development`
Audited release HEAD: `91041094a58b43b3f85b940e7d7c9e8d9ae72222`
Audit mode: local/repository read-only; production, DNS, Meta, WhatsApp, and real users were not contacted.

## Verdict

- **READY FOR PRODUCTION DEPLOYMENT: NO.** The repository release is internally consistent and locally regression-clean, but the deployed production baseline, Supabase catalog/Auth/Storage/Edge state, backup capability, Pages deployment source, DNS/TLS state, security headers, and production Meta assets are not verified. Several repository-level hardening blockers also remain.
- **READY FOR REAL WHATSAPP PILOT: NO.** Only the inbound Edge receiver and fake provider exist. A real provider adapter, permanent worker, approved production Meta assets/templates, production ingress proof, monitoring, rate limits, and operator runbooks are absent or unverified.

Unknown external state is not marked PASS. This audit does not authorize a deployment, migration, user creation, DNS change, Meta change, queue action, or message.

## Release and architecture evidence

- Local and `origin/web-platform-development` both resolve to `91041094a58b43b3f85b940e7d7c9e8d9ae72222`; divergence is `0/0`.
- The tracked worktree and index were clean at audit start. Only expected `supabase/.temp/` was untracked.
- No release tags or deployment workflow are present. `origin/main` is at `29e0e55`, but repository evidence does not prove that it, or any other commit, is the currently deployed production revision. Therefore no “last production-deployed commit” is guessed and no cumulative production delta is claimed.
- The intended web topology is a static multi-page HTML/CSS/JavaScript site documented as GitHub Pages, with Supabase providing Postgres, Auth, Storage, RLS/RPCs, and Edge Functions.
- `CNAME` declares the apex domain `aadhyantmanpower.in`.
- The tracked browser configuration identifies intended Supabase project ref `wsuctjhbqiedttfnwjvf` and URL `https://wsuctjhbqiedttfnwjvf.supabase.co`. This is configuration evidence, not verified production identity.
- The intended Edge function name is `whatsapp-webhook`. Its exact production URL, deployed version/source, `verify_jwt` setting, secret inventory, and runtime status are not recorded or verified.
- The repository contains no confirmed production Meta App ID, WABA ID, phone-number ID, registered production number, approved template inventory, callback subscription state, or production delivery evidence.

## Configuration separation

`config.js` is the single tracked browser configuration consumed by the public site, Admin, Candidate Portal, Employer Portal, and Contractor Portal through `supabase-client.js`. It currently points directly at the intended production Supabase project and contains only a browser publishable key; no service-role material is present.

Session persistence, refresh, and callback detection are enabled only for `/admin/`, `/company/`, `/contractor/`, and `/candidate/portal/`. Public routes use non-persistent sessions.

NONPROD review is implemented outside tracked runtime source by ignored loopback-only review servers that replace `config.js` in memory, restrict the Host header, and add `NONPROD REVIEW`. The approved NONPROD ref is distinct from the tracked production ref. The ignored DPAPI Admin credential and `.env.*` review/staging files are not tracked. No NONPROD ref, badge, `test.invalid` identity, DB credential, or privileged key occurs in the shipped HTML/JavaScript/CSS runtime.

Blockers:

1. There is no tracked environment-aware release mechanism or hostname/project allowlist. An ordinary local static server loads the production configuration by default and can contact production.
2. `config.js` has no documented cache policy or version/atomic-release contract, creating a stale-config/mixed-artifact risk.
3. The private staging denylist contains the production project ref, but the derived direct production DB hostname was not proven present in the host denylist. Complete the denylist before any further write-capable database action.
4. The staging guard correctly fails the current release HEAD until an operator explicitly reviews and updates its privately approved HEAD; this is expected after public-only commits and must never be bypassed.

Required correction: produce an allowlisted deployment artifact with explicit environment injection, bind production config to the approved production hostname/project ref, fail closed on mismatch, give `config.js` a no-cache/revalidation policy, and keep hashed static assets long-cacheable.

## Migration manifest and immutability

The repository manifest is exactly `supabase/schema.sql` followed by one migration for every number 007–029: 24 files total, no gaps, duplicates, or migration 030+.

| Artifact | SHA-256 | Result |
| --- | --- | --- |
| Migration 026 | `9e086c31978912f179491e687b5b8f0927c6710f9b5389a4245dbead20413e82` | Matches the blob present at W7A runtime-validation closure |
| Migration 027 | `5b2f7226df9f79729d741aef84ba36011153921691c4694e10104ae65dcddfe0` | Matches the blob present at W7A runtime-validation closure |
| Migration 028 | `54c7e66a45703a95261aa9fee96f92474255a54de20d3a48ae6fc4efff2454ec` | Matches approved documentation |
| Migration 029 | `a1214b6beea3e575d4594edef8adacbf34b53ee2da20e52761fdefd3a50ecd1e` | Matches approved documentation and validated blob |
| `schema.sql` + 007–029 manifest | `7429888214faca7524c1e119674684ab8765052bb36701dd82b22353de07ac46` | Matches approved documentation and guard |

Migrations 026 and 027 had no exact SHA-256 values in the pre-audit narrative documentation. The values above are now recorded from the immutable current files and their Git blob equality to the W7A runtime-validation closure; they are not evidence that production contains those definitions.

All migrations except corrective migration 020 contain explicit `BEGIN`/`COMMIT`. Migration 020 is immutable and must be run through a reviewed runner with a single transaction/stop-on-error boundary. Do not edit it or paste its statements separately.

NONPROD evidence confirms the ordered schema through 029 and its checkpoints. Production installation state is unknown. A migration file is intent, not evidence of a production object.

## Exact production database preflight and deployment design

Do not execute this sequence until a separate production read-only inventory and then a separate production mutation approval are granted.

1. Record operator, maintenance window, release HEAD, exact manifest hashes, intended project ref, and approved change ticket.
2. From the production dashboard/management plane, independently verify project ref, project name/environment, organization, region, database host, database name, and current plan. Compare against a production allowlist and complete staging denylist. Do not trust cached CLI linkage.
3. Require TLS and run a transaction declared `READ ONLY`; record only database/user/server identity, version, and read-only status. Stop on any mismatch.
4. Confirm a fresh provider snapshot/PITR point exists, record its identifier/time, and prove restore capability into an isolated project. Export schema/catalog and non-PII row counts/digests. Do not export sensitive rows into audit artifacts.
5. Capture production migration ledger if present and the actual definitions of all application tables, columns, constraints, indexes, triggers, functions, owners, function configuration, policies, grants, Storage buckets/policies, and relevant Auth hooks. Capture existing W7/Edge objects separately.
6. Compare actual objects and definitions to `schema.sql` and migrations 007–029. Determine the exact installed prefix/object-equivalent posture. If history is absent, ambiguous, hand-edited, partially installed, or definition-drifted, stop and prepare a separately reviewed reconciliation plan. Never infer installation from filenames.
7. On an empty approved project only, apply `schema.sql` first and migrations 007–029 once in exact order. On an existing production project, do not replay `schema.sql` or any installed migration; apply only a proven contiguous missing suffix.
8. Use a pinned PostgreSQL client, TLS, `ON_ERROR_STOP=1`, per-file checksums, sanitized logs, and a transaction boundary for every file. Wrap immutable migration 020 at the runner level. Stop on the first error; do not weaken a preflight or rerun fragments.
9. After each migration, verify its expected catalog delta and that pre-existing row counts/digests and protected grants remain unchanged. If verification fails, stop before the next migration.
10. Postflight the complete 029 catalog: 27 repository-created public tables with RLS, function ownership/security/search paths, grants, policies, triggers, indexes, Storage bucket/policies, W7 tables/RPCs, and zero browser grant on W7 base tables.
11. Confirm zero queued/claimed/sending outbound rows and zero queued/sending campaigns before any Edge or Admin enablement. Do not insert a real or synthetic Candidate, requirement, campaign, message, or Auth identity as a catalog check.
12. Keep sending workers, Graph credentials, campaign queueing, Meta callback, and public sensitive intake disabled until their later launch gates pass.

Stop conditions include identity ambiguity, missing backup/restore proof, non-contiguous migration state, hash drift, unexpected objects/data, failed preflight, partial application, broader grants, missing RLS, non-empty sendable queues, or any inability to prove production isolation.

Repository SQL checkpoints 009–032 create transaction-scoped synthetic fixtures, including Auth/role contexts. They are **NONPROD-only** and must not be run against production even though they normally roll back. Production postflight should use read-only catalog/reconciliation queries. Any later production smoke record requires its own explicit approval, internal identity, manifest, bounded scope, and verified cleanup; no `test.invalid` identity is permitted.

## Database and runtime security review

- Static scan found 27 repository-created public tables and an RLS-enable declaration for all 27.
- All 164 `SECURITY DEFINER` function definitions have `search_path = ''`.
- No unconditional `USING (true)` or `WITH CHECK (true)` policy was found.
- Browser W7 mutations remain service-role-only; W7 Admin projections are bounded and masked.
- The only dynamic SQL found is a migration-007 `DO` block that formats allowlisted fixed table/trigger identifiers. No runtime function uses dynamic SQL.
- The migration-028 audience-freeze delete operates only on the locked mutable draft campaign audience and is part of the reviewed lifecycle, not destructive migration behavior.
- Public Employer/Candidate direct inserts are intentionally column-limited and RLS-bound. Candidate Storage upload/delete is restricted to the private candidate bucket and server-validated ownership paths.
- Canonical W3, W7B, and new Admin product controllers are RPC-only. However, legacy compatibility logic in `admin/admin.js` still performs direct base-table reads and controlled direct status/note updates. That fails the requested “no direct Admin table writes” readiness criterion. It must be removed/disabled in a production artifact or explicitly accepted only after production grants/RLS are independently verified.
- Production RLS, grants, owners, and definitions remain BLOCKED until read-only production catalog comparison.

## Auth and production Admin bootstrap

Candidate signup/login and server-derived profile linkage exist. Company and Contractor signup/login create pending organization memberships through reviewed server triggers and require Aadhyant approval before active portal access. Admin login requires Supabase Auth plus `get_current_staff_session`; route hiding is not authorization.

Production Auth settings are not repository-controlled or verified: email confirmation, SMTP, redirect allowlist, CAPTCHA, password policy, recovery, MFA, rate limits, session duration, leaked-password protection, and provider settings are unknown. Legacy `SUPABASE_SETUP.md` says to disable public signup for an older admin-only stage, which conflicts with the current Candidate/Company/Contractor signup product and must not be followed without an updated Auth decision. Company exposes password recovery; Candidate, Contractor, and Admin do not provide equivalent recovery UI.

Safe production Admin bootstrap procedure:

1. Use a real named administrator email; never use NONPROD, synthetic, shared, or `test.invalid` identity.
2. Configure production Auth security first, require confirmed email, strong unique password, and MFA if supported/approved.
3. Have a project owner create/invite the Auth user through the production management plane. Do not expose an Admin signup route.
4. In a separately approved transaction, insert that exact Auth UUID into `public.admin_users`; record operator/correlation without password or token.
5. Sign in through the production Admin URL and verify `get_current_staff_session` returns bootstrap authority. Use reviewed staff-management RPCs for ordinary staff profiles/roles; grant least privilege.
6. Verify an authenticated non-allowlisted user and every external portal identity are denied Admin access. Maintain two controlled break-glass owners and a removal/recovery procedure.

No production user may be created during readiness review or zero-send deployment.

## Public website and Admin review

Local static verification covered 43 HTML files with zero broken local targets. The twelve core public pages each have one title, description, canonical URL under the apex domain, and one `h1`, with no NONPROD/test/internal identifier leakage. Organization JSON-LD contains only published business information. The exact visible identity is consistent: Aadhyant Manpower & Staffing; `+91 95867 85800`; `aadhyantmanpowerstaffing@gmail.com`; GSTIN `24ACNFA4445J1Z9`; Kadi, Mahesana, Gujarat 384440. Privacy, Terms, and Data Deletion links are present.

The public Candidate, Employer, and Contractor journeys and Portal Login remain canonical and locally tested. The Admin shell, role gating, safe projections, loading/empty/error states, responsive behavior, and W7 views remain locally tested. Admin has no public navigation link and its pages include `noindex`.

Readiness gaps:

- Candidate Portal pages, Company registration, and several Contractor private pages lack `noindex,nofollow`.
- `robots.txt` and a sitemap are absent.
- Job detail is client-rendered at a query URL; no fabricated `JobPosting` data is emitted.
- No production routes, real Jobs projection, console/network behavior, or deployed Admin session were contacted in this audit.
- The privacy policy does not yet receive documented human/legal signoff for compulsory Aadhaar fingerprinting, Candidate documents, bank/UAN/ESIC data, minors, retention/deletion operations, and production WhatsApp processing. A formal retention schedule is explicitly absent.

## Hosting, performance, SEO, and headers

Core public HTML totals 106,032 bytes; the largest page is approximately 12.2 KB. The `assets/` directory totals approximately 89.7 KB. No raster `<img>` assets are used, avoiding image layout/weight issues. No new runtime framework is present. Public Jobs and homepage requests are bounded.

GitHub Pages is documented as the intended host, but repository evidence does not establish its configured source branch/folder, currently deployed commit, custom-domain state, HTTPS enforcement, or rollback behavior. No GitHub Actions deployment workflow or allowlisted artifact exists. Publishing the repository root could expose approximately 125 non-runtime tracked files, including `supabase/`, SQL tests/migrations, scripts, project documentation, and test source. Even without credentials, that is an unacceptable production artifact boundary.

Thirty-three pages load `@supabase/supabase-js@2` from jsDelivr without an exact version or Subresource Integrity. A compromised or unexpected CDN update would execute in authenticated portals. There is no CSP, HSTS declaration/verification, frame protection, referrer policy, permissions policy, MIME-sniffing protection, or explicit `config.js`/asset cache policy in the repository. GitHub Pages does not provide repository-defined custom response headers through the files present here, so the actual hosting/CDN control plane must be selected and verified before deployment.

Required domain plan (do not execute during audit):

- Keep the apex `https://aadhyantmanpower.in/` canonical because all canonical tags use it.
- Verify the Pages/default-host identity and domain ownership in the hosting dashboard.
- Export the current DNS zone and TTLs. At execution time, obtain the provider’s current official apex A/AAAA or ALIAS/ANAME records; do not rely on copied historical IPs.
- Point `www` by the provider’s approved CNAME and enforce one HTTPS redirect from `www` to apex.
- Verify certificate issuance, HTTPS enforcement, mixed-content absence, canonical redirects, and Auth redirect URLs before traffic cutover.
- Roll back by restoring the captured exact DNS records and previous frontend artifact; preserve the old target until TTL plus monitoring window expires.

## WhatsApp and Meta readiness

W7A provides signature-verified, size-bounded, idempotent inbound/status handling; W7B provides approved campaign/audience/outbox contracts; W7C provides exact `INTERESTED` correlation and canonical application idempotency. Raw arbitrary inbound free text is discarded; safe structured metadata is bounded; Admin projections mask contacts.

The repository contains only the provider interface and `FakeWhatsAppProvider`. There is no real Graph adapter, continuously running outbox worker, permanent worker host, production callback deployment, or production rate-limit/alert runbook. Production Meta App/WABA/phone-number assets, business verification, callback, verify token, App Secret, subscriptions, access-token rotation, approved templates/languages/variables, throughput tier, quality status, consent evidence, suppression/STOP operations, and status delivery are unknown. NONPROD test-number behavior did not prove real Meta inbound delivery.

Before real messaging, manually verify all of those assets in the correct production business context; store secrets only in the production secret manager; verify GET challenge and exact raw-body signature handling; prove inbound and status callback delivery; approve templates; confirm marketing versus transactional consent; test STOP/suppression at enqueue and claim; set rate/concurrency/retry budgets; monitor provider-call ambiguity; and train operators on failed/reconciliation states. No campaign queue action is a smoke test.

## Staged real-message launch plan

### Stage A — zero-send production deployment

- Prerequisites: every P0 closed, verified backup/restore, exact production identity/catalog, allowlisted artifact, headers/config/Auth configured, sends/workers/Graph credentials disabled, Meta callback unchanged or disabled, and zero sendable rows.
- Validate only route availability, Auth denials, safe read projections, catalog, logs, and empty states. Do not create users/records or queue campaigns.
- Hard stop: any identity mismatch, failed migration/postflight, unexpected request host, secret/config leak, RLS denial failure, sendable row, worker activity, or production error spike.

### Stage B — one controlled internal/operator message

- Requires separate explicit messaging authorization, production Meta assets, real provider/worker review, internal consented operator number, exact one-message manifest, and active observation.
- Prove one inbound and, if separately approved, one template outbound; verify signature, dedupe, provider ID, status progression, audit, suppression, and no duplicate.
- Hard stop: missing ingress/status, correlation mismatch, duplicate, unexpected recipient, raw/sensitive logging, unbounded retry, or any ambiguous provider outcome.

### Stage C — small approved internal/known test audience

- Freeze an explicitly enumerated consented internal audience, cap volume and concurrency, use one approved template, and require operator review before queue.
- Hard stop: any recipient outside manifest, suppression failure, delivery/error threshold breach, monitoring gap, or complaint/opt-out handling failure.

### Stage D — limited real-Candidate pilot

- Requires legal/privacy approval, verifiable consent, approved retention/deletion operations, trained support, daily volume cap, manual audience review, and rollback owner.
- Hard stop: consent ambiguity, wrong vacancy/candidate correlation, privacy disclosure, STOP failure, elevated provider errors/blocks, duplicate send/application, or support capacity breach.

### Stage E — general campaign operation

- Requires signed pilot review, stable deliverability/quality, cost and throughput budgets, on-call ownership, incident/rotation runbooks, periodic suppression/reconciliation audit, and approved scale limits.
- Hard stop: quality degradation, budget/rate breach, monitoring loss, backlog/lease anomalies, privacy incident, or provider policy issue.

## Data, privacy, and legal posture

- Candidate/Company/Contractor projections are role-scoped; Company/Contractor views omit Candidate contact and internal data. Admin canonical projections expose contact only to approved roles; W7 Admin projections are masked.
- Full Aadhaar is not retained, but deterministic SHA-256 over a 12-digit enumerable space is not adequate protection against offline enumeration. Key-managed HMAC/tokenization is required before real Aadhaar collection.
- Bank account displays are masked, and UAN/ESIC values are conditionally validated, but production encryption/key management, retention, deletion, access review, and incident procedures are not established.
- Candidate documents use a private bucket and short-lived signed URLs, but declared MIME/extension/size checks are not magic-byte inspection, malware scanning, quarantine, content disarm, or retention enforcement.
- W7 persists hashes and bounded/redacted summaries, not raw webhook bodies or arbitrary free text. Formal retention/deletion periods and DLP/incident handling remain unapproved.
- Browser runtime contains no literal UUID fixtures, NONPROD ref, synthetic identity, privileged key, or raw secret. Errors shown to users are generally bounded; no application console logging was found as an operational dependency.
- Privacy Policy, Terms, and Data Deletion exist and contain correct business contacts, but require qualified human/legal review for the actual production data lifecycle. This audit does not invent legal conclusions.

## Backup and rollback

### Prerequisites

Before launch, capture and verify: provider DB snapshot/PITR, restore drill into isolation, schema/catalog/grant/policy/function dump, Storage bucket/policy inventory plus protected object backup strategy, Auth settings/users configuration export where supported, Edge function source/version/settings and secret-name inventory, Meta callback/subscription/template export, DNS zone/TTLs, hosting configuration, and previous frontend artifact/commit.

### Rollback actions

- **Frontend/Public/Admin:** redeploy the previous verified allowlisted artifact by normal reviewed deployment; do not force-push or reset shared Git history. Keep database/Edge changes disabled but intact.
- **Auth:** disable new external signup or affected routes through the approved control plane if intake is unsafe; revoke affected sessions/roles only through an incident plan. Never delete users as a generic rollback.
- **Edge:** disable callback/traffic or deploy the previously captured reviewed function version and settings. Do not delete webhook history. Keep outbound worker disabled.
- **Database:** stop feature rollout and writes, inspect transaction outcome, compare to baseline, and use a reviewed forward-fix. Additive migrations are not rolled back by dropping tables/columns. Restore/PITR only under incident authority after impact analysis and isolated restore verification.
- **Meta:** pause templates/sending and restore the captured callback/subscription configuration manually. Rotate a secret only through the incident/rotation runbook.
- **DNS:** restore the exact exported records and prior hosting target; observe TTL/certificate/redirect behavior. Do not improvise record values.

## Observability and operations

Repository capabilities include `audit_logs`, application stage history, W7 webhook/outbound/message event ledgers, Admin campaign status, Incoming, and Failed/Attention views. Supabase supplies platform logs when configured.

Critical gaps: no verified production log retention/access, external error monitoring, alert routing/on-call ownership, Edge availability/latency/error SLOs, Auth anomaly monitoring, queue-depth/lease/reconciliation alerts, campaign quality/cost budgets, Storage malware/retention operations, incident runbook, secret rotation drill, or tested production restore procedure. The Failed/Attention UI is useful but is not active alerting.

## Local validation record

- Public focused tests: 24/24 PASS.
- Full frontend regression: 182/182 PASS.
- Admin/W7B focused regression: 92/92 PASS.
- W7 Edge tests: 21/21 PASS.
- JavaScript syntax: 16/16 PASS.
- Staging identity guard assertion tests: PASS.
- Static routes: 43 HTML files, zero broken local targets.
- Core metadata/headings/canonicals: 12/12 PASS; zero runtime NONPROD/test/internal-ID leakage.
- SQL static security: 27/27 created public tables declare RLS; 164/164 `SECURITY DEFINER` functions use empty `search_path`; zero unconditional true policies; no migration 030+.
- Credential/history scan: no private key, Supabase secret, service-role JWT, credential URL, or tracked `.env`. One Meta-token-shaped regex hit was inspected and is only part of a documented SHA-256 checksum. One browser publishable key is expected public configuration.
- `git diff --check`: required again after this document is finalized.

## Blocker register

### P0 — must fix before any production deployment

1. Authorize and complete read-only production Supabase/Auth/Storage/Edge, hosting/deployed-commit, DNS/TLS, and backup inventory; establish the true production baseline.
2. Repository/local P0-A is implemented and tested. Production remains blocked until Pages is separately switched from repository-root publication to the reviewed `dist/` Actions artifact.
3. Verify backup/PITR and complete an isolated restore drill; approve the exact missing migration suffix and transactional runner, including migration 020 containment.
4. Replace default-production local config behavior with explicit environment/host identity binding and cache-safe atomic configuration; complete the production DB-host denylist.
5. Select/configure a host/CDN capable of the required HTTPS headers and cache controls; pin/self-host Supabase JS or use an exact version with reviewed integrity/CSP.
6. Resolve Aadhaar deterministic-hash risk and document upload scanning/quarantine/retention, or keep all sensitive Candidate intake routes unavailable in production through a server-authoritative gate.
7. Reconcile and approve production Auth settings for all four audiences, redirects, email confirmation/recovery, rate limits/CAPTCHA, session security, and Admin MFA/bootstrap.
8. Remove/disable legacy Admin direct-table write compatibility paths or explicitly approve them only after exact production RLS/grant proof.
9. Obtain human/legal approval for privacy, deletion, retention, minors, sensitive identifiers/documents, and WhatsApp data handling.

### P1 — must fix before real-user or WhatsApp launch

1. Implement/review a real Meta provider adapter and permanent outbox worker; keep fake provider out of production sending.
2. Verify production Meta App, WABA, phone-number ID, registered number, callback, secrets, subscriptions, templates, consent/STOP, rate limits, quality, and token rotation.
3. Resolve real production inbound/status delivery with a separately authorized internal test; NONPROD test-number behavior is not proof.
4. Add active monitoring/alerts, SLOs, on-call and incident/secret-rotation runbooks, queue reconciliation, Auth diagnostics, and cost/quality budgets.
5. Add abuse protection for public signup/intake and complete Candidate/Contractor/Admin recovery policy/UI as required.
6. Add `noindex,nofollow` to private portal/auth routes that currently lack it and verify crawl behavior.
7. Complete load/failure/retry/concurrency testing for webhook/outbox/campaign paths and a controlled pilot rehearsal.

### P2 — launchable only after risk acceptance; fix soon

1. Add reviewed `robots.txt` and sitemap for crawlable public routes.
2. Formalize dependency/SBOM and periodic vulnerability review beyond the current static scan.
3. Reconcile older milestone/setup documentation whose current-state language predates Candidate Portal and later closures.

### P3 — enhancement

1. Add governed server-rendered job detail/complete `JobPosting` structured data when safe organization/job fields exist.
2. Add the deferred safe W7C conversion/audit projections rather than fabricating them in Admin.
3. Add richer production analytics only after privacy, consent, and retention governance.

## Production launch checklist

### A. Git/release

- [x] **PASS** Branch, local HEAD, remote HEAD, 0/0 divergence, and reviewed release history are exact.
- [x] **PASS** Tracked tree/index were clean; only `supabase/.temp/` was untracked.
- [ ] **BLOCKED** Last production-deployed commit and current deployed artifact are not proven.
- [x] **PASS** Repository/local P0-A implementation now builds and validates an explicit allowlisted `dist/` artifact through a manual-only workflow.
- [ ] **MANUAL** Production Pages still publishes the legacy repository-root source; switching it to GitHub Actions and deploying `dist/` require separate approval.

### B. Production target identity

- [x] **PASS** Repository-intended Supabase ref/URL and apex domain are identified.
- [ ] **BLOCKED** Actual production project/database identity and catalog are not verified.
- [ ] **BLOCKED** Production Edge inventory/version/config/secrets posture is not verified.
- [ ] **MANUAL** Authorize a read-only production inventory before any write-capable plan.

### C. Backup

- [x] **PASS** Current Free-plan, zero-backup/PITR capability and the P0-B target plan are documented in `PRODUCTION_BACKUP_RESTORE_PLAN.md`.
- [ ] **BLOCKED** No usable production backup exists; paid plan and conditional Option A versus PITR Option B approval is pending.
- [ ] **BLOCKED** Isolated restore drill has not been evidenced.
- [ ] **MANUAL** Approve billing, retention, RPO/RTO, restore target/access, and named rollback ownership before any P0-B mutation.
- [ ] **MANUAL** Capture DB, Storage, Auth settings, Edge, Meta, DNS, hosting, and prior artifact baselines.

### D. Database

- [x] **PASS** Repository manifest 007–029 is complete and hash-consistent.
- [x] **PASS** NONPROD migration/checkpoint evidence through 029 is documented.
- [ ] **BLOCKED** Production installed prefix/object drift is unknown.
- [ ] **BLOCKED** Exact missing-suffix execution authorization and postflight are absent.
- [ ] **NOT APPLICABLE** Runtime SQL fixture checkpoints are not suitable for production.

### E. Auth

- [x] **PASS** Repository role/linkage/RPC design is server-authoritative and locally tested.
- [ ] **BLOCKED** Production provider, confirmation, redirect, recovery, MFA, CAPTCHA/rate, SMTP, and session settings are unknown.
- [ ] **BLOCKED** Current legacy setup guidance conflicts with external portal signup needs.
- [ ] **MANUAL** Bootstrap only a real named Admin after Auth and DB approval.

### F. Frontend/Admin

- [x] **PASS** Public, portal, and Admin local regressions pass; routes and canonical role journeys are intact.
- [x] **PASS** No tracked NONPROD badge/ref or privileged credential is in runtime files.
- [ ] **BLOCKED** Production config identity binding, artifact boundary, and deployed smoke are absent.
- [ ] **BLOCKED** Legacy Admin direct-table write paths remain.
- [ ] **MANUAL** Verify all changed routes at production URLs only after zero-send deployment approval.

### G. Edge

- [x] **PASS** Local Edge signature, parsing, idempotency, status, and W7C tests pass 21/21.
- [ ] **BLOCKED** Production function is not deployed/inventoried/verified.
- [ ] **BLOCKED** Production rate limit, logging, alerts, and callback proof are absent.
- [ ] **NOT APPLICABLE** A real sender is not part of the current Edge receiver.

### H. Meta/WhatsApp

- [x] **PASS** Consent/suppression, durable outbox, status monotonicity, and INTERESTED idempotency contracts exist.
- [ ] **BLOCKED** Real provider/worker and production Meta assets/templates are absent or unverified.
- [ ] **BLOCKED** Real inbound production proof and staged messaging approval are absent.
- [ ] **MANUAL** Perform Stages B–E only under separate explicit message authorization.

### I. Domain/DNS/HTTPS

- [x] **PASS** Apex canonical strategy is consistent in source and `CNAME`.
- [ ] **BLOCKED** Current DNS, Pages custom-domain source, certificate, HTTPS enforcement, and www redirect are unverified.
- [ ] **MANUAL** Export existing zone/TTLs and use current official provider records during an approved change window.

### J. Security/privacy

- [x] **PASS** Static RLS/search-path/runtime leak and credential scans pass.
- [ ] **BLOCKED** Aadhaar key-managed protection and document scanning/quarantine are absent.
- [ ] **BLOCKED** Security headers, exact trusted frontend dependency, retention/deletion controls, and legal signoff are absent.
- [ ] **MANUAL** Complete a production threat/security review and approve sensitive-data operations.

### K. Observability

- [x] **PASS** Audit/history ledgers and Admin Failed/Attention visibility exist in repository contracts.
- [ ] **BLOCKED** Production logs, alerts, SLOs, on-call, error monitoring, and runbooks are not established.
- [ ] **MANUAL** Validate alert delivery and operator ownership before traffic or messages.

### L. Controlled smoke test

- [ ] **BLOCKED** Stage-A production identity/deployment prerequisites are not met.
- [ ] **MANUAL** Use read-only/zero-write route, denial, catalog, and log checks after separate deployment approval.
- [ ] **NOT APPLICABLE** No live message belongs in Stage A.

### M. Pilot launch

- [ ] **BLOCKED** Stages B–D prerequisites, provider worker, Meta approval, consented audience, and monitoring are absent.
- [ ] **MANUAL** Require an exact recipient/message manifest and separate approval at every stage.

### N. Rollback

- [x] **PASS** Repository architecture favors forward-fix DB recovery and prior-artifact frontend rollback.
- [ ] **BLOCKED** Actual previous artifacts, snapshots, DNS/Meta baselines, and restore rehearsal are not captured.
- [ ] **MANUAL** Assign rollback owner, thresholds, decision authority, and communication channel before launch.

## Privileged read-only production export — 2026-08-24

This export used authenticated management `GET` requests and Supabase's server-enforced `/database/query/read-only` endpoint. The SQL execution context reported `transaction_read_only=on` and role `supabase_read_only_user`. No production write, migration, checkpoint, Auth or Storage mutation, backup/restore, deployment, DNS change, Meta action, or message occurred. Access tokens and secret-valued configuration fields were held only in memory and were not printed or recorded.

### Exact production baseline

- Supabase project `wsuctjhbqiedttfnwjvf` is `ACTIVE_HEALTHY` in `ap-northeast-1`, PostgreSQL 17.6 (platform build 17.6.1.155).
- The exact application catalog is object-equivalent through migration 015: twelve public tables, the migration-011 public projection, and the migration-015 Company/Contractor projections are present; migration-016 foundation tables and every later Candidate-document/W7 table are absent.
- `supabase_migrations.schema_migrations` and the entire `supabase_migrations` schema are absent. Production therefore has no authoritative migration ledger. The missing suffix must be proven from catalog preflight and never inferred from a ledger that does not exist.
- All twelve public application tables have RLS enabled. The catalog contains 40 public policies, 43 public indexes, 12 application triggers, and the expected 007–015 constraints and application function signatures. No application-object name/signature/security-setting drift from the repository 007–015 surface was found. A byte-for-byte function-body or historic execution proof is impossible without a prior catalog fingerprint/ledger, so the deployment preflight must recapture definitions and hashes.
- All 26 repository application functions in `public`/`private` use explicit `search_path=''`; all externally callable mutation functions are `SECURITY DEFINER` and ACL-scoped as expected. Supabase additionally owns `public.rls_auto_enable()` and the `ensure_rls` event trigger with `search_path=pg_catalog`; this is a platform-managed object, not an application migration.
- Anonymous access is limited by RLS/policy. `authenticated` has `SELECT` only on `admin_users`, `candidates`, `employer_requirements`, and `interviews`; it has `INSERT, SELECT, UPDATE` on the other eight legacy application tables, still bounded by RLS.
- Auth has two confirmed email users, one non-orphaned Admin link, one active Company platform account, and no enrolled MFA factors. Email/password signup and email confirmation are enabled. The allowlist is `https://aadhyantmanpower.in/**`. There is no custom SMTP, CAPTCHA, password complexity, breached-password check, session timebox, inactivity timeout, or single-session enforcement. Password minimum length is 6; TOTP capability is enabled but unenrolled; refresh-token rotation is enabled with a 10-second reuse interval; JWT lifetime is 3600 seconds.
- Storage has zero buckets and zero `storage` RLS policies. The global file limit is 50 MiB. No Candidate document bucket, MIME restriction, object policy, scanning, or quarantine capability exists in production.
- WAL-G capability is enabled, but PITR is disabled, the physical-backup inventory is empty, and no active backup/PITR add-on is present. No restorable production point is currently proven.
- Edge Function inventory is empty; `whatsapp-webhook` is not deployed.
- GitHub Pages is a legacy build from `main` `/`, custom domain `aadhyantmanpower.in`, HTTPS enforcement on. The built deployment is commit `29e0e553d06a0d3039a64053b443f75200feab88`, not release `91041094a58b43b3f85b940e7d7c9e8d9ae72222`. Publishing repository root currently exposes SQL migrations/tests and internal documentation.
- Database SSL enforcement is off. Network restrictions allow `0.0.0.0/0` and `::/0`. PgBouncer is transaction mode on `db.wsuctjhbqiedttfnwjvf.supabase.co:6543`; the direct database endpoint also uses that hostname. The regional Supavisor/pooler hostname is `aws-1-ap-northeast-1.pooler.supabase.com`.

### Legacy Admin compatibility matrix

| Browser path | Production ACL/RLS result | Classification |
|---|---|---|
| `interviews` history `SELECT` | authenticated `SELECT`; Admin RLS policy | Allowed for a linked Admin |
| `requirement_contractors` and nested `contractors` `SELECT` | authenticated `SELECT`; Admin RLS policies | Allowed for a linked Admin |
| `candidate_applications` with nested `candidates`/`employer_requirements` `SELECT` | authenticated `SELECT` on all relations; Admin RLS policies | Allowed for a linked Admin |
| Dynamic `SELECT`/count on requirements, Candidates, Companies, Contractors | authenticated `SELECT`; Admin RLS policies | Allowed for a linked Admin |
| Company/Contractor membership and nested `platform_users` `SELECT` | authenticated `SELECT`; Admin RLS policies | Allowed for a linked Admin |
| Post-RPC verification reads on Applications/Interviews | authenticated `SELECT`; Admin RLS policies | Allowed for a linked Admin |
| Direct `UPDATE` of `candidates(status, internal_notes)` | no authenticated `UPDATE` table grant | Denied |
| Direct `UPDATE` of `employer_requirements(status, internal_notes)` | no authenticated `UPDATE` table grant | Denied |
| Admin mutation RPCs present through migration 015 | authenticated execute plus server-side `private.is_admin()` | Allowed only for a linked Admin |
| Current release Admin workspaces requiring migrations 016–029 | required tables/RPCs absent | Denied/incompatible until controlled migration |

The direct-update compatibility path must be removed rather than widening production table grants. Read paths should also be moved behind safe Admin projections where practical; no remediation may rely on browser-held broad base-table privileges.

## Ordered P0 remediation plan

### P0-A — allowlisted deployment artifact

- **Defect/evidence:** legacy Pages publishes `main` repository root and exposes SQL/tests/docs; deployed commit is divergent from the approved release.
- **Required change:** create a deterministic `dist/` build from an explicit runtime allowlist and a reviewed GitHub Pages Actions workflow using the Pages artifact/deploy actions. Include only approved HTML, CSS, JavaScript, favicon/data required at runtime, role portals, legal routes, and a generated environment config. Exclude `.git*`, docs, tests, `supabase/`, scripts, package metadata, local environment files, logs, and source-only QA artifacts. Produce an artifact manifest and digest.
- **Prerequisites:** agree the release branch-to-production promotion rule and archive the current Pages artifact/commit metadata.
- **Rollback:** redeploy the archived prior artifact by digest; never reset or force-push a branch.
- **Risk:** high confidentiality/release-integrity risk if allowlist is incomplete or permissive.
- **Action/approval:** repository change first; changing Pages source/workflow and deploying require separate production deployment approval.

#### P0-A repository/local implementation — 2026-08-25

- **Repository status: PASS. Production switch: BLOCKED/MANUAL.** `scripts/build-production-artifact.js` starts from a verified repository-root `dist/` target, removes only that generated directory, and copies a file-by-file allowlist. `dist/` is ignored and is never committed as source.
- The allowlist covers all 43 current HTML routes; root runtime `CNAME`, `style.css`, `script.js`, and `supabase-client.js`; the public stylesheet, favicon, Jobs/legal/navigation scripts; the complete Admin runtime; and the Candidate, Company, and Contractor portal CSS/JavaScript. The production `config.js` is generated rather than copied.
- Unused `assets/js/reference-data.js` and `assets/data/README.md` are not shipped. Repository SQL, `supabase/`, tests, scripts, Markdown documentation, package metadata, source maps, environment/local Auth material, logs, temporary/QA files, and NONPROD-only material are prohibited by both positive inventory and negative assertions.
- Build command: `npm run build:production`. Verification command: `node scripts/build-production-artifact.js --verify`. Focused regression command: `npm run test:artifact`.
- The generated configuration is explicitly bound to origin `https://aadhyantmanpower.in`, project ref `wsuctjhbqiedttfnwjvf`, and its exact Supabase URL. Only the already-public browser publishable key is extracted from tracked source; the builder rejects secret/service-role-shaped configuration, NONPROD refs, loopback hosts, and synthetic identities. `supabase-client.js` refuses to initialize the client when a generated artifact is served from any other origin. P0-E still owns atomic release/config cache policy and broader local safety-guard changes.
- `artifact-manifest.json` records the production target, every payload path in deterministic order, byte length, per-file SHA-256, payload totals, and aggregate payload digest. It also enumerates both metadata files. `artifact-digest.sha256` is the SHA-256 of the canonical manifest. File/directory modes and timestamps are normalized, and two same-HEAD rebuilds must produce byte-identical trees and the same digest.
- Current local artifact: 66 payload files plus two integrity metadata files, 707,020 total bytes. Manifest SHA-256: `3d36b723e12d9594e9b7b7c31eb985da2191671ae6e6afd5299ef2c0e136ede2`; aggregate payload SHA-256: `e5a561bc85fa03d66543ee44c99ef1672c81f1c721f0b1745f8a5a0aab490d44`.
- Local HTTP verification serves every current runtime HTML route. Representative internal paths under `supabase/`, migrations/tests, repository tests/scripts, AGENTS, schema/setup, and readiness documentation return 404. The complete tree contains zero prohibited files.
- `.github/workflows/pages-production.yml` is manual-only. Its build job has only `contents: read`, builds/tests/verifies `dist/`, and uploads exactly `dist`. The deploy job exists for later reviewed use but requires an explicit Boolean input, the exact `web-platform-development` ref, the protected `github-pages` environment, and only `pages: write` plus `id-token: write`. Official Actions are pinned to reviewed immutable commit SHAs. The workflow performs no database, Edge, Meta, messaging, secret, or DNS action.
- Rollback requires retaining the prior deployed artifact/commit metadata and the new artifact manifest/digest. A later approved switch must be reversible by redeploying the prior captured artifact, never by resetting or force-pushing shared history.
- GitHub Pages remains configured to publish legacy `main` `/`; no workflow was dispatched, no Pages setting was switched, and no artifact was deployed during P0-A implementation.

### P0-B — backup/restore proof

- **Defect/evidence:** PITR off, zero backup entries, zero backup add-ons, no proven restore point or drill.
- **Required change:** select and enable an approved managed backup/PITR tier or create an approved encrypted logical/physical backup process; capture Auth/Storage/Edge/config baselines; restore into a separately named isolated project; verify catalog, row-count/digest invariants, Auth linkage, and private Storage metadata; document retention and RTO/RPO.
- **Prerequisites:** backup owner, encryption/key custody, retention/legal approval, isolated target and budget.
- **Rollback:** backup enablement/settings revert only after a successful retained baseline; the drill target is isolated and must not share production credentials or callbacks.
- **Risk:** critical—migrations must not start without a tested recovery path.
- **Action/approval:** dashboard/infrastructure action and isolated restore mutation; explicit production backup-setting and separate restore-drill approval required.

#### P0-B planning/read-only review — 2026-08-25

- **Planning status: PASS. Recovery proof: BLOCKED.** The authenticated read-only organization endpoint reports the Free plan. Production has zero selected add-ons; the backup endpoint still reports WAL-G enabled, PITR disabled, and no physical backup entries.
- Current project add-on inventory offers PITR retention of 7/14/28 days at $100/$200/$400 per month. Current Supabase documentation requires a paid plan and at least Small compute for PITR; the read-only inventory prices Small at approximately $15/month. Exact organization/project/temporary-clone charges require Dashboard checkout approval.
- The cost-minimized review concludes that PITR is not inherently required for migrations 016–029. Conditional Option A—Pro daily physical backup plus an exact, encrypted, write-frozen Supabase CLI logical bundle restored successfully into a fresh isolated project—can satisfy P0-B for the current small pre-launch dataset. It fails closed to Option B if the writer freeze, secure export, Auth/Vault/extension recovery, or exact restore proof cannot be established.
- Expected current-organization recurring baselines are approximately $35/month for Option A and $140/month for Option B before taxes/overages, based on two active projects and the current provider pricing/compute credit. Dashboard checkout remains authoritative.
- The full comparison, privacy boundary, Option A frozen-snapshot/eight-hour RTO posture, Option B five-minute/four-hour posture, human decisions, and fail-closed migration gate are in `PRODUCTION_BACKUP_RESTORE_PLAN.md`.
- No plan/add-on was purchased, no PITR or backup was enabled, no backup was triggered, and no restore/project mutation occurred during planning.

### P0-C — production DB catalog/drift proof

- **Defect/evidence:** object boundary is 015 but no migration ledger exists; historic body-level identity cannot be proven.
- **Required change:** preserve this read-only baseline; add a repository preflight that exports canonical table/column/constraint/index/trigger/policy/ACL/function-definition fingerprints and fails closed unless production matches the approved 015 baseline exactly. Record the missing suffix as 016–029 only after review. Never replay `schema.sql` or 007–015.
- **Prerequisites:** P0-B recovery proof before any subsequent write; independent review of catalog fingerprints and migration preflights.
- **Rollback:** read-only preflight has none; catalog mismatch stops the release.
- **Risk:** critical if drift is ignored; low for the read-only tooling itself.
- **Action/approval:** repository tooling/documentation; no mutation approval for export, but any corrective migration requires separate production mutation approval.

### P0-D — DB network/TLS hardening

- **Defect/evidence:** database SSL enforcement off; IPv4/IPv6 CIDRs fully open.
- **Required change:** inventory exact CI/operator egress and supported Supabase pooler/direct requirements; enforce TLS; restrict database CIDRs to approved operator/runner paths; validate transaction-pooler compatibility and emergency access. Do not depend on mutable IPv6 literals.
- **Prerequisites:** P0-B, P0-C, a tested access path, break-glass owner, and an exported current setting baseline.
- **Rollback:** restore the exact prior CIDRs/SSL setting only under incident authority; retain dashboard access for recovery.
- **Risk:** high availability risk from lockout; high security risk if left open.
- **Action/approval:** Supabase infrastructure mutation; explicit production network/SSL approval required.

### P0-E — environment/config binding

- **Defect/evidence:** tracked production config is the browser default; local safeguards denylist the project ref but omit the direct DB/API/pooler hosts; `config.js` is cached for 600 seconds.
- **Required change:** generate config during the allowlisted build from an explicit environment manifest; bind expected origin, project ref, API host, and release digest; make local/NONPROD servers refuse production identity unless separately authorized; deliver config atomically with `no-store` or equivalent revalidation. Add all production hosts to the safety guard.
- **Prerequisites:** P0-A artifact design and exact host inventory below.
- **Rollback:** redeploy the prior signed config/artifact pair; never mix HTML from one release with config from another.
- **Risk:** critical environment-crossing risk.
- **Action/approval:** repository plus hosting/CDN configuration; production delivery requires deployment approval.

### P0-F — web security headers/dependency pinning

- **Defect/evidence:** no CSP, HSTS, MIME, frame, referrer or permissions headers; Supabase JS uses an unpinned CDN major without SRI.
- **Required change:** select a hosting/CDN control plane that can set reviewed headers and differentiated caching; self-host or pin an exact reviewed Supabase JS build with integrity; create a CSP covering only proven origins; test portals and static pages under the policy.
- **Prerequisites:** P0-A and P0-E; documented external-host inventory.
- **Rollback:** versioned header/config policy and prior dependency artifact, with an emergency CSP rollback that does not remove HTTPS.
- **Risk:** high browser compromise/availability risk from a wrong CSP.
- **Action/approval:** repository and hosting/CDN action; production header/hosting changes require deployment/infrastructure approval.

### P0-G — Auth production hardening

- **Defect/evidence:** password minimum 6, no complexity/HIBP/CAPTCHA/session expiry/single-session policy/custom SMTP; zero MFA enrollments including the sole Admin.
- **Required change:** approve exact password/session/rate/CAPTCHA values; configure a verified custom SMTP sender and recovery delivery; keep redirects restricted to the production origin; require named Admin TOTP/MFA before Admin access; define recovery and bootstrap ownership; verify Candidate/Company/Contractor confirmation flows in an isolated controlled account set.
- **Prerequisites:** P0-A/E/F origin stability, Auth runbook, real named operator approval, and rollback export.
- **Rollback:** restore the reviewed prior Auth config; do not disable confirmation or MFA merely to bypass an incident.
- **Risk:** high account takeover and lockout/delivery risk.
- **Action/approval:** Supabase Auth dashboard mutation plus possible UI/runbook changes; explicit production Auth approval and manual Admin enrollment required.

### P0-H — sensitive-data/document gating

- **Defect/evidence:** production currently has no document bucket/policies/scanning; migration 025 would introduce Candidate documents; deterministic Aadhaar fingerprint and retention/legal posture remain unresolved.
- **Required change:** keep document/Aadhaar/bank/UAN/ESIC intake server-authoritatively disabled until approved encryption/keying, MIME/magic-byte validation, malware scanning/quarantine, retention/deletion, least-privilege signed access, audit, and legal rules exist. Review whether Aadhaar should be collected at all; replace deterministic unkeyed fingerprinting before enabling that field.
- **Prerequisites:** privacy/legal decision, threat model, Storage architecture and operational owner.
- **Rollback:** disable the feature gate and signed-access issuance; preserve audit evidence and do not delete live data without separate approval.
- **Risk:** critical privacy/regulatory risk.
- **Action/approval:** repository, database and Storage work; production enablement/mutation requires separate approval.

### P0-I — legacy Admin compatibility/removal

- **Defect/evidence:** two direct browser update paths are denied by current grants; other direct reads rely on broad authenticated base-table grants; current Admin product requires absent 016–029 RPCs.
- **Required change:** remove both direct table updates and replace them with reviewed Admin-only RPCs; prefer safe projections/RPCs for direct reads and counts; retain server-authoritative role checks and masked projections. Do not widen `authenticated` grants as a compatibility fix.
- **Prerequisites:** P0-C catalog fingerprints and reviewed RPC contracts coordinated with P0-J.
- **Rollback:** redeploy prior Admin artifact only against its proven catalog; database privilege rollback must not broaden access.
- **Risk:** high authorization/data-integrity risk.
- **Action/approval:** repository/runtime change plus migration where a missing RPC is required; production mutation approval required for DB changes and deployment approval for Admin.

### P0-J — controlled migrations 016–029

- **Defect/evidence:** release needs 016–029; production is 015-equivalent with no migration ledger.
- **Required change:** after exact preflight, apply only the contiguous suffix in reviewed checkpoints: 016–020, 021–022, 023–025 (with P0-H gates closed), 026–027, 028, then 029. Stop after every checkpoint for catalog/hash/invariant verification. Never execute NONPROD fixture checkpoints or create synthetic production users/data. Install a truthful migration ledger only through a separately reviewed strategy; do not fabricate historic rows.
- **Prerequisites:** P0-B/C/D/E/H/I complete, approved runner identity, maintenance window, zero-send posture, and exact stop conditions.
- **Rollback:** transactional rollback for a currently executing migration; forward-fix after commit; restore only from the proven P0-B recovery point for catastrophic failure.
- **Risk:** critical irreversible schema/data-path risk.
- **Action/approval:** production database mutation; explicit migration-by-migration production approval required.

### P0-K — zero-send production deployment

- **Defect/evidence:** production serves the obsolete root artifact, has no Edge webhook, and cannot run the approved release against the 015 catalog.
- **Required change:** deploy the signed allowlisted frontend/Admin artifact and reviewed production Edge receiver only after P0-A–J; keep Meta callback/subscriptions and all provider send workers disabled; run route, Auth-denial, catalog, log, and empty-state smoke checks without messages or real-user actions.
- **Prerequisites:** P0-A–J remote-closed, artifact/config digests, rollback artifacts, operator checklist, observability, and separate deployment approval.
- **Rollback:** redeploy the prior signed frontend/Admin artifact and prior Edge version or disable the new receiver route under the approved runbook; database remains forward-fixed/restored only per P0-B/J.
- **Risk:** high integration risk; WhatsApp/real-user launch remains a separate P1 boundary.
- **Action/approval:** production deployment/infrastructure action; explicit zero-send production deployment approval required.

### Production denylist host requirements

The guard must match project ref `wsuctjhbqiedttfnwjvf` and reject at least these exact production hosts/origins regardless of URL form, case, port or DNS resolution:

- `wsuctjhbqiedttfnwjvf.supabase.co` — Data API, Auth, Storage and Edge origin;
- `db.wsuctjhbqiedttfnwjvf.supabase.co` — direct PostgreSQL and project PgBouncer (`5432`/`6543` as applicable);
- `aws-1-ap-northeast-1.pooler.supabase.com` — regional Supavisor/pooler hostname;
- `aadhyantmanpower.in` and `www.aadhyantmanpower.in` — production frontend origins; and
- `aadhyantmanpowerstaffing-collab.github.io` — current GitHub Pages backing host.

The guard must continue to require the approved NONPROD ref/host identity rather than merely checking that the target is absent from this list. Do not pin transient IP addresses as identity.

## Exact next approval boundary

The cost-minimized next boundary is human selection of Option A, acceptance of the approximately $35/month current-organization baseline, approval of an enforceable all-writer maintenance freeze and encrypted server-side export handling, and naming of recovery owners. After that decision, request a narrowly bounded P0-B production-infrastructure mutation authorization to upgrade the organization to Pro without PITR and wait for a listed daily physical backup. The exact logical export/freeze and fresh-project restore drill remain separately authorized boundaries. If those Option A controls are rejected, select Option B and separately authorize Pro, production Small compute, and seven-day PITR instead. A future Pages switch still requires its own production deployment approval after the remaining P0 prerequisites are closed. Stop before purchasing/upgrading anything without that approval, creating/deleting a restore target, changing Pages, Auth, Storage, production network/TLS, applying migrations, deploying Edge/frontend/Admin, changing DNS/Meta, or sending any message.
