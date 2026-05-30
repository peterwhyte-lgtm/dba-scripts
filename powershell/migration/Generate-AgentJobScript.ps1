<#
.SYNOPSIS
Generates sp_add_job DDL to recreate all SQL Agent jobs on the target server.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a migration-ready Agent job script; review owner_login_name before running on target.

.DESCRIPTION
Connects to the source server, runs Generate-AgentJobScript.sql, and writes the full DDL to a .sql file
in output-files\migration\. The script captures the NVARCHAR(MAX) column without truncation and does
not go through the CSV pipeline.

IMPORTANT: Review owner_login_name values in the generated script — these must be valid logins on the
target server. Map them before running.

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
Full path for the generated .sql file. Defaults to output-files\migration\agent-jobs-<server>-<timestamp>.sql.

.EXAMPLE
# Local instance, Windows auth
.\powershell\migration\Generate-AgentJobScript.ps1

.EXAMPLE
# Remote server
.\powershell\migration\Generate-AgentJobScript.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
# Set server once for the session, then run
.\helpers\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-AgentJobScript.ps1

.EXAMPLE
# Save to a specific path
.\powershell\migration\Generate-AgentJobScript.ps1 -ServerInstance PROD01 -OutputPath C:\migration\agent-jobs.sql
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
$sqlScript = Join-Path $repoRoot 'sql\migration\Generate-AgentJobScript.sql'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

if (-not $OutputPath) {
    $safeName = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outDir = Join-Path $repoRoot 'output-files\migration'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $OutputPath = Join-Path $outDir "agent-jobs-$safeName-$ts.sql"
} else {
    $outDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
}

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }
Write-Host ''
Write-Host '[generate] Generating Agent job migration script...' -ForegroundColor Cyan
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
    Write-Host '[generate] No DDL produced — instance may have no SQL Agent jobs.' -ForegroundColor Yellow
    return
}

[System.IO.File]::WriteAllText($OutputPath, $ddlText, [System.Text.Encoding]::UTF8)

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done — $lineCount lines, $($ddlText.Length) characters" -ForegroundColor Green
Write-Host "[generate] File   : $OutputPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Review owner_login_name values and map to valid logins on the target before running.' -ForegroundColor Yellow
Write-Host ''
