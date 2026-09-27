param([ValidateSet('success','preflight_native','preflight_malformed','forward_native','forward_missing_marker','postcheck_native','postcheck_malformed','verify_success','verify_failure','missing_approval','both_modes','wrong_ca','hash_mismatch','missing_image')][string]$Scenario='success')
# Local orchestration mocks only. No network, database, or real Docker commands.
$ErrorActionPreference='Stop'
$global:caseName=$Scenario;$global:stageCalls=@();$global:passwordPrompts=0
$global:fixtureRoot=Join-Path $PSScriptRoot 'fixtures'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('document-upgrade-unit-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$global:fakeCa=Join-Path $temp 'ca.crt';Set-Content -LiteralPath $global:fakeCa -Value 'synthetic test'
function global:Get-FileHash {
    param([string]$LiteralPath,[string]$Algorithm)
    if($global:caseName -eq 'hash_mismatch' -and $LiteralPath.EndsWith('forward_proposed.sql')){return [pscustomobject]@{Hash='wrong'}}
    if($LiteralPath -eq 'C:\Users\ASUS\Downloads\prod-ca-2021 (1).crt'){
        return [pscustomobject]@{Hash=$(if($global:caseName -eq 'wrong_ca'){'wrong'}else{'700723581420DD1AC98FD7E9AC529F0EF210EADCAF87FC868A3AD7D114C2F3B7'})}
    }
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm $Algorithm
}
function global:Resolve-Path {param([string]$LiteralPath) [pscustomobject]@{Path=$global:fakeCa}}
function global:Read-Host {
    param([string]$Prompt,[switch]$AsSecureString)
    $global:passwordPrompts++;ConvertTo-SecureString 'synthetic-never-networked' -AsPlainText -Force
}
function global:docker {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    switch($Arguments[0]){
        'context' {if($Arguments[1] -eq 'show'){'desktop-linux'}else{'unix:///synthetic.sock'}}
        'image' {if($global:caseName -eq 'missing_image'){$global:LASTEXITCODE=1;Write-Error 'No such image'}else{'sha256:synthetic'}}
        'run' {
            $kind=switch($Arguments[-1]){'/work/preflight_read_only.sql'{'preflight'}'/work/forward_proposed.sql'{'forward'}'/work/postcheck_read_only.sql'{'postcheck'}default{throw 'Unpinned SQL dispatch'}}
            $global:stageCalls+=@($kind)
            $readOnly=if($kind -eq 'forward'){'off'}else{'on'}
            if($Arguments -notcontains 'PGPASSWORD' -or $Arguments -notcontains 'PGSSLMODE=verify-full' -or
                $Arguments -notcontains 'PGSSLSNI=1' -or $Arguments -notcontains 'PGUSER=postgres.wsuctjhbqiedttfnwjvf' -or
                $Arguments -notcontains '--no-password' -or $Arguments -notcontains '--pull=never' -or
                -not ($Arguments -match ('^PGOPTIONS=.*default_transaction_read_only='+$readOnly+' '))){throw 'Transport guard missing'}
            if($global:caseName -eq ($kind+'_native') -or ($global:caseName -eq 'verify_failure' -and $kind -eq 'postcheck')){
                $global:LASTEXITCODE=3;Write-Error 'psql:/work/preflight_read_only.sql:33: ERROR: P0001: Onboarding source contract mismatch; collect exact deployed definition'
            }else{
                $rows=@(Get-Content -LiteralPath (Join-Path $global:fixtureRoot ($kind+'-success.txt')))
                if($global:caseName -eq ($kind+'_malformed')){'ARBITRARY_PASS'}
                elseif($global:caseName -eq 'forward_missing_marker' -and $kind -eq 'forward'){$rows[0..($rows.Count-2)]}
                else{$rows}
            }
        }
        default {throw 'Unexpected Docker command'}
    }
}
$env:PGPASSWORD='prior-synthetic-value';$caught=$false
try{
    $parameters=@{EvidenceRoot=$temp}
    if($Scenario -like 'verify_*'){$parameters.VerifyOnly=$true}
    elseif($Scenario -eq 'both_modes'){$parameters.VerifyOnly=$true;$parameters.IApproveAdminDocumentsProductionUpgrade=$true}
    elseif($Scenario -ne 'missing_approval'){$parameters.IApproveAdminDocumentsProductionUpgrade=$true}
    try{& (Join-Path $PSScriptRoot 'START_APPROVED_UPGRADE.ps1') @parameters}catch{$caught=$true}
    if($env:PGPASSWORD -ne 'prior-synthetic-value'){throw 'Password environment not restored'}
    if($Scenario -in @('missing_approval','both_modes','wrong_ca','hash_mismatch')){
        if(-not $caught -or $global:stageCalls.Count -ne 0 -or $global:passwordPrompts -ne 0){throw 'Guard did not stop dispatch'}
    }else{
        $file=Get-ChildItem -LiteralPath $temp -Recurse -Filter 'execution-result.json'
        $report=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $expected=if($Scenario -in @('success','verify_success')){'PASS'}else{'FAIL'}
        if($report.result -ne $expected){throw 'Wrong overall verdict'}
        $calls=if($Scenario -eq 'missing_image'){''}elseif($Scenario -like 'preflight_*'){'preflight'}elseif($Scenario -like 'forward_*'){'preflight,forward'}elseif($Scenario -like 'verify_*'){'postcheck'}else{'preflight,forward,postcheck'}
        if(($global:stageCalls -join ',') -ne $calls){throw 'Wrong dispatch sequence or retry'}
        $state=if($Scenario -eq 'success' -or $Scenario -like 'postcheck_*'){'COMMITTED'}elseif($Scenario -like 'forward_*'){'COMMIT_UNCONFIRMED'}else{'NOT_DISPATCHED'}
        if($report.databaseState -ne $state){throw 'Commit/verification state was conflated'}
        if((Get-Content -LiteralPath $file.FullName -Raw) -match 'synthetic-never-networked|prior-synthetic-value'){throw 'Credentials in evidence'}
    }
    Write-Output ('EXECUTION_ORCHESTRATION_'+$Scenario.ToUpperInvariant()+'=PASS')
}finally{$env:PGPASSWORD=$null;Remove-Item -LiteralPath $temp -Recurse -Force}
