$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Execution.Core.psm1') -Force
$count=0
function MustReject([string[]]$Rows,[string]$Stage,[int]$ExitCode=0){
    $rejected=$false
    try{Test-DocumentStageOutput -Lines $Rows -NativeExit $ExitCode -Stage $Stage | Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Parser accepted invalid evidence'}
}
foreach($stage in @('preflight','forward','postcheck')){
    $rows=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot ('fixtures/'+$stage+'-success.txt')))
    Test-DocumentStageOutput -Lines $rows -NativeExit 0 -Stage $stage | Out-Null;$count++
    MustReject $rows $stage 2;$count++
    MustReject $rows $stage 3;$count++
    MustReject @() $stage;$count++
    MustReject @($rows[-1]) $stage;$count++
    MustReject @($rows[0..($rows.Count-2)]) $stage;$count++
    MustReject @($rows+$rows[-1]) $stage;$count++
    $bad=@($rows);$bad[-1]='FORGED_PASS';MustReject $bad $stage;$count++
    $bad=@($rows);$bad[0]='COMMIT';MustReject $bad $stage;$count++
}
Write-Output ('ADMIN_DOCUMENT_EXECUTION_PARSER=PASS; CHECKS='+$count)
