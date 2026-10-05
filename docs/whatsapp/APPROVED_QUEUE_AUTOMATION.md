# Approved WhatsApp queue automation — disabled release candidate

Prepared 2026-10-05. Source baseline: `c35f0fc11306be898aa2f1285b5b369500b1aaad`
on `web-platform-development`. Default branch independently verified: `main`.

## Outcome and scope

The existing real TEST reached DELIVERED; its INTERESTED response created one
canonical application at 2026-10-05 15:47:53 UTC, with audit action
`whatsapp.interested_application_created`. The operator confirmed the Admin
application stage Interested and separately supplied SENDER_DISABLED=PASS,
SENT=0, FAILED=0. The earlier recovery wrapper's final error remains recorded;
it is not evidence that the delivered message failed. Do not replay recovery.

Production read-only inventory found no `cron.job`, zero queued/sending messages,
and zero reconciliation-required messages. The current repository has no send
scheduler workflow. This does not prove that no external scheduler exists;
the operator must confirm there is only one sending authority before activation.

This change prepares the missing timer for the existing canonical worker. It
does not create campaigns, select candidates, approve audiences, enqueue jobs,
rearm failures, change STOP/consent, change SQL/Edge code, or call Meta directly.
Admin must still preview, freeze, approve and queue the selected audience.
Approving a vacancy alone does not send a message.

## Four scoped files

- `.github/workflows/whatsapp-approved-queue.yml`
- `scripts/whatsapp/run-approved-queue.cjs`
- `tests/whatsapp/approved-queue.test.cjs`
- This release record.

The website allowlist excludes the server-side script and workflow. No frontend
or configuration file changes. No new package dependency is required.

## Bounds

- Installation is hard-disabled by `false &&` in the job condition, independently
  of any existing repository variable. Removing this lock requires a separate
  reviewed code change and activation approval; variable changes alone cannot send.
- Disabled unless repository variable `WHATSAPP_QUEUE_AUTOMATION_ENABLED` is exactly `true`.
- A strict UTC `WHATSAPP_QUEUE_APPROVED_FROM` / `WHATSAPP_QUEUE_APPROVED_UNTIL`
  interval is mandatory, at most one hour. Outside it, no network call occurs.
- Cron `2-57/5 * * * *`: one scheduled opportunity every five minutes.
- At most twelve successful preceding/current worker opportunities per window;
  the caller rejects a thirteenth. The existing worker handles at most one row.
- Only the exact repository, main-branch schedule event, first run attempt and
  immutable `WHATSAPP_QUEUE_APPROVED_SOURCE_SHA` are accepted.
- Failed/cancelled/unfinished prior schedule runs in the approved interval stop
  later sends. Missing, malformed, unavailable or truncated history fails closed.
- No manual-dispatch trigger and no automatic HTTP retries or redirects.
- Dedicated `WHATSAPP_WORKER_SECRET` only; no Meta token or Supabase database
  credential enters GitHub. The automatically supplied GITHUB_TOKEN has only
  contents/read and actions/read permissions.
- Fixed deployed worker endpoint; body is `{}`. No destination/batch override.
- Native worker failures and unknown outcomes latch later scheduled runs off.
- Failed or ambiguous outbox rows are never reset by this adapter.
- Expiring/disabling the GitHub timer does not change the Supabase sender secret.
  The operator must also restore `WHATSAPP_SENDER_ENABLED=false` after a pilot.

## Current contract limitation — before any real pilot

Read-only inspection of deployed `claim_whatsapp_outbound_batch` and
`mark_whatsapp_provider_call_started` confirms current consent checks at claim
and provider-start. Their bodies do not independently recheck vacancy closure
or whether an application was created after audience approval/queueing.
The inspected live `admin_queue_whatsapp_campaign` checks open requirement and
consent; the repository's historical prose describes broader checks than that
current live body. Do not infer stronger guarantees from that prose.

Unattended real campaigns remain BLOCKED pending a source-faithful local test
of cancellation/closed-vacancy/existing-application changes after queueing and
a reviewed correction if the intended contract requires stopping such sends.
This timer must not be used to hide or bypass that boundary. It can be installed
disabled and subsequently exercised with the Supabase sender still disabled.

## Local validation (not a live scheduled send)

Commands executed from repository root:

```sh
node --test tests/whatsapp/approved-queue.test.cjs
npm test
node scripts/build-production-artifact.js
node --test tests/production-artifact.test.js
git diff --check
```

- New focused tests: 35 PASS, 0 FAIL (including the installation lock).
- Existing complete frontend suite: 350 PASS, 0 FAIL.
- Artifact boundary tests: 6 PASS (also included in the frontend suite).
- Production artifact build and YAML parser: PASS.
- Tests use injected synthetic GitHub history/worker results, plus actual
  loopback HTTP for request shape, JSON response, redirect rejection and timeout.
- No claim that these local tests validate genuine GitHub Actions scheduling,
  environment secret delivery, live Meta sending or database concurrency.
- No Production/NONPROD writes, worker invocations, sends, pushes or deployments
  performed while preparing this change.

## Exact staged release procedure

1. Review only the four files and the resulting focused source commit. Obtain
   explicit approval to install the timer **disabled**, as required by AGENTS.md.
2. Push the reviewed source commit to `web-platform-development`. Record its full
   immutable SHA; this becomes `WHATSAPP_QUEUE_APPROVED_SOURCE_SHA`.
3. Add only the exact reviewed workflow file to `main` through a scoped reviewed
   change. Do not merge the application development branch into main. The workflow
   checks out the approved source SHA for its script. A development-branch-only
   workflow does not receive cron events.
4. Keep the repository enable variable `false` and Supabase sender `false`.
   Create the dedicated GitHub environment `whatsapp-production`, restricted to
   main, with suitable reviewers. Store the existing worker key there using the
   authenticated operator UI; never print it in chat or a shell command argument.
5. Set repository variables for the pinned source SHA and a reviewed future
   one-hour-or-shorter UTC window (`YYYY-MM-DDTHH:mm:ssZ`). These variables belong
   at repository level because the job-level condition uses them before entry
   into the environment.
6. With separate approval for a disabled-sender scheduling check, remove the
   workflow installation lock in a reviewed commit, then enable only the GitHub
   variable for that window. Confirm a genuine scheduled run emits
   `QUEUE_AUTOMATION=SENDER_DISABLED; SENT=0; FAILED=0`. Disable the variable again.
   If the environment requires review, the operator must approve that job; never
   remove protection merely to make scheduling pass.
7. Resolve the live contract limitation above and rehearse it locally before
   proposing any real campaign pilot. Review exact recipients, campaign, eligible
   vacancy, opt-in, costs and a bounded time window. Obtain explicit real-send
   approval. No bulk or permanent activation is included in disabled installation.
8. Before a future authorized pilot: no pending uncertain outcomes, only the
   reviewed queue, no other worker/scheduler, correct worker/template, and fresh
   source/runtime identity. Enable sender only during that reviewed window.
9. After pilot: disable GitHub variable and sender, verify delivered/callback,
   INTERESTED and STOP outcomes using read-only evidence. If a run fails, do not
   rerun it; reconcile provider/outbox state before authorizing another window.

GitHub schedules can be delayed or dropped and run on the default branch.
This is a bounded pilot timer, not an exact-time SLA or a high-volume sender.
Official scheduling reference:
https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule

## Stop procedure

Set GitHub `WHATSAPP_QUEUE_AUTOMATION_ENABLED=false` and Supabase
`WHATSAPP_SENDER_ENABLED=false`. Let an in-flight provider request resolve; do
not cancel/retry it to manufacture a known result. Read the outbox/provider
evidence before any further action. Do not delete failed rows or attempt locks.
