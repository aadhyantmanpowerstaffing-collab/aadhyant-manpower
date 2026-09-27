[CmdletBinding()]
param(
    [string]$EvidenceRoot='D:\Aadhyant-Review\Document-Joining-Production-Evidence',
    [switch]$IApproveAdminDocumentsProductionUpgrade,
    [switch]$VerifyOnly,
    [switch]$SelfTest,
    [switch]$CheckArtifactsOnly
)
# Fixed SQL/target only. No migration replay, arbitrary SQL, retry, or automatic rollback.
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$pins=@{
    'preflight_read_only.sql' = '49e42c4559d6015a8152addce98d4567e5715da8b929840c0840a69c3a463b15'
    'forward_proposed.sql' = '810a67ea870655a6df6df8e1bc8cdda8a853e659c10c86cc85f40ca8bc1f8229'
    'postcheck_read_only.sql' = 'f1a285cdf9d0a88a487e36efb14b7d7cf5a44c35e76d9b728c07877ef4274dba'
    'Execution.Core.psm1' = 'bba56142885c337e852f912eece341b6d9c82bb4e6ea1731a67d27a466b6de8a'
    'test_execution_parser.ps1' = 'ab6097b936f064aa1ac8850ad972f9d75e6b9c883eb2fe4745ef9eb809aeee32'
    'fixtures/preflight-success.txt' = '96353d8d6bde5282d827ffbc5f9d6dc850c93477e08819e4ac9473c98a8abb16'
    'fixtures/forward-success.txt' = '6f09c48bf0c1726a5ecc6664edc5157a072931cdd30f75b4c124f17fc42754f2'
    'fixtures/postcheck-success.txt' = '7a8bdba0223718da937466a93b6c4b73e7363743d10b7554d352c3227b9ed40a'
}
foreach($name in $pins.Keys){
    if((Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash -ne $pins[$name]){throw ('Artifact hash mismatch: '+$name)}
}
Import-Module (Join-Path $root 'Execution.Core.psm1') -Force
if($CheckArtifactsOnly){Write-Output 'ADMIN_DOCUMENT_EXECUTION_ARTIFACTS=PASS';return}
if($SelfTest){& (Join-Path $root 'test_execution_parser.ps1');return}
if($VerifyOnly -and $IApproveAdminDocumentsProductionUpgrade){throw 'Choose VerifyOnly or approved execution, never both'}
if(-not $VerifyOnly -and -not $IApproveAdminDocumentsProductionUpgrade){throw 'Production execution requires explicit approval and -IApproveAdminDocumentsProductionUpgrade'}

$ca='C:\Users\ASUS\Downloads\prod-ca-2021 (1).crt'
$caHash='700723581420DD1AC98FD7E9AC529F0EF210EADCAF87FC868A3AD7D114C2F3B7'
if((Get-FileHash -LiteralPath $ca -Algorithm SHA256).Hash -ne $caHash){throw 'Pinned Production CA SHA-256 mismatch'}
$ca=(Resolve-Path -LiteralPath $ca).Path
if($root.Contains(',') -or $ca.Contains(',')){throw 'Docker mount paths must not contain commas'}
$image='supabase/postgres@sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00'
$runId='document-upgrade-'+[guid]::NewGuid().ToString('N').Substring(0,12)
$evidence=Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $runId
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$priorPassword=$env:PGPASSWORD;$bstr=[IntPtr]::Zero;$stage='LOCAL_DOCKER_CHECK'
$summary=[ordered]@{
    project='wsuctjhbqiedttfnwjvf';runId=$runId;
    mode=$(if($VerifyOnly){'VERIFY_ONLY'}else{'APPROVED_UPGRADE'});
    startedUtc=[DateTime]::UtcNow.ToString('o');result='INCOMPLETE';databaseState='NOT_DISPATCHED';
    frontendDeployment='NOT_DISPATCHED';image=$image;repairSha256=$pins['forward_proposed.sql'];
    stages=[ordered]@{}
}
function Save-ExecutionSummary {
    $summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $evidence 'execution-result.json') -Encoding UTF8
}
function Invoke-ExecutionNative([string[]]$Arguments){
    $errFile=Join-Path $evidence ('.native-'+[guid]::NewGuid().ToString('N')+'.txt')
    $priorPreference=$ErrorActionPreference
    try{
        $ErrorActionPreference='Continue'
        $lines=@(& docker @Arguments 2> $errFile)
        $nativeExit=$LASTEXITCODE
        $ErrorActionPreference=$priorPreference
        if($nativeExit -ne 0){
            $raw=if(Test-Path -LiteralPath $errFile){Get-Content -LiteralPath $errFile -Raw}else{''}
            $summary.nativeExit=$nativeExit
            $summary.failure=Get-DocumentFailureEvidence -ErrorText ([string]$raw)
            throw "NATIVE_EXIT=$nativeExit"
        }
        return $lines
    }finally{
        $ErrorActionPreference=$priorPreference
        if(Test-Path -LiteralPath $errFile){Remove-Item -LiteralPath $errFile -Force}
    }
}
function Invoke-PinnedStage([ValidateSet('preflight','forward','postcheck')][string]$Kind){
    # Defense in depth: VerifyOnly cannot dispatch a write even if orchestration changes.
    if($Kind -eq 'forward' -and ($VerifyOnly -or -not $IApproveAdminDocumentsProductionUpgrade)){throw 'Write dispatch is forbidden in this mode'}
    $sqlFile=@{preflight='preflight_read_only.sql';forward='forward_proposed.sql';postcheck='postcheck_read_only.sql'}[$Kind]
    $options=if($Kind -eq 'forward'){'PGOPTIONS=-c default_transaction_read_only=off -c statement_timeout=60000 -c idle_in_transaction_session_timeout=30000'}else{'PGOPTIONS=-c default_transaction_read_only=on -c statement_timeout=30000 -c idle_in_transaction_session_timeout=30000'}
    $stageArguments=@('run','--rm','--pull=never','--entrypoint','psql',
        '--mount',('type=bind,src='+$root+',dst=/work,readonly'),
        '--mount',('type=bind,src='+$ca+',dst=/cert/ca.crt,readonly'),
        '-e','PGPASSWORD','-e','PGHOST=aws-0-ap-northeast-1.pooler.supabase.com',
        '-e','PGPORT=5432','-e','PGDATABASE=postgres','-e','PGUSER=postgres.wsuctjhbqiedttfnwjvf',
        '-e','PGSSLMODE=verify-full','-e','PGSSLROOTCERT=/cert/ca.crt','-e','PGSSLSNI=1',
        '-e','PGCONNECT_TIMEOUT=15','-e',$options,
        $image,'-X','-A','-t','--no-password','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
        '-f',('/work/'+$sqlFile))
    $rows=@(Invoke-ExecutionNative -Arguments $stageArguments)
    Test-DocumentStageOutput -Lines $rows -NativeExit 0 -Stage $Kind | Out-Null
    $rows | Set-Content -LiteralPath (Join-Path $evidence ($Kind+'-output.txt')) -Encoding UTF8
    $summary.stages[$Kind]='PASS'
}
try{
    if($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe|unix)://'){throw 'REMOTE_DOCKER_FORBIDDEN'}
    $context=(@(Invoke-ExecutionNative @('context','show')) -join '').Trim()
    $endpoint=(@(Invoke-ExecutionNative @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}')) -join '').Trim()
    if($endpoint -notmatch '^(npipe|unix)://'){throw 'LOCAL_DOCKER_SOCKET_REQUIRED'}
    Invoke-ExecutionNative @('image','inspect',$image,'--format','{{.Id}}') | Out-Null
    $stage='PASSWORD_PROMPT'
    $secure=Read-Host 'Production database password' -AsSecureString
    $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr);$env:PGPASSWORD=$plain
    if(-not $VerifyOnly){
        $stage='READ_ONLY_PREFLIGHT'
        Invoke-PinnedStage -Kind preflight
        Write-Host 'ADMIN_DOCUMENT_PREFLIGHT=PASS'
        $stage='APPROVED_TRANSACTION'
        # Persist intent before dispatch. Interruption can never be mistaken for rollback.
        $summary.databaseState='COMMIT_UNCONFIRMED'
        Save-ExecutionSummary
        Invoke-PinnedStage -Kind forward
        $summary.databaseState='COMMITTED'
        Save-ExecutionSummary
        Write-Host 'ADMIN_DOCUMENT_REPAIR=COMMITTED'
    }
    $stage='READ_ONLY_POSTCHECK'
    Invoke-PinnedStage -Kind postcheck
    Write-Host 'ADMIN_DOCUMENT_POSTCHECK=PASS'
    $summary.result='PASS'
    Write-Host 'OVERALL_VERIFICATION=PASS'
}catch{
    $summary.result='FAIL';$summary.failureStage=$stage
    Write-Host 'OVERALL_VERIFICATION=FAIL'
    Write-Host ('FAILURE_STAGE='+$stage)
    if($summary.Contains('failure')){
        Write-Host ('FAILURE_CATEGORY='+$summary.failure.category)
        Write-Host ('SQLSTATE='+$summary.failure.sqlState)
        Write-Host ('SQL_LINE='+$summary.failure.sqlLine)
        foreach($label in $summary.failure.checks){Write-Host ('CATALOG_MISMATCH='+$label)}
    }else{Write-Host 'FAILURE_CATEGORY=LOCAL_OR_OUTPUT_VALIDATION_FAILURE'}
    if($summary.databaseState -ne 'NOT_DISPATCHED'){Write-Host 'NEXT_ACTION=VERIFY_ONLY; DO_NOT_REPLAY_REPAIR'}
}finally{
    $env:PGPASSWORD=$priorPassword;$plain=$null;$secure=$null
    if($bstr -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)}
    $summary.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Save-ExecutionSummary
    Write-Host ('DATABASE_STATE='+$summary.databaseState)
    Write-Host 'FRONTEND_DEPLOYMENT=NOT_DISPATCHED'
    Write-Host ('ADMIN_DOCUMENT_EVIDENCE='+$evidence)
}
if($summary.result -cne 'PASS'){exit 1}
