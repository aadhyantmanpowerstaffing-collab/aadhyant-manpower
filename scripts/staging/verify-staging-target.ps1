[CmdletBinding()]
param(
    [string]$EnvFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Guard {
    param([Parameter(Mandatory)][string]$Message)
    throw "STAGING GUARD REFUSED: $Message"
}

function Read-GuardEnvironment {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Stop-Guard "Environment file is missing: $Path"
    }

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { Stop-Guard 'Environment file contains an invalid assignment.' }
        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if ($values.ContainsKey($name)) { Stop-Guard "Duplicate environment key: $name" }
        $values[$name] = $value
    }
    return $values
}

function Require-Value {
    param(
        [Parameter(Mandatory)][hashtable]$Values,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not $Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) {
        Stop-Guard "Required value is blank: $Name"
    }
    return [string]$Values[$Name]
}

function Split-IdentityList {
    param([Parameter(Mandatory)][string]$Value)
    $items = @($Value.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    if ($items.Count -eq 0) { Stop-Guard 'A required denylist is empty.' }
    return $items
}

function Get-MigrationManifestHash {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $rootPrefix = $RepositoryRoot.TrimEnd('\') + '\'
    $migrations = @(
        Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'supabase\migrations') -File -Filter '*.sql' |
            Where-Object { $_.Name -match '^(00[7-9]|01[0-9])_' } |
            Sort-Object Name
    )
    $expectedNumbers = @(7..19)
    $actualNumbers = @($migrations | ForEach-Object { [int]$_.Name.Substring(0, 3) })
    if (@($actualNumbers | Group-Object | Where-Object Count -ne 1).Count -ne 0) {
        Stop-Guard 'Duplicate migration number detected in the required 007-019 range.'
    }
    if (@(Compare-Object $expectedNumbers $actualNumbers -SyncWindow 0).Count -ne 0) {
        Stop-Guard 'Expected exactly one migration for each number 007-019.'
    }
    $files = @(
        Join-Path $RepositoryRoot 'supabase\schema.sql'
        $migrations | Select-Object -ExpandProperty FullName
    )
    if ($files.Count -ne 14) { Stop-Guard 'Expected schema.sql plus exactly migrations 007-019.' }

    $manifestLines = foreach ($file in $files) {
        if (-not $file.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Stop-Guard 'Migration manifest file is outside the repository root.'
        }
        $relative = $file.Substring($rootPrefix.Length).Replace('\', '/')
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative=$hash"
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($manifestLines -join "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($EnvFile)) {
    $EnvFile = Join-Path $repositoryRoot '.env.staging.local'
}
$values = Read-GuardEnvironment -Path ([IO.Path]::GetFullPath($EnvFile))

$branch = (& git -C $repositoryRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne 'web-platform-development') {
    Stop-Guard "Wrong Git branch: $branch"
}
$trackedStatus = @(& git -C $repositoryRoot status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0 -or $trackedStatus.Count -ne 0) {
    Stop-Guard 'Tracked worktree or index is not clean.'
}

$head = (& git -C $repositoryRoot rev-parse HEAD).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $head -notmatch '^[0-9a-f]{40}$') { Stop-Guard 'Cannot resolve Git HEAD.' }

$expectedProjectRef = (Require-Value $values 'AADHYANT_STAGING_EXPECTED_PROJECT_REF').ToLowerInvariant()
$expectedDbHost = (Require-Value $values 'AADHYANT_STAGING_EXPECTED_DB_HOST').ToLowerInvariant()
$stagingUrlText = Require-Value $values 'AADHYANT_STAGING_URL'
$dbUrlText = Require-Value $values 'AADHYANT_STAGING_DB_URL'
$productionProjectRefs = Split-IdentityList (Require-Value $values 'AADHYANT_PRODUCTION_DENYLIST_PROJECT_REFS')
$productionDbHosts = Split-IdentityList (Require-Value $values 'AADHYANT_PRODUCTION_DENYLIST_DB_HOSTS')
$approvedCommit = (Require-Value $values 'AADHYANT_STAGING_APPROVED_GIT_COMMIT').ToLowerInvariant()
$approvedManifestHash = (Require-Value $values 'AADHYANT_STAGING_APPROVED_MIGRATION_MANIFEST_SHA256').ToLowerInvariant()

if ($expectedProjectRef -notmatch '^[a-z0-9]{20}$') { Stop-Guard 'Expected staging project ref is malformed.' }
if ($expectedDbHost -notmatch '^[a-z0-9.-]+$') { Stop-Guard 'Expected staging DB host is malformed.' }
if ($approvedCommit -notmatch '^[0-9a-f]{40}$' -or $approvedCommit -ne $head) {
    Stop-Guard 'Git HEAD does not equal the approved staging-test commit.'
}
if ($approvedManifestHash -notmatch '^[0-9a-f]{64}$') { Stop-Guard 'Approved migration manifest hash is malformed.' }

try { $stagingUri = [Uri]$stagingUrlText } catch { Stop-Guard 'Staging URL is malformed.' }
try { $dbUri = [Uri]$dbUrlText } catch { Stop-Guard 'Staging DB URL is malformed.' }
if ($stagingUri.Scheme -ne 'https' -or $stagingUri.Host -ne "$expectedProjectRef.supabase.co") {
    Stop-Guard 'Staging URL does not exactly match the expected project ref.'
}
if ($dbUri.Scheme -notin @('postgres', 'postgresql')) { Stop-Guard 'DB URL is not PostgreSQL.' }
if ($dbUri.Host.ToLowerInvariant() -ne $expectedDbHost) { Stop-Guard 'DB URL host is not the staging allowlist host.' }

$dbUser = [Uri]::UnescapeDataString($dbUri.UserInfo.Split(':')[0]).ToLowerInvariant()
$directHost = "db.$expectedProjectRef.supabase.co"
$isDirect = $expectedDbHost -eq $directHost -and $dbUser -eq 'postgres'
$isSessionPooler = $expectedDbHost.EndsWith('.pooler.supabase.com') -and $dbUser -eq "postgres.$expectedProjectRef" -and $dbUri.Port -eq 5432
if (-not ($isDirect -or $isSessionPooler)) {
    Stop-Guard 'DB identity is neither the expected direct endpoint nor session-pooler identity.'
}

if ($productionProjectRefs -contains $expectedProjectRef) { Stop-Guard 'Production project ref detected.' }
if ($productionDbHosts -contains $expectedDbHost) { Stop-Guard 'Production DB host detected.' }

$actualManifestHash = Get-MigrationManifestHash -RepositoryRoot $repositoryRoot
if ($actualManifestHash -ne $approvedManifestHash) { Stop-Guard 'Migration manifest differs from the approved value.' }

Write-Output 'STAGING STATIC GUARD PASSED'
Write-Output "Branch: $branch"
Write-Output "Commit: $head"
Write-Output "Project ref: $($expectedProjectRef.Substring(0,4))...$($expectedProjectRef.Substring(16,4))"
Write-Output "DB host: $expectedDbHost"
Write-Output "Connection mode: $(if ($isDirect) { 'direct' } else { 'session-pooler' })"
Write-Output "Migration manifest SHA-256: $actualManifestHash"
Write-Output 'REMOTE READ-ONLY IDENTITY CHECK STILL REQUIRED BEFORE ANY MUTATION.'
