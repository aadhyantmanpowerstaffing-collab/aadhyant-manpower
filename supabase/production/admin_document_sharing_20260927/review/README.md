# Admin documents and joining details: Production read-only check

The user-supplied v2 isolated run `resume-e2e-998030b5be06` completed with
`LOCAL_DOCUMENT_BROWSER_REHEARSAL=PASS`. Do not repeat that local run.

This package checks whether the current Production catalog matches the baseline
required by the tested upgrade. It contains no repair or write-dispatch mode.
It does not read document contents or Candidate bank/UAN/ESIC values, change
permissions, or send messages. The SQL uses a read-only transaction and ROLLBACK.

## Run once

1. Keep Docker Desktop running. Extract this ZIP.
2. Open PowerShell in the extracted folder containing `START_READ_ONLY_CHECK.ps1`.
3. Run these three commands:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force
Get-ChildItem -Recurse -File | Unblock-File
.\START_READ_ONLY_CHECK.ps1
```

Enter the database password only at the secure local prompt. Do not paste it
into chat. The CA file and digest, Production project/host and local Docker
image digest are pinned to the already-used values. The image must already be
present locally; this script never pulls it or uses a remote Docker endpoint.

Success ends with:

```text
ADMIN_DOCUMENT_PREFLIGHT=PASS
PRODUCTION_MUTATION=NOT_DISPATCHED
ADMIN_DOCUMENT_EVIDENCE=D:\Aadhyant-Review\Document-Joining-Production-Evidence\document-preflight-...
```

Send the console result. On failure, send its sanitized failure category and
catalog labels; do not retry automatically. `review-result.json` is sanitized.
No write or deployment is authorized by a preflight PASS.

## Validation and limits

- The unchanged SQL already passed the genuine local v2 rehearsal.
- The actual native psql output is also exercised through this PowerShell parser
  using the local PostgreSQL engine; see `validation.json`.
- Parser rejects native failure, missing/extra rows, missing rollback, SQL FAIL,
  and arbitrary PASS substrings. This avoids the prior diagnostic-parser issue.
- `-SelfTest` and `-CheckArtifactsOnly` never connect to a database.
- The Windows PowerShell 5.1-compatible wrapper is based on the previously used
  pinned read-only transport. Authoring tests use PowerShell 7.4.6 on Linux;
  this new wrapper has not yet been executed on the user's Windows machine.
- A source mismatch blocks the release. The next action is review of that exact
  mismatch, not changing expected hashes to force PASS or replaying migrations.
- The new upgrade and frontend deployment remain separate approval steps.
