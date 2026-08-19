<#
.SYNOPSIS
Generates RESTORE DATABASE scripts with WITH MOVE for all online user databases on the instance.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a RESTORE WITH MOVE script template for migration to a target server with different drive paths.

.DESCRIPTION
Connects to the source server, runs Generate-RestoreWithMoveScript.sql, and writes the full DDL to a .sql
file in output-files\migration\. Use when the target server has different drive letters or folder paths
from the source.

The generated script contains DECLARE variables at the top for backup path and drive path prefixes.
Edit these variables in the .sql file before running on the target:
  @BackupPath  — UNC or local path to the .bak files
  @OldDataRoot — data file path prefix on SOURCE
  @NewDataRoot — data file path prefix on TARGET
  @OldLogRoot  — log file path prefix on SOURCE
  @NewLogRoot  — log file path prefix on TARGET

If source and target have identical drive layouts, use Generate-RestoreScript.sql instead.

After running the output on the target:
  1. Verify all databases are ONLINE
  2. Run Fix-OrphanedUsers.sql to re-map database users to logins
  3. Run Get-PostMigrationValidation.ps1 on both servers and compare output

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputPath
Full path for the generated .sql file. Defaults to output-files\migration\restore-with-move-<server>-<timestamp>.sql.

.EXAMPLE
.\powershell\migration\Generate-RestoreWithMoveScript.ps1

.EXAMPLE
.\powershell\migration\Generate-RestoreWithMoveScript.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-RestoreWithMoveScript.ps1
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [ValidateSet('Sql', 'Csv')]
    [string]$OutputFormat   = 'Sql',
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username  -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password  -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Generate-RestoreWithMoveScript.sql'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$sqlOutDir = Join-Path $repoRoot 'output-files\migration'
New-Item -ItemType Directory -Path $sqlOutDir -Force | Out-Null

$sqlOutPath = if ($OutputFormat -eq 'Csv') {
    Join-Path $sqlOutDir "restore-with-move-$safeName-$ts.sql"
} elseif ($OutputPath) {
    $d = Split-Path $OutputPath -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $OutputPath
} else {
    Join-Path $sqlOutDir "restore-with-move-$safeName-$ts.sql"
}

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }
Write-Host ''
Write-Host '[generate] Generating RESTORE WITH MOVE script...' -ForegroundColor Cyan
Write-Host "[generate] Server  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[generate] Auth    : $authLabel" -ForegroundColor Cyan
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
    $ddlText = $result.script
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.' }
    $sqlcmdArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript, '-y', '0', '-b', '-C')
    if ($Username -and $Password) { $sqlcmdArgs += @('-U', $Username, '-P', $Password) }
    else                          { $sqlcmdArgs += '-E' }
    $lines = & $sqlcmdExe.Source @sqlcmdArgs
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe failed with exit code $LASTEXITCODE" }
    $ddlText = (($lines | Select-Object -Skip 2) -join "`r`n").TrimEnd()
}

if (-not $ddlText -or $ddlText.Trim() -eq '') {
    Write-Host '[generate] No online user databases found.' -ForegroundColor Yellow
    return
}

[System.IO.File]::WriteAllText($sqlOutPath, $ddlText, [System.Text.Encoding]::UTF8)

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done - $lineCount lines" -ForegroundColor Green
Write-Host "[generate] .sql   : $sqlOutPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Edit the DECLARE variables at the top of the .sql file (BackupPath, OldDataRoot, NewDataRoot, etc.)' -ForegroundColor Yellow
Write-Host 'before running on the target server.' -ForegroundColor Yellow
Write-Host ''

if ($OutputFormat -eq 'Csv' -and $OutputPath) {
    $csvDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $csvDir)) { New-Item -ItemType Directory -Path $csvDir -Force | Out-Null }
    [PSCustomObject]@{ ddl = $ddlText } |
        Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
}