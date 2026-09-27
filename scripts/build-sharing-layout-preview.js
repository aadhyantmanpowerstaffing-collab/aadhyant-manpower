'use strict';

// Offline, synthetic layout review only. Never included in the production artifact.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');

function buildPreview() {
  const fixture = 'tests/fixtures/sharing-layout-preview/';
  let panel = read(fixture + 'panel.html');
  for (const file of ['company/company.css', 'assets/css/resume-sharing.css']) {
    panel = panel.replace(`<link rel="stylesheet" href="../../../${file}">`, () => `<style>${read(file)}</style>`);
  }
  panel = panel.replace(/<script\b[^>]*\bsrc="[^"]*"[^>]*><\/script>/g, '');
  const modeDeclaration = "const portal = new URLSearchParams(location.search).get('portal') || 'company';";
  const fixtureScript = read(fixture + 'preview.js');
  if (!fixtureScript.includes(modeDeclaration)) throw new Error('Preview mode declaration changed.');
  const samples = {};
  for (const mode of ['company', 'admin', 'contractor']) {
    const script = read('assets/js/resume-sharing.js') + '\n' +
      fixtureScript.replace(modeDeclaration, `const portal = ${JSON.stringify(mode)};`);
    samples[mode] = panel.replace('</body>', () =>
      `<script>${script.replace(/<\/script/gi, '<\\/script')}</script></body>`);
  }

  // Insert markup before serializing nested documents. A later global <head>
  // replacement would inject unescaped attribute quotes into the JSON payload.
  const csp = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-src 'self' about:; connect-src 'none'">`;
  const shell = read(fixture + 'index.html').split('<script>')[0].replace('<head>', '<head>' + csp);
  const serialized = JSON.stringify(samples).replace(/</g, '\\u003c');
  return shell + `<script>
'use strict';
const samples = ${serialized};
function show(mode) {
  if (!Object.prototype.hasOwnProperty.call(samples, mode)) return;
  document.querySelectorAll('iframe').forEach(frame => { frame.srcdoc = samples[mode]; });
  document.querySelectorAll('nav a').forEach(link => {
    link.setAttribute('aria-current', link.hash === '#' + mode ? 'page' : 'false');
  });
}
document.querySelectorAll('nav a').forEach(link => {
  const mode = new URL(link.href).searchParams.get('portal');
  link.href = '#' + mode;
  link.onclick = event => { event.preventDefault(); show(mode); };
});
show('company');
</script><noscript>This preview needs JavaScript enabled in your browser.</noscript></body></html>\n`;
}

if (require.main === module) {
  if (!process.argv[2]) throw new Error('Pass an output HTML path.');
  fs.writeFileSync(path.resolve(process.argv[2]), buildPreview());
  process.stdout.write('OFFLINE_SHARING_PREVIEW=BUILT\n');
}
module.exports = { buildPreview };
