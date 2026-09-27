param([ValidateSet('success','native_failure','malformed','missing_image','wrong_ca')][string]$Scenario='success')
# Transport orchestration only. These mocks cannot prove a remote database result.
$ErrorActionPreference='Stop'
$global:reviewScenario=$Scenario
$global:reviewSqlCalls=0
$global:reviewPasswordPrompts=0
$temp=Join-Path ([IO.Path]::GetTempPath()) ('document-review-unit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$global:reviewFakeCa=Join-Path $temp 'ca.crt'
Set-Content -LiteralPath $global:reviewFakeCa -Value 'synthetic transport test; not a certificate'
$global:reviewFixture=Join-Path $PSScriptRoot 'fixtures/preflight-success.txt'
function global:Get-FileHash {
    param([string]$LiteralPath,[string]$Algorithm)
    if ($LiteralPath -eq 'C:\Users\ASUS\Downloads\prod-ca-2021 (1).crt') {
        $value=if($global:reviewScenario -eq 'wrong_ca'){'wrong'}else{'700723581420DD1AC98FD7E9AC529F0EF210EADCAF87FC868A3AD7D114C2F3B7'}
        return [pscustomobject]@{Hash=$value}
    }
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}
function global:Resolve-Path { param([string]$LiteralPath) [pscustomobject]@{Path=$global:reviewFakeCa} }
function global:Read-Host {
    param([string]$Prompt,[switch]$AsSecureString)
    $global:reviewPasswordPrompts++
    ConvertTo-SecureString 'synthetic-never-networked' -AsPlainText -Force
}
function global:docker {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    switch ($Arguments[0]) {
        'context' { if($Arguments[1] -eq 'show'){'desktop-linux'}else{'unix:///synthetic-docker.sock'} }
        'image' { if($global:reviewScenario -eq 'missing_image'){$global:LASTEXITCODE=1;Write-Error 'No such image'}else{'sha256:synthetic'} }
        'run' {
            $global:reviewSqlCalls++
            if($Arguments -notcontains 'PGPASSWORD' -or $Arguments -notcontains 'PGSSLMODE=verify-full' -or $Arguments -notcontains 'PGSSLSNI=1' -or
                $Arguments -notcontains 'PGUSER=postgres.wsuctjhbqiedttfnwjvf' -or $Arguments -notcontains '--no-password' -or
                $Arguments -notcontains '--pull=never' -or $Arguments[-1] -ne '/work/preflight_read_only.sql' -or
                -not ($Arguments -match '^PGOPTIONS=.*default_transaction_read_only=on')) { throw 'Transport guard missing' }
            if($global:reviewScenario -eq 'native_failure') {
                $global:LASTEXITCODE=3
                Write-Error 'psql:/work/preflight_read_only.sql:33: ERROR: P0001: Onboarding source contract mismatch; collect exact deployed definition'
            } elseif($global:reviewScenario -eq 'malformed') {'ADMIN_DOCUMENT_PREFLIGHT=PASS'}
            else {Get-Content -LiteralPath $global:reviewFixture}
        }
        default {throw 'Unexpected transport command'}
    }
}
$env:PGPASSWORD='prior-synthetic-value'
$caught=$false
try {
    try { & (Join-Path $PSScriptRoot 'START_READ_ONLY_CHECK.ps1') -EvidenceRoot $temp } catch {$caught=$true}
    if($env:PGPASSWORD -ne 'prior-synthetic-value'){throw 'Password environment was not restored'}
    if($Scenario -eq 'wrong_ca') {
        if(-not $caught -or $global:reviewSqlCalls -ne 0 -or $global:reviewPasswordPrompts -ne 0){throw 'CA failure did not stop dispatch'}
    } else {
        $file=Get-ChildItem -LiteralPath $temp -Recurse -Filter 'review-result.json'
        $report=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $wanted=if($Scenario -eq 'success'){'PASS'}else{'FAIL'}
        if($report.result -ne $wanted){throw 'Unexpected result'}
        if($report.productionMutation -ne 'NOT_DISPATCHED'){throw 'Unexpected mutation marker'}
        $expectedCalls=if($Scenario -eq 'missing_image'){0}else{1}
        if($global:reviewSqlCalls -ne $expectedCalls){throw 'Unexpected SQL calls or retry'}
        if($Scenario -eq 'native_failure' -and $report.failure.category -ne 'ONBOARDING_CONTRACT_MISMATCH'){throw 'Native failure classification lost'}
        if((Get-Content -LiteralPath $file.FullName -Raw) -match 'synthetic-never-networked|prior-synthetic-value'){throw 'Credential in evidence'}
    }
    Write-Output ('TRANSPORT_ORCHESTRATION_'+$Scenario.ToUpperInvariant()+'=PASS')
} finally {
    $env:PGPASSWORD=$null
    Remove-Item -LiteralPath $temp -Recurse -Force
}
