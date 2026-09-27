// Local native psql -> PostgreSQL engine -> actual PowerShell parser. No remote connection.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
const run = promisify(execFile);
const here = fileURLToPath(new URL('.', import.meta.url));
const tools = process.env.RESUME_SQL_TOOLS;
const pwsh = process.env.REVIEW_POWERSHELL;
assert.ok(tools && pwsh, 'RESUME_SQL_TOOLS and REVIEW_POWERSHELL are required');
const { PGlite } = await import(pathToFileURL(join(tools, 'protocol_tools/node_modules/@electric-sql/pglite/dist/index.js')));
const { PGLiteSocketServer } = await import(pathToFileURL(join(tools, 'protocol_tools/node_modules/@electric-sql/pglite-socket/dist/index.js')));
const db = new PGlite();
const server = new PGLiteSocketServer({ db, host: '127.0.0.1', port: 0, maxConnections: 1 });
const read = path => readFile(join(here, path), 'utf8');
try {
  await db.exec(await read('../../tenant_resume_access_20260926/fixture_sql_engine_only.sql'));
  await db.exec('ALTER TABLE storage.objects DROP COLUMN is_delete_marker');
  await server.start();
  const env = { ...process.env, LD_LIBRARY_PATH: join(tools,'psql17/files/usr/lib/x86_64-linux-gnu'),
    PGHOST:'127.0.0.1', PGPORT:server.getServerConn().split(':').at(-1), PGUSER:'postgres',
    PGDATABASE:'template1', PGPASSWORD:'local-only', PGSSLMODE:'disable', PGOPTIONS:'' };
  const psql = async(file, readOnly=false) => run(join(tools,'psql17/files/usr/lib/postgresql/17/bin/psql'),
    ['-X','-A','-t','--no-password','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-f',join(here,file)],
    { env:{...env,PGOPTIONS:readOnly?'-c default_transaction_read_only=on -c statement_timeout=30000':''},
      timeout:60000, maxBuffer:1024*1024 });
  await psql('../../tenant_resume_access_20260926/forward_proposed.sql');
  await db.exec(await read('../fixture_onboarding.sql'));
  await mkdir(join(here,'fixtures'),{recursive:true});
  const executions={};
  for(const [stage,file,readOnly] of [['preflight','preflight_read_only.sql',true],['forward','forward_proposed.sql',false],['postcheck','postcheck_read_only.sql',true]]) {
    const r=await psql('../'+file,readOnly);
    await writeFile(join(here,'fixtures/'+stage+'-success.txt'),r.stdout);
    executions[stage]={nativeExit:0,lineCount:r.stdout.trim().split(/\r?\n/).length};
  }
  const parser=await run(pwsh,['-NoLogo','-NoProfile','-NonInteractive','-File',join(here,'test_execution_parser.ps1')],{timeout:30000});
  assert.match(parser.stdout,/ADMIN_DOCUMENT_EXECUTION_PARSER=PASS; CHECKS=27/);
  let replay;
  try{await psql('../forward_proposed.sql');}catch(error){replay=error;}
  assert.equal(replay?.code,3);
  assert.ok(!replay.stdout.includes('ADMIN_DOCUMENT_REPAIR=COMMITTED'));
  const post=await psql('../postcheck_read_only.sql',true);
  assert.ok(post.stdout.includes('ADMIN_DOCUMENT_POSTCHECK=PASS'));
  await writeFile(join(here,'validation.json'),JSON.stringify({
    result:'PASS',scope:'Actual native psql17/PGlite SQL-to-PowerShell7.4.6 parser. Not genuine services or Production.',
    executions,parserChecks:27,secondExecutionNativeExit:3,postcheckAfterRejectedReplay:'PASS',productionConnections:0
  },null,2)+'\n');
  console.log('EXECUTION_SQL_TO_POWERSHELL_PARSER=PASS');

} finally { await server.stop(); await db.close(); }
