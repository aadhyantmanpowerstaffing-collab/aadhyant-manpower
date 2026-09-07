'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const REPOSITORY_ROOT = path.resolve(__dirname, '..');
const DIST_ROOT = path.join(REPOSITORY_ROOT, 'dist');
const FIXED_TIMESTAMP = new Date('2000-01-01T00:00:00.000Z');
const PINNED_SUPABASE_JS = Object.freeze({
  version: '2.112.4',
  integrity: 'sha384-yiVMs0R/Jyz7OhoXa/DsEMUSBLjEhr/QJta2ONO+zB6I8/GmNg/7AUFrZmAJV7KV'
});
const MANIFEST_PATH = 'artifact-manifest.json';
const DIGEST_PATH = 'artifact-digest.sha256';

const PRODUCTION_BINDING = Object.freeze({
  environment: 'production',
  expectedOrigin: 'https://aadhyantmanpower.in',
  supabaseProjectRef: 'wsuctjhbqiedttfnwjvf',
  supabaseUrl: 'https://wsuctjhbqiedttfnwjvf.supabase.co'
});

// This is deliberately a file-by-file allowlist. Do not replace it with a glob,
// directory copy, or a repository-root copy.
const SOURCE_RUNTIME_FILES = Object.freeze([
  'CNAME',
  'index.html',
  'style.css',
  'script.js',
  'supabase-client.js',
  'about/index.html',
  'admin/admin-auth.js',
  'admin/admin-product.js',
  'admin/admin.css',
  'admin/admin.js',
  'admin/index.html',
  'admin/login.html',
  'admin/recruitment-operations.js',
  'admin/staff-management.js',
  'admin/vacancy-review.css',
  'admin/vacancy-review.js',
  'admin/whatsapp-campaigns.js',
  'assets/css/public.css',
  'assets/favicon.svg',
  'assets/js/jobs.js',
  'assets/js/legal-consent.js',
  'assets/js/public-navigation.js',
  'assets/js/registration-options.js',
  'candidate/index.html',
  'candidate/portal/applications.html',
  'candidate/portal/batch2-jobs.css',
  'candidate/portal/batch2-jobs.js',
  'candidate/portal/candidate.css',
  'candidate/portal/candidate.js',
  'candidate/portal/documents.html',
  'candidate/portal/index.html',
  'candidate/portal/interviews.html',
  'candidate/portal/jobs.html',
  'candidate/portal/joinings.html',
  'candidate/portal/login.html',
  'candidate/portal/onboarding.html',
  'candidate/portal/profile.html',
  'candidate/portal/register.html',
  'candidate/register/index.html',
  'company/applications.html',
  'company/batch2-vacancies.css',
  'company/batch2-vacancies.js',
  'company/company.css',
  'company/company.js',
  'company/index.html',
  'company/interviews.html',
  'company/joinings.html',
  'company/login.html',
  'company/profile.html',
  'company/register.html',
  'company/requirements.html',
  'contact/index.html',
  'contractor/applications.html',
  'contractor/assignments.html',
  'contractor/batch2-vacancies.css',
  'contractor/batch2-vacancies.js',
  'contractor/contractor.css',
  'contractor/contractor.js',
  'contractor/index.html',
  'contractor/interviews.html',
  'contractor/joinings.html',
  'contractor/login.html',
  'contractor/profile.html',
  'contractor/register.html',
  'contractor/vacancies.html',
  'data-deletion/index.html',
  'hire-manpower/index.html',
  'hire-manpower/requirement/index.html',
  'industries/index.html',
  'jobs/index.html',
  'privacy/index.html',
  'services/index.html',
  'staffing-partner/index.html',
  'terms/index.html'
]);

const GENERATED_RUNTIME_FILES = Object.freeze(['config.js']);
const PAYLOAD_PATHS = Object.freeze([...SOURCE_RUNTIME_FILES, ...GENERATED_RUNTIME_FILES].sort(comparePaths));
const METADATA_PATHS = Object.freeze([DIGEST_PATH, MANIFEST_PATH].sort(comparePaths));
const EXPECTED_ARTIFACT_PATHS = Object.freeze([...PAYLOAD_PATHS, ...METADATA_PATHS].sort(comparePaths));

const PROHIBITED_EXACT_BASENAMES = new Set([
  'agents.md',
  'package.json',
  'package-lock.json',
  'production_readiness.md',
  'public_website_product_phase.md',
  'supabase_setup.md',
  'web_platform_schema.md'
]);
const PROHIBITED_SEGMENTS = new Set([
  '.git', '.github', 'node_modules', 'scripts', 'supabase', 'tests'
]);
const PROHIBITED_EXTENSIONS = new Set([
  '.bak', '.db', '.env', '.log', '.map', '.md', '.pem', '.ps1', '.py', '.sql', '.tmp', '.ts'
]);
const SENSITIVE_CONTENT_PATTERNS = Object.freeze([
  { name: 'NONPROD project reference', pattern: /zrluniaccvcdrvfwgrmj/i },
  { name: 'NONPROD marker', pattern: /\bNONPROD(?:UCTION)?\b/i },
  { name: 'loopback URL or host', pattern: /(?:https?:\/\/)?(?:127\.0\.0\.1|localhost|\[?::1\]?)(?::\d+)?/i },
  { name: 'synthetic identity', pattern: /test\.invalid/i },
  { name: 'private key', pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/ },
  { name: 'Supabase secret key', pattern: /\bsb_secret_[A-Za-z0-9_-]{12,}\b/ },
  { name: 'JWT-shaped credential', pattern: /\beyJ[A-Za-z0-9_-]{12,}\.eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{10,}\b/ },
  { name: 'service-role credential assignment', pattern: /(?:service[_-]?role|SUPABASE_SERVICE_ROLE_KEY)\s*[:=]\s*['"][^'"]{8,}['"]/i },
  { name: 'password literal assignment', pattern: /\bpassword\s*[:=]\s*['"][^'"]{8,}['"]/i },
  { name: 'credential-bearing database URL', pattern: /postgres(?:ql)?:\/\/[^\s:@/]+:[^\s@/]+@/i },
  { name: 'DPAPI/local Auth artifact', pattern: /(?:DPAPI|\.env\.admin-auth\.local)/i },
  { name: 'internal SQL statement', pattern: /\b(?:create|alter|drop)\s+(?:table|function|policy|schema)\b/i },
  {
    name: 'raw Aadhaar-shaped value',
    pattern: /\b\d{4}[ -]?\d{4}[ -]?\d{4}\b/g,
    allowMatch: (value) => value.replace(/\D/g, '') === '919586785800'
  },
  { name: 'literal UUID fixture', pattern: /\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/i }
]);

function comparePaths(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function getReleaseRevision() {
  return 'production';
}

function productionCspMeta() {
  return '<meta http-equiv="Content-Security-Policy" content="default-src \'self\'; base-uri \'self\'; object-src \'none\'; frame-ancestors \'none\'; form-action \'self\'; script-src \'self\' https://cdn.jsdelivr.net; style-src \'self\' \'unsafe-inline\'; img-src \'self\' data: blob:; font-src \'self\'; connect-src \'self\' https://wsuctjhbqiedttfnwjvf.supabase.co wss://wsuctjhbqiedttfnwjvf.supabase.co;">';
}

function transformRuntimeHtml(sourcePath, content, releaseRevision) {
  let transformed = content;
  if (!transformed.includes('Content-Security-Policy')) {
    transformed = transformed.replace(/<meta\s+charset="[^"]+">/i, (match) => `${match}\n  ${productionCspMeta()}`);
  }
  if (/^(?:admin\/|candidate\/portal\/|company\/|contractor\/)/i.test(sourcePath)
      && !/<meta\s+name="robots"/i.test(transformed)) {
    transformed = transformed.replace(/<meta\s+charset="[^"]+">/i, (match) => `${match}\n  <meta name="robots" content="noindex,nofollow">`);
  }
  transformed = transformed.replace(/(src="(?:\.\.\/)*config\.js)("\s+defer)?/gi, `$1?rev=${releaseRevision}$2`);
  transformed = transformed.replace(/(src="(?:\.\.\/)*config\.js)(")/gi, `$1?rev=${releaseRevision}$2`);
  return transformed;
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

function fail(message) {
  throw new Error(message);
}

function assertSafeDistRoot() {
  const expected = path.resolve(REPOSITORY_ROOT, 'dist');
  if (DIST_ROOT !== expected || path.dirname(DIST_ROOT) !== REPOSITORY_ROOT || path.basename(DIST_ROOT) !== 'dist') {
    fail(`Refusing unsafe artifact path: ${DIST_ROOT}`);
  }
}

function assertUniqueCaseInsensitive(paths, label) {
  const seen = new Map();
  for (const item of paths) {
    const normalized = item.normalize('NFC').toLowerCase();
    const prior = seen.get(normalized);
    if (prior) fail(`${label} case collision: ${prior} and ${item}`);
    seen.set(normalized, item);
  }
}

function assertAllowedPath(relativePath) {
  const normalized = toPosix(relativePath).replace(/^\.\//, '');
  const lower = normalized.toLowerCase();
  const segments = lower.split('/');
  const basename = segments.at(-1);
  const extension = path.posix.extname(lower);

  if (!normalized || normalized.startsWith('/') || normalized.includes('..')) {
    fail(`Unsafe artifact path: ${relativePath}`);
  }
  if (segments.some((segment) => PROHIBITED_SEGMENTS.has(segment))) {
    fail(`Prohibited directory in artifact path: ${relativePath}`);
  }
  if (segments.some((segment) => segment.startsWith('.git') || segment.startsWith('.env'))) {
    fail(`Prohibited hidden configuration in artifact path: ${relativePath}`);
  }
  if (PROHIBITED_EXACT_BASENAMES.has(basename)
      || /^w7.*\.md$/i.test(basename)
      || /^web_platform_.*\.md$/i.test(basename)
      || /^post_w7c.*\.md$/i.test(basename)) {
    fail(`Prohibited internal filename in artifact path: ${relativePath}`);
  }
  if (PROHIBITED_EXTENSIONS.has(extension)) {
    fail(`Prohibited extension in artifact path: ${relativePath}`);
  }
}

function listFiles(root) {
  const files = [];
  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => comparePaths(a.name, b.name))) {
      const absolute = path.join(current, entry.name);
      const relative = toPosix(path.relative(root, absolute));
      if (entry.isSymbolicLink()) fail(`Symbolic links are not allowed in the artifact: ${relative}`);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.isFile()) files.push(relative);
      else fail(`Unsupported artifact entry: ${relative}`);
    }
  }
  walk(root);
  return files.sort(comparePaths);
}

function listRepositoryHtml() {
  const ignoredRoots = new Set(['.git', '.github', 'dist', 'dist-staging', 'node_modules', 'scripts', 'supabase', 'tests']);
  const files = [];
  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true }).sort((a, b) => comparePaths(a.name, b.name))) {
      if (current === REPOSITORY_ROOT && ignoredRoots.has(entry.name)) continue;
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else if (entry.isFile() && entry.name.toLowerCase().endsWith('.html')) {
        files.push(toPosix(path.relative(REPOSITORY_ROOT, absolute)));
      }
    }
  }
  walk(REPOSITORY_ROOT);
  return files.sort(comparePaths);
}

function readProductionPublishableKey() {
  const sourcePath = path.join(REPOSITORY_ROOT, 'config.js');
  const source = fs.readFileSync(sourcePath, 'utf8');
  const urlMatches = [...source.matchAll(/supabaseUrl\s*:\s*['"]([^'"]+)['"]/g)].map((match) => match[1]);
  const keyMatches = [...source.matchAll(/supabasePublishableKey\s*:\s*['"]([^'"]+)['"]/g)].map((match) => match[1]);
  if (urlMatches.length !== 1 || urlMatches[0] !== PRODUCTION_BINDING.supabaseUrl) {
    fail('Tracked browser config does not contain exactly the approved production Supabase URL');
  }
  if (keyMatches.length !== 1 || !/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(keyMatches[0])) {
    fail('Tracked browser config does not contain exactly one browser publishable key');
  }
  if (/sb_secret_|service[_-]?role\s*[:=]|zrluniaccvcdrvfwgrmj|test\.invalid|127\.0\.0\.1|localhost/i.test(source)) {
    fail('Tracked browser config contains prohibited secret, NONPROD, synthetic, or loopback material');
  }
  return keyMatches[0];
}

function renderProductionConfig(publishableKey) {
  const values = { ...PRODUCTION_BINDING, releaseRevision: getReleaseRevision(), supabasePublishableKey: publishableKey };
  return [
    '// Generated by scripts/build-production-artifact.js. Browser-publishable configuration only.',
    '// P0-E may strengthen release/cache binding; never add privileged or secret material here.',
    'window.AADHYANT_CONFIG = Object.freeze({',
    `  environment: ${JSON.stringify(values.environment)},`,
    `  expectedOrigin: ${JSON.stringify(values.expectedOrigin)},`,
    `  releaseRevision: ${JSON.stringify(values.releaseRevision)},`,
    '  sensitiveIntakeEnabled: false,',
    `  supabaseProjectRef: ${JSON.stringify(values.supabaseProjectRef)},`,
    `  supabaseUrl: ${JSON.stringify(values.supabaseUrl)},`,
    `  supabasePublishableKey: ${JSON.stringify(values.supabasePublishableKey)}`,
    '});',
    ''
  ].join('\n');
}

function assertSourceInventory() {
  assertUniqueCaseInsensitive([...PAYLOAD_PATHS, ...METADATA_PATHS], 'Artifact path');
  const sourceSet = new Set(SOURCE_RUNTIME_FILES);
  const repositoryHtml = listRepositoryHtml();
  const allowlistedHtml = SOURCE_RUNTIME_FILES.filter((item) => item.endsWith('.html')).sort(comparePaths);
  if (JSON.stringify(repositoryHtml) !== JSON.stringify(allowlistedHtml)) {
    const missing = repositoryHtml.filter((item) => !sourceSet.has(item));
    const stale = allowlistedHtml.filter((item) => !repositoryHtml.includes(item));
    fail(`HTML allowlist mismatch; unlisted=${missing.join(',') || 'none'} stale=${stale.join(',') || 'none'}`);
  }

  for (const relativePath of SOURCE_RUNTIME_FILES) {
    assertAllowedPath(relativePath);
    const absolute = path.join(REPOSITORY_ROOT, relativePath);
    if (!fs.existsSync(absolute) || !fs.statSync(absolute).isFile()) {
      fail(`Missing required runtime source: ${relativePath}`);
    }
    if (fs.lstatSync(absolute).isSymbolicLink()) fail(`Runtime source must not be a symlink: ${relativePath}`);
    if (relativePath.endsWith('.html')) {
      const html = fs.readFileSync(absolute, 'utf8');
      const pinned = `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@${PINNED_SUPABASE_JS.version}`;
      if (html.includes('supabase-js') && (!html.includes(pinned) || !html.includes(`integrity="${PINNED_SUPABASE_JS.integrity}"`) || !html.includes('crossorigin="anonymous"'))) {
        fail(`Unpinned or unverifiable Supabase browser dependency: ${relativePath}`);
      }
      if (html.includes('supabase-js@2"')) fail(`Floating Supabase browser dependency: ${relativePath}`);
    }
  }

  const cname = fs.readFileSync(path.join(REPOSITORY_ROOT, 'CNAME'), 'utf8').trim();
  if (cname !== 'aadhyantmanpower.in') fail(`Unexpected CNAME value: ${cname}`);
}

function normalizeLocalReference(sourcePath, reference) {
  if (!reference || /^(?:mailto:|tel:|javascript:|data:|#)/i.test(reference)) return null;
  const sourceDirectory = path.posix.dirname(`/${sourcePath}`).replace(/\/$/, '');
  const base = new URL(`${PRODUCTION_BINDING.expectedOrigin}${sourceDirectory}/`);
  const resolved = new URL(reference, base);
  if (resolved.origin !== PRODUCTION_BINDING.expectedOrigin) return null;
  let pathname = decodeURIComponent(resolved.pathname).replace(/^\/+/, '');
  if (!pathname || pathname.endsWith('/')) pathname += 'index.html';
  else if (!path.posix.extname(pathname)) pathname += '/index.html';
  return pathname;
}

function assertHtmlDependencies(payloadSet) {
  for (const sourcePath of SOURCE_RUNTIME_FILES.filter((item) => item.endsWith('.html'))) {
    const html = fs.readFileSync(path.join(REPOSITORY_ROOT, sourcePath), 'utf8');
    const references = [...html.matchAll(/\b(?:href|src)\s*=\s*['"]([^'"]+)['"]/gi)].map((match) => match[1]);
    for (const reference of references) {
      const localPath = normalizeLocalReference(sourcePath, reference);
      if (localPath && !payloadSet.has(localPath)) {
        fail(`Unallowlisted local dependency from ${sourcePath}: ${reference} -> ${localPath}`);
      }
    }
  }
}

function assertContentSafe(relativePath, buffer) {
  const extension = path.posix.extname(relativePath).toLowerCase();
  const isText = extension === '.html' || extension === '.css' || extension === '.js'
    || extension === '.svg' || extension === '.json' || extension === '.sha256' || relativePath === 'CNAME';
  if (!isText) return;
  const content = buffer.toString('utf8');
  for (const finding of SENSITIVE_CONTENT_PATTERNS) {
    finding.pattern.lastIndex = 0;
    let match;
    while ((match = finding.pattern.exec(content))) {
      if (!finding.allowMatch || !finding.allowMatch(match[0])) {
        fail(`${finding.name} found in artifact file: ${relativePath}`);
      }
      if (!finding.pattern.global) break;
    }
  }
}

function payloadEntries() {
  return PAYLOAD_PATHS.map((relativePath) => {
    const buffer = fs.readFileSync(path.join(DIST_ROOT, relativePath));
    assertAllowedPath(relativePath);
    assertContentSafe(relativePath, buffer);
    return { path: relativePath, bytes: buffer.length, sha256: sha256(buffer) };
  });
}

function aggregatePayload(entries) {
  const canonical = entries.map((entry) => `${entry.path}\0${entry.bytes}\0${entry.sha256}\n`).join('');
  return sha256(Buffer.from(canonical, 'utf8'));
}

function writeManifest() {
  const files = payloadEntries();
  const manifest = {
    schemaVersion: 1,
    target: PRODUCTION_BINDING,
    metadataFiles: METADATA_PATHS,
    payloadFileCount: files.length,
    payloadTotalBytes: files.reduce((total, item) => total + item.bytes, 0),
    aggregatePayloadSha256: aggregatePayload(files),
    files
  };
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  fs.writeFileSync(path.join(DIST_ROOT, MANIFEST_PATH), manifestBytes, { mode: 0o644 });
  const artifactDigest = sha256(manifestBytes);
  fs.writeFileSync(path.join(DIST_ROOT, DIGEST_PATH), `${artifactDigest}  ${MANIFEST_PATH}\n`, { mode: 0o644 });
  return artifactDigest;
}

function normalizeArtifactMetadata() {
  const directories = [];
  function walk(current) {
    directories.push(current);
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const absolute = path.join(current, entry.name);
      if (entry.isDirectory()) walk(absolute);
      else {
        fs.chmodSync(absolute, 0o644);
        fs.utimesSync(absolute, FIXED_TIMESTAMP, FIXED_TIMESTAMP);
      }
    }
  }
  walk(DIST_ROOT);
  directories.sort((a, b) => b.length - a.length);
  for (const directory of directories) {
    fs.chmodSync(directory, 0o755);
    fs.utimesSync(directory, FIXED_TIMESTAMP, FIXED_TIMESTAMP);
  }
}

function verifyArtifact() {
  assertSafeDistRoot();
  if (!fs.existsSync(DIST_ROOT) || !fs.statSync(DIST_ROOT).isDirectory()) fail('dist/ does not exist');
  const actualPaths = listFiles(DIST_ROOT);
  assertUniqueCaseInsensitive(actualPaths, 'dist path');
  if (JSON.stringify(actualPaths) !== JSON.stringify(EXPECTED_ARTIFACT_PATHS)) {
    const unexpected = actualPaths.filter((item) => !EXPECTED_ARTIFACT_PATHS.includes(item));
    const missing = EXPECTED_ARTIFACT_PATHS.filter((item) => !actualPaths.includes(item));
    fail(`Artifact inventory mismatch; unexpected=${unexpected.join(',') || 'none'} missing=${missing.join(',') || 'none'}`);
  }
  for (const relativePath of actualPaths) assertAllowedPath(relativePath);

  const manifestBytes = fs.readFileSync(path.join(DIST_ROOT, MANIFEST_PATH));
  const manifest = JSON.parse(manifestBytes.toString('utf8'));
  const digestLine = fs.readFileSync(path.join(DIST_ROOT, DIGEST_PATH), 'utf8').trim();
  const expectedDigestLine = `${sha256(manifestBytes)}  ${MANIFEST_PATH}`;
  if (digestLine !== expectedDigestLine) fail('Artifact manifest digest mismatch');
  if (JSON.stringify(manifest.target) !== JSON.stringify(PRODUCTION_BINDING)) fail('Artifact target binding mismatch');
  if (JSON.stringify(manifest.metadataFiles) !== JSON.stringify(METADATA_PATHS)) fail('Artifact metadata inventory mismatch');

  const entries = payloadEntries();
  if (JSON.stringify(entries) !== JSON.stringify(manifest.files)) fail('Artifact file hash manifest mismatch');
  if (manifest.payloadFileCount !== entries.length) fail('Artifact file count mismatch');
  if (manifest.payloadTotalBytes !== entries.reduce((total, item) => total + item.bytes, 0)) fail('Artifact byte count mismatch');
  if (manifest.aggregatePayloadSha256 !== aggregatePayload(entries)) fail('Artifact payload digest mismatch');

  const payloadSet = new Set(PAYLOAD_PATHS);
  assertHtmlDependencies(payloadSet);
  const config = fs.readFileSync(path.join(DIST_ROOT, 'config.js'), 'utf8');
  if (!config.includes(`expectedOrigin: ${JSON.stringify(PRODUCTION_BINDING.expectedOrigin)}`)
      || !config.includes(`supabaseProjectRef: ${JSON.stringify(PRODUCTION_BINDING.supabaseProjectRef)}`)
      || !config.includes(`supabaseUrl: ${JSON.stringify(PRODUCTION_BINDING.supabaseUrl)}`)) {
    fail('Generated production config is not bound to the approved origin/project');
  }

  const totalBytes = actualPaths.reduce((total, item) => total + fs.statSync(path.join(DIST_ROOT, item)).size, 0);
  return Object.freeze({
    artifactDigest: sha256(manifestBytes),
    aggregatePayloadSha256: manifest.aggregatePayloadSha256,
    payloadFileCount: manifest.payloadFileCount,
    artifactFileCount: actualPaths.length,
    payloadTotalBytes: manifest.payloadTotalBytes,
    artifactTotalBytes: totalBytes,
    paths: actualPaths
  });
}

function buildArtifact() {
  assertSafeDistRoot();
  assertSourceInventory();
  assertHtmlDependencies(new Set(PAYLOAD_PATHS));
  fs.rmSync(DIST_ROOT, { recursive: true, force: true });
  fs.mkdirSync(DIST_ROOT, { recursive: false, mode: 0o755 });

  const releaseRevision = getReleaseRevision();
  for (const relativePath of SOURCE_RUNTIME_FILES) {
    const destination = path.join(DIST_ROOT, relativePath);
    fs.mkdirSync(path.dirname(destination), { recursive: true, mode: 0o755 });
    if (relativePath.endsWith('.html')) {
      const source = fs.readFileSync(path.join(REPOSITORY_ROOT, relativePath), 'utf8');
      fs.writeFileSync(destination, transformRuntimeHtml(relativePath, source, releaseRevision), { mode: 0o644, flag: 'wx' });
    } else {
      fs.copyFileSync(path.join(REPOSITORY_ROOT, relativePath), destination, fs.constants.COPYFILE_EXCL);
    }
  }
  const generatedConfig = renderProductionConfig(readProductionPublishableKey());
  fs.writeFileSync(path.join(DIST_ROOT, 'config.js'), generatedConfig, { mode: 0o644 });
  writeManifest();
  normalizeArtifactMetadata();
  return verifyArtifact();
}

function main() {
  const option = process.argv[2];
  if (option && option !== '--verify') fail(`Unknown option: ${option}`);
  const result = option === '--verify' ? verifyArtifact() : buildArtifact();
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`Production artifact validation failed: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = Object.freeze({
  DIGEST_PATH,
  DIST_ROOT,
  EXPECTED_ARTIFACT_PATHS,
  MANIFEST_PATH,
  PAYLOAD_PATHS,
  PRODUCTION_BINDING,
  SOURCE_RUNTIME_FILES,
  assertAllowedPath,
  assertContentSafe,
  buildArtifact,
  verifyArtifact
});
