# Admin documents and joining details — proposed Production upgrade

Status: prepared and locally validated; new Production mutation and frontend
release approval PENDING. Downloading this package is not approval.

## Evidence and scope

- User genuine v2 local Auth/Storage/shared-browser run: PASS,
  `resume-e2e-998030b5be06`.
- User Production read-only preflight: PASS,
  `document-preflight-864a86a72b5b`; no mutation dispatched.
- Repair SQL remains exactly the genuine v2 tested artifact:
  `810a67ea870655a6df6df8e1bc8cdda8a853e659c10c86cc85f40ca8bc1f8229`.
- API/RLS/Storage boundaries, Admin selection, cross-tenant denial, revocation,
  and invalidation on edits retain the recorded local evidence.
- The execution wrapper uses the successful review's pinned Production
  host/project/CA/image and password handling. It is separately validated with
  actual native SQL output and PowerShell parser plus mocked failure sequencing.
  This wrapper has not yet run against Production or Windows.

The upgrade extends the existing canonical sharing ledger. Candidate sharing
consent is not an additional action. Admin chooses each verified active document
and separately chooses bank details, UAN or ESIC for an eligible recipient.
Recipients receive no automatic access. Full values are available only through
authorized detail requests, not broad lists or logs. Existing account numbers
stored only as a hash cannot be recovered; those Candidates save them once.
Downloaded copies cannot be recalled by stopping subsequent access.

## Review without connecting

In this folder:

```powershell
.\START_APPROVED_UPGRADE.ps1 -SelfTest
.\START_APPROVED_UPGRADE.ps1 -CheckArtifactsOnly
```

Both modes are local. There is no default write dispatch. The script does not
install migrations, contact NONPROD, commit, push, deploy, or send messages.

## Execute only after explicit approval of this package

Keep Docker Desktop running, extract the package and open PowerShell in the
folder containing the runner. Use the existing pinned CA file. Run once:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Get-ChildItem -Recurse -File | Unblock-File
.\START_APPROVED_UPGRADE.ps1 -IApproveAdminDocumentsProductionUpgrade
```

Enter the database password only in its secure local prompt. The runner checks
all hashes, performs a fresh read-only preflight, then the single guarded
transaction, then a separate read-only postcheck. It stops after any failure
and never automatically retries or rolls back a committed change.

Expected successful markers:

```text
ADMIN_DOCUMENT_PREFLIGHT=PASS
ADMIN_DOCUMENT_REPAIR=COMMITTED
ADMIN_DOCUMENT_POSTCHECK=PASS
OVERALL_VERIFICATION=PASS
DATABASE_STATE=COMMITTED
FRONTEND_DEPLOYMENT=NOT_DISPATCHED
```

Sanitized evidence is saved under
`D:\Aadhyant-Review\Document-Joining-Production-Evidence`.

## Interrupted or unsuccessful execution

- `DATABASE_STATE=NOT_DISPATCHED`: no repair was sent by this run.
- `COMMIT_UNCONFIRMED`: a write was dispatched but completion was not proven.
- `COMMITTED`: the transaction's native output and committed marker passed;
  any later failure is verification/evidence handling, not an inferred rollback.

For either dispatched state, do not replay the repair. Run only:

```powershell
.\START_APPROVED_UPGRADE.ps1 -VerifyOnly
```

VerifyOnly dispatches the read-only postcheck, with no preflight/repair writes.
A FAIL requires inspecting the sanitized stage/SQLSTATE and affected catalog.
The separate operational-stop SQL in source revokes sharing while preserving
documents and joining data; it requires its own approval and is not auto-run.

## Frontend release after database verification

The separately reviewed source patch is against commit
`7bb195d5574f8e994fe5d363b542f87d27594011` and changes these six tracked files:

- `assets/js/resume-sharing.js`
- `candidate/portal/applications.html`
- `candidate/portal/candidate.js`
- `candidate/portal/documents.html`
- `tests/candidate-portal-ui.test.js`
- `tests/resume-sharing.test.js`

The accompanying source manifest lists the new scoped backend/rehearsal/release
artifacts. After approval, verify remote branch state, review the scoped commit,
run the existing production artifact build, push normally to
`web-platform-development`, then dispatch `pages-production.yml` on that ref
with `deploy_production=true`. No force push or silent merge of unrelated work.

Deploy the tested frontend after database PASS; stale consent/share mutation
buttons intentionally fail closed until the new frontend is loaded. Verify live
asset bytes, then use the approved TEST application to check Admin sharing,
recipient access and revocation. Local component PASS is not whole-site live E2E.
