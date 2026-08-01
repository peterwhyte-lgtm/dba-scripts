<#
.SYNOPSIS
Compare current sp_configure and key database settings against a saved baseline.

.DESCRIPTION
Run with -SaveBaseline to capture a point-in-time snapshot of sp_configure values and
key database properties to a JSON file. Run without it (or with -BaselineFile) to compare
current state against the saved baseline and report drift. Designed for change tracking:
run after maintenance windows to confirm only expected settings changed.

.NOTES
ScriptType  : hybrid
TargetScope : single server
RiskLevel   : SAFE

.EXAMPLE
# Save a baseline
.\Compare-ConfigurationBaseline.ps1 -ServerInstance PROD01 -SaveBaseline

# Compare current state to saved baseline
.\Compare-ConfigurationBaseline.ps1 -ServerInstance PROD01

# Compare to a specific baseline file
.\Compare-ConfigurationBaseline.ps1 -ServerInstance PROD01 -BaselineFile .\output-files\baselines\PROD01-baseline.json
#>

param(
    [string]$ServerInstance = '.',
    [switch]$SaveBaseline,
    [string]$BaselineFile,
    [ValidateSet('Table', 'Csv')]
    [string]$OutputFormat = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$runner     = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'
$baselineDir = Join-Path $repoRoot 'output-files\baselines'

$resolvedName = if ($ServerInstance -in @('.','localhost')) { $env:COMPUTERNAME } else { $ServerInstance }
$safeName     = ($resolvedName -replace '[\\,\.:]+', '-').Trim('-')
$defaultBaseline = Join-Path $baselineDir "$safeName-baseline.json"

# ── Collect current state ──────────────────────────────────────────────────────
function Get-CurrentSnapshot {
    param([string]$Server)

    $configSql = @"
SELECT name, CAST(value_in_use AS NVARCHAR(100)) AS current_value
FROM sys.configurations
ORDER BY name;
"@
    $dbPropSql = @"
SELECT name AS database_name,
       recovery_model_desc, compatibility_level,
       CAST(is_auto_shrink_on  AS VARCHAR(5)) AS auto_shrink,
       CAST(is_auto_close_on   AS VARCHAR(5)) AS auto_close,
       page_verify_option_desc,
       CAST(is_encrypted       AS VARCHAR(5)) AS is_tde
FROM sys.databases
WHERE database_id > 4
ORDER BY name;
"@
    $useModule = $null -ne (Get-Module -Name SqlServer -ListAvailable | Select-Object -First 1)

    $configRows = if ($useModule) {
        Invoke-Sqlcmd -ServerInstance $Server -Query $configSql -TrustServerCertificate
    } else {
        & sqlcmd -S $Server -Q $configSql -s "," -W -h -1 2>$null |
            ConvertFrom-Csv -Header 'name','current_value'
    }

    $dbRows = if ($useModule) {
        Invoke-Sqlcmd -ServerInstance $Server -Query $dbPropSql -TrustServerCertificate
    } else {
        & sqlcmd -S $Server -Q $dbPropSql -s "," -W -h -1 2>$null |
            ConvertFrom-Csv -Header 'database_name','recovery_model_desc','compatibility_level',
                                    'auto_shrink','auto_close','page_verify_option_desc','is_tde'
    }

    return @{
        captured_at    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        server_instance = $Server
        sp_configure   = @($configRows  | ForEach-Object { @{ name=$_.name; value=$_.current_value } })
        db_properties  = @($dbRows      | ForEach-Object {
            @{  database_name         = $_.database_name
                recovery_model        = $_.recovery_model_desc
                compatibility_level   = $_.compatibility_level
                auto_shrink           = $_.auto_shrink
                auto_close            = $_.auto_close
                page_verify           = $_.page_verify_option_desc
                tde                   = $_.is_tde
            }
        })
    }
}

$snapshot = Get-CurrentSnapshot -Server $ServerInstance

# ── Save baseline mode ─────────────────────────────────────────────────────────
if ($SaveBaseline) {
    if (-not (Test-Path $baselineDir)) { New-Item -ItemType Directory -Path $baselineDir -Force | Out-Null }
    $outFile = if ($BaselineFile) { $BaselineFile } else { $defaultBaseline }
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $outFile -Encoding UTF8
    Write-Host "Baseline saved: $outFile" -ForegroundColor Green
    Write-Host "  Captured: $($snapshot.captured_at) | Server: $ServerInstance" -ForegroundColor Gray
    Write-Host "  sp_configure entries: $($snapshot.sp_configure.Count) | Databases: $($snapshot.db_properties.Count)" -ForegroundColor Gray
    return
}

# ── Compare mode ──────────────────────────────────────────────────────────────
$baseFile = if ($BaselineFile) { $BaselineFile } else { $defaultBaseline }

if (-not (Test-Path $baseFile)) {
    Write-Warning "No baseline found at: $baseFile"
    Write-Host "Run with -SaveBaseline to capture a baseline first." -ForegroundColor Yellow
    return
}

$baseline = Get-Content $baseFile -Raw | ConvertFrom-Json

Write-Host "Comparing $ServerInstance against baseline from $($baseline.captured_at)" -ForegroundColor Cyan

$diffs = [System.Collections.Generic.List[PSCustomObject]]::new()

# sp_configure drift
$baseConfig = @{}
$baseline.sp_configure | ForEach-Object { $baseConfig[$_.name] = $_.value }

foreach ($row in $snapshot.sp_configure) {
    $baseVal = $baseConfig[$row.name]
    if ($null -eq $baseVal) {
        $diffs.Add([PSCustomObject]@{
            section       = 'sp_configure'
            item          = $row.name
            baseline_value = '(not in baseline)'
            current_value  = $row.value
            change_type    = 'ADDED'
        })
    } elseif ($baseVal -ne $row.value) {
        $diffs.Add([PSCustomObject]@{
            section        = 'sp_configure'
            item           = $row.name
            baseline_value = $baseVal
            current_value  = $row.value
            change_type    = 'CHANGED'
        })
    }
}

# Database property drift
$baseDbMap = @{}
$baseline.db_properties | ForEach-Object { $baseDbMap[$_.database_name] = $_ }

foreach ($db in $snapshot.db_properties) {
    $base = $baseDbMap[$db.database_name]
    if ($null -eq $base) {
        $diffs.Add([PSCustomObject]@{
            section        = 'database'
            item           = $db.database_name
            baseline_value = '(new database)'
            current_value  = "recovery=$($db.recovery_model) compat=$($db.compatibility_level)"
            change_type    = 'NEW_DB'
        })
        continue
    }
    $props = @('recovery_model','compatibility_level','auto_shrink','auto_close','page_verify','tde')
    foreach ($p in $props) {
        if ($base.$p -ne $db.$p) {
            $diffs.Add([PSCustomObject]@{
                section        = "database.$($db.database_name)"
                item           = $p
                baseline_value = $base.$p
                current_value  = $db.$p
                change_type    = 'CHANGED'
            })
        }
    }
}

if ($diffs.Count -eq 0) {
    Write-Host "`nNo configuration drift detected vs baseline from $($baseline.captured_at)" -ForegroundColor Green
    return
}

Write-Host "`n$($diffs.Count) difference(s) found:" -ForegroundColor Yellow

if ($OutputFormat -eq 'Csv') {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outFile   = if ($OutputPath) { $OutputPath } else {
        $outDir = Join-Path $repoRoot 'output-files\reviews\reporting'
        if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
        Join-Path $outDir "Compare-ConfigurationBaseline-$safeName-$timestamp.csv"
    }
    $diffs | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
    Write-Host "Output saved: $outFile" -ForegroundColor Green
} else {
    $diffs | Format-Table section, item, baseline_value, current_value, change_type -AutoSize
}
