'use strict';

const path = require('node:path');
const { buildArtifact, root } = require('./build-pages-artifact.js');

buildArtifact({ mode: 'staging', outputDir: path.join(root, 'dist-staging') });
