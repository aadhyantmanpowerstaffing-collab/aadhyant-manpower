# Admin WhatsApp manual replies — prepared release

## Production release completed — 16 October 2026

Explicit production approval received at 20:55:00 IST. Reviewed native source `467900fdfa4206ec72c790f6ebbe3c341b441b9e`, tree `e04958afacfeca40d7b697d5f19a113028391c16`, promoted without force after confirming shared HEAD and live generic-worker baseline. Migration installed as `20261016152547 / whatsapp_operator_replies`; source SHA256 remains `06fcb07872bbaded037d8733cd65f6362acc221927a560ee4ba875d9219330a1`.

New Edge `whatsapp-operator-reply` v1 ACTIVE, verify_jwt=true; all three downloaded source files exactly match reviewed source. Runtime archive SHA256 `cf9f12bf098acd05d9a2139297315bfe2a413e14e1f25f3752dd651e6d7aaa6d`. Private-helper denials, service-only claim and authenticated guarded entry-point ACLs and empty search paths verified. Post-migration advisors retain existing categories and identify the five additional intentionally guarded authenticated Admin endpoints; no anonymous access was introduced. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable .

Pages run `38924054598` succeeded (build `117050962662`, deploy `117051846021`). CI passed 577/577 tests with zero failures/skips, plus artifact boundary and manifest checks. Live JS matches SHA256 `4a41f4d19c211584c02819a80681ccc567269260418532c41a3beae4b05f4f4c`; CSS matches `10397c01c3b3d3336e560d7e0ffd5508b64ddec205b6f9eb748a65164f1d93c5`.

Authenticated live UI verified Inbox, selected retained contact ending 5800, real reply-window expiry `17 October 2026 16:10:38 IST`, labelled textarea, 0/2000 counter and enabled Send Reply. Screenshot captured without entering text or pressing Send. Operator reply rows=0, contacts=5, outbound=39, applications=6. Employer replies remain enabled and automatic candidate alerts remain disabled. No real message/test was sent. Verified URL: `https://aadhyantmanpower.in/admin/?release=20261016-operator-replies#whatsappConsole`. Earlier prepared/unreleased statements below are historical and superseded by this completion entry.

User authorized adding Type a reply and Send on 16 October 2026 at 20:39:51 IST. This implementation is prepared and tested, not deployed. There have been no production mutations or real message sends for this task.

## Operator experience

Select a contact in Inbox or Sent. The conversation has a labelled reply composer, 2,000-character limit and a masked recipient heading. Server-supplied status shows the signed inbound reply-window expiry or the specific reason sending is unavailable. Closed windows point the operator to an existing approved campaign template or a new incoming message; there is no free-text window bypass or automatic template send.

Send Reply explicitly prepares one durable canonical outbox record and invokes the dedicated authenticated dispatcher. The recipient is always the selected canonical contact, never a browser-supplied phone. A browser/transport failure retains the draft and its durable message/operation identity. Check / Resume Reply explicitly resumes/checks that same identity and may send an unattempted queued reply, as stated beside the button; rapid clicks share the busy guard and the textarea is locked during dispatch. A refreshed page restores the author’s canonical pending reply and resumes the same message ID. Other in-flight replies block new preparation for that contact. Successful provider acceptance clears the text and shows status. Write Another Reply is offered only after a known terminal result. A queued, unattempted reply can be discarded through an author-scoped RPC. Ambiguous outcomes cannot be automatically retried or replaced by another reply to the contact before reconciliation.

Replies written here are projected from their saved canonical text into the existing conversation history, using DOM text nodes. Legacy inbound/outgoing records keep their privacy-safe activity summaries; raw candidate registration answers and capability URLs remain hidden. Read markers, provider delivery receipts, consent, marketing subscription and recruitment records are unchanged. No compose action is triggered merely by opening a contact or preview.

## Canonical sender and security

Migration: `20261016151003_whatsapp_operator_replies.sql`. The existing outbox gains operator author/body columns with an exact purpose, payload, nonblank text, size and single-attempt shape constraint. There is no separate message store. The original generic claim body is retained with only an additional exclusion for operator_reply alongside employer_post_job; its vacancy eligibility guard remains present. The existing message-type constraint keeps all registration and employer reply branches.

All browser RPCs require the existing Admin access predicate IS TRUE. Preparation uses stable author+operation idempotency with content/contact mismatch rejection, serializes actor/contact limits and binds the most recent signed canonical inbound message received within the preceding 24 hours (future and unsigned messages excluded). Contact suppression, STOP/opt-out, ambiguous identity and stale sender verification block preparation. Limits are 10 prepared replies/contact/10 minutes and 100/operator/hour.

`whatsapp-operator-reply` requires production Origin and a real user JWT. Before any service claim, the authenticated status RPC verifies both Admin permission and authorship. It accepts only a prepared message UUID, never arbitrary text/destination. Configured phone and business account must match server secrets. The claim is service-only; the final provider boundary deliberately uses the *real operator JWT* to recheck Admin access and authorship, plus contact/sender/expiry/lease eligibility under row locks. It does not simulate another user's auth context. The body comes from the canonical row and is revalidated before sending.

The existing single-attempt session outbox sender performs the provider call and saves its provider receipt through existing W7A mark-sent/failure RPCs. Timeouts, HTTP 5xx, malformed receipts or unconfirmed receipt saves require reconciliation; no automatic second provider call. Explicit provider rejection is terminal. The generic queue cannot claim or expire the dedicated manual-reply lease. Signed status webhooks continue updating existing canonical delivery state.

No raw provider response, token, private body or destination is logged or returned by the dispatcher. New functions have empty search paths; private helpers have no browser/service EXECUTE grants, claim is service-only, Admin entry points are authenticated-only with internal guards. Table direct-access grants are unchanged.

## Verification and review preview

PostgreSQL runtime tests cover stable preparation, content mismatch, exact history text, no consent changes, generic worker exclusion, single claims, expired leases, reconciliation blocking, future/expired/unsigned inbound, STOP/suppression, identity conflict, stale sender, role revocation and changed author after claim, sender mismatch, input validation, cancellation, rate limits and privilege denials.

Edge tests verify real-user versus service credentials at the appropriate boundaries, one provider attempt, replay, denied Admin/author access, final boundary denial, timeout/5xx/malformed receipt/receipt-save uncertainty, deterministic rejection, invalid origin/request shape, and canonical payload validation. DOM tests verify closed-window disabling, blank rejection, retained draft and stable-ID recovery, and rapid double-click suppression.

Interactive synthetic preview: `tests/fixtures/operator-reply-design-preview.html`. It embeds actual console code/styles and fixed in-memory data. Send only simulates; there is no network or real credential. Test fixtures remain excluded by the existing production build boundary. No local graphical browser QA is claimed because its required managed browser plugin was unavailable.

Meta's official message documentation was verified for the existing 24-hour session implementation in the preceding employer release; a current retrieval attempt returned 429. No pricing claim is made. Reference: https://developers.facebook.com/documentation/business-messaging/whatsapp/messages/send-messages . Existing Supabase function/security guidance applies: https://supabase.com/docs/guides/database/functions .

## Authorized release boundary

Production approval for this new manual-reply feature is still required by root AGENTS.md before migration, new Edge deployment and site publication. After approval: recheck shared source and actual deployed generic-claim baseline; promote the reviewed tree without force; apply the new migration; deploy `whatsapp-operator-reply` with index.ts plus `_shared/whatsapp/server-headers.ts` and `_shared/whatsapp/registration-reply.ts`, verify_jwt=true; publish the existing Pages workflow; verify source hashes, grants, authenticated composer and real retained histories without pressing Send. Keep existing Post Job and automatic-candidate-alert settings unchanged. Real recipient tests require explicit recipient/message authorization; deployment alone must not send anything.

Read-only pre-release check: the actual live generic claim function matches the previous reviewed employer release exactly. Recheck before migration application if the shared source or deployment changes.

Final validation: **577/577 full regression tests passed**, zero failures or skips; all six final composer behavior tests passed after the final wording refinement. Production build, manifest verification, 6/6 artifact-boundary tests, JS syntax and git diff checks passed. A preceding full-suite process ended early while another isolated PostgreSQL suite was running; the affected existing suite passed 37/37 in isolation, then full sequential regressions passed 576/576 and finally 577/577 after pending-reply restoration was added. No assertions were removed or weakened. Migration SHA256: `06fcb07872bbaded037d8733cd65f6362acc221927a560ee4ba875d9219330a1`.
