[CmdletBinding()]
param(
    [string]$EnvFile,
    [switch]$RunAssertionTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Identity {
    param([Parameter(Mandatory)][string]$Message)
    throw "STAGING IDENTITY REFUSED: $Message"
}

function Test-StagingIdentity {
    param(
        [Parameter(Mandatory)][string]$ExpectedProjectRef,
        [Parameter(Mandatory)][string]$ExpectedHost,
        [Parameter(Mandatory)][string]$ConfiguredUser,
        [Parameter(Mandatory)][string]$ConfiguredHost,
        [Parameter(Mandatory)][string]$ConfiguredDatabase,
        [Parameter(Mandatory)][string]$ConfiguredPort,
        [Parameter(Mandatory)][string]$SslMode,
        [Parameter(Mandatory)][string[]]$ProductionProjectRefs,
        [Parameter(Mandatory)][string[]]$ProductionHosts,
        [Parameter(Mandatory)][pscustomobject]$Actual
    )

    $expectedUser = "postgres.$ExpectedProjectRef"
    $failures = [Collections.Generic.List[string]]::new()
    if ($ExpectedProjectRef -notmatch '^[a-z0-9]{20}$') { $failures.Add('Expected project ref is malformed.') }
    if ($ExpectedHost -notmatch '^[a-z0-9.-]+$') { $failures.Add('Expected host is malformed.') }
    if ($ConfiguredUser -cne $expectedUser) { $failures.Add('Configured connection username is not the approved Session Pooler identity.') }
    if ($ConfiguredHost -cne $ExpectedHost) { $failures.Add('Configured host is not the approved staging host.') }
    if ($ConfiguredDatabase -cne 'postgres') { $failures.Add('Configured database is not postgres.') }
    if ($ConfiguredPort -cne '5432') { $failures.Add('Configured port is not 5432.') }
    if ($SslMode -cne 'require') { $failures.Add('TLS is not required.') }
    if ($ProductionProjectRefs -contains $ExpectedProjectRef) { $failures.Add('Production project ref detected.') }
    if ($ProductionHosts -contains $ExpectedHost) { $failures.Add('Production host detected.') }
    if ([string]$Actual.database_name -cne 'postgres') { $failures.Add('Remote database is not postgres.') }
    if ([string]$Actual.database_user -cne 'postgres') { $failures.Add('Unexpected backend database role.') }
    if ([string]$Actual.server_port -cne '5432') { $failures.Add('Unexpected remote server port.') }
    if ([string]$Actual.server_version -notmatch '^17\.6(?:\D|$)') { $failures.Add('Unexpected PostgreSQL server version.') }
    if ([string]$Actual.transaction_read_only -cne 'on') { $failures.Add('Remote transaction is not read-only.') }
    return $failures.ToArray()
}

function Invoke-AssertionTests {
    $base = @{
        ExpectedProjectRef = 'abcdefghijklmnopqrst'
        ExpectedHost = 'staging.pooler.supabase.com'
        ConfiguredUser = 'postgres.abcdefghijklmnopqrst'
        ConfiguredHost = 'staging.pooler.supabase.com'
        ConfiguredDatabase = 'postgres'
        ConfiguredPort = '5432'
        SslMode = 'require'
        ProductionProjectRefs = @('zyxwvutsrqponmlkjihg')
        ProductionHosts = @('production.pooler.supabase.com')
        Actual = [pscustomobject]@{
            database_name = 'postgres'
            database_user = 'postgres'
            server_port = '5432'
            server_version = '17.6'
            transaction_read_only = 'on'
        }
    }
    $cases = @(
        @{ Name = 'approved pooler user and postgres backend role'; Mutate = {}; Pass = $true },
        @{ Name = 'wrong connection user'; Mutate = { param($v) $v.ConfiguredUser = 'postgres.wrongprojectref0000' }; Pass = $false },
        @{ Name = 'unexpected backend role'; Mutate = { param($v) $v.Actual.database_user = 'unexpected_role' }; Pass = $false },
        @{ Name = 'production denylist conflict'; Mutate = { param($v) $v.ProductionProjectRefs = @($v.ExpectedProjectRef) }; Pass = $false },
        @{ Name = 'read-only disabled'; Mutate = { param($v) $v.Actual.transaction_read_only = 'off' }; Pass = $false },
        @{ Name = 'wrong database and port'; Mutate = { param($v) $v.Actual.database_name = 'other'; $v.Actual.server_port = '6543' }; Pass = $false }
    )
    foreach ($case in $cases) {
        $values = @{}
        foreach ($key in $base.Keys) {
            if ($key -eq 'Actual') {
                $values[$key] = [pscustomobject]@{}
                foreach ($property in $base.Actual.psobject.Properties) { $values[$key] | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value }
            } elseif ($base[$key] -is [array]) { $values[$key] = @($base[$key]) }
            else { $values[$key] = $base[$key] }
        }
        & $case.Mutate $values
        $failed = @(Test-StagingIdentity @values).Count -gt 0
        if ($failed -eq $case.Pass) { throw "Assertion test failed: $($case.Name)" }
    }
    Write-Output 'STAGING IDENTITY ASSERTION TESTS PASSED'
}

if ($RunAssertionTests) {
    Invoke-AssertionTests
    exit 0
}

function Read-Environment {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Stop-Identity 'Environment file is missing.' }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) { Stop-Identity 'Environment file contains an invalid assignment.' }
        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
        if ($values.ContainsKey($name)) { Stop-Identity "Duplicate environment key: $name" }
        $values[$name] = $value
    }
    return $values
}

function Require-Value {
    param([Parameter(Mandatory)][hashtable]$Values, [Parameter(Mandatory)][string]$Name)
    if (-not $Values.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($Values[$Name])) { Stop-Identity "Required value is blank: $Name" }
    return [string]$Values[$Name]
}

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($EnvFile)) { $EnvFile = Join-Path $repositoryRoot '.env.staging.local' }

& (Join-Path $PSScriptRoot 'verify-staging-target.ps1') -EnvFile $EnvFile
if ($LASTEXITCODE -ne 0) { Stop-Identity 'Static staging guard failed.' }

$values = Read-Environment -Path ([IO.Path]::GetFullPath($EnvFile))
$projectRef = (Require-Value $values 'AADHYANT_STAGING_EXPECTED_PROJECT_REF').ToLowerInvariant()
$expectedHost = (Require-Value $values 'AADHYANT_STAGING_EXPECTED_DB_HOST').ToLowerInvariant()
$password = Require-Value $values 'AADHYANT_STAGING_DB_PASSWORD'
$productionRefs = @((Require-Value $values 'AADHYANT_PRODUCTION_DENYLIST_PROJECT_REFS').Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$productionHosts = @((Require-Value $values 'AADHYANT_PRODUCTION_DENYLIST_DB_HOSTS').Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$configuredUser = "postgres.$projectRef"
$psql = Join-Path $env:LOCALAPPDATA 'AadhyantTools\PostgreSQL-18.6\pgsql\bin\psql.exe'
if (-not (Test-Path -LiteralPath $psql -PathType Leaf)) { Stop-Identity 'Approved PostgreSQL client is missing.' }

try {
    $env:PGHOST = $expectedHost
    $env:PGPORT = '5432'
    $env:PGUSER = $configuredUser
    $env:PGDATABASE = 'postgres'
    $env:PGSSLMODE = 'require'
    $env:PGPASSWORD = $password
    $sql = @'
BEGIN TRANSACTION READ ONLY;

SELECT
  current_database() AS database_name,
  current_user AS database_user,
  inet_server_addr() AS server_address,
  inet_server_port() AS server_port,
  current_setting('server_version') AS server_version,
  current_setting('transaction_read_only') AS transaction_read_only;

ROLLBACK;
'@
    $output = @($sql | & $psql -X -v ON_ERROR_STOP=1 --csv --quiet)
    if ($LASTEXITCODE -ne 0) { Stop-Identity 'Read-only query failed.' }
    $csv = @($output | Where-Object { $_ -match '^(database_name,|postgres,)' })
    if ($csv.Count -ne 2) { Stop-Identity 'Read-only query returned an unexpected shape.' }
    $actual = ($csv -join "`n") | ConvertFrom-Csv
    $failures = @(Test-StagingIdentity -ExpectedProjectRef $projectRef -ExpectedHost $expectedHost -ConfiguredUser $configuredUser -ConfiguredHost $env:PGHOST -ConfiguredDatabase $env:PGDATABASE -ConfiguredPort $env:PGPORT -SslMode $env:PGSSLMODE -ProductionProjectRefs $productionRefs -ProductionHosts $productionHosts -Actual $actual)
    if ($failures.Count -gt 0) { Stop-Identity ($failures -join ' ') }
    Write-Output 'STAGING READ-ONLY IDENTITY VERIFIED'
    Write-Output 'Connection user: postgres.<approved-staging-ref>'
    Write-Output 'Backend database role: postgres'
    Write-Output 'Database: postgres'
    Write-Output 'Server port: 5432'
    Write-Output "Server version: $($actual.server_version)"
    Write-Output 'Transaction read-only: on'
    Write-Output 'TLS: required'
} finally {
    'PGPASSWORD', 'PGHOST', 'PGPORT', 'PGUSER', 'PGDATABASE', 'PGSSLMODE' | ForEach-Object {
        [Environment]::SetEnvironmentVariable($_, $null, 'Process')
    }
}
