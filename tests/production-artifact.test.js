'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { buildArtifact, root, verifyArtifact } = require('../scripts/build-pages-artifact.js');

test('preview artifact cannot reach production Supabase and production artifact preserves reviewed config', () => {
  const temporaryRoot = fs.mkdtempSync(path.join(root, '.tmp-pages-artifact-'));
  const previewDir = path.join(temporaryRoot, 'preview');
  const productionDir = path.join(temporaryRoot, 'production');
  try {
    buildArtifact({ mode: 'preview', outputDir: previewDir });
    verifyArtifact({ mode: 'preview', outputDir: previewDir });
    const previewConfig = fs.readFileSync(path.join(previewDir, 'config.js'), 'utf8');
    assert.match(previewConfig, /supabaseUrl:\s*''/);
    assert.match(previewConfig, /supabasePublishableKey:\s*''/);
    assert.match(previewConfig, /candidateOtpEnabled:\s*false/);
    assert.doesNotMatch(previewConfig, /wsuctjhbqiedttfnwjvf/);

    buildArtifact({ mode: 'production', outputDir: productionDir });
    verifyArtifact({ mode: 'production', outputDir: productionDir });
    const sourceConfig = fs.readFileSync(path.join(root, 'config.js'), 'utf8');
    const productionConfig = fs.readFileSync(path.join(productionDir, 'config.js'), 'utf8');
    assert.equal(productionConfig, sourceConfig);
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

test('artifact builder refuses a symlinked output directory', () => {
  const temporaryRoot = fs.mkdtempSync(path.join(root, '.tmp-pages-artifact-'));
  const linkedOutput = path.join(temporaryRoot, 'linked-output');
  const outside = path.join(temporaryRoot, 'outside');
  try {
    fs.mkdirSync(outside);
    fs.writeFileSync(path.join(outside, '.aadhyant-pages-artifact'), 'format=1\nmode=preview\n');
    fs.symlinkSync(outside, linkedOutput, 'dir');
    assert.throws(
      () => buildArtifact({ mode: 'preview', outputDir: linkedOutput }),
      /Refusing symlinked artifact output/,
    );
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});
