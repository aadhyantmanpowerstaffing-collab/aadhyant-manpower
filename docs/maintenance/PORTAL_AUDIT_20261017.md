# Aadhyant portal review — 17 October 2026

## Scope and evidence

Reviewed the existing production portal and repository, not a replacement implementation. The original complete regression passed 578/578. After adding the correction and its runtime regression coverage to the standard test command, the complete regression passed 581/581 with zero failures/skips. Checked all 46 production HTML routes for referenced local files/links: no missing target. Production allowlisted artifact build and verification passed with unchanged frontend payload aggregate `f8fbaa7a82f30f3973dc493659893ff54deb7ba2eb6354c9cc5fafbc72deab6d`.

Read-only live UI checks: homepage correctly displays no public openings after the authorized dummy cleanup; Candidate login and account-creation pages render; Post Job links route Company and Contractor visitors to their separate login boundaries. No production signup, application, vacancy, message or test record was created. Existing authenticated-role behavior is covered by local regression; this review does not claim a real employer/candidate end-to-end walkthrough or a complete mobile visual audit.

Production security catalog: no public base table with RLS disabled. Most advisor notices describe intentional private/RPC-only tables and role-scoped SECURITY DEFINER endpoints, not independently demonstrated vulnerabilities. Application definer functions use an empty search_path. The platform-supplied `rls_auto_enable` event-trigger function uses `pg_catalog` and is not an ordinary RPC; do not remove its RLS protection based solely on a generic lint.

## Confirmed findings

1. **Public interest approval gate missing.** Live `public.register_candidate_requirement_interest(text,jsonb)` checks open/public/unfilled, but does not call the canonical review gate. A direct call can register interest against an unapproved open/public requirement even though normal public job listing excludes it. No currently affected production job was tested or fabricated. Isolated PGlite reproduction executes the retained function body and demonstrates the gap. Corrective migration `20261017041450_public_interest_review_guard.sql` adds `private.vacancy_is_application_eligible(r.id)` to the existing locked requirement lookup. API signature, grants, identity reuse and duplicate behavior stay unchanged. Three runtime checks prove reproduction; rejection of pending/draft/correction/rejected/closed/null, private/filled and contractor-ambiguous requirements with zero writes; approved registration and deduplication. Correction is prepared locally, **not installed in production**; separate production approval is required under AGENTS.md.

2. **Staging credential stored as a plain Actions variable.** GitHub staging environment contains a variable named `CLOUDFLARE_API_TOKEN`. No value is retained in this document. Current staging workflow already reads `secrets.CLOUDFLARE_API_TOKEN`, so the plain variable is unnecessary for that workflow and exposes a credential to people allowed to view variables. Treat the existing token as exposed: an authorized human should rotate/revoke it, store the replacement only as an encrypted staging secret, and remove the plain variable. Secret replacement is a manual credential boundary. No token was copied into code, a file, a test, another service, or this report; no Cloudflare configuration changed during this review.

3. **Leaked-password protection disabled.** Supabase Auth advisor reports this setting off. Verify plan support and enable it through supported Auth settings when available; no purchase/upgrade is authorized by this review. Remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection .

4. **Performance advisories.** 41 unindexed foreign-key notices, 35 unused-index notices, and 5 multiple-permissive-policy notices. These are not proof of a current functional failure or an access leak. Do not drop indexes or alter policies indiscriminately. Prioritize actual query plans and expected access before a separate measured optimization. Remediation: https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys .

## Remaining operational boundary

Registered-alert scheduler connection is verified with a real zero-send worker result and heartbeat. Database automatic alerts stay OFF. Fresh Meta sync on 17 October still reports compatible v4 PENDING; do not substitute cached approval or enable sending early. The separate legacy `scheduler_ready=false` flag governs future scheduled selected-contact campaigns; it is not the registered worker heartbeat and must not be flipped just because the registered worker succeeds. No generic/manual campaign scheduler was installed by this review.

After approval, use the authenticated Admin activation control and one actual vacancy with explicitly intended real recipients. Old dummy data remains cleared. A live send is not part of this audit.
