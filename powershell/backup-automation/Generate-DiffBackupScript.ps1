<#
.SYNOPSIS
Generates a DIFFERENTIAL backup T-SQL script for all online user databases.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Generate differential backup DDL for review and execution in SSMS.

.DESCRIPTION
Executes sql\backups\Generate-DiffBackupScript.sql and writes the result to
output-files\backups\ as a .sql file ready to open in SSMS. When called from
the web UI (-OutputPath supplied) also writes a single-column CSV so the web UI
renders the DDL with a Copy button.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER if set.

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputFormat
Accepted for compatibility with the web UI run path. Has no effect on output format.

.PARAMETER OutputPath
When supplied (web UI mode), writes a single-column CSV so the web UI can display
and copy the generated script.

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\backup-automation\Generate-DiffBackupScript.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\powershell\backup-automation\Generate-DiffBackupScript.ps1 -ServerInstance PROD01\SQL2019
#>
param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [ValidateSet('Table','Csv')]
    [string]$OutputFormat   = 'Table',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\backups\Generate-DiffBackupScript.sql'
if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

Write-Host '[generate] Generating DIFFERENTIAL backup script...' -ForegroundColor Cyan
Write-Host "[generate] Server : $ServerInstance"                 -ForegroundColor Cyan

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
    $ddlText = (Invoke-Sqlcmd @params).script
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.' }
    $sqlArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript, '-y', '0', '-b', '-C')
    if ($Username -and $Password) { $sqlArgs += @('-U', $Username, '-P', $Password) } else { $sqlArgs += '-E' }
    $lines = & $sqlcmdExe.Source @sqlArgs
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe failed with exit code $LASTEXITCODE" }
    $ddlText = ($lines -join "`r`n").Trim()
}

if (-not $ddlText -or $ddlText.Trim() -eq '') {
    Write-Host '[generate] No output — no online user databases found.' -ForegroundColor Yellow
    return
}

$safeName   = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$ts         = Get-Date -Format 'yyyyMMdd-HHmmss'
$sqlOutDir  = Join-Path $repoRoot 'output-files\backups'
New-Item -ItemType Directory -Path $sqlOutDir -Force | Out-Null
$sqlOutPath = Join-Path $sqlOutDir "backup-script-diff-$safeName-$ts.sql"
[System.IO.File]::WriteAllText($sqlOutPath, $ddlText, [System.Text.Encoding]::UTF8)

if ($OutputPath) {
    $csvDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $csvDir)) { New-Item -ItemType Directory -Path $csvDir -Force | Out-Null }
    [PSCustomObject]@{ script = $ddlText } |
        Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
}

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done — $lineCount lines  |  $($ddlText.Length) chars" -ForegroundColor Green
Write-Host "[generate] .sql : $sqlOutPath" -ForegroundColor Green
Write-Host ''
Write-Host '  Open the .sql file above in SSMS to review and execute.' -ForegroundColor DarkGray
