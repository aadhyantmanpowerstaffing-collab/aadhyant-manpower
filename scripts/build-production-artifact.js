'use strict';

const path = require('node:path');
const { buildArtifact, root, verifyArtifact } = require('./build-pages-artifact.js');

const outputDir = path.join(root, 'dist');
if (process.argv.includes('--verify')) verifyArtifact({ mode: 'production', outputDir });
else buildArtifact({ mode: 'production', outputDir });
