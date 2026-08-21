# W5 Staging Runtime Validation Evidence

Status: W5 backend and security runtime validation is COMPLETE on dedicated NONPROD staging. Live Contractor Portal browser validation and browser-fixture cleanup remain PENDING; W5 is not formally closed.

## Scope and validation results

Validation used only the approved dedicated NONPROD staging environment over TLS. Production was not contacted, no deployment or outbound integration ran, and W6 was not started. This evidence intentionally omits project identifiers, database hosts and URLs, credentials, keys, tokens, and synthetic fixture identifiers.

- Migration 021, the Contractor Portal foundation, applied successfully.
- Corrective migration 022 applied successfully and preserved the reviewed W5 security contract.
- Focused checkpoint 023, full checkpoint 022, and focused runtime coverage checkpoint 024: PASS.
- W4, W3, W2, and migration-015 regression checkpoints: PASS.
- Legacy/public checkpoints for public jobs, candidate interest, application management, and interview management: PASS.
- Frontend regressions: 92/92 PASS.
- Every checkpoint was transaction-scoped and rollback-scoped; final synthetic residue was zero.

## Runtime role and authorization matrix

- **Contractor Owner / Manager:** Contractor Portal access, own context and vacancies, vacancy creation/management, allowlisted profile administration, and safe own-vacancy application/interview/joining progress.
- **Contractor Recruiter:** own portal and approved vacancy management; protected profile administration denied.
- **Coordinator:** approved projections read-only; vacancy mutations denied.
- **Inactive contractor member:** operational portal and profile denied.
- **Contractor B:** own tenant only; Contractor A profile, vacancies, applications, interviews, joinings, and mutations denied.
- **Company-only user, internal W3 staff without contractor membership, non-member, and anonymous:** Contractor Portal denied.

Tenant identity is derived from `auth.uid()` and requires exactly one active contractor membership. Contractor IDs and Company IDs are not accepted as trusted browser ownership. Ambiguous active membership fails closed by the reviewed helper contract. Contractor vacancy client/worksite text does not infer Company Portal ownership or membership.

## Vacancy lifecycle and approval authority

Runtime tests passed Draft -> Submitted -> Under Review -> Approved, plus Correction Required, correction edit, resubmission, Rejected, Cancelled, and Closed. Invalid and terminal regressions, contractor self-review/self-approval, and direct publication were denied. Pre-approval records remain private and unavailable for candidate matching.

Internal review authority passed for `bootstrap_admin`, `super_admin`, and `admin`. Internal `recruiter` and `operations`, contractor identities, company identities, and anonymous callers cannot perform review or approval mutations.

## Canonical W3 bridge

Runtime validation proved that contractor submission creates exactly one canonical `employer_requirements` record and exactly one contractor-origin `requirement_contractors` link. Aadhyant approval updates that same requirement to Open/Assigned and recruitment-ready; W3 consumes the same record without cloning or parallel vacancy storage. Contractor linkage, reviewer attribution, and review timestamp remained intact.

## Dashboard and progress evidence

Contractor-scoped Draft, Under Review, Approved/Active, Needs Action, Total Openings, Applications, Interviews, Selected, Joining Pending, and Joined metrics passed. A zero-data contractor returned numeric zeros. Multi-row coverage proved that joins did not multiply totals: 12 openings remained 12, four applications remained four, three interviews remained three, and selected/joining-pending/joined counts remained distinct.

## Privacy and W3 mutation boundary

Contractor projections expose only own approved-vacancy candidate display name, qualification, specialization, experience summary, location, application stage, and safe interview/joining progress. They do not expose Candidate Master, phone, WhatsApp, Auth linkage, candidate UUID, internal candidate notes, recruiter/staff notes, unrelated history, or other contractor/company candidate data.

Interview and joining projections are read-only. Contractor identities were denied scheduling, rescheduling, finalization/outcome, joining creation/update, and internal W3 mutation RPCs at the authorization boundary.

## Profile security

Owner/Manager allowlisted profile update and fresh-read persistence passed. Protected legal/agency identity, registration, verification, primary email, account/platform state, and system ownership fields remained unchanged. Recruiter profile administration and inactive-member operational profile access were denied.

## Resolved defect history

Production migration/runtime defects:

- Migration 021 initially used a PostgreSQL-invalid composite-record multi-target `INTO` pattern. Because the migration transaction rolled back completely, migration 021 was corrected before its successful fresh apply.
- The installed migration-021 `manage_contractor_portal_vacancy` function contained an ambiguous `id` reference. Corrective migration 022 qualified the identifier without changing tenancy, lifecycle, privacy, locking, or grants.

Checkpoint-only defects:

- Focused checkpoint 023 attempted a canonical assertion through contractor-visible base-table access that migration-015 RLS correctly hid. The test separated privileged canonical inspection from browser-role denial assertions.
- Full checkpoint 022 attempted to rediscover an RPC-created fixture ID through an RLS-hidden base table. It now captures and reuses the RPC-returned ID transaction-locally.
- Focused checkpoint 024 closed the remaining elevated-role, lifecycle, isolation, profile, anonymous-denial, and aggregate combinations.

## Remaining boundary

Backend/security runtime validation is complete, but live localhost browser validation is pending. Browser fixtures, manual browser execution, cleanup, and final zero-residue evidence require separate authorization. No statement in this record authorizes production contact, deployment, or W6 work.
