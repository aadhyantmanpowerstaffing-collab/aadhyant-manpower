'use strict';

// Server-side schedule adapter only. All recipient selection and outbox state
// remain in the existing Admin RPCs / deployed worker. No Graph API calls.
const { execFileSync } = require('node:child_process');
const REPOSITORY = 'aadhyantmanpowerstaffing-collab/aadhyant-manpower';
const WORKFLOW = 'whatsapp-approved-queue.yml';
const WORKER = 'https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-outbox-worker';
class SafeFailure extends Error {}
const fail = code => { throw new SafeFailure(code); };
const timestamp = value => {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value)) fail('INVALID_WINDOW');
  const time = Date.parse(value);
  if (!Number.isFinite(time) || new Date(time).toISOString().replace('.000Z', 'Z') !== value) fail('INVALID_WINDOW');
  return time;
};

async function run(env = process.env, dependencies = {}) {
  // Missing configuration is an intentional no-network stop, including no GitHub call.
  if (env.WHATSAPP_QUEUE_AUTOMATION_ENABLED !== 'true') return { status: 'AUTOMATION_DISABLED', sent: 0, failed: 0 };
  const clock = dependencies.clock || Date.now;
  const now = clock();
  const start = timestamp(env.WHATSAPP_QUEUE_APPROVED_FROM);
  const end = timestamp(env.WHATSAPP_QUEUE_APPROVED_UNTIL);
  if (end <= start || end - start > 3600000) fail('WINDOW_MUST_BE_AT_MOST_ONE_HOUR');
  if (now < start || now >= end) return { status: 'OUTSIDE_APPROVED_WINDOW', sent: 0, failed: 0 };
  if (env.GITHUB_ACTIONS !== 'true' || env.GITHUB_REPOSITORY !== REPOSITORY ||
      env.GITHUB_REF !== 'refs/heads/main' || env.GITHUB_EVENT_NAME !== 'schedule' ||
      env.GITHUB_RUN_ATTEMPT !== '1' || !/^\d+$/.test(env.GITHUB_RUN_ID || '')) fail('UNAPPROVED_RUN_CONTEXT');
  if (!/^[a-f0-9]{40}$/.test(env.WHATSAPP_QUEUE_APPROVED_SOURCE_SHA || '')) fail('PINNED_SOURCE_REQUIRED');
  const actualSha = dependencies.head ? dependencies.head() : execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  if (actualSha !== env.WHATSAPP_QUEUE_APPROVED_SOURCE_SHA) fail('SOURCE_SHA_MISMATCH');
  if (!/^[a-f0-9]{64}$/.test(env.WHATSAPP_WORKER_SECRET || '') || !env.GITHUB_TOKEN) fail('CREDENTIAL_CONFIGURATION');
  const fetcher = dependencies.fetcher || fetch;
  const timeout = dependencies.timeoutMs ?? 45000;

  // A failure/ambiguous result in this approved window latches later runs off.
  // Never rerun a failed workflow; reconcile first, then separately approve a new window.
  let history;
  try {
    const response = await fetcher(`https://api.github.com/repos/${REPOSITORY}/actions/workflows/${WORKFLOW}/runs?per_page=100&event=schedule`, {
      method: 'GET', redirect: 'error', signal: AbortSignal.timeout(timeout),
      headers: { authorization: `Bearer ${env.GITHUB_TOKEN}`, accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' }
    });
    if (response.status !== 200) fail('HISTORY_HTTP_FAILURE');
    history = await response.json();
  } catch (error) {
    if (error instanceof SafeFailure) throw error;
    fail('HISTORY_UNAVAILABLE');
  }
  if (!history || !Array.isArray(history.workflow_runs) || history.workflow_runs.length > 100) fail('HISTORY_MALFORMED');
  const runs = history.workflow_runs;
  if (!runs.some(r => String(r.id) === env.GITHUB_RUN_ID)) fail('CURRENT_RUN_NOT_IN_HISTORY');
  if (runs.some(r => !Number.isSafeInteger(r.id) || !Number.isFinite(Date.parse(r.created_at)))) fail('HISTORY_MALFORMED');
  if (runs.length === 100 && runs.every(r => Date.parse(r.created_at) >= start)) fail('HISTORY_TRUNCATED');
  const previous = runs.filter(r => String(r.id) !== env.GITHUB_RUN_ID && Date.parse(r.created_at) >= start);
  if (previous.some(r => r.status !== 'completed' || r.conclusion !== 'success')) fail('PREVIOUS_RUN_NOT_SUCCESSFUL');
  if (previous.length >= 12) fail('PILOT_RUN_BUDGET_EXHAUSTED');
  const current = runs.find(r => String(r.id) === env.GITHUB_RUN_ID);
  if (Date.parse(current.created_at) < start || Date.parse(current.created_at) >= end) fail('RUN_CREATED_OUTSIDE_WINDOW');
  if (clock() >= end) fail('WINDOW_EXPIRED_BEFORE_WORKER');

  let body;
  try {
    // One attempt only: no redirect, retry, destination, template or batch override.
    const response = await fetcher(WORKER, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(timeout),
      headers: { 'content-type': 'application/json', 'x-whatsapp-worker-key': env.WHATSAPP_WORKER_SECRET }, body: '{}'
    });
    if (response.status !== 200) fail('WORKER_HTTP_FAILURE_RECONCILE');
    body = await response.json();
  } catch (error) {
    if (error instanceof SafeFailure) throw error;
    fail('WORKER_OUTCOME_UNKNOWN_RECONCILE');
  }
  if (!body || Array.isArray(body) || Object.keys(body).sort().join(',') !== 'failed,sent,status' ||
      !Number.isInteger(body.sent) || !Number.isInteger(body.failed) || body.sent < 0 || body.failed < 0 ||
      body.sent + body.failed > 1) fail('WORKER_REPLY_INVALID_RECONCILE');
  if (body.status === 'SENDER_DISABLED' && body.sent === 0 && body.failed === 0) return body;
  if (body.status !== 'WORKER_COMPLETED') fail('WORKER_REPLY_INVALID_RECONCILE');
  if (body.failed !== 0) fail('PROVIDER_FAILURE_RECONCILE');
  return body;
}

module.exports = { run, SafeFailure, REPOSITORY, WORKER };
if (require.main === module) {
  run().then(result => {
    console.log(`QUEUE_AUTOMATION=${result.status}; SENT=${result.sent}; FAILED=${result.failed}`);
  }).catch(error => {
    console.error(`QUEUE_AUTOMATION=${error instanceof SafeFailure ? error.message : 'LOCAL_FAILURE'}; NO_RETRY`);
    process.exitCode = 1;
  });
}
