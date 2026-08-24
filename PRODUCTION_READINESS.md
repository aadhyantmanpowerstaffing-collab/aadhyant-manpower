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
2. Create an allowlisted deployment artifact/workflow. Do not publish the repository root or its internal SQL/tests/docs/scripts.
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
- [ ] **BLOCKED** Allowlisted build/deployment artifact and workflow do not exist.

### B. Production target identity

- [x] **PASS** Repository-intended Supabase ref/URL and apex domain are identified.
- [ ] **BLOCKED** Actual production project/database identity and catalog are not verified.
- [ ] **BLOCKED** Production Edge inventory/version/config/secrets posture is not verified.
- [ ] **MANUAL** Authorize a read-only production inventory before any write-capable plan.

### C. Backup

- [ ] **BLOCKED** Production backup/PITR plan, snapshot, and retention are unknown.
- [ ] **BLOCKED** Isolated restore drill has not been evidenced.
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

## Exact next approval boundary

The next safe boundary is **not deployment**. Obtain explicit approval for a read-only production inventory covering Supabase project/database catalog, Auth/Storage/Edge settings, backup capability, GitHub Pages deployment source/current commit, and DNS/TLS state, with no data mutation and no Meta/message action. Separately authorize remediation of the P0 repository/runtime blockers. Only after those items are reviewed, fixed, retested, and remote-closed should a zero-send production deployment proposal be submitted.
