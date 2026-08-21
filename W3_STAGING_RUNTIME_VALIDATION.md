# W3 Staging Runtime Validation

Status: database/security runtime validation, live localhost browser validation, and synthetic-fixture cleanup complete on dedicated NONPROD staging. W3 technical audit: PASS.

## Scope and safety

Migration 018 was applied once to the approved dedicated NONPROD staging database. Production was not contacted, no deployment occurred, and no outbound integration was used. Every checkpoint fixture was synthetic and transaction-scoped. Post-test verification found no persistent Auth, staff, candidate, requirement, application, interview, joining, history, or audit fixture residue.

- Migration 018: PASS
- Migration 018 SHA-256: `87125417de6b7201aea58b360741d3daecb3b4e766c9cbe96f292d8f40009c69`
- Checkpoint 018: PASS with final `ROLLBACK`
- Rollback cleanup and zero-residue verification: PASS
- Required regressions 015, 016, and 017: PASS
- Legacy checkpoints 011, 012, 013, and 014: PASS

## Runtime role matrix

| Actor | Verified W3 behavior |
|---|---|
| `bootstrap_admin` | Full approved recruitment operations |
| `super_admin` | Full approved recruitment operations |
| `admin` | Full approved recruitment operations |
| `recruiter` | Candidate CRM, requirements, applications, and interviews; joining read-only; joining mutation denied |
| `operations` | Selected/application context and joining management; candidate mutation outside the approved scope denied |
| `viewer` | Projected read-only access; mutation denied; contact PII suppressed |
| inactive staff | Internal recruitment access denied |
| non-member | Internal recruitment access denied |
| company user | Internal recruitment access denied |
| contractor user | Internal recruitment access denied |
| anonymous | Internal recruitment access denied |

W2 Staff Management authority remains independent and unchanged.

## Functional results

Runtime validation passed for the Candidate CRM core workflow and recruiter candidate update, operations selected-context restrictions, the internal requirement projection, candidate-to-requirement application creation and duplicate prevention, validated application transitions and automatic stage history, recruiter joining-stage bypass denial, interview scheduling/rescheduling/result/finalization, joining creation and application synchronization, joined-state regression protection, and viewer PII suppression.

Migration 015 tenant isolation remained authoritative. Migration 016 foundation objects and migration 017 staff-security boundaries passed regression. Public jobs, candidate requirement-interest registration, admin application management, and legacy interview scheduling/rescheduling/results passed their rollback-scoped checkpoints.

## Live browser validation

Manual validation used a loopback-only localhost copy with a visible `NONPROD / STAGING` banner and synthetic staging data. Bootstrap/admin completed the candidate-to-requirement workflow through application transitions, interview scheduling/rescheduling and selected outcome, joining pending, and joined. Recruiter retained Candidate CRM, matching, application, and interview operations while Joining / Placement remained read-only and Staff Management remained unavailable. Operations received selected/application context and joining management while candidate, generic application-transition, and interview mutations remained unavailable. Viewer received projected read-only views with contact PII and internal notes suppressed.

The live workflow verified constrained candidate editing, structured candidate/application detail dialogs, valid-stage-only application transitions, server-controlled interview and joining synchronization, read-only finalized states, W3/legacy section isolation, and safe missing-value rendering. No browser operation used direct operational-table access or user-entered UUIDs.

## Fixture cleanup

The ignored exact-ID W3 browser fixture manifest was used for dependency-ordered cleanup. Application-side rows, audit rows, tenant/staff fixtures, and nine non-bootstrap Auth fixtures were removed first. Bootstrap recovery remained intact until that cleanup and the bootstrap-only intermediate verification passed; the synthetic bootstrap Auth user was removed last and its `admin_users` row cascaded as designed.

Final read-only verification found zero manifest residue across Auth users/dependencies, staff, tenant memberships/entities, candidates/preferences, requirements/assignments, applications/stage history, interviews, joinings, and audit logs. No orphan references were found, no non-W3 staging rows were removed, no real data was affected, and production was not contacted.

## Resolved checkpoint defects

Four test-only defects were corrected during validation:

- checkpoint 018 compared the catalog search path using a formatting-sensitive exact string;
- the operations block tried to obtain an application ID through an intentionally RLS-hidden table read instead of the approved projection RPC;
- the viewer block filtered for `selected` after the application had advanced to `joined`;
- checkpoint 011 still expected tenant base-read policies intentionally removed by migration 015.

No production migration defect was established by these failures. Each corrected checkpoint subsequently passed. Migration 018 was not reapplied.

## Coverage limitations

Backend runtime validation is complete, but it was not exhaustive across every candidate filter combination, every invalid requirement state, every invalid or arbitrary application transition, every interview result/status combination, operations-detail PII, approved-role contact PII, or every joining date/left-state variant.

Representative candidate search/filter behavior, role-dependent PII, application and interview validation, and joining date/status validation passed live browser validation. Exhaustively enumerating every equivalent combination remains a non-blocking coverage limitation.

W3 is technically complete and ready for an evidence-only closure commit, review, and separately authorized push.
