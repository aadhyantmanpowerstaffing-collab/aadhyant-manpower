# Desktop-to-Web Migration Blueprint

Status: mapping and migration design only. No desktop or Supabase data was read, exported, transformed, or written by this milestone.

## 1. Principles

- Supabase UUID tables are canonical for the web platform; desktop integer IDs are source identifiers, never target primary keys.
- Add `migration_source`/`migration_source_id` or a dedicated `migration_id_map(source_system, entity_type, source_id, target_id, source_hash, migrated_at)` during migration so reruns are idempotent.
- Normalize Indian phone numbers before matching; never link solely by similar names.
- Report collisions and require human review. Do not silently overwrite web records.
- Preserve original timestamps where trustworthy and record migration timestamps separately.
- Migrate only production-relevant canonical desktop rows. The desktop contains both `candidate_master` and a legacy `candidates` table; they must not both become new web candidates blindly.
- Credentials, verify tokens, App Secrets, access tokens, local passwords, and keyring values are never migrated as data rows. Provision server secrets separately.
- Raw payload migration is optional and retention-limited; prefer operational message fields and hashes.

## 2. Entity-level decisions

| Desktop entity | Existing web entity | Target | Decision |
|---|---|---|---|
| `candidate_master` | `candidates` | `candidates` + preferences | Migrate reviewed canonical rows |
| legacy desktop `candidates` | `candidates` | none by default | Do not migrate until provenance/dedup report proves rows are distinct/useful |
| desktop `companies` | `companies` | `companies` | Migrate reviewed organizations; do not overwrite onboarded web tenants |
| desktop `vacancies` | `employer_requirements` | `employer_requirements` | Transform into canonical requirement records |
| desktop Flow `candidate_applications` | web `candidate_applications` | `candidate_applications` | Migrate only rows that identify a real requirement; otherwise retain as candidate intake/source history |
| `whatsapp_conversations` | none | `whatsapp_contacts` + `whatsapp_conversations` | Migrate active/history if operationally required |
| `whatsapp_messages` | none | `whatsapp_messages` | Migrate selected retention window, preserving provider IDs |
| `chatbot_contacts` | none | `chatbot_contacts`/sessions | Migrate current consent/handoff/language carefully; do not resume stale flows automatically |
| `chatbot_events` | none | audit/system conversation events | Optional history migration |
| `candidate_intake_sessions` | web `candidates`/applications | review/intake session | Migrate incomplete sessions as paused review items, completed facts only after candidate reconciliation |
| `templates` | none | `message_templates` | Migrate metadata; resync authoritative status from Meta |
| `campaigns` | none | `campaigns` | Migrate definitions/history, not blindly restart schedules |
| `queue_items` | none | `campaign_recipients`/outbox history | Migrate terminal history; do not enqueue old Pending items automatically |
| `delivery_events` | none | `delivery_events` | Migrate where provider message ID is present and retention permits |
| desktop users/audit/settings | `admin_users`/Auth | staff/audit/settings | Do not migrate password hashes; map approved operators to Supabase Auth manually |

## 3. Candidate field mapping

| Desktop table/field | Existing web field | Target | Transformation | Migrate? |
|---|---|---|---|---|
| `candidate_master.id` | `candidates.id` UUID | ID map only | store source ID in migration map | Yes |
| `candidate_code` | none | `candidates.candidate_code` additive | trim; unique collision report | Yes |
| `full_name` | `full_name` | same | Unicode trim/collapse whitespace | Yes |
| `mobile` | `mobile`, `whatsapp_number` | normalized phone fields | accept +91/91/0/10-digit; canonical 10-digit web plus E.164 search value | Yes |
| `age` | `age` | same | integer; resolve web 16–75 vs intake 18–65 policy before load | Yes, after policy |
| `gender` | `gender` | same | map allowed vocabulary; report unsupported values | Yes |
| `qualification` | `highest_qualification` | same | vocabulary crosswalk (`10th Pass` -> `10th`, etc.); retain original if Other | Yes |
| `trade` | `specialization` | same | trim; reference-data normalization later | Yes |
| `experience` | `total_experience`/candidate type | structured preference/profile | do not invent years from Fresher; convert numeric only if semantically years | Conditional |
| `state` | `state` | same | canonical state/UT spelling | Yes |
| `district` | `district` | same | trim/title normalization without losing local spelling | Yes |
| `city` | `current_location` | same | trim | Yes |
| `company` | previous/current employment text | candidate employment child/fallback | do not link company CRM solely by text | Conditional |
| `whatsapp_optin` | `consent` plus channel preference | consent record/contact | opt-in timestamp/source required; boolean alone is insufficient for new marketing consent | Historical only |
| `status` | `status`, profile/availability statuses | mapped candidate lifecycle | explicit crosswalk and exception report | Yes |
| `created_at`,`updated_at` | same | same | parse UTC/declared local timezone; preserve source | Yes |
| `candidate_groups`/members | none | `tags`/candidate tags | group -> tag with source namespace | Optional |

Candidate dedupe precedence:

1. exact normalized mobile/WhatsApp;
2. explicit migration ID map;
3. manually reviewed email/identity evidence if available;
4. never name-only automatic merge.

When a web candidate already exists, produce a field-level comparison. Prefer verified/current web values; append missing non-conflicting values only after review.

## 4. Company mapping

| Desktop field | Existing web field | Target/transformation | Migrate? |
|---|---|---|---|
| `companies.id` | UUID `companies.id` | migration ID map | Yes |
| `company_id` | none | optional external/source code | Yes |
| `company_name` | `legal_name`,`trade_name` | default legal name; manual review when legal/trade distinction unknown | Yes |
| `contact_person` | membership/contact not canonical org field | company contact child or onboarding note | Conditional |
| `mobile_no`,`email` | `main_phone`,`main_email` | normalize/lowercase | Yes |
| `address`,`city`,`state`,`pin_code` | same | trim, validate six-digit pincode | Yes |
| `industry`,`website` | same | normalize URL/industry reference | Yes |
| `remarks` | none | internal note with migration source | Optional |
| `is_deleted` | account/archive state | archived/suspended mapping; do not delete | Yes |
| timestamps | timestamps | preserve | Yes |

Match potential existing web companies using reviewed GSTIN/CIN first, then exact normalized legal name + phone/email. Desktop lacks GSTIN/CIN, so automatic merges are high-risk.

## 5. Vacancy/requirement mapping

| Desktop `vacancies` field | Existing web `employer_requirements` | Transformation | Migrate? |
|---|---|---|---|
| `id` | UUID `id` | ID map | Yes |
| `vacancy_id` | `requirement_code` | preserve as legacy/source reference; let web code policy decide canonical code | Yes |
| `company_id` | `company_id` | resolve through company ID map | Yes |
| `title` | `job_role` | trim | Yes |
| `description` | `additional_notes` or approved public description | classify public vs internal before load | Conditional |
| `qualification` | `qualification` | vocabulary normalization | Yes |
| `skills` | `iti_trade`/future skills child | split only with reviewed delimiter; otherwise preserve text | Yes |
| `experience_min/max` | `experience_requirement` | do not collapse numeric ranges inaccurately; add structured columns later or preserve detail | Conditional |
| `salary_min/max` | same | decimal, nonnegative, range validation | Yes |
| `location` | `job_location` | normalize place text | Yes |
| `openings` | `required_headcount` | integer > 0 | Yes |
| `status` Open/Closed/Hold | `requirement_stage` | Open->open, Closed->closed, Hold->on_hold | Yes |
| `is_deleted` | archive/cancel state | never hard-delete; mark cancelled/archived | Yes |
| timestamps | timestamps | preserve | Yes |

Do not create a web `vacancies` table. Existing `employer_requirements` is canonical.

## 6. WhatsApp contact/conversation mapping

| Desktop field | Target field | Transformation | Migrate? |
|---|---|---|---|
| conversation `wa_id` | `whatsapp_contacts.wa_id` | normalized unique digits | Yes |
| `profile_name` | contact profile name | Unicode trim | Yes |
| `candidate_id` | contact/conversation candidate FK | resolve candidate ID map; nullable | Yes |
| `last_message_at/preview` | conversation denormalization | recompute from migrated messages; compare source | Yes |
| `unread_count` | conversation unread | preferably reset or recompute per rollout policy | Conditional |
| `interested` | contact/application/intake event | create audited interest event; do not treat as application automatically | Yes |
| `last_incoming_at` | same | timezone conversion | Yes |
| chatbot selected vacancy | conversation requirement FK | vacancy ID map | Yes if still open |
| assigned recruiter | none in desktop | null/unassigned | No source |

One web contact must represent one normalized WA ID. Merge multiple desktop rows only through deterministic phone equivalence and retain source IDs in the map.

## 7. Message mapping

| Desktop `whatsapp_messages` | Target | Transformation | Migrate? |
|---|---|---|---|
| `id` | migration map/source ID | no target PK reuse | Yes |
| `conversation_id` | conversation FK | resolve ID map | Yes |
| `whatsapp_message_id` | provider message ID | preserve unique; duplicates reported | Yes |
| `direction` | same | incoming/outgoing | Yes |
| `sender_type` | actor type | incoming->candidate; bot/human/system preserved | Yes |
| `message_type` | content type | text/interactive/Flow/etc. vocabulary map | Yes |
| `message_text` | text | preserve UTF-8 | Yes |
| interactive ID/title | structured content | store safe structured JSON | Yes |
| `status` | current delivery state | monotonic vocabulary mapping | Yes |
| `raw_payload` | webhook event reference | normally do not bulk-copy; hash/minimize and retention-limit | Usually No |
| `message_at`,`received_at` | same | UTC conversion | Yes |

Recommended scope: migrate only the approved retention window plus messages linked to active intake/application/recruitment cases. Archive older history separately if legally required.

## 8. Chatbot and intake mapping

| Desktop field | Target | Transformation | Migrate? |
|---|---|---|---|
| chatbot `language` | contact/session language | `gu`,`hi`,`en` | Yes |
| `current_state`,`previous_state`,`conversation_step` | chatbot session | map only known compatible states | Conditional |
| `last_intent` | session/contact telemetry | preserve | Optional |
| `bot_enabled`,`human_handoff` | conversation bot mode | handoff/opt-out takes precedence | Yes |
| `unknown_count`, cooldown timestamps | session telemetry | reset unless needed | Usually No |
| `selected_vacancy_id` | selected requirement FK | ID map; clear if closed/missing | Conditional |
| `job_result_ids/offset` | transient session state | do not migrate stale results | No |
| `chatbot_events` | conversation system/audit events | source-tagged append-only events | Optional |

Candidate intake fields map directly to the existing web candidate fields: name, age, gender, qualification, specialization, city, district, state, experience category/details, current employment/company/role/location, preferred location, and interview availability.

Rules:

- completed intake does not create a second candidate; reconcile with `candidate_master` mapping;
- active/incomplete intake imports as `paused_migration_review`, never auto-resumes or auto-messages;
- Flow tokens/provider submission IDs may be retained for idempotency, but no secret values are involved;
- submitted payload JSON should be minimized and retained only if policy requires it;
- operator approval remains required before candidate creation/linking.

## 9. Templates, campaigns, queue, and delivery

| Desktop | Target | Transformation | Migrate? |
|---|---|---|---|
| template Meta ID/name/language/category/status | `message_templates` | preserve; resync current Meta status/components | Yes |
| header/body/footer/buttons/variables JSON | template version/components | validate JSON and variable indexes | Yes |
| soft-delete/active | archive state | preserve | Yes |
| campaign name/template/audience/schedule/status | `campaigns` | store historical snapshot and source | Yes |
| media metadata/path | Storage object reference | upload only approved existing files; checksum/MIME scan | Conditional |
| queue recipient/candidate/phone | `campaign_recipients` | resolve IDs and normalized phone | Yes |
| Pending/Running items | outbox | import as paused historical state, never auto-send | No automatic send |
| Sent/Failed terminal rows | recipient history | preserve provider ID/error/attempts | Yes |
| delivery status/timestamps/errors | message/recipient + `delivery_events` | monotonic mapping and unique event key | Yes |

## 10. Settings, auth, and secrets

- Map only non-secret chatbot/business-hour/UI settings after a setting-by-setting review.
- Do not migrate desktop window state, filesystem paths, backup paths, or local webhook host/port.
- Do not copy desktop `users.password_hash`; invite/create Supabase Auth identities and assign reviewed staff roles.
- Do not export Windows keyring credentials. Provision Meta credentials in the production server secret store through a controlled rotation procedure.
- Do not migrate the temporary/public tunnel URL.

## 11. Staged migration procedure

1. Freeze a read-only desktop backup copy and record SQLite checksum/schema version.
2. Export counts and collision reports without secrets.
3. Create staging Supabase clone/project and target migrations.
4. Load reference organizations, candidates, requirements, then applications/interviews/joinings.
5. Load WhatsApp contacts/conversations/messages within retention scope.
6. Load template/campaign/delivery history with all sends disabled.
7. Reconcile counts, required fields, phone collisions, FK completeness, provider-ID uniqueness, and status distributions.
8. Run application/RLS/security tests with each role.
9. Obtain human sign-off on merge conflicts and sampled records.
10. Rehearse rerun; second run must create zero duplicates.
11. Perform production migration in a separately approved window with workers/feature flags controlled.
12. Keep desktop read-only for a defined audit period; do not delete it as part of cutover.

## 12. Reconciliation gates

- Every migrated row has one source-to-target ID map and source hash.
- Candidate normalized phone collisions are zero unresolved.
- No application references a missing candidate/requirement/contractor assignment.
- No conversation references a wrong candidate due to formatting-only ambiguity.
- No duplicate provider message IDs.
- Terminal delivery counts match source by campaign/status.
- No Pending desktop queue item becomes sendable automatically.
- No secret value appears in exports, logs, browser bundles, or migration tables.
- RLS role tests prove companies/contractors cannot access unrelated candidate/internal data.
