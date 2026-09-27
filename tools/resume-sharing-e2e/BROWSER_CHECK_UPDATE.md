# Browser network classification correction — v3, 27 September 2026

The supplied v2 run (`resume-e2e-b9d85ff6bd3d`) passed genuine local Auth/Storage setup, the guarded SQL sequence, both recipient PDF downloads, tenant isolation, Candidate withdrawal and Admin revocation. Both downloaded SDK Blobs were 414-byte application/pdf files with `%PDF-` and SHA-256 `99f21978f69ca643db051efefb505d92a546d9f119bb232cd20a909bf5f60a35`, matching the original upload. The zero-byte CDP response capture did not represent an empty downloaded PDF.

The run then failed the final network assertion: expected 0 blocked requests, received 10. Every listed request was `chrome://resources`, GET, script or stylesheet, loaded for the built-in PDF viewer. The assertion reused the preceding stage name, producing an incorrect `ADMIN_REVOCATION=FAIL` label after that stage had already passed.

## Exact correction

- Allow only browser-internal `chrome://resources` GET script/stylesheet resources, with no credentials or port, as `BUILTIN_CHROME_RESOURCE`.
- Record them separately as `internalChromeResourceRequests`. They are not backend requests.
- Retain exact loopback backend/frontend and pinned SDK matching. Unknown external origins, unrelated extensions/Chrome hosts, Chrome fetch/XHR/navigation and non-GET requests remain blocked.
- Set `BACKEND_LOOPBACK_GUARD` before its final assertion. Nonzero blocked requests still fail the run.
- Preserve PDF size/hash/prefix/MIME, consent, authorization and revocation assertions.
- No website component, database SQL, grants, policies or Production state changed.

## Validation

Executed `node --test tools/resume-sharing-e2e/browser_download_evidence.test.mjs tests/resume-sharing.test.js`: 22 PASS, 0 FAIL (11 harness and 11 existing component tests). This includes the supplied ten-request classification, denial of an additional external request, and execution of the actual final gate snippet to prove correct failure labeling and no overall PASS after a failed gate. JavaScript syntax and whitespace checks passed.

The actual v2 user evidence is preserved in `evidence/user_run_v2_20260927.json`; it remains an overall FAIL. Earlier v1 evidence is preserved separately. Corrected v3 genuine execution remains pending because Docker/Chrome are unavailable on the development host. The new ZIP runs the same isolated genuine sequence and saves evidence before cleanup. It must finish `LOCAL_RESUME_BROWSER_REHEARSAL=PASS` to establish overall local completion.

This is a real-services browser component rehearsal; it does not prove every surrounding portal page or Production deployment.
