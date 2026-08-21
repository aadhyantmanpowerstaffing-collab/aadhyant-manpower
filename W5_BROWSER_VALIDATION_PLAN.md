# W5 Contractor Portal Browser Validation Plan

Status: manual localhost Contractor Portal validation and manifest-bound fixture cleanup are COMPLETE on dedicated NONPROD staging. Validated implementation HEAD: `ce5200a4bfc9d9f20824d3fb250ef3802628a440`. W5 is ready for formal closure after evidence review, authorized push, and remote HEAD verification.

## Safety and recovery boundary

Use a fresh temporary copy outside the repository, bound only to `127.0.0.1`, configured only with the staging URL and publishable browser key, and marked visibly `NONPROD / STAGING`. Do not use tunnels, LAN binding, database credentials, service/secret keys, management tokens, real people, real companies, or deliverable contact details. Do not send email, SMS, WhatsApp, or invitations.

Preserve a verified internal recovery/bootstrap path throughout fixture creation and the internal approval bridge. Never remove recovery before bridge evidence is complete, every non-recovery fixture is removed, and an alternate recovery posture is verified where required. A synthetic recovery identity is removed last.

## Browser identity matrix

| Identity | Expected browser behavior |
| --- | --- |
| Anonymous | Contractor Portal denied; no protected-content flash |
| Contractor Owner / Manager | Full own-tenant dashboard, vacancy lifecycle, safe progress, allowlisted profile update, and logout |
| Contractor Recruiter | Own portal and permitted vacancy management; profile read-only |
| Contractor Coordinator | Approved read-only portal; no create/edit/submit/cancel controls |
| Inactive contractor member | Authentication may succeed, but operational portal is denied |
| Contractor B Owner | Contractor B only; all Contractor A data and object URLs denied |
| Company-only user | Contractor Portal denied |
| Internal W3 staff without contractor membership | Contractor tenant portal denied; internal review workspace remains available according to staff role |
| Non-member | Contractor Portal denied |
| Recovery/bootstrap | Internal recovery and approved review bridge only; never a contractor tenant identity |

## Primary Contractor business flow

Contractor login -> Dashboard -> Submit Vacancy -> Save Draft -> My Vacancies -> View/Edit Draft -> Submit for Review -> Aadhyant internal login -> inspect the same vacancy -> Request Correction or Approve -> Contractor sees status and safe feedback -> correction edit/resubmit where exercised -> Aadhyant approves -> the same canonical requirement becomes W3 recruitment-ready -> W3 candidate matching/progress -> Contractor sees safe Applications -> Interviews -> Joining Status -> allowlisted Contractor Profile update -> logout.

Before approval, verify that the vacancy remains private and is not exposed to candidates or public jobs. Approval must update the same canonical `employer_requirements` row; it must not create a duplicate or parallel vacancy.

## Page and role checks

### Anonymous

- Open the Contractor login and every supported direct operational URL.
- Confirm redirect/containment at login, unusable protected navigation, no tenant name, counts, vacancies, candidates, interviews, joining, or profile data, and no protected-content flash.

### Owner / Manager

- Verify own contractor identity and dashboard metrics.
- Create a structured vacancy as Draft, view it in My Vacancies, edit it, and submit it.
- Verify clear Submitted/Under Review/Correction Required/Approved states and safe correction feedback.
- After internal approval, verify safe applications, interview progress, and joining progress.
- Update one allowlisted profile field, require a successful persisted fresh read, hard refresh, and verify protected fields remain unchanged.
- Verify logout, refresh, back navigation, expired/cleared session, and direct-route behavior.

### Recruiter and Coordinator

- Recruiter: own dashboard/vacancies and permitted vacancy controls; no profile-save control or internal review authority.
- Coordinator: approved read-only pages with no create, edit, submit, resubmit, cancel, close, or profile-save actions.

### Denied and isolation identities

- Inactive member, Company-only user, internal staff without contractor membership, and non-member: Contractor Portal denied.
- Contractor B: own profile/vacancies only; Contractor A vacancy IDs/direct URLs, applications, interviews, joining, and profile context unavailable.

## Contractor and Company separation

- Contractor authentication alone must not open the Company Portal.
- Company membership alone must not open the Contractor Portal.
- Client/worksite display text must not infer or grant registered Company ownership.
- Matching a registered Company name must not expose Company data or create Company membership.
- Contractor and Company navigation, session resolution, tenant RPCs, and data projections remain separate.

## Internal review and W3 canonical bridge

Use authorized internal bootstrap/super-admin/admin access to locate the contractor-origin submission, contractor identity, review state, and safe feedback. Exercise request-correction and/or approval as planned. Confirm the same requirement code/record becomes Open and recruitment-ready in W3, contractor linkage persists, and no duplicate requirement appears. Recruiter/Operations approval controls must be absent or denied according to the runtime contract.

## Privacy checks

Inspect rendered content, accessible names, direct routes, page-consumed network responses, error messages, exports if any, and mobile layouts. Contractor must never receive Candidate Master, phone, WhatsApp, Auth ID, candidate UUID, internal candidate notes, recruiter/staff notes, unrelated application history, other-contractor data, unrelated Company data, audit logs, Staff Management, or the internal Admin shell.

## UX and responsive review

- No `prompt()` or operational `alert()` flow.
- No UUID entry, raw internal status entry, or manual ISO timestamp entry.
- Structured fields, controlled choices, date/time controls, bounded feedback, confirmations, and readable validation errors.
- Clear Draft, review, correction, rejection, approval, cancellation, and closure language.
- Useful empty/loading/error states without protected-data flash.
- Desktop, tablet, and mobile navigation; touch targets; wrapping cards/tables; viewport-safe forms/dialogs; keyboard focus and accessible labels.
- Page/tab isolation: Contractor pages never reveal Company or internal Admin modules.

## Planned synthetic fixture matrix

| Label | Auth required | Linkage/state | Browser purpose | Cleanup dependency |
| --- | --- | --- | --- | --- |
| `contractor_owner_or_manager` | Yes | Active Owner/Manager of Contractor A | Primary workflow and profile persistence | Remove after tenant dependencies |
| `contractor_recruiter` | Yes | Active Recruiter of Contractor A | Vacancy management/profile denial | Remove after membership |
| `contractor_coordinator` | Yes | Active Coordinator of Contractor A | Read-only UI | Remove after membership |
| `inactive_contractor_member` | Yes | Suspended/inactive Contractor A membership | Denial | Remove after membership |
| `contractor_b_owner` | Yes | Active Owner of Contractor B only | Cross-tenant isolation and optional zero-data dashboard | Remove after Contractor B dependencies |
| `company_only_user` | Yes | Active synthetic Company membership, no contractor membership | Portal separation denial | Remove after company membership |
| `internal_staff` | Yes | Approved internal role, no contractor membership | Internal review bridge and tenant denial | Remove after staff roles/profile |
| `non_member` | Yes | Auth only | Denial | Remove near end |
| `recovery_bootstrap` | Yes | Internal recovery/admin only | Recovery and approval bridge | Remove last if synthetic |
| Synthetic Contractor A | No | Active/verified primary tenant | Main portal scope | Remove after links/memberships |
| Synthetic Contractor B | No | Active/verified isolation tenant | Isolation/optional zero-data metrics | Remove after its links/membership |
| A Draft vacancy | No | Canonical private Draft + contractor-origin link | Edit/submit flow | Remove after recruitment dependencies |
| A Submitted/Correction vacancy | No | Canonical pre-approval state | Review/correction/resubmit | Remove after feedback evidence |
| A Approved vacancy | No | Canonical Open/Assigned, same record | W3 bridge and safe progress | Remove after recruitment dependencies |
| B vacancy | No | Contractor B only | Isolation | Remove after its dependencies |
| Safe candidate/application | No | Linked only to A Approved vacancy | Privacy and progress | Remove after interview/joining/history |
| Interview and joining | No | Linked to A application | Read-only progress | Remove before application |

Use only synthetic data. An ignored local manifest may hold labels, synthetic emails, exact IDs, original states, and cleanup dependencies. It must never contain passwords, access/refresh tokens, service/secret keys, database credentials, or connection strings.

## Manifest-bound cleanup plan

1. Stop browser mutations and capture sanitized evidence.
2. Remove manifest-bound interviews.
3. Remove manifest-bound joinings.
4. Remove application history and other application dependencies.
5. Remove applications.
6. Remove dedicated candidate dependencies and candidates.
7. Remove requirement dependencies.
8. Remove contractor-origin links.
9. Remove every manifest-bound requirement, including browser-created records.
10. Remove contractor and company memberships.
11. Remove synthetic contractor/company entities.
12. Remove platform users.
13. Remove synthetic staff roles and profiles.
14. Remove manifest-associated audit rows under the approved cleanup procedure.
15. Remove non-recovery Auth users.
16. Verify the intended recovery-only posture and recovery usability.
17. Remove synthetic recovery/bootstrap linkage and Auth identity last, if applicable.
18. Verify zero residue, no orphans, no cross-tenant residue, and unchanged unrelated staging baseline.
19. Remove the ignored local fixture manifest and temporary browser copy.
20. Stop the loopback-only localhost server and verify the port is no longer listening.

Fixture creation, browser execution, evidence recording, and cleanup completed under separate authorization. Final verification found zero W5 residue, zero orphans or cross-tenant links, and an unchanged unrelated staging baseline.

## Completed browser evidence

The full identity matrix passed. Owner exercised the canonical vacancy flow through correction, resubmission, and approval; Recruiter retained vacancy management with read-only profile; Coordinator remained read-only; inactive and non-contractor identities were denied; and Contractor B saw only its own tenant. Contractor authentication did not grant Company Portal access, and Company-only authentication did not grant Contractor Portal access.

`AAD-2026-000086` persisted its structured fields, correction from maximum wage 35000 to 32000, Approved/Open state, and ten openings. Internal review and W3 consumed that same canonical requirement without cloning it. Candidate/application, interview, and joining pages exposed only their safe read-only projections. Owner profile persistence and protected-field immutability passed. Desktop, 768px tablet, approximately 386-400px mobile, responsive modal, keyboard navigation, and Escape-to-close behavior passed.

## History-cache defect resolution

The initial logout test found that browser Back could restore stale protected DOM from history/BFCache after the live session had been cleared. The centralized fix at `ce5200a4bfc9d9f20824d3fb250ef3802628a440` conceals protected content during logout and `pagehide`, then reloads persisted or `back_forward` restorations through the normal authorization gate. The focused Login -> Dashboard -> Logout -> Login -> Back retest passed with no tenant identity, metrics, or protected content restored.

## Completed cleanup

The authoritative ignored manifest governed exact-ID cleanup of all browser fixtures, including `AAD-2026-000086` and eleven audit rows. Dependent recruitment records were removed before requirements and tenant parents. Nine non-recovery Auth users were removed before recovery; recovery/bootstrap was verified and removed last. Final checks found zero W5 Auth/database residue and zero orphan/cross-tenant references. The manifest and temporary copy were removed, and `127.0.0.1:4175` was stopped. Production was not contacted and no deployment occurred.
