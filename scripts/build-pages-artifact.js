'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const markerFile = '.aadhyant-pages-artifact';
const manifestFile = 'artifact-manifest.json';
const rootFiles = [
  'CNAME',
  'config.js',
  'index.html',
  'script.js',
  'style.css',
  'supabase-client.js',
];
const publicDirectories = [
  'about',
  'admin',
  'assets',
  'candidate',
  'company',
  'contact',
  'contractor',
  'data-deletion',
  'hire-manpower',
  'industries',
  'jobs',
  'privacy',
  'services',
  'staffing-partner',
  'terms',
];
const textExtensions = new Set(['.css', '.html', '.js', '.json', '.svg', '.txt', '.xml']);
const forbiddenText = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_SECRET_KEY',
  'WHATSAPP_ACCESS_TOKEN',
  'SEND_SMS_HOOK_SECRET',
  'META_WA_ACCESS_TOKEN',
];

function inside(parent, candidate) {
  const relative = path.relative(parent, candidate);
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative);
}

function copyEntry(source, destination) {
  const stat = fs.lstatSync(source);
  if (stat.isSymbolicLink()) throw new Error(`Refusing to publish symlink: ${path.relative(root, source)}`);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const child of fs.readdirSync(source).sort()) {
      copyEntry(path.join(source, child), path.join(destination, child));
    }
    return;
  }
  if (!stat.isFile()) throw new Error(`Refusing non-file artifact entry: ${path.relative(root, source)}`);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

function replaceQuotedProperty(source, property, value) {
  const expression = new RegExp(`(\\b${property}\\s*:\\s*)'[^']*'`);
  if (!expression.test(source)) throw new Error(`Missing ${property} in config.js`);
  return source.replace(expression, `$1'${value}'`);
}

function replaceBooleanProperty(source, property, value) {
  const expression = new RegExp(`(\\b${property}\\s*:\\s*)(?:true|false)`);
  if (!expression.test(source)) throw new Error(`Missing ${property} in config.js`);
  return source.replace(expression, `$1${value ? 'true' : 'false'}`);
}

function stagingSettings(env) {
  const expectedOrigin = 'https://aadhyant-web-platform-staging.pages.dev';
  const origin = String(env.STAGING_EXPECTED_ORIGIN || '');
  const url = String(env.STAGING_SUPABASE_URL || '');
  const key = String(env.STAGING_SUPABASE_PUBLISHABLE_KEY || '');
  const revision = String(env.STAGING_RELEASE_REVISION || '');
  if (origin !== expectedOrigin) throw new Error('Unexpected staging origin');
  if (!/^https:\/\/[a-z0-9]{20}\.supabase\.co$/.test(url)) throw new Error('Invalid staging Supabase URL');
  if (!/^sb_publishable_[A-Za-z0-9_-]{16,}$/.test(key)) throw new Error('Invalid staging publishable key');
  if (!/^[a-f0-9]{7,64}$/i.test(revision)) throw new Error('Invalid staging release revision');
  return { url, key, revision };
}

function configureArtifact(output, mode, env) {
  const configPath = path.join(output, 'config.js');
  let config = fs.readFileSync(configPath, 'utf8');
  if (mode === 'preview') {
    config = replaceQuotedProperty(config, 'supabaseUrl', '');
    config = replaceQuotedProperty(config, 'supabasePublishableKey', '');
    config = replaceQuotedProperty(config, 'candidateOtpCaptchaSiteKey', '');
    config = replaceBooleanProperty(config, 'candidateOtpEnabled', false);
  }
  if (mode === 'staging') {
    const settings = stagingSettings(env);
    config = replaceQuotedProperty(config, 'supabaseUrl', settings.url);
    config = replaceQuotedProperty(config, 'supabasePublishableKey', settings.key);
    config = replaceQuotedProperty(config, 'candidateOtpCaptchaSiteKey', '');
    config = replaceBooleanProperty(config, 'candidateOtpEnabled', false);
  }
  fs.writeFileSync(configPath, config);
}

function walkFiles(directory, prefix = '') {
  const entries = [];
  for (const name of fs.readdirSync(directory).sort()) {
    const full = path.join(directory, name);
    const relative = path.join(prefix, name);
    const stat = fs.lstatSync(full);
    if (stat.isSymbolicLink()) throw new Error(`Artifact contains symlink: ${relative}`);
    if (stat.isDirectory()) entries.push(...walkFiles(full, relative));
    else if (stat.isFile()) entries.push(relative.split(path.sep).join('/'));
    else throw new Error(`Artifact contains unsupported entry: ${relative}`);
  }
  return entries;
}

function payloadFiles(output) {
  return walkFiles(output).filter((file) => file !== markerFile && file !== manifestFile).sort();
}

function digestFile(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function assertNoSecrets(output, files) {
  for (const relative of files) {
    const extension = path.extname(relative).toLowerCase();
    if (!textExtensions.has(extension)) continue;
    const content = fs.readFileSync(path.join(output, relative), 'utf8');
    for (const forbidden of forbiddenText) {
      if (content.includes(forbidden)) throw new Error(`Forbidden server secret reference in artifact: ${relative}`);
    }
  }
}

function artifactFiles(output) {
  const files = payloadFiles(output);
  assertNoSecrets(output, files);
  return files.map((relative) => {
    const full = path.join(output, relative);
    return { path: relative, sha256: digestFile(full), bytes: fs.statSync(full).size };
  });
}

function normalizeOutput(outputDir) {
  const output = path.resolve(outputDir);
  if (!inside(root, output)) throw new Error('Artifact output must remain inside the repository');
  return output;
}

function prepareOutput(output) {
  if (fs.existsSync(output)) {
    if (fs.lstatSync(output).isSymbolicLink()) {
      throw new Error(`Refusing symlinked artifact output: ${path.relative(root, output)}`);
    }
    const marker = path.join(output, markerFile);
    if (!fs.statSync(output).isDirectory() || !fs.existsSync(marker)) {
      throw new Error(`Refusing to overwrite unmarked output: ${path.relative(root, output)}`);
    }
    fs.rmSync(output, { recursive: true, force: true });
  }
  fs.mkdirSync(output, { recursive: true });
}

function buildArtifact({ mode, outputDir, env = process.env }) {
  if (!['preview', 'production', 'staging'].includes(mode)) throw new Error('Unsupported artifact mode');
  const output = normalizeOutput(outputDir);
  prepareOutput(output);
  for (const file of rootFiles) copyEntry(path.join(root, file), path.join(output, file));
  for (const directory of publicDirectories) copyEntry(path.join(root, directory), path.join(output, directory));
  configureArtifact(output, mode, env);
  const manifest = {
    format: 1,
    mode,
    releaseRevision: mode === 'staging' ? stagingSettings(env).revision : null,
    files: artifactFiles(output),
  };
  fs.writeFileSync(path.join(output, manifestFile), `${JSON.stringify(manifest, null, 2)}\n`);
  fs.writeFileSync(path.join(output, markerFile), `format=1\nmode=${mode}\n`);
  return manifest;
}

function verifyArtifact({ mode, outputDir }) {
  const output = normalizeOutput(outputDir);
  const expectedMarker = `format=1\nmode=${mode}\n`;
  if (!fs.existsSync(path.join(output, markerFile)) || fs.readFileSync(path.join(output, markerFile), 'utf8') !== expectedMarker) {
    throw new Error('Artifact marker is missing or invalid');
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(output, manifestFile), 'utf8'));
  if (manifest.format !== 1 || manifest.mode !== mode || !Array.isArray(manifest.files)) {
    throw new Error('Artifact manifest is invalid');
  }
  const current = artifactFiles(output);
  if (JSON.stringify(current) !== JSON.stringify(manifest.files)) {
    throw new Error('Artifact manifest does not match the generated files');
  }
  return manifest;
}

module.exports = { buildArtifact, verifyArtifact, root };
