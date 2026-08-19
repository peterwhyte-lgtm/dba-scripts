<#
.SYNOPSIS
Generates SQL Agent job DDL for routine housekeeping: integrity check (DBCC CHECKDB),
history cleanup (backup/job/mail history), and error log cycling.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a ready-to-run SQL script that creates three housekeeping agent jobs.
               Retention periods and schedule hours are declared in the SQL — edit before generating.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputPath
Full path for the generated .sql file. Defaults to output-files\maintenance\maintenance-jobs-<server>-<ts>.sql.

.EXAMPLE
.\powershell\wrappers\maintenance\Generate-MaintenanceJobs.ps1

.EXAMPLE
.\powershell\wrappers\maintenance\Generate-MaintenanceJobs.ps1 -ServerInstance PROD01\SQL2019
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [string]$OutputPath,
    [ValidateSet('Sql','Csv')]
    [string]$OutputFormat   = 'Sql'
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username  -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password  -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$sqlScript = Join-Path $repoRoot 'sql\maintenance\Generate-MaintenanceJobs.sql'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir    = Join-Path $repoRoot 'output-files\maintenance'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

$sqlOutPath = if ($OutputPath) {
    $d = Split-Path $OutputPath -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $OutputPath
} else {
    Join-Path $outDir "maintenance-jobs-$safeName-$ts.sql"
}

Write-Host ''
Write-Host '[generate] Generating maintenance job DDL...' -ForegroundColor Cyan
Write-Host "[generate] Server  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[generate] Output  : $sqlOutPath" -ForegroundColor Cyan
Write-Host ''

$ddlText = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $params = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        InputFile              = $sqlScript
        QueryTimeout           = 120
        MaxCharLength          = 2000000
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }
    $result  = Invoke-Sqlcmd @params
    $ddlText = $result.ddl
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.' }
    $sqlcmdArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript, '-y', '0', '-b', '-C')
    if ($Username -and $Password) { $sqlcmdArgs += @('-U', $Username, '-P', $Password) }
    else                          { $sqlcmdArgs += '-E' }
    $lines = & $sqlcmdExe.Source @args
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe failed with exit code $LASTEXITCODE" }
    $ddlText = (($lines | Select-Object -Skip 2) -join "`r`n").TrimEnd()
}

if (-not $ddlText -or $ddlText.Trim() -eq '') {
    Write-Host '[generate] No DDL produced.' -ForegroundColor Yellow
    return
}

$isCsv = $OutputFormat -eq 'Csv' -or $sqlOutPath -like '*.csv'
if ($isCsv) {
    [PSCustomObject]@{ ddl = $ddlText } |
        Export-Csv -LiteralPath $sqlOutPath -NoTypeInformation -Encoding UTF8
} else {
    [System.IO.File]::WriteAllText($sqlOutPath, $ddlText, [System.Text.Encoding]::UTF8)
}

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done - $lineCount lines" -ForegroundColor Green
Write-Host "[generate] Output : $sqlOutPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Review history retention days and schedule hours in the SQL before running on target.' -ForegroundColor Yellow
Write-Host ''