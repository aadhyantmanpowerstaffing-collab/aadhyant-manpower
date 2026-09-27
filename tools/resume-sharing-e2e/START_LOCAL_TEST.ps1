[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$EvidenceRoot,
  [ValidateRange(20000,64000)][int]$BasePort=61421,
  [switch]$KeepStack
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidenceBase=[IO.Path]::GetFullPath($EvidenceRoot)
if ($evidenceBase -eq $repo -or $evidenceBase.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceRoot must be outside the repository.' }
$runId='resume-e2e-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$evidence=Join-Path $evidenceBase $runId
$stack=Join-Path ([IO.Path]::GetTempPath()) $runId
$container='supabase_db_'+$runId
$npx=if ($env:OS -eq 'Windows_NT') {'npx.cmd'} else {'npx'}
$stage='LOCAL_HOST_PRECHECK'; $started=$false; $stackCreated=$false
$saved=@{}; $report=[ordered]@{runId=$runId;result='BLOCKED';stages=@{};scope='Fresh local resume-sharing Auth/Storage and browser component rehearsal';productionConnections=0}
$envNames=@('SUPABASE_TELEMETRY_DISABLED','RESUME_E2E_SITE','RESUME_E2E_URL','RESUME_E2E_BACKEND','RESUME_E2E_ANON_KEY','RESUME_E2E_EMAIL_A','RESUME_E2E_EMAIL_B','RESUME_E2E_PASSWORD','RESUME_E2E_EVIDENCE_DIR')
foreach($name in $envNames){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
function Safe-ErrorText([string]$text){
  $text=$text -replace 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+','REDACTED_JWT'
  $text=$text -replace 'sb_(secret|publishable)_[A-Za-z0-9_-]+','REDACTED_KEY'
  $text=$text -replace '(?i)postgres(?:ql)?://\S+','REDACTED_DATABASE_URL'
  if($env:RESUME_E2E_PASSWORD){$text=$text.Replace($env:RESUME_E2E_PASSWORD,'REDACTED_PASSWORD')}
  if($text.Length -gt 3500){$text=$text.Substring(0,3500)}
  return $text
}
function Invoke-Native([string]$Label,[string]$Executable,[string[]]$Arguments,[switch]$SecretOutput){
  $errFile=Join-Path $evidence ('.native-'+[guid]::NewGuid().ToString('N')+'.txt')
  $prior=$ErrorActionPreference
  try{
    $ErrorActionPreference='Continue'
    $out=@(& $Executable @Arguments 2> $errFile)
    $nativeExit=$LASTEXITCODE
    $ErrorActionPreference=$prior
    $err=if(Test-Path -LiteralPath $errFile){[IO.File]::ReadAllText($errFile)}else{''}
    if($nativeExit -ne 0){
      $details=if($SecretOutput){'Native error output suppressed for a credential-bearing command.'}else{Safe-ErrorText (($out -join "`n")+"`n"+$err)}
      $report.stages[$Label]='FAIL'; throw "$Label failed; exit=$nativeExit; $details"
    }
    $report.stages[$Label]='PASS'
    return ($out -join "`n")
  }finally{$ErrorActionPreference=$prior;if(Test-Path -LiteralPath $errFile){Remove-Item -LiteralPath $errFile -Force}}
}
function Run-Sql([string]$Label,[string]$Path,[string]$Marker){
  if($container -notmatch '^supabase_db_resume-e2e-[a-f0-9]{12}$'){throw 'Only the newly created Resume Sharing test container is allowed.'}
  $destination='/tmp/'+$runId+'-'+[IO.Path]::GetFileName($Path)
  Invoke-Native ($Label+'_COPY') 'docker' @('cp',$Path,($container+':'+$destination)) | Out-Null
  $out=Invoke-Native $Label 'docker' @('exec','-e','PGOPTIONS=-c aadhyant.resume_fixture=local-only',$container,'psql','-X','-A','-t','-v','ON_ERROR_STOP=1','-h','/var/run/postgresql','-p','5432','-U','postgres','-d','postgres','-f',$destination)
  if(-not (($out -split '\r?\n') -ccontains $Marker)){throw "$Label missing exact result marker: $Marker"}
  [IO.File]::WriteAllText((Join-Path $evidence ($Label+'.txt')),$out+"`n")
  Write-Output ($Label+'=PASS')
}
try{
  foreach($tool in @('docker','node',$npx)){if(-not(Get-Command $tool -ErrorAction SilentlyContinue)){throw "Required local executable unavailable: $tool"}}
  if($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe|unix)://'){throw 'Remote Docker endpoints are forbidden.'}
  $context=(Invoke-Native 'DOCKER_CONTEXT' 'docker' @('context','show')).Trim()
  $endpoint=(Invoke-Native 'DOCKER_ENDPOINT' 'docker' @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}')).Trim()
  if($endpoint -notmatch '^(npipe|unix)://'){throw 'Only a local Docker socket is permitted.'}
  $report.dockerContext=$context
  $report.dockerServer=(Invoke-Native 'DOCKER_ENGINE' 'docker' @('version','--format','{{.Server.Version}}')).Trim()
  $existing=Invoke-Native 'CONTAINER_COLLISION_CHECK' 'docker' @('ps','-a','--format','{{.Names}}')
  if(($existing -split '\r?\n') -contains $container){throw 'Disposable container name collision.'}
  foreach($port in (($BasePort-1)..($BasePort+10))){
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port)
    try{$listener.Start()}finally{$listener.Stop()}
  }
  $stage='ARTIFACT_VERIFICATION'
  $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_manifest.json') -Raw | ConvertFrom-Json
  foreach($item in $manifest.files){
    $path=[IO.Path]::GetFullPath((Join-Path $repo $item.path))
    if(-not $path.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Artifact path escapes repository.'}
    if((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash -ne $item.sha256){throw ('Artifact hash mismatch: '+$item.path)}
  }
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'bootstrap_local_supabase.sql') -Destination $evidence
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'local_manifest.json') -Destination $evidence
  Push-Location $PSScriptRoot
  try { Invoke-Native 'PINNED_NPM_INSTALL' $npx @('--yes','npm@10.9.2','ci','--ignore-scripts','--no-audit','--no-fund') | Out-Null } finally { Pop-Location }
  $env:SUPABASE_TELEMETRY_DISABLED='1'
  $stage='STACK_INITIALIZATION'
  New-Item -ItemType Directory -Path $stack | Out-Null; $stackCreated=$true
  $version=(Invoke-Native 'SUPABASE_VERSION' $npx @('--yes','supabase@2.111.0','--version')).Trim()
  if($version -notmatch '(^|\s)2\.111\.0($|\s)'){throw 'Supabase CLI version mismatch.'}
  Invoke-Native 'SUPABASE_INIT' $npx @('--yes','supabase@2.111.0','init','--workdir',$stack) | Out-Null
  Invoke-Native 'LOCAL_CONFIG' 'node' @((Join-Path $PSScriptRoot 'configure_local_stack.mjs'),$stack,$runId,[string]$BasePort) | Out-Null
  Copy-Item -LiteralPath (Join-Path $stack 'supabase/config.toml') -Destination (Join-Path $evidence 'local-config.toml')
  $report.stackDirectory=$stack
  $stage='GENUINE_STACK_START'; $started=$true
  Invoke-Native $stage $npx @('--yes','supabase@2.111.0','start','--workdir',$stack) -SecretOutput | Out-Null
  Write-Output 'GENUINE_LOCAL_STACK=PASS'
  $statusText=Invoke-Native 'LOCAL_STATUS' $npx @('--yes','supabase@2.111.0','status','--workdir',$stack,'-o','json') -SecretOutput
  $status=$statusText | ConvertFrom-Json
  $api=[string]$status.API_URL; $anon=[string]$status.ANON_KEY
  if(-not $api -and $status.api){$api=[string]$status.api.url}
  if(-not $anon -and $status.auth){$anon=[string]$status.auth.anon_key}
  if($api -ne ('http://127.0.0.1:'+$BasePort) -or -not $anon){throw 'Local status did not return the expected loopback API and browser key.'}
  $report.imageId=(Invoke-Native 'LOCAL_IMAGE_ID' 'docker' @('inspect',$container,'--format','{{.Image}}')).Trim()
  $stage='FIXTURE_BOOTSTRAP'
  Run-Sql $stage (Join-Path $PSScriptRoot 'bootstrap_local_supabase.sql') 'RESUME_FIXTURE_BOOTSTRAP=PASS'
  $env:RESUME_E2E_SITE=$repo
  $env:RESUME_E2E_URL='http://127.0.0.1:'+($BasePort+10)
  $env:RESUME_E2E_BACKEND=$api; $env:RESUME_E2E_ANON_KEY=$anon
  $env:RESUME_E2E_EMAIL_A=$runId+'-a@example.test'; $env:RESUME_E2E_EMAIL_B=$runId+'-b@example.test'
  $env:RESUME_E2E_PASSWORD='Local!'+[guid]::NewGuid().ToString('N')+'aA9'
  $env:RESUME_E2E_EVIDENCE_DIR=$evidence
  $stage='GENUINE_AUTH_CREATE'
  Invoke-Native $stage 'node' @((Join-Path $PSScriptRoot 'exercise_local_api.mjs'),'prepare') | Write-Output
  $stage='AUTH_RECIPIENT_MAPPING'
  Run-Sql $stage (Join-Path $evidence 'synthetic-resume-mapping.sql') 'RESUME_AUTH_MAPPING=PASS'
  $stage='LOCAL_REPAIR_PREFLIGHT'
  Run-Sql $stage (Join-Path $repo 'supabase/production/tenant_resume_access_20260926/preflight_read_only.sql') 'TENANT_RESUME_PREFLIGHT|PASS|none'
  $stage='LOCAL_RESUME_REPAIR'
  Run-Sql $stage (Join-Path $repo 'supabase/production/tenant_resume_access_20260926/forward_proposed.sql') 'TENANT_RESUME_REPAIR=COMMITTED'
  $stage='LOCAL_RESUME_POSTCHECK'
  Run-Sql $stage (Join-Path $repo 'supabase/production/tenant_resume_access_20260926/postcheck_read_only.sql') 'TENANT_RESUME_POSTCHECK|PASS|none'
  $stage='GENUINE_RESUME_UPLOAD'
  Invoke-Native $stage 'node' @((Join-Path $PSScriptRoot 'exercise_local_api.mjs'),'verify') | Write-Output
  $stage='RESUME_BROWSER_COMPONENT_FLOW'
  Invoke-Native $stage 'node' @((Join-Path $PSScriptRoot 'run_browser.mjs')) | Write-Output
  $report.result='PASS'
}catch{
  $report.result='FAIL'; $report.failureStage=$stage; $report.error=Safe-ErrorText $_.Exception.Message
  Write-Output ('LOCAL_REHEARSAL_STAGE='+$stage)
  Write-Output ('LOCAL_REHEARSAL_ERROR='+$report.error)
}finally{
  # Save reproducible configuration/bootstrap and sanitized results before cleanup.
  $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'rehearsal-result.json') -Encoding UTF8
  if($started -and -not $KeepStack){
    try{Invoke-Native 'SCOPED_CLEANUP' $npx @('--yes','supabase@2.111.0','stop','--workdir',$stack,'--project-id',$runId,'--no-backup') -SecretOutput | Out-Null}
    catch{$report.cleanup='FAIL';$report.result='FAIL'}
  }
  try{
    if($stackCreated -and -not $KeepStack -and $report.cleanup -ne 'FAIL'){Remove-Item -LiteralPath $stack -Recurse -Force}
  }catch{$report.cleanup='FAIL';$report.result='FAIL'}
  finally{foreach($name in $envNames){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}}
  $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'rehearsal-result.json') -Encoding UTF8
  Write-Output ('SANITIZED_LOCAL_EVIDENCE='+$evidence)
}
if($report.result -ne 'PASS'){exit 1}
Write-Output 'LOCAL_RESUME_BROWSER_REHEARSAL=PASS'
