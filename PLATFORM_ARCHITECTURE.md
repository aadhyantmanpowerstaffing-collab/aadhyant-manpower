# Aadhyant Core Platform Architecture

## Purpose

Aadhyant remains the controlled operational bridge between companies, contractors, candidates, and Aadhyant administrators. It is not an unrestricted marketplace. Access to private company information and candidate identity/contact information is based on ownership, assignment, workflow state, and explicit authorization.

Milestone 7 defines the relational foundation only. It does not add company, contractor, or candidate dashboards and does not expose new data publicly.

## Roles

### Admin

An Aadhyant administrator is authenticated through Supabase Auth and separately allowlisted in `admin_users`. This remains the only admin authorization mechanism. Admins can manage operational entities under RLS. Being present in `platform_users` never grants admin access.

### Company

A company Auth user has a `platform_users` row with `account_type = 'company'` and one or more approved `company_users` memberships. A company can have multiple people with minimal membership roles: `owner`, `hr_admin`, `recruiter`, or `viewer`.

Future company policies must limit access to the user's active company memberships, company-owned requirements, and explicitly disclosed application information for those requirements. Company users must never receive general candidate-table access.

### Contractor

A contractor Auth user has `account_type = 'contractor'` and one or more approved `contractor_users` memberships. Minimal membership roles are `owner`, `manager`, `recruiter`, and `coordinator`.

Future contractor policies must limit access to the contractor's own profile, requirements assigned through `requirement_contractors`, and applications connected to those assignments. Contractors cannot self-assign or self-approve.

### Candidate

A candidate Auth user has `account_type = 'candidate'`. After identity verification, one existing `candidates` row may be linked through nullable `candidates.user_id`. Candidate accounts can later read their own profile, applications, interviews, and joining status. They cannot update selection, interview results, or joining decisions.

## Account status decision

`platform_users.account_status` uses `pending`, `active`, `suspended`, and `rejected`. `active` means the account has been approved and may participate; a separate `approved` state would duplicate that meaning. Company and contractor entity verification remains separate through `verification_status` (`pending`, `verified`, `rejected`) because verification of an organization is different from enabling or suspending access.

## Core entities

- `admin_users`: existing Aadhyant admin allowlist; unchanged.
- `platform_users`: non-admin Auth identity and account lifecycle.
- `companies`: employer/industrial-unit organization profile.
- `company_users`: many-to-many company membership.
- `contractors`: contractor/agency organization profile.
- `contractor_users`: many-to-many contractor membership.
- `employer_requirements`: existing public requirement table, extended into the central requirement entity.
- `candidates`: existing public registrations, extended for optional account linking and profile lifecycle.
- `requirement_contractors`: admin-controlled contractor assignments.
- `candidate_applications`: candidate-to-requirement workflow.
- `interviews`: repeatable interview events per application.
- `candidate_joinings`: one current joining lifecycle per application.

## Relationship diagram

```text
auth.users
   |
   +-- admin_users --------------------------> Admin access to operations
   |
   +-- platform_users
          |
          +-- company_users ----> companies
          |                         |
          |                         v
          |                  employer_requirements
          |                         |
          +-- contractor_users -> contractors
                                    |
                                    v
                         requirement_contractors
                                    |
                                    v
candidates ----------------> candidate_applications
   |                                |
   +-- own Auth link                +--> interviews
                                    |
                                    +--> candidate_joinings
```

Operational sequence:

```text
Company
  ↓
Requirement
  ↓
Requirement Contractor Assignment
  ↓
Candidate Application
  ↓
Interview
  ↓
Selection / Joining Pending
  ↓
Joining

Candidate → Applications
Contractor → Assigned Requirements
Admin → All Operational Management
```

## Existing table compatibility

### Candidates

`candidates` remains the core registration/profile table. Existing public registrations receive safe lifecycle defaults and retain `user_id = NULL`. Linking must be a verified admin/account-activation action; names or mobile-number matches alone must never link an Auth account automatically. `user_id` is unique so one Auth identity cannot claim multiple candidate profiles.

### Employer requirements

`employer_requirements` remains the central requirement table. Existing fields, public INSERT grants, RLS policies, status workflow, and dashboard queries stay intact. New company and structured job fields are additive. `required_headcount` remains the openings source rather than adding a duplicate `openings` column. Existing free-text `salary_wage` remains; optional numeric bounds support future filtering without removing legacy values.

## Requirement codes

New rows after migration receive codes such as `AAD-2026-000001`. A PostgreSQL sequence supplies the numeric component, so concurrent inserts cannot collide and no `MAX()+1` logic exists. UUID remains the relational primary key. The year is descriptive and the sequence remains globally increasing across years.

Existing requirements are not backfilled automatically; their `requirement_code` remains null until a separately reviewed backfill is approved. This prevents Milestone 7 from rewriting live records.

## Contractor assignments

`requirement_contractors` links one contractor to one requirement with assigned headcount, status, assignment timestamps, assigning Auth user, and admin-only notes. A unique requirement/contractor pair avoids accidental duplicate assignments. There is no contractor self-insert policy in Milestone 7.

## Candidate applications

`candidate_applications` links candidates to requirements and optionally to the exact contractor assignment that sourced them. A composite foreign key requires the referenced assignment to belong to the same requirement as the application. Using `requirement_contractor_id` instead of a free contractor ID therefore prevents a contractor assignment for one requirement from being attached to another requirement's application. One candidate/requirement pair represents the current application lifecycle.

Supported sources are `direct`, `contractor`, `admin`, `whatsapp`, `campus`, and `referral`. Workflow status supports `interested`, `applied`, `screening`, `shortlisted`, `interview`, `selected`, `rejected`, `joining_pending`, `joined`, `left`, and `cancelled`. The database constrains valid states but does not force a strictly linear transition; operational rules can be added after workflow UI is defined.

## Interviews and joining

Interviews are a separate table because an application may be rescheduled or have multiple interview events. Joining is also separate because it is an operational lifecycle, not merely an application status. `candidate_joinings` stores one current joining record per application. Attendance, payroll, ESIC/UAN/PF, accommodation, and workforce timesheets are intentionally deferred.

## RLS and data visibility

Milestone 7 enables RLS on every new table, revokes access from `anon` and `authenticated`, and then grants SELECT/INSERT/UPDATE only through policies that call the existing `private.is_admin()` allowlist helper. There are no DELETE policies or grants.

Company, contractor, and candidate policies are intentionally not activated yet. Their future milestones must add narrow policies with all of these checks:

1. Auth user has the expected `platform_users.account_type` and `account_status = 'active'`.
2. Organization membership is active.
3. Company records match an active `company_users.company_id`.
4. Contractor records flow through an active `requirement_contractors` assignment.
5. Candidate records match `candidates.user_id = auth.uid()` for self access.
6. Recruitment decisions and internal notes remain admin-controlled.

No future protected-table policy should use unrestricted `using (true)` or `with check (true)`.

## Candidate privacy and controlled disclosure

- Admin: full operational visibility under the allowlist.
- Candidate: own profile and own workflow only.
- Contractor: candidate contact only when connected to its assigned requirement/application and only after a dedicated disclosure policy is approved.
- Company: candidate contact only for its own requirement after an approved workflow state or explicit authorization.

Broad SELECT on `candidates` is never appropriate for companies or contractors. A future secure implementation should expose contact data through narrowly scoped security-invoker views or RPCs after disclosure rules are defined, rather than granting full-row access.

## Company and public data visibility

Candidates should eventually see a safe job projection only: job role, generalized location, qualification, compensation range where approved, and public workflow information. They should not see HR personal contact details, company internal notes, contractor commercial data, or the full `employer_requirements` row.

The preferred future public-job design is a dedicated security-invoker view or narrowly scoped RPC projecting approved columns and filtering `requirement_visibility = 'public'`, `requirement_stage = 'open'`, and `published_at is not null`. Milestone 7 creates neither the view nor an anonymous SELECT policy because the publishing workflow does not exist yet.

## Future registration activation order

1. Company registration creates a pending Auth identity, `platform_users`, company profile, and membership; admin verification activates access.
2. Contractor registration follows the same pending organization and membership process.
3. Candidate account activation links an existing candidate only after identity verification or creates a controlled new profile.
4. Admin authorization continues exclusively through manually controlled `admin_users` membership.

The current public employer and candidate forms remain anonymous, insert-only, and fully compatible throughout this transition.
