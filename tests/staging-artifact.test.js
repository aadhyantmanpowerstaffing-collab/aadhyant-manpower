'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const { buildArtifact, root, verifyArtifact } = require('../scripts/build-pages-artifact.js');

test('staging artifact uses only staging public config and excludes repository internals', () => {
  const temporaryRoot = fs.mkdtempSync(path.join(root, '.tmp-pages-artifact-'));
  const outputDir = path.join(temporaryRoot, 'artifact');
  try {
    buildArtifact({
      mode: 'staging',
      outputDir,
      env: {
        STAGING_EXPECTED_ORIGIN: 'https://aadhyant-web-platform-staging.pages.dev',
        STAGING_SUPABASE_URL: 'https://zrluniaccvcdrvfwgrmj.supabase.co',
        STAGING_SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_staging_test_key_123456789',
        STAGING_RELEASE_REVISION: 'a'.repeat(40),
      },
    });
    verifyArtifact({ mode: 'staging', outputDir });
    const config = fs.readFileSync(path.join(outputDir, 'config.js'), 'utf8');
    assert.match(config, /zrluniaccvcdrvfwgrmj\.supabase\.co/);
    assert.match(config, /sb_publishable_staging_test_key_123456789/);
    assert.match(config, /candidateOtpEnabled:\s*false/);
    assert.doesNotMatch(config, /wsuctjhbqiedttfnwjvf/);
    for (const excluded of ['.github', 'docs', 'scripts', 'supabase', 'tests']) {
      assert.equal(fs.existsSync(path.join(outputDir, excluded)), false, `${excluded} was published`);
    }
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});
