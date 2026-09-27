[CmdletBinding()]
param(
    [string]$EvidenceRoot = 'D:\Aadhyant-Review\Document-Joining-Production-Evidence',
    [switch]$SelfTest,
    [switch]$CheckArtifactsOnly
)
# No write mode, target override, SQL override, repair dispatcher or automatic retry.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$pins = @{
    'preflight_read_only.sql' = '49e42c4559d6015a8152addce98d4567e5715da8b929840c0840a69c3a463b15'
    'Review.Core.psm1' = '84a1df8956f18656f91f2795b97670e295b466301a39b0dc649c3e7133f5de72'
    'test_review_parser.ps1' = '86c6be1a2458f9c5191be5870526688b3b53714523ed29d621420cfe35d6421a'
    'fixtures/preflight-success.txt' = '96353d8d6bde5282d827ffbc5f9d6dc850c93477e08819e4ac9473c98a8abb16'
}
foreach ($name in $pins.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $root $name) -Algorithm SHA256).Hash -ne $pins[$name]) {
        throw ('Artifact hash mismatch: ' + $name)
    }
}
Import-Module (Join-Path $root 'Review.Core.psm1') -Force
if ($CheckArtifactsOnly) { Write-Output 'ADMIN_DOCUMENT_REVIEW_ARTIFACTS=PASS'; return }
if ($SelfTest) { & (Join-Path $root 'test_review_parser.ps1'); return }

$ca = 'C:\Users\ASUS\Downloads\prod-ca-2021 (1).crt'
$caHash = '700723581420DD1AC98FD7E9AC529F0EF210EADCAF87FC868A3AD7D114C2F3B7'
if ((Get-FileHash -LiteralPath $ca -Algorithm SHA256).Hash -ne $caHash) { throw 'Pinned Production CA SHA-256 mismatch' }
$ca = (Resolve-Path -LiteralPath $ca).Path
if ($root.Contains(',') -or $ca.Contains(',')) { throw 'Docker mount paths must not contain commas' }
$image = 'supabase/postgres@sha256:f371b5f3f2ac0a05703f33d6e6134515fb2498cab708fb948a0aeb7481467c00'
$runId = 'document-preflight-' + [guid]::NewGuid().ToString('N').Substring(0,12)
$evidence = Join-Path ([IO.Path]::GetFullPath($EvidenceRoot)) $runId
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$priorPassword = $env:PGPASSWORD
$bstr = [IntPtr]::Zero
$stage = 'LOCAL_DOCKER_CHECK'
$summary = [ordered]@{
    scope='Production catalog only'; project='wsuctjhbqiedttfnwjvf'; runId=$runId;
    startedUtc=[DateTime]::UtcNow.ToString('o'); result='INCOMPLETE';
    productionMutation='NOT_DISPATCHED'; repairApproval='PENDING';
    sqlSha256=$pins['preflight_read_only.sql']; image=$image
}
function Invoke-ReadOnlyNative([string[]]$Arguments) {
    $errFile = Join-Path $evidence ('.native-' + [guid]::NewGuid().ToString('N') + '.txt')
    $priorPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 sends native stderr through its error stream.
        $ErrorActionPreference = 'Continue'
        $lines = @(& docker @Arguments 2> $errFile)
        $nativeExit = $LASTEXITCODE
        $ErrorActionPreference = $priorPreference
        if ($nativeExit -ne 0) {
            $raw = if (Test-Path -LiteralPath $errFile) { Get-Content -LiteralPath $errFile -Raw } else { '' }
            $summary.nativeExit = $nativeExit
            $summary.failure = Get-DocumentFailureEvidence -ErrorText ([string]$raw)
            throw "NATIVE_EXIT=$nativeExit"
        }
        return $lines
    } finally {
        $ErrorActionPreference = $priorPreference
        if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force }
    }
}
try {
    if ($env:DOCKER_HOST -and $env:DOCKER_HOST -notmatch '^(npipe|unix)://') { throw 'REMOTE_DOCKER_FORBIDDEN' }
    $context = (@(Invoke-ReadOnlyNative @('context','show')) -join '').Trim()
    $endpoint = (@(Invoke-ReadOnlyNative @('context','inspect',$context,'--format','{{.Endpoints.docker.Host}}')) -join '').Trim()
    if ($endpoint -notmatch '^(npipe|unix)://') { throw 'LOCAL_DOCKER_SOCKET_REQUIRED' }
    Invoke-ReadOnlyNative @('image','inspect',$image,'--format','{{.Id}}') | Out-Null
    $stage = 'PASSWORD_PROMPT'
    $secure = Read-Host 'Production database password' -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $env:PGPASSWORD = $plain
    $stage = 'READ_ONLY_PREFLIGHT_SQL'
    $dockerArguments = @(
        'run','--rm','--pull=never','--entrypoint','psql',
        '--mount',('type=bind,src='+$root+',dst=/work,readonly'),
        '--mount',('type=bind,src='+$ca+',dst=/cert/ca.crt,readonly'),
        '-e','PGPASSWORD','-e','PGHOST=aws-0-ap-northeast-1.pooler.supabase.com',
        '-e','PGPORT=5432','-e','PGDATABASE=postgres','-e','PGUSER=postgres.wsuctjhbqiedttfnwjvf',
        '-e','PGSSLMODE=verify-full','-e','PGSSLROOTCERT=/cert/ca.crt','-e','PGSSLSNI=1',
        '-e','PGCONNECT_TIMEOUT=15',
        '-e','PGOPTIONS=-c default_transaction_read_only=on -c statement_timeout=30000 -c idle_in_transaction_session_timeout=30000',
        $image,'-X','-A','-t','--no-password','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose',
        '-f','/work/preflight_read_only.sql'
    )
    $lines = @(Invoke-ReadOnlyNative -Arguments $dockerArguments)
    $stage = 'OUTPUT_VALIDATION'
    Test-DocumentPreflightOutput -Lines $lines -NativeExit 0 | Out-Null
    $summary.result = 'PASS'
    $summary.nativeExit = 0
    $lines | Set-Content -LiteralPath (Join-Path $evidence 'preflight-output.txt') -Encoding UTF8
    Write-Host 'ADMIN_DOCUMENT_PREFLIGHT=PASS'
} catch {
    $summary.result = 'FAIL'
    $summary.failureStage = $stage
    # Only our fixed categories appear in console/report, never arbitrary exception text.
    Write-Host 'ADMIN_DOCUMENT_PREFLIGHT=FAIL'
    Write-Host ('FAILURE_STAGE=' + $stage)
    if ($summary.Contains('failure')) {
        Write-Host ('FAILURE_CATEGORY=' + $summary.failure.category)
        Write-Host ('SQLSTATE=' + $summary.failure.sqlState)
        Write-Host ('SQL_LINE=' + $summary.failure.sqlLine)
        foreach ($label in $summary.failure.checks) { Write-Host ('CATALOG_MISMATCH=' + $label) }
    } else { Write-Host 'FAILURE_CATEGORY=LOCAL_OR_OUTPUT_VALIDATION_FAILURE' }
} finally {
    $env:PGPASSWORD = $priorPassword
    $plain = $null; $secure = $null
    if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    $summary.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'review-result.json') -Encoding UTF8
    Write-Host 'PRODUCTION_MUTATION=NOT_DISPATCHED'
    Write-Host ('ADMIN_DOCUMENT_EVIDENCE=' + $evidence)
}
if ($summary.result -cne 'PASS') { exit 1 }
