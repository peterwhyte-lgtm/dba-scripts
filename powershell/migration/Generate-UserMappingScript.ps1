<#
.SYNOPSIS
Generates CREATE USER and role membership DDL for all user databases.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a migration-ready user mapping script to run on the target after logins and databases are in place.

.DESCRIPTION
Connects to the source server, runs Generate-UserMappingScript.sql, and writes the full DDL to a .sql file
in output-files\migration\. The script captures the NVARCHAR(MAX) column without truncation and does
not go through the CSV pipeline.

Run on TARGET server after databases are restored AND logins are created (run Generate-LoginScript first).

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' (local), or $env:DBASCRIPTS_SERVER if set via Set-SqlConnection.ps1.
Accepts: SERVERNAME, SERVERNAME\INSTANCE, SERVERNAME,PORT

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth, or set via Set-SqlConnection.ps1.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputPath
Full path for the generated .sql file. Defaults to output-files\migration\user-mapping-<server>-<timestamp>.sql.

.EXAMPLE
# Local instance, Windows auth
.\powershell\migration\Generate-UserMappingScript.ps1

.EXAMPLE
# Remote server
.\powershell\migration\Generate-UserMappingScript.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
# Set server once for the session, then run all three generate scripts
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LoginScript.ps1
.\powershell\migration\Generate-AgentJobScript.ps1
.\powershell\migration\Generate-UserMappingScript.ps1

.EXAMPLE
# Save to a specific path
.\powershell\migration\Generate-UserMappingScript.ps1 -ServerInstance PROD01 -OutputPath C:\migration\user-mapping.sql
#>

param(
    [string]$ServerInstance = '.',
    [string]$Database       = 'master',
    [string]$Username,
    [string]$Password,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Respect session-level defaults set by Set-SqlConnection.ps1
if ($ServerInstance -eq '.' -and $env:DBASCRIPTS_SERVER) { $ServerInstance = $env:DBASCRIPTS_SERVER }
if (-not $Username  -and $env:DBASCRIPTS_USER)            { $Username = $env:DBASCRIPTS_USER }
if (-not $Password  -and $env:DBASCRIPTS_PASS)            { $Password = $env:DBASCRIPTS_PASS }

$repoRoot  = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$sqlScript = Join-Path $repoRoot 'sql\migration\Generate-UserMappingScript.sql'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

if (-not $OutputPath) {
    $safeName = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outDir = Join-Path $repoRoot 'output-files\migration'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $OutputPath = Join-Path $outDir "user-mapping-$safeName-$ts.sql"
} else {
    $outDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
}

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }
Write-Host ''
Write-Host '[generate] Generating user mapping migration script...' -ForegroundColor Cyan
Write-Host "[generate] Server  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[generate] Auth    : $authLabel" -ForegroundColor Cyan
Write-Host "[generate] Output  : $OutputPath" -ForegroundColor Cyan
Write-Host ''

$ddlText = $null

$invokeSqlcmd = Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue
if ($invokeSqlcmd) {
    $params = @{
        ServerInstance         = $ServerInstance
        Database               = $Database
        InputFile              = $sqlScript
        QueryTimeout           = 300
        MaxCharLength          = 2000000
        TrustServerCertificate = $true
        ErrorAction            = 'Stop'
    }
    if ($Username -and $Password) { $params['Username'] = $Username; $params['Password'] = $Password }
    Write-Host '[generate] Using Invoke-Sqlcmd' -ForegroundColor DarkGray
    $result  = Invoke-Sqlcmd @params
    $ddlText = $result.ddl
} else {
    $sqlcmdExe = Get-Command sqlcmd.exe -ErrorAction SilentlyContinue
    if (-not $sqlcmdExe) { throw 'Neither Invoke-Sqlcmd nor sqlcmd.exe is available on PATH.' }
    $sqlcmdArgs = @('-S', $ServerInstance, '-d', $Database, '-i', $sqlScript,
                    '-h', '-1', '-y', '0', '-W', '-b', '-C')
    if ($Username -and $Password) { $sqlcmdArgs += @('-U', $Username, '-P', $Password) }
    else                          { $sqlcmdArgs += '-E' }
    Write-Host '[generate] Using sqlcmd.exe' -ForegroundColor DarkGray
    $lines = & $sqlcmdExe.Source @sqlcmdArgs
    if ($LASTEXITCODE -ne 0) { throw "sqlcmd.exe failed with exit code $LASTEXITCODE" }
    $ddlText = ($lines -join "`r`n").Trim()
}

if (-not $ddlText -or $ddlText.Trim() -eq '') {
    Write-Host '[generate] No DDL produced — instance may have no user databases with non-default users.' -ForegroundColor Yellow
    return
}

[System.IO.File]::WriteAllText($OutputPath, $ddlText, [System.Text.Encoding]::UTF8)

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done — $lineCount lines, $($ddlText.Length) characters" -ForegroundColor Green
Write-Host "[generate] File   : $OutputPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Run on target AFTER databases are restored and logins are created.' -ForegroundColor Yellow
Write-Host ''
