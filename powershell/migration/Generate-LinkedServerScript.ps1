<#
.SYNOPSIS
Generates sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers on the instance.

.NOTES
ScriptType   : DDL-generator
TargetScope  : single server
RiskLevel    : SAFE
Purpose      : Produce a migration-ready linked server script to run on the target server after migration.

.DESCRIPTION
Connects to the source server, runs Generate-LinkedServerScript.sql, and writes the full DDL to a .sql file
in output-files\migration\. The script captures the NVARCHAR(MAX) column without truncation.

IMPORTANT: Linked server login mappings with stored remote credentials cannot have passwords scripted.
Mappings using stored credentials are scripted with a placeholder (ENTER_PASSWORD_HERE).
Re-enter the remote password manually on the target for each HIGH-risk mapping flagged by
Get-LinkedServerSecurity.ps1.

.PARAMETER ServerInstance
SQL Server instance to query. Defaults to '.' or $env:DBASCRIPTS_SERVER.

.PARAMETER Database
Initial connection database. Defaults to 'master'.

.PARAMETER Username
SQL login username. Omit for Windows (integrated) auth.

.PARAMETER Password
SQL login password. Omit for Windows auth.

.PARAMETER OutputPath
Full path for the generated .sql file. Defaults to output-files\migration\linked-server-script-<server>-<timestamp>.sql.

.EXAMPLE
.\powershell\migration\Generate-LinkedServerScript.ps1

.EXAMPLE
.\powershell\migration\Generate-LinkedServerScript.ps1 -ServerInstance PROD01\SQL2019

.EXAMPLE
.\tools\local-sql\Set-SqlConnection.ps1 -ServerInstance PROD01\SQL2019
.\powershell\migration\Generate-LinkedServerScript.ps1
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
$sqlScript = Join-Path $repoRoot 'sql\migration\Generate-LinkedServerScript.sql'

if (-not (Test-Path -LiteralPath $sqlScript)) { throw "SQL script not found: $sqlScript" }

$safeName  = ($ServerInstance -replace '[\\/:*?"<>|]', '-').Trim('-')
$ts        = Get-Date -Format 'yyyyMMdd-HHmmss'
$sqlOutDir = Join-Path $repoRoot 'output-files\migration'
New-Item -ItemType Directory -Path $sqlOutDir -Force | Out-Null

$sqlOutPath = if ($OutputFormat -eq 'Csv') {
    Join-Path $sqlOutDir "linked-server-script-$safeName-$ts.sql"
} elseif ($OutputPath) {
    $d = Split-Path $OutputPath -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $OutputPath
} else {
    Join-Path $sqlOutDir "linked-server-script-$safeName-$ts.sql"
}

$authLabel = if ($Username) { "SQL ($Username)" } else { 'Windows (integrated)' }
Write-Host ''
Write-Host '[generate] Generating linked server migration script...' -ForegroundColor Cyan
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
    $ddlText = $result.ddl
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
    Write-Host '[generate] No linked servers found on this instance.' -ForegroundColor Yellow
    return
}

[System.IO.File]::WriteAllText($sqlOutPath, $ddlText, [System.Text.Encoding]::UTF8)

$lineCount = ($ddlText -split "`n").Count
Write-Host "[generate] Done - $lineCount lines" -ForegroundColor Green
Write-Host "[generate] .sql   : $sqlOutPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Review ENTER_PASSWORD_HERE placeholders - stored credentials cannot be scripted.' -ForegroundColor Yellow
Write-Host 'Run Get-LinkedServerSecurity.ps1 to identify HIGH-risk login mappings.' -ForegroundColor Yellow
Write-Host ''

if ($OutputFormat -eq 'Csv' -and $OutputPath) {
    $csvDir = Split-Path $OutputPath -Parent
    if (-not (Test-Path $csvDir)) { New-Item -ItemType Directory -Path $csvDir -Force | Out-Null }
    [PSCustomObject]@{ ddl = $ddlText } |
        Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
}