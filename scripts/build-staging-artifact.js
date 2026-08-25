'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const production = require('./build-production-artifact.js');

const ROOT = path.resolve(__dirname, '..');
const DIST = path.join(ROOT, 'dist-staging');
const NONPROD_REF = 'zrluniaccvcdrvfwgrmj';
const NONPROD_URL = `https://${NONPROD_REF}.supabase.co`;
const PRODUCTION_REF = production.PRODUCTION_BINDING.supabaseProjectRef;
const PRODUCTION_URL = production.PRODUCTION_BINDING.supabaseUrl;

function fail(message) { throw new Error(message); }
function sha256(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function env(name) { const value = process.env[name]; if (!value) fail(`Missing staging input: ${name}`); return value.trim(); }
function rejectUnsafe(name, value) {
  if (/zrluniaccvcdrvfwgrmj/i.test(value) && name !== 'STAGING_SUPABASE_PROJECT_REF' && name !== 'STAGING_SUPABASE_URL') fail(`${name} contains a prohibited literal`);
  if (new RegExp(`${PRODUCTION_REF}|${PRODUCTION_URL.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'i').test(value)) fail(`${name} contains production binding`);
  if (/localhost|127\.0\.0\.1|\[?::1\]?|sb_secret_|service[_-]?role|postgres(?:ql)?:\/\/[^\s:@/]+:[^\s@/]+@|password\s*[:=]|test\.invalid|-----BEGIN/i.test(value)) fail(`${name} contains prohibited material`);
}
function assertSafeText(relative, content) {
  if (/zrluniaccvcdrvfwgrmj|localhost|127\.0\.0\.1|\[?::1\]?|sb_secret_|service[_-]?role|postgres(?:ql)?:\/\/[^\s:@/]+:[^\s@/]+@|password\s*[:=]\s*['"][^'"]{8,}['"]|test\.invalid|-----BEGIN|eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{10,}/i.test(content)) fail(`Unsafe content in staging artifact: ${relative}`);
}
function main() {
  const origin = env('STAGING_EXPECTED_ORIGIN');
  const ref = env('STAGING_SUPABASE_PROJECT_REF');
  const url = env('STAGING_SUPABASE_URL');
  const key = env('STAGING_SUPABASE_PUBLISHABLE_KEY');
  const revision = env('STAGING_RELEASE_REVISION');
  if (origin !== 'https://aadhyant-web-platform-staging.pages.dev') fail('Unexpected staging origin');
  if (ref !== NONPROD_REF || url !== NONPROD_URL) fail('Staging Supabase binding mismatch');
  if (!/^sb_publishable_[A-Za-z0-9_-]{20,}$/.test(key)) fail('Invalid staging publishable key');
  [origin, ref, url, key, revision].forEach((value, index) => rejectUnsafe(['STAGING_EXPECTED_ORIGIN','STAGING_SUPABASE_PROJECT_REF','STAGING_SUPABASE_URL','STAGING_SUPABASE_PUBLISHABLE_KEY','STAGING_RELEASE_REVISION'][index], value));
  if (fs.existsSync(DIST)) fs.rmSync(DIST, { recursive: true, force: true });
  fs.mkdirSync(DIST, { recursive: true });
  for (const relative of production.SOURCE_RUNTIME_FILES) {
    const source = path.join(ROOT, relative); const target = path.join(DIST, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const content = fs.readFileSync(source);
    if (/\.(?:html|css|js|svg)$/i.test(relative)) assertSafeText(relative, content.toString('utf8'));
    fs.writeFileSync(target, content);
  }
  const config = `window.AADHYANT_CONFIG = Object.freeze({environment:'staging',expectedOrigin:${JSON.stringify(origin)},releaseRevision:${JSON.stringify(revision)},sensitiveIntakeEnabled:false,supabaseProjectRef:${JSON.stringify(ref)},supabaseUrl:${JSON.stringify(url)},supabasePublishableKey:${JSON.stringify(key)}});\n`;
  fs.writeFileSync(path.join(DIST, 'config.js'), config);
  const files = [];
  (function walk(dir) { for (const entry of fs.readdirSync(dir, { withFileTypes: true })) { const abs=path.join(dir,entry.name); if(entry.isDirectory()) walk(abs); else { const rel=path.relative(DIST,abs).replaceAll(path.sep,'/'); files.push({path:rel,bytes:fs.statSync(abs).size,sha256:sha256(fs.readFileSync(abs))}); } } })(DIST);
  files.sort((a,b)=>a.path.localeCompare(b.path));
  const manifest = { schemaVersion:1, target:{environment:'staging',expectedOrigin:origin,supabaseProjectRef:ref,supabaseUrl:url}, files, aggregatePayloadSha256:sha256(files.map((f)=>`${f.path}\0${f.bytes}\0${f.sha256}\n`).join('')) };
  fs.writeFileSync(path.join(DIST,'artifact-manifest.json'), `${JSON.stringify(manifest,null,2)}\n`);
  fs.writeFileSync(path.join(DIST,'artifact-digest.sha256'), `${sha256(fs.readFileSync(path.join(DIST,'artifact-manifest.json')))}  artifact-manifest.json\n`);
  process.stdout.write(`${JSON.stringify({output:DIST,files:files.length,aggregatePayloadSha256:manifest.aggregatePayloadSha256},null,2)}\n`);
}
if (require.main === module) { try { main(); } catch (error) { process.stderr.write(`Staging artifact validation failed: ${error.message}\n`); process.exitCode=1; } }
module.exports = { DIST, NONPROD_REF, NONPROD_URL };
