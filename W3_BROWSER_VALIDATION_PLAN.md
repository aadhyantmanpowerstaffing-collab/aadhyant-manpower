# W3 Browser Validation Plan

Status: planned only. No browser fixtures have been created and no live browser test has started.

## Safety gates

Before fixture creation or testing, require the static staging guard and read-only identity verifier to pass for the dedicated NONPROD project. Use a loopback-only localhost staging copy with a visible `NONPROD / STAGING` banner and browser-safe publishable configuration only. Never include service-role credentials or server secrets.

Maintain an ignored exact fixture manifest. Use synthetic Auth identities and synthetic candidate, requirement, application, interview, joining, company, and contractor records only. Do not use real phone numbers, deliverable email addresses, or real business data. Preserve a synthetic bootstrap recovery identity until every other cleanup step succeeds.

## Access matrix

| Context | Manual expectation |
|---|---|
| Unauthenticated | Direct W3 routes redirect to login; recruitment modules are inaccessible |
| `bootstrap_admin` | Dashboard, Candidates, Requirements, Applications, Interviews, Joining / Placement, and permitted Staff Management are visible and usable |
| `super_admin` | All W3 modules visible and usable |
| `admin` | All approved recruitment modules visible and usable |
| `recruiter` | Candidates, Requirements, Applications, and Interviews usable; Joining read-only; joining mutation unavailable; Staff Management remains W2-controlled |
| `operations` | Selected/application context and Joining / Placement management available; recruiter-only candidate mutation unavailable |
| `viewer` | Approved projected modules read-only; mutation controls absent or semantically disabled; contact PII suppressed |
| inactive staff | Login may authenticate, but internal W3 access is denied |
| non-member | Internal W3 access denied |
| company user | Internal W3 modules and routes denied |
| contractor user | Internal W3 modules and routes denied |
| Anonymous RPC caller | Internal W3 RPC execution denied |

## Manual workflow matrix

### Candidates

- Load the bounded candidate list and verify phone, WhatsApp, Auth linkage, and unrestricted notes are absent.
- Exercise representative keyword, location, state/district, qualification, candidate-type, and status filters.
- Open candidate detail as recruiter/admin and confirm approved contact fields; repeat as operations/viewer and confirm contact fields are null.
- Perform one permitted recruiter update and verify it through a fresh projected read.
- Confirm operations and viewer mutation controls are unavailable and direct mutation RPC calls are denied.

### Requirements

- Load internal requirement list/detail and verify company, role, location, openings, status, salary, shift, and facilities where stored.
- Confirm employer contact fields, internal/admin notes, and tenant ownership internals are absent.
- Confirm migration-015 company/contractor portal projections remain separate from the internal W3 view.

### Applications

- Match a synthetic active candidate to a synthetic open requirement and verify the projected application ID and initial stage.
- Repeat the match and verify duplicate handling without a duplicate row.
- Exercise a representative permitted transition and verify history display and actor attribution.
- Exercise representative invalid, arbitrary, terminal, and recruiter joining-bypass transitions and verify denial.

### Interviews

- Schedule and reschedule an interview and verify round/history presentation.
- Record a valid completed outcome and verify application synchronization and final-state UI.
- Exercise representative absent/cancelled-with-result, completed-without-result, and finalized-update denials.

### Joining / Placement

- As operations, create joining context for a selected application and exercise expected date, joined actual date, and joined-to-left behavior.
- Verify application-stage synchronization and terminal regression denial.
- As recruiter and viewer, confirm joining is readable but mutation controls are unavailable and mutation RPC calls are denied.

### Dashboard, routes, and browser security

- Verify W3 dashboard counts load through the dashboard RPC and reflect the synthetic workflow.
- Test direct W3 URLs in every unauthorized context.
- From DevTools on localhost staging, use only the existing browser Supabase client to verify unauthorized W3 mutation RPC denial and direct operational-table mutation denial. Do not print sessions, tokens, or configuration values.

## Fixture and cleanup strategy

Prepare synthetic identities for bootstrap, super-admin, admin, recruiter, operations, viewer, inactive staff, non-member, company user, and contractor user. Prepare one synthetic company and contractor plus the minimum candidate/requirement/application/interview/joining graph required by the workflow tests.

Before creation, record exact expected IDs, links, roles, statuses, and baseline counts in the ignored manifest. After validation, remove manifest-bound application/business rows in foreign-key-safe order, remove fixture audit rows by exact actor/entity IDs, delete non-bootstrap Auth users, verify only bootstrap recovery remains, then remove bootstrap last. Finish with zero-residue queries across Auth dependencies, staff, recruitment, tenant, history, and audit tables. Stop the localhost server and remove the temporary browser copy and ignored fixture manifest only after evidence is recorded.

Fixture creation, browser execution, cleanup, and push each require separate authorization.
