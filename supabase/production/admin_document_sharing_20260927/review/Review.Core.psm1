Set-StrictMode -Version 2.0

function Test-DocumentPreflightOutput {
    [CmdletBinding()]
    param([AllowEmptyCollection()][string[]]$Lines, [int]$NativeExit)
    if ($NativeExit -ne 0) { throw "NATIVE_EXIT=$NativeExit" }
    $actual = @($Lines | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $expected = @('BEGIN', 'SET', 'DO', 'ADMIN_DOCUMENT_PREFLIGHT=PASS', 'ROLLBACK')
    if ($actual.Count -ne $expected.Count) { throw 'OUTPUT_MISSING_OR_MALFORMED' }
    for ($i = 0; $i -lt $expected.Count; $i++) {
        if ($actual[$i] -cne $expected[$i]) { throw 'OUTPUT_MISSING_OR_MALFORMED' }
    }
    return $true
}

function Get-DocumentFailureEvidence {
    param([AllowEmptyString()][string]$ErrorText)
    # PowerShell can wrap native stderr and add ANSI formatting before redirection.
    $ErrorText = [regex]::Replace($ErrorText, '\x1b\[[0-9;]*[A-Za-z]', '')
    $ErrorText = [regex]::Replace($ErrorText, '(?m)^\s*\|\s?', '')
    $ErrorText = [regex]::Replace($ErrorText, '\s+', ' ')
    $state = 'UNKNOWN'
    if ($ErrorText -match '(?m)(?:ERROR|FATAL):\s+([0-9A-Z]{5}):') { $state = $Matches[1] }
    $line = 'UNKNOWN'
    if ($ErrorText -match 'preflight_read_only\.sql:(\d+):') { $line = $Matches[1] }
    $category = 'NATIVE_FAILURE'
    $checks = @()
    if ($ErrorText.Contains('Resume baseline mismatch:')) {
        $category = 'RESUME_BASELINE_MISMATCH'
        # Only the known guard's catalog labels; never raw definitions or values.
        if ($ErrorText -match 'Resume baseline mismatch: ([a-zA-Z0-9_:.(), ]+)') {
            $checks = @($Matches[1].Trim() -split ',(?=(?:helper:|table:|function:|executor|storage_|private_bucket|documents_acl|sharing_))')
        }
    } elseif ($ErrorText.Contains('Onboarding source contract mismatch; collect exact deployed definition')) {
        $category = 'ONBOARDING_CONTRACT_MISMATCH'
    } elseif ($ErrorText.Contains('Canonical onboarding table with RLS required')) {
        $category = 'ONBOARDING_TABLE_OR_RLS_MISMATCH'
    } elseif ($ErrorText.Contains('Unexpected browser onboarding privileges')) {
        $category = 'ONBOARDING_PRIVILEGE_MISMATCH'
    } elseif ($ErrorText.Contains('Upgrade collision; do not replay')) {
        $category = 'UPGRADE_ALREADY_PRESENT_OR_COLLISION'
    }
    [pscustomobject]@{sqlState=$state; sqlLine=$line; category=$category; checks=$checks}
}

Export-ModuleMember -Function Test-DocumentPreflightOutput,Get-DocumentFailureEvidence
