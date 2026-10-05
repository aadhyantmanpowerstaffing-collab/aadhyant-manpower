'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const { run, REPOSITORY, WORKER } = require('../../scripts/whatsapp/run-approved-queue.cjs');
const sha = 'a'.repeat(40);
const env = () => ({
  WHATSAPP_QUEUE_AUTOMATION_ENABLED: 'true', WHATSAPP_QUEUE_APPROVED_FROM: '2026-10-05T16:00:00Z',
  WHATSAPP_QUEUE_APPROVED_UNTIL: '2026-10-05T17:00:00Z', GITHUB_ACTIONS: 'true',
  GITHUB_REPOSITORY: REPOSITORY, GITHUB_REF: 'refs/heads/main', GITHUB_EVENT_NAME: 'schedule',
  GITHUB_RUN_ATTEMPT: '1', GITHUB_RUN_ID: '1000', WHATSAPP_QUEUE_APPROVED_SOURCE_SHA: sha,
  WHATSAPP_WORKER_SECRET: 'b'.repeat(64), GITHUB_TOKEN: 'synthetic-test-token'
});
const current = { id: 1000, created_at: '2026-10-05T16:10:00Z', status: 'in_progress', conclusion: null };
const good = { status: 'WORKER_COMPLETED', sent: 1, failed: 0 };
test('installed workflow is hard-disabled regardless of repository variables', () => {
  const workflow = fs.readFileSync('.github/workflows/whatsapp-approved-queue.yml', 'utf8');
  assert.match(workflow, /if: >-\s+false &&/);
  assert.doesNotMatch(workflow, /workflow_dispatch:/);
});
const make = (reply = good, prior = []) => {
  const calls = [];
  return { calls, dependencies: { clock: () => Date.parse('2026-10-05T16:10:30Z'), head: () => sha,
    fetcher: async (url, init) => { calls.push({ url, init });
      return new Response(JSON.stringify(url === WORKER ? reply : { workflow_runs: [current, ...prior] }), { status: 200 });
    }
  } };
};
test('default off performs zero network calls', async () => {
  const f = make(); assert.equal((await run({}, f.dependencies)).status, 'AUTOMATION_DISABLED'); assert.equal(f.calls.length, 0);
});
test('CLI defaults off without credentials', () => {
  const r = spawnSync(process.execPath, ['scripts/whatsapp/run-approved-queue.cjs'], { encoding: 'utf8', env: {} });
  assert.equal(r.status, 0); assert.match(r.stdout, /AUTOMATION_DISABLED/);
});
for (const [label, change] of [
  ['wrong repository', { GITHUB_REPOSITORY: 'someone/fork' }],
  ['wrong branch', { GITHUB_REF: 'refs/heads/web-platform-development' }],
  ['manual rerun', { GITHUB_RUN_ATTEMPT: '2' }],
  ['manual dispatch', { GITHUB_EVENT_NAME: 'workflow_dispatch' }],
  ['no pinned source', { WHATSAPP_QUEUE_APPROVED_SOURCE_SHA: 'main' }],
  ['no secret', { WHATSAPP_WORKER_SECRET: '' }],
  ['invalid timestamp', { WHATSAPP_QUEUE_APPROVED_FROM: 'tomorrow' }],
  ['oversized window', { WHATSAPP_QUEUE_APPROVED_UNTIL: '2026-10-06T17:00:00Z' }]
]) test(`${label}: zero network`, async () => {
  const f = make(); await assert.rejects(run({ ...env(), ...change }, f.dependencies)); assert.equal(f.calls.length, 0);
});
test('expired window performs zero network', async () => {
  const f = make(); f.dependencies.clock = () => Date.parse('2026-10-05T17:00:00Z');
  assert.equal((await run(env(), f.dependencies)).status, 'OUTSIDE_APPROVED_WINDOW'); assert.equal(f.calls.length, 0);
});
test('source mismatch performs zero network', async () => {
  const f = make(); f.dependencies.head = () => 'c'.repeat(40); await assert.rejects(run(env(), f.dependencies), /SOURCE_SHA_MISMATCH/); assert.equal(f.calls.length, 0);
});
test('one canonical request with exact body, endpoint and dedicated header', async () => {
  const f = make(); assert.deepEqual(await run(env(), f.dependencies), good); assert.equal(f.calls.length, 2);
  const c = f.calls[1]; assert.equal(c.url, WORKER); assert.equal(c.init.method, 'POST'); assert.equal(c.init.body, '{}');
  assert.equal(c.init.redirect, 'error'); assert.equal(c.init.headers['x-whatsapp-worker-key'], env().WHATSAPP_WORKER_SECRET);
  assert.equal(c.init.headers.authorization, undefined);
});
for (const conclusion of ['failure', 'cancelled', 'timed_out', null]) test(`prior ${conclusion} latches worker off`, async () => {
  const f = make(good, [{ id: 999, created_at: current.created_at, status: 'completed', conclusion }]);
  await assert.rejects(run(env(), f.dependencies), /PREVIOUS_RUN_NOT_SUCCESSFUL/); assert.equal(f.calls.length, 1);
});
test('failure before approved window does not block separately reviewed window', async () => {
  const f = make(good, [{ id: 999, created_at: '2026-10-04T16:00:00Z', status: 'completed', conclusion: 'failure' }]);
  assert.deepEqual(await run(env(), f.dependencies), good);
});
test('twelve prior runs exhaust pilot budget', async () => {
  const f = make(good, Array.from({ length: 12 }, (_, i) => ({ id: i + 1, created_at: current.created_at, status: 'completed', conclusion: 'success' })));
  await assert.rejects(run(env(), f.dependencies), /BUDGET_EXHAUSTED/); assert.equal(f.calls.length, 1);
});
test('window expiring during history lookup blocks worker', async () => {
  const f = make(); let n = 0; f.dependencies.clock = () => Date.parse(n++ ? '2026-10-05T17:00:00Z' : '2026-10-05T16:30:00Z');
  await assert.rejects(run(env(), f.dependencies), /WINDOW_EXPIRED_BEFORE_WORKER/); assert.equal(f.calls.length, 1);
});
for (const body of [
  { status: 'WORKER_COMPLETED', sent: 2, failed: 0 }, { status: 'WORKER_COMPLETED', sent: '1', failed: 0 },
  { status: 'SENDER_DISABLED', sent: 1, failed: 0 }, { status: 'WORKER_COMPLETED', sent: 0, failed: 1 },
  { ...good, leaked: 'synthetic-sensitive-value' }, null
]) test(`reject invalid/failure result ${JSON.stringify(body)}`, async () => {
  const f = make(body); await assert.rejects(run(env(), f.dependencies)); assert.equal(f.calls.length, 2);
});
test('disabled worker is explicit zero-send success', async () => {
  const reply = { status: 'SENDER_DISABLED', sent: 0, failed: 0 }; const f = make(reply);
  assert.deepEqual(await run(env(), f.dependencies), reply);
});
test('HTTP/transport/malformed errors never retry or expose raw responses', async t => {
  for (const kind of ['http', 'transport', 'json', 'redirect', 'timeout']) await t.test(kind, async () => {
    const f = make(); const original = f.dependencies.fetcher;
    f.dependencies.fetcher = async (url, init) => {
      if (url !== WORKER) return original(url, init);
      f.calls.push({ url, init });
      if (kind === 'http') return new Response('synthetic-sensitive-value', { status: 429 });
      if (kind === 'json') return new Response('synthetic-sensitive-value', { status: 200 });
      throw new Error('synthetic-sensitive-value');
    };
    await assert.rejects(run(env(), f.dependencies), error => !error.message.includes('synthetic-sensitive-value'));
    assert.equal(f.calls.length, 2);
  });
});
test('actual loopback HTTP: response parsing, body/header and redirects', async t => {
  const received = []; let mode = 'ok';
  const server = http.createServer(async (req, res) => {
    let body = ''; for await (const chunk of req) body += chunk;
    received.push({ path: req.url, body, headers: req.headers });
    if (mode === 'redirect') { res.writeHead(302, { location: '/must-not-follow' }); res.end(); return; }
    if (mode === 'timeout') return;
    res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(good));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); });
  for (const variant of ['ok', 'redirect', 'timeout']) {
    mode = variant; const f = make(); const original = f.dependencies.fetcher; f.dependencies.timeoutMs = 100;
    f.dependencies.fetcher = (url, init) => url === WORKER ? fetch(`http://127.0.0.1:${server.address().port}/worker`, init) : original(url, init);
    if (variant === 'ok') assert.deepEqual(await run(env(), f.dependencies), good);
    else await assert.rejects(run(env(), f.dependencies));
  }
  assert.equal(received.length, 3); assert.ok(received.every(r => r.path === '/worker' && r.body === '{}'));
  assert.equal(received[0].headers['x-whatsapp-worker-key'], env().WHATSAPP_WORKER_SECRET);
});
