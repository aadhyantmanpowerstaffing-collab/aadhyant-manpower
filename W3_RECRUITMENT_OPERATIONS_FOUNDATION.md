# W3 Recruitment Operations Foundation

Status: database/security runtime validation, live localhost browser validation, technical audit, and synthetic-fixture cleanup complete on dedicated NONPROD staging. Migration 018 has not been applied to production.

## Reused canonical model

W3 adds no replacement domain tables. It uses `candidates` as Candidate CRM, `employer_requirements` as the requirement/vacancy record, the unique candidate/requirement pair in `candidate_applications`, the W1 `application_stages` and trigger-maintained `application_stage_history`, migration-014 `interviews`, and one joining record per application in `candidate_joinings`. Existing public interest registration, admin application/interview contracts, and migration-015 tenant projections remain installed.

## Permission matrix

| Capability | Bootstrap | Super admin | Admin | Recruiter | Operations | Viewer |
|---|---:|---:|---:|---:|---:|---:|
| Recruitment dashboard and projected lists | Manage | Manage | Manage | Manage | Selected/joining context | Read only |
| Candidate contact PII/detail notes | Yes | Yes | Yes | Yes | No | No |
| Candidate workflow mutation | Yes | Yes | Yes | Yes | No | No |
| Requirement recruiting view | Yes | Yes | Yes | Yes | Yes | Read only |
| Application creation/transition | Yes | Yes | Yes | Yes | No | No |
| Interview scheduling/outcome | Yes | Yes | Yes | Yes | Context only | Read only |
| Joining/placement mutation | Yes | Yes | Yes | View only | Yes | Read only |

Active W2 membership remains mandatory. Inactive staff, non-members, anonymous callers, and every `platform_users` identity—including company and contractor users—are denied. Staff Management remains independently controlled by W2.

## Migration 018

Private helpers derive the caller only from `auth.uid()`: `is_bootstrap_recruitment_admin`, `can_view_recruitment`, `can_manage_candidates`, `can_manage_applications`, `can_manage_interviews`, and `can_manage_joinings`. All are fixed-search-path security-definer helpers with browser execution revoked.

Authenticated clients receive narrow RPCs for permissions and metrics; candidate, requirement, application, interview, and joining projections; candidate workflow edits; candidate-to-requirement application creation; validated stage transitions; interview scheduling/outcomes; and joining upsert. Mutations generate sanitized `audit_logs` entries. Application inserts and transitions continue to use the W1 stage-history trigger, preserving actor and correlation attribution.

No direct table privilege or RLS policy is added for W3 roles. Migration 015 company/contractor RPCs and policies are unchanged. Existing bootstrap table access remains compatible, while ordinary staff use only W3 projections.

## Candidate CRM and privacy

Candidate lists omit phone, WhatsApp, address-like detail, free-form notes, and Auth linkage. Candidate detail exposes phone/WhatsApp and internal notes only to bootstrap, super-admin, admin, and recruiter managers. Viewer receives those fields as null. Operations sees only candidates with selected/joining context and receives no contact PII. Search supports name/location, state, district, qualification, candidate type, and workflow status with bounded pagination.

Candidate workflow edits are restricted to the existing candidate status vocabulary, interview availability, and a length-bounded internal note. W3 does not add document access or public/tenant Candidate CRM projections.

## Requirements, applications, interviews, and joining

The requirement workspace projects recruiting facts already stored on `employer_requirements`, including company, code, role, location, headcount/progress, qualification/trade, experience, approved age/gender criteria, salary, shift, facilities, and stage. Contact details and internal notes are omitted.

Application creation requires an active candidate and open requirement and relies on the canonical unique constraint for duplicate prevention. Transitions use the existing database vocabulary and an explicit transition graph; arbitrary strings and unsupported jumps fail. The application detail projection includes stage and interview history without unrelated tenant internals.

Interview scheduling reuses the canonical table, round numbering, and one-current-scheduled-interview constraint. Recruiters/admins schedule and record supported outcomes; selected/rejected results synchronize an eligible application. Joining reuses `candidate_joinings`; operations/admins manage supported joining states, and the application stage is synchronized to joining pending, joined, or left.

## Admin UI

The guarded `/admin/` shell adds Dashboard, Candidates, Requirements, Applications, Interviews, and Joining / Placement modules after `get_recruitment_permissions()` succeeds. All data access uses W3 RPCs—never direct table queries. Mutation controls are derived from server-returned permissions; server authorization remains authoritative. Staff Management visibility remains W2-controlled.

## Tests and limitations

The rollback-scoped SQL checkpoint covers bootstrap, super-admin, admin, recruiter, operations, viewer, inactive staff, non-member, company, contractor, and anonymous callers; projected reads; PII suppression; candidate mutation; application duplicate/invalid transition protection; automatic history; interviews; joining; grants/search paths; and preservation of W2/migration-015 contracts. Focused frontend tests cover navigation, role-aware controls, read-only viewer behavior, and RPC-only browser data access.

Dedicated NONPROD staging validation is complete: checkpoint 018, required regressions 015–017, legacy checkpoints 011–014, live browser role/workflow validation, technical audit, fixture cleanup, and final zero-residue verification passed. Detailed evidence is recorded in `W3_STAGING_RUNTIME_VALIDATION.md`; the completed browser matrix is recorded in `W3_BROWSER_VALIDATION_PLAN.md`. W3 is ready for an evidence-only closure commit and separately authorized push.

W3 deliberately does not add advanced matching/scoring, assignment ownership, standalone note feeds, documents/OCR, WhatsApp, campaigns, chatbot/Flows, Meta templates, payroll, attendance, PF/ESIC, billing, or mobile applications. The first UI uses bounded lists and simple operator dialogs; richer accessible editors, saved filters, bulk workflows, and optimistic concurrency remain future enhancements.
