'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const {
  DIST_ROOT,
  EXPECTED_ARTIFACT_PATHS,
  PRODUCTION_BINDING,
  SOURCE_RUNTIME_FILES,
  assertAllowedPath,
  assertContentSafe,
  buildArtifact,
  verifyArtifact
} = require('../scripts/build-production-artifact.js');

const REQUIRED_ROUTES = Object.freeze([
  '/',
  '/jobs/',
  '/candidate/',
  '/candidate/register/',
  '/hire-manpower/',
  '/hire-manpower/requirement/',
  '/staffing-partner/',
  '/about/',
  '/services/',
  '/industries/',
  '/contact/',
  '/privacy/',
  '/terms/',
  '/data-deletion/',
  '/candidate/portal/',
  '/candidate/portal/login.html',
  '/company/',
  '/company/login.html',
  '/contractor/',
  '/contractor/login.html',
  '/admin/',
  '/admin/login.html'
]);

const ALL_HTML_ROUTES = Object.freeze(SOURCE_RUNTIME_FILES
  .filter((item) => item.endsWith('.html'))
  .map((item) => item === 'index.html' ? '/' : `/${item}`.replace(/\/index\.html$/, '/'))
  .sort());

const PROHIBITED_HTTP_PATHS = Object.freeze([
  '/supabase/schema.sql',
  '/supabase/migrations/029_whatsapp_interested_applications.sql',
  '/supabase/tests/',
  '/AGENTS.md',
  '/PRODUCTION_READINESS.md',
  '/WEB_PLATFORM_SCHEMA.md',
  '/SUPABASE_SETUP.md',
  '/tests/',
  '/scripts/'
]);

function hashTree() {
  return EXPECTED_ARTIFACT_PATHS.map((relativePath) => {
    const bytes = fs.readFileSync(path.join(DIST_ROOT, relativePath));
    return `${relativePath}\0${bytes.length}\0${crypto.createHash('sha256').update(bytes).digest('hex')}`;
  }).join('\n');
}

function artifactServer() {
  return http.createServer((request, response) => {
    let pathname;
    try {
      pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    } catch (_error) {
      response.writeHead(400).end('Bad request');
      return;
    }
    let relativePath = pathname.replace(/^\/+/, '');
    if (!relativePath || relativePath.endsWith('/')) relativePath += 'index.html';
    const absolute = path.resolve(DIST_ROOT, relativePath);
    const safePrefix = `${path.resolve(DIST_ROOT)}${path.sep}`;
    if (!absolute.startsWith(safePrefix) || !fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' }).end('Not found');
      return;
    }
    const extension = path.extname(absolute).toLowerCase();
    const contentType = extension === '.html' ? 'text/html; charset=utf-8'
      : extension === '.css' ? 'text/css; charset=utf-8'
        : extension === '.js' ? 'text/javascript; charset=utf-8'
          : extension === '.svg' ? 'image/svg+xml' : 'application/octet-stream';
    response.writeHead(200, { 'content-type': contentType }).end(fs.readFileSync(absolute));
  });
}

async function listen(server) {
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  return `http://127.0.0.1:${server.address().port}`;
}

async function close(server) {
  await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
}

test('builder creates the exact allowlisted deterministic artifact', () => {
  const first = buildArtifact();
  const firstTree = hashTree();
  const second = buildArtifact();
  const secondTree = hashTree();
  assert.deepEqual(second, first);
  assert.equal(secondTree, firstTree);
  assert.equal(first.payloadFileCount, SOURCE_RUNTIME_FILES.length + 1);
  assert.equal(first.artifactFileCount, EXPECTED_ARTIFACT_PATHS.length);
  assert.equal(first.paths.length, new Set(first.paths.map((item) => item.toLowerCase())).size);
});

test('manifest verification rejects prohibited path and credential-shaped content classes', () => {
  for (const prohibited of [
    'supabase/schema.sql', 'tests/example.js', 'scripts/deploy.ps1', 'AGENTS.md',
    'WEB_PLATFORM_SCHEMA.md', '.env.production', '.git/config', 'assets/app.js.map'
  ]) {
    assert.throws(() => assertAllowedPath(prohibited));
  }
  for (const [name, content] of [
    ['NONPROD ref', 'zrluniaccvcdrvfwgrmj'],
    ['loopback', 'http://127.0.0.1:4173'],
    ['synthetic identity', 'operator@test.invalid'],
    ['secret key', 'sb_secret_abcdefghijklmnopqrstuvwxyz'],
    ['private key', '-----BEGIN PRIVATE KEY-----'],
    ['SQL', 'create table public.private_data(id uuid);']
  ]) {
    assert.throws(() => assertContentSafe('probe.js', Buffer.from(content)), name);
  }
  assert.doesNotThrow(() => assertContentSafe('config.js', Buffer.from(
    `supabasePublishableKey: 'sb_publishable_abcdefghijklmnopqrstuvwxyz'; supabaseUrl: '${PRODUCTION_BINDING.supabaseUrl}';`
  )));
});

test('dist inventory contains no unexpected, internal, or source-only files', () => {
  const result = verifyArtifact();
  assert.deepEqual(result.paths, EXPECTED_ARTIFACT_PATHS);
  assert.ok(result.paths.includes('CNAME'));
  assert.ok(result.paths.includes('artifact-manifest.json'));
  assert.ok(!result.paths.includes('assets/js/reference-data.js'));
  assert.ok(!result.paths.some((item) => /(?:^|\/)(?:supabase|tests|scripts)(?:\/|$)/i.test(item)));
  assert.ok(!result.paths.some((item) => /\.(?:md|sql|ps1|ts|map|log)$/i.test(item)));
});

test('generated config is production-bound and loopback serving cannot initialize Supabase', () => {
  const config = fs.readFileSync(path.join(DIST_ROOT, 'config.js'), 'utf8');
  const client = fs.readFileSync(path.join(DIST_ROOT, 'supabase-client.js'), 'utf8');
  assert.match(config, /environment: "production"/);
  assert.match(config, /expectedOrigin: "https:\/\/aadhyantmanpower\.in"/);
  assert.match(config, /supabaseProjectRef: "wsuctjhbqiedttfnwjvf"/);
  assert.match(config, /supabaseUrl: "https:\/\/wsuctjhbqiedttfnwjvf\.supabase\.co"/);
  assert.match(config, /supabasePublishableKey: "sb_publishable_/);
  assert.doesNotMatch(config, /zrluniaccvcdrvfwgrmj|127\.0\.0\.1|localhost|test\.invalid|sb_secret_|service[_-]?role/i);
  assert.match(client, /window\.location\.origin === config\.expectedOrigin/);
  assert.match(client, /\|\| !expectedOriginMatches/);

  let loopbackCreateCalls = 0;
  const loopbackWindow = {
    location: { origin: 'http://127.0.0.1:4173', pathname: '/candidate/portal/' },
    supabase: { createClient: () => { loopbackCreateCalls += 1; } }
  };
  vm.runInNewContext(config, { window: loopbackWindow });
  vm.runInNewContext(client, { window: loopbackWindow });
  assert.equal(loopbackCreateCalls, 0);
  assert.equal(loopbackWindow.aadhyantSupabase.isConfigured, false);

  let productionCreateCalls = 0;
  const productionWindow = {
    location: { origin: PRODUCTION_BINDING.expectedOrigin, pathname: '/candidate/portal/' },
    supabase: { createClient: () => { productionCreateCalls += 1; return {}; } }
  };
  vm.runInNewContext(config, { window: productionWindow });
  vm.runInNewContext(client, { window: productionWindow });
  assert.equal(productionCreateCalls, 1);
  assert.equal(productionWindow.aadhyantSupabase.isConfigured, true);
});

test('loopback server serves every runtime route and returns 404 for internal paths', async (t) => {
  const server = artifactServer();
  const origin = await listen(server);
  t.after(() => close(server));

  const runtimeRoutes = [...new Set([...ALL_HTML_ROUTES, ...REQUIRED_ROUTES])].sort();
  assert.equal(ALL_HTML_ROUTES.length, 43);
  for (const route of runtimeRoutes) {
    const response = await fetch(`${origin}${route}`);
    assert.equal(response.status, 200, route);
    assert.match(response.headers.get('content-type') || '', /^text\/html/, route);
  }
  for (const route of PROHIBITED_HTTP_PATHS) {
    const response = await fetch(`${origin}${route}`);
    assert.equal(response.status, 404, route);
  }
});

test('workflow is manual-only, least-privilege, SHA-pinned, and uploads dist only', () => {
  const workflow = fs.readFileSync(path.join(__dirname, '..', '.github', 'workflows', 'pages-production.yml'), 'utf8');
  assert.match(workflow, /^\s*workflow_dispatch:/m);
  assert.doesNotMatch(workflow, /^\s*(?:push|schedule):/m);
  assert.match(workflow, /^permissions:\s*\n\s+contents: read/m);
  assert.match(workflow, /path: dist/);
  assert.doesNotMatch(workflow, /path:\s*[.'"]?\s*$/m);
  assert.match(workflow, /inputs\.deploy_production == true/);
  assert.match(workflow, /github\.ref == 'refs\/heads\/web-platform-development'/);
  assert.match(workflow, /environment:\s*\n\s+name: github-pages/m);
  assert.match(workflow, /permissions:\s*\n\s+pages: write\s*\n\s+id-token: write/m);
  assert.doesNotMatch(workflow, /@[vV]\d/);
  assert.doesNotMatch(workflow, /supabase|migration|edge|meta|whatsapp|secret/i);
});
