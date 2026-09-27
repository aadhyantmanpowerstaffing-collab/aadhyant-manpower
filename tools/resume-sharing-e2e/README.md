# Genuine local resume-sharing rehearsal

This runner creates one disposable official Supabase CLI 2.111.0 stack on unique loopback ports (default 61421–61431). It never links a remote Supabase project and has no Production endpoint, password or service credential. Docker must use a local unix/npipe endpoint. Existing containers and the repository config are not changed.

Prerequisites: Docker Desktop Linux engine running, Node.js 20+, installed Google Chrome, and free local ports. Internet is needed for pinned npm packages, official Docker images, and the same pinned browser SDK CDN used by the site. It does not use an authenticated Production browser session.

From the standalone extracted root:

```powershell
.\START_LOCAL_TEST.ps1 -EvidenceRoot 'D:\Aadhyant-Review\Resume-Sharing-Evidence'
```

From the repository:

```powershell
.\tools\resume-sharing-e2e\START_LOCAL_TEST.ps1 -EvidenceRoot 'D:\Aadhyant-Review\Resume-Sharing-Evidence'
```

The runner checks hashes, starts a fresh genuine Auth/Storage stack, loads source-derived canonical tables/helpers and the existing document contract, creates six synthetic accounts through Auth signup, and maps those IDs into application tables. It executes the exact proposed preflight → forward transaction → postcheck, then uploads a synthetic PDF and uses the source registration/Admin-review RPCs.

Playwright opens a local rehearsal page containing the actual new `assets/js/resume-sharing.js` component. Each actor signs in through genuine password Auth in a separate browser context. The checks cover explicit unchecked Candidate consent, no access from consent alone, Admin release, own-company actual PDF Storage response, cross-company denial, Candidate withdrawal, separate Contractor consent/release, and Admin revocation. Backend requests must stay on loopback; only the exact pinned SDK CDN is allowed externally. No RPC or session is fabricated.

**Coverage boundary:** this checks the new browser component with real services. The surrounding production Candidate/Admin/Company/Contractor portal navigation is covered by source tests here, not full portal browser E2E. The earlier completed Candidate login/upload/Apply and Admin document checks are preserved separately.

A successful run ends `LOCAL_RESUME_BROWSER_REHEARSAL=PASS`. It writes stage results, exact SQL markers, synthetic IDs/fixture and sanitized browser evidence before removing only its new stack. It does not persist passwords, JWTs or Auth keys. `-KeepStack` is optional for explicit local debugging. On any failure later stages stop; no Production command is dispatched. Share `rehearsal-result.json` and `resume-browser-result.json` if created; do not send passwords or tokens.

The supplied v2 genuine Windows run passed the browser sharing/download/revocation checks but failed its final network classification assertion. The v3 harness correction passes focused tests on the development machine; a complete genuine v3 run is pending. Docker/Chrome are unavailable on the development machine.

`build_local_fixture.py` regenerates the source-derived bootstrap in the full repository. It never rewrites managed Auth/Storage definitions, uses no constant-return helpers and does not replay migration history. The materialized SQL is included for execution, so Python is not needed by the Windows launcher.

## 2026-09-27 v3 update

See `BROWSER_CHECK_UPDATE.md`. The v2 run downloaded correct PDFs for Company and Contractor and passed both withdrawal/revocation stages. Ten internal Chrome PDF-viewer script/style requests were mistakenly counted as nonlocal backend traffic. The test now classifies these narrowly, preserves external-request rejection, and reports the final network failure under its own stage. Functional SQL and website files remain unchanged. Failure details print directly in PowerShell and are preserved in JSON evidence.
