$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Review.Core.psm1') -Force
$lines = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/preflight-success.txt'))
Test-DocumentPreflightOutput -Lines $lines -NativeExit 0 | Out-Null
$checks = 1
function MustReject([string[]]$Rows, [int]$Code=0) {
    $rejected = $false
    try { Test-DocumentPreflightOutput -Lines $Rows -NativeExit $Code | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Parser accepted invalid evidence' }
}
MustReject @(); $checks++
MustReject $lines 3; $checks++
MustReject $lines 2; $checks++
MustReject @('ADMIN_DOCUMENT_PREFLIGHT=PASS'); $checks++
MustReject @('BEGIN','SET','DO','ADMIN_DOCUMENT_PREFLIGHT=FAIL','ROLLBACK'); $checks++
MustReject @('BEGIN','SET','DO','ADMIN_DOCUMENT_PREFLIGHT=PASS','COMMIT'); $checks++
MustReject @('BEGIN','SET','DO','ADMIN_DOCUMENT_PREFLIGHT=PASS','ROLLBACK','ADMIN_DOCUMENT_PREFLIGHT=PASS'); $checks++
MustReject @('BEGIN','SET','DO','prefix ADMIN_DOCUMENT_PREFLIGHT=PASS','ROLLBACK'); $checks++
MustReject @('BEGIN','SET','DO','ADMIN_DOCUMENT_PREFLIGHT=PASS'); $checks++
$failure = Get-DocumentFailureEvidence 'psql:/work/preflight_read_only.sql:33: ERROR: P0001: Onboarding source contract mismatch; collect exact deployed definition'
if ($failure.category -cne 'ONBOARDING_CONTRACT_MISMATCH' -or $failure.sqlState -cne 'P0001' -or $failure.sqlLine -cne '33') { throw 'Failure classification incorrect' }; $checks++
$failure = Get-DocumentFailureEvidence "     | psql:/work/preflight_read_only.sql:33: ERROR: P0001: Onboarding source`n     | contract mismatch; collect exact deployed definition"
if ($failure.category -cne 'ONBOARDING_CONTRACT_MISMATCH') { throw 'Wrapped native error classification lost' }; $checks++
$failure = Get-DocumentFailureEvidence 'psql:/work/preflight_read_only.sql:33: ERROR: P0001: Resume baseline mismatch: function:public.test(text,integer),storage_baseline'
if ($failure.checks.Count -ne 2 -or $failure.category -cne 'RESUME_BASELINE_MISMATCH') { throw 'Catalog labels lost' }; $checks++
$failure = Get-DocumentFailureEvidence 'connection rejected password=DO_NOT_PRINT; arbitrary native private contents'
if (($failure | ConvertTo-Json -Depth 4) -match 'DO_NOT_PRINT|private contents') { throw 'Raw native error leaked' }; $checks++
Write-Output ('ADMIN_DOCUMENT_REVIEW_PARSER=PASS; CHECKS=' + $checks)
