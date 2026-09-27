# Local Admin documents / joining details rehearsal

This is the new Admin-only sharing model: all document categories, plus separately shared bank/UAN/ESIC items. It does not ask the Candidate to authorize a share. The test uses synthetic accounts, genuine local Supabase Auth/Storage, current RPCs, and the real shared frontend component. It does not test every surrounding portal navigation page.

The v1 genuine run failed at the optional Storage delete-marker column. v2 fixes and regression-tests that exact error. The corrected genuine run is NOT yet PASS. The authoring workspace has no Docker executable/engine. Do not deploy this package based only on the SQL/unit results or the old consent-based v3 browser result.

On Windows, start Docker Desktop. Requirements: Node 20+, installed Chrome, Windows PowerShell and enough local disk. From the extracted package's top-level folder (or repository root), run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Get-ChildItem -Recurse -File | Unblock-File
.\tools\document-sharing-e2e\START_LOCAL_TEST.ps1 -EvidenceRoot 'D:\Aadhyant-Review\Document-Joining-Sharing-Evidence'
```

Ports default to 62421–62431. Use `-BasePort` if occupied. The runner checks ports and local Docker socket, uses a new random project/container, disables historical migration/seed replay, checks artifact hashes and each native exit/marker, and keeps the stack alive through all checks. Existing Docker projects are untouched. It requires no Production database password and has no remote mode.

Expected final marker: `LOCAL_DOCUMENT_BROWSER_REHEARSAL=PASS`.

Tests cover: genuine login; no Candidate sharing-consent control; unshared access denied; Admin explicit per-item shares; genuine PDF and PNG upload/register/verify/download with matching bytes; separate bank/UAN/ESIC view; other Company denied; Contractor-specific share; Admin revoke; edited joining details require new Admin sharing; zero non-local backend requests. Only the exact pinned SDK script is allowed remotely. Browser-internal PDF resources are not backend requests.

Sanitized reports, fixture source and configuration are saved before scoped cleanup. The generated password/token lives only in process memory and is restored/cleared afterward. `-KeepStack` is available only for inspecting this newly created local fixture.

Rebuild the materialized harness from repo root with `python tools/document-sharing-e2e/build_rehearsal.py` after changing the upgrade package. This copies reviewed source definitions, not a Production dump or credentials.
