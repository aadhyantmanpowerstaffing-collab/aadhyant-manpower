# Sharing layout review — 2026-09-27

Status: preview accepted; scoped commit, push and Production deployment explicitly approved by the user on 2026-09-27. Deployment execution is recorded separately.

The reported problem was a long mixed list of uploaded documents, bank fields, UAN and ESIC, with the recipient repeated for every item. The shared component now groups items into Documents, Bank details, UAN (PF), and ESIC. Admin sees the recipient once above its groups. Only one group is open at a time. Opening a group performs no detail RPC; View details still requires a fresh authorized read.

Financial values use a responsive definition list. Closing or switching groups clears the values and invalidates pending reads. The existing 60-second hiding rule, exact recipient/item/revision parameters, double-submit protection, current authorization RPCs, and authenticated document downloads are preserved. Admin stays on the selected group after a share action.

The three portal explanations that incorrectly referenced Candidate consent or denied all recipient access now describe the already-deployed Admin-controlled sharing contract. No database, role, Storage policy, auth, config, or grant changes are included.

## Validation

- Focused shared-component and portable-preview tests: 20 PASS.
- Latest full frontend run: 322 PASS; 2 artifact-inventory checks encountered transient workspace-sync temporary files. The affected artifact suite was then rerun unchanged: 6 PASS, 0 FAIL. All 324 test cases have passing evidence across those runs.
- Production artifact tests: 6 PASS, 0 FAIL on the focused rerun.
- Production artifact build: PASS; new scoped CSS included, preview fixtures excluded.
- JavaScript syntax and git diff whitespace check: PASS.
- Browser visual / responsive execution: NOT COMPLETED. The cloud browser rejects local file URLs; its runtime also disallowed a local preview listener. No alternate browser or policy workaround was used.
- Genuine Auth/Storage runtime evidence from the prior release is unchanged. It is not claimed as browser proof for this new layout.

The current document-sharing rehearsal script and its generator open the appropriate accordion before exercising each control. Its source manifest was updated only for the changed source and harness files plus the new stylesheet. The revised real-backend rehearsal was not executed here. Historical ZIPs and Production repair SQL were not modified or replayed.

## Reproducible preview

Open `tests/fixtures/sharing-layout-preview/index.html` in a local browser. It uses the actual proposed JS and CSS with labeled synthetic response data. It does not load Supabase, credentials, accounts or remote endpoints. Select Company, Admin or Contractor; the two frames show 780px and 390px widths.

Check: category separation; opening another category closes the previous one; View details fetches only on demand; closing/reopening hides values; Admin share/stop keeps the selected category; no horizontal overflow. This synthetic preview tests presentation only and is not a new database/security proof.

A portable copy named `Document_Sharing_Layout_Preview.html` was also prepared for user review, with networking blocked by CSP. Browser rendering of this file remains unverified in this environment.

Rebuild the portable file with `node scripts/build-sharing-layout-preview.js <output.html>`. The initial portable file displayed blank frames because CSP insertion modified already-serialized nested HTML, producing invalid JavaScript. The generator now inserts CSP before serialization and escapes embedded HTML. The regression executes the generated outer script and each of the three embedded view scripts, checks both frame documents, and confirms the real component renders all four categories with no initial financial-detail reads. This is script/DOM validation, not a browser visual result.

## Release boundary

The user downloaded the corrected portable preview, accepted the layout, and explicitly approved commit, push and Production deployment. Commit only the reviewed UI/test/preview files, push normally to web-platform-development, and run pages-production.yml with deploy_production=true. Do not replay any database repair. Verify the resulting artifact/asset identities and check the released layout. The automated browser limitations above remain recorded; user acceptance does not imply whole-site E2E coverage.
