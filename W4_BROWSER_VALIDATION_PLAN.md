# W4 Company Portal Browser Validation Plan

Status: manual localhost browser validation COMPLETE on dedicated NONPROD staging. Manifest-bound fixture cleanup remains PENDING; W4 is not formally closed.

## Safety and recovery

Use a localhost-only copy bound to `127.0.0.1`, configured only with the NONPROD staging URL and publishable key, with a persistent `NONPROD / STAGING` banner and no tunnel. Never include database credentials, secret/service keys, tokens, real people/business data, or deliverable contact details. Preserve the existing internal bootstrap/recovery path until every other dependency is removed; a synthetic recovery identity, if explicitly required, is removed last only after another recovery path is verified.

## Identity matrix

1. **Anonymous:** denied, no protected-content flash.
2. **Owner / HR Admin:** Dashboard, My Requirements, create/edit/detail, safe Applications, Interviews, Joining Status, allowlisted Company Profile update, logout/refresh/session behavior.
3. **Company Recruiter:** own dashboard and requirements, permitted management, safe progress views, no protected profile administration.
4. **Company Viewer:** approved read-only portal; no create/edit/close/profile actions.
5. **Inactive member, contractor, internal W3 staff without company membership, and non-member:** denied.
6. **Company B Owner:** only Company B context/data; Company A direct URLs and object parameters denied.

The Company Portal must expose neither `/admin/` navigation nor Staff Management/W3 modules.

## Company HR workflow and canonical bridge

Company A HR login → Dashboard → Create Requirement → Save private Draft → My Requirements → Detail → Edit Draft → safe application progress → interview visibility → joining visibility → allowlisted Company Profile update → logout.

Then use authorized internal bootstrap/admin or recruiter access to confirm the same canonical requirement appears in W3 with matching code/fields and no duplicate record or re-entry. Company activation remains unavailable; internal W3 activation stays authoritative.

## Browser privacy and UX checks

- Never render candidate phone, WhatsApp, UUID/Auth linkage, internal/recruiter notes, unrelated history, other-company data, Candidate Master, audit logs, Staff Management, or Admin modules.
- Inspect visible content, accessible names, direct URLs, page-consumed network payloads, and errors without printing secrets.
- No `prompt()`, operational `alert()`, UUID entry, raw status entry, or manual ISO timestamp entry.
- Verify readable validation/errors/empty states, keyboard focus, accessible controls, page isolation, UTF-8 rendering, responsive desktop/tablet/mobile navigation, touch targets, and viewport-safe forms/dialogs.
- Dashboard includes correct Company A metrics and an optional zero-data company with numeric zeros.
- Requirements cover search/filter, create, edit, close/cancel, terminal state, and Company B exclusion.
- Applications, interviews, and joinings remain own-company and read-only where designed; direct W3 mutation RPC attempts remain denied.

## Planned fixture matrix

| Label | Auth | State/linkage | Purpose |
| --- | --- | --- | --- |
| `company_a_hr_admin` | Yes | Active Company A HR Admin | Full HR workflow/profile |
| `company_a_recruiter` | Yes | Active Company A Recruiter | Management without profile/W3 authority |
| `company_a_viewer` | Yes | Active Company A Viewer | Read-only UI |
| `company_a_inactive` | Yes | Inactive Company A member | Denial |
| `company_b_owner` | Yes | Active Company B Owner | Isolation |
| `contractor_user` | Yes | Synthetic contractor only | Denial |
| `internal_staff` | Yes | Internal staff, no membership | Denial and canonical bridge |
| `non_member` | Yes | No platform membership | Denial |
| `zero_company_owner` | Optional | Active zero-data company | Zero dashboard |
| Synthetic Companies A/B | No | Active verified tenants | Tenant scope |
| A draft/open requirements; B requirement | No | Canonical requirements | Lifecycle/isolation |
| A safe candidate/application | No | Linked only to A open requirement | Privacy/progress |
| A interview and joining | No | Valid canonical dependencies | Read-only progress |

An ignored local manifest may contain labels, synthetic emails, entity/Auth IDs, original states, dependencies, and cleanup IDs only—never passwords, tokens, keys, or connection strings.

## Dependency-safe cleanup

1. Stop browser mutations and record sanitized evidence.
2. Delete manifest-bound interviews and joinings.
3. Delete application history/dependencies, then applications.
4. Delete dedicated candidate dependencies and candidates.
5. Delete requirement dependencies and requirements.
6. Delete company/contractor memberships, then tenant entities.
7. Delete manifest-bound audit rows where approved.
8. Delete non-recovery platform and Auth users.
9. Verify only intended bootstrap/recovery remains; remove a manifest-created recovery identity last only when another recovery path is proven.
10. Verify zero residue/orphans across all fixture tables, remove local artifacts, and stop the loopback server.

Fixture creation and browser execution completed under separate authorization. Cleanup still requires separate authorization.

## Accepted browser evidence

- Anonymous, suspended-member, contractor, internal-staff, and non-member access boundaries passed without protected-data exposure.
- Company A HR Admin completed dashboard, requirement creation/detail/edit, safe recruitment-progress views, allowlisted profile update, and logout checks. Draft `AAD-2026-000060` persisted with headcount `12` and is recorded in the ignored fixture manifest.
- Company A Recruiter retained approved requirement-management access but no protected profile administration. Company A Viewer remained read-only.
- Company B Owner saw Company B only, zero-data metrics, and no Company A requirement, candidate/application, interview, joining, or profile data.
- Candidate PII/internal notes, Candidate Master, internal Admin/Staff Management, UUID entry, raw status entry, and prompt/alert operational flows were absent.
- The Company Profile persistence verification and suspended-member status wording fixes passed focused manual retests.
