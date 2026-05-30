<#
.SYNOPSIS
Creates many SQL Server test databases with randomised names and configurable sizes.

.NOTES
ScriptType   : automation
TargetScope  : single server
RiskLevel    : HIGH IMPACT — creates databases
Purpose      : Lab and migration simulation — generate a large set of named databases quickly.

.DESCRIPTION
Uses SMO to create databases with explicit data/log file paths. Falls back to SQL Server
default locations if SMO path detection fails. Writes a CSV of created database names.

.PARAMETER ServerInstance   Target SQL Server instance. Defaults to '.'.
.PARAMETER DatabaseCount    Number of databases to create. Required.
.PARAMETER Prefix           Name prefix. Defaults to 'migdb'.
.PARAMETER InitialSizeMB    Data file initial size in MB. Defaults to 25.
.PARAMETER LogSizeMB        Log file initial size in MB. Defaults to 10.
.PARAMETER StartIndex       Starting numeric index. Defaults to 1.
.PARAMETER OutputFile       CSV path for created database names. Defaults to .\created_databases.csv.
.PARAMETER BatchDelayMs     Milliseconds to pause between creates. Defaults to 10.

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\New-MultipleDatabases.ps1 -DatabaseCount 20 -Prefix testdb

.EXAMPLE
pwsh -ExecutionPolicy Bypass -File .\powershell\lab\New-MultipleDatabases.ps1 -DatabaseCount 100 -Prefix migdb -InitialSizeMB 50
#>

param(
    [string]$ServerInstance  = '.',
    [Parameter(Mandatory=$true)]
    [int]   $DatabaseCount,
    [string]$Prefix          = 'migdb',
    [int]   $InitialSizeMB   = 25,
    [int]   $LogSizeMB       = 10,
    [int]   $StartIndex      = 1,
    [string]$OutputFile      = "$PWD\created_databases.csv",
    [int]   $BatchDelayMs    = 10
)
$ErrorActionPreference = 'Stop'

function Get-DefaultPaths-SMO {
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')
        $svr  = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance
        $data = $svr.Settings.DefaultFile
        $log  = $svr.Settings.DefaultLog
        if ($data -and $log) { return @{ Data = $data; Log = $log } }
    }
    catch { }
    return $null
}

function New-RandomSuffix([int]$len) {
    $chars = [char[]](48..57 + 97..122)
    -join (1..$len | ForEach-Object { $chars | Get-Random })
}

$paths = Get-DefaultPaths-SMO
if (-not $paths) {
    Write-Warning 'Could not determine SQL Server default data/log paths via SMO. Files will be created in SQL Server default locations.'
}

[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Smo')
$server   = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance
$created  = [System.Collections.Generic.List[string]]::new()
$endIndex = $StartIndex + $DatabaseCount - 1

for ($i = $StartIndex; $i -le $endIndex; $i++) {
    $suffix = New-RandomSuffix -len 8
    $name   = "${Prefix}_${i}_${suffix}"

    if ($server.Databases[$name]) {
        Write-Host "Skipping existing: $name" -ForegroundColor Yellow
        continue
    }

    if ($paths) {
        $mdf  = Join-Path $paths.Data.TrimEnd('\') "${name}.mdf"
        $ldf  = Join-Path $paths.Log.TrimEnd('\')  "${name}_log.ldf"
        $tsql = "CREATE DATABASE [$name] ON PRIMARY (NAME=N'${name}_Data', FILENAME=N'$mdf', SIZE=${InitialSizeMB}MB, FILEGROWTH=10MB) LOG ON (NAME=N'${name}_Log', FILENAME=N'$ldf', SIZE=${LogSizeMB}MB, FILEGROWTH=10MB);"
    }
    else {
        $tsql = "CREATE DATABASE [$name];"
    }

    try {
        $server.ConnectionContext.ExecuteNonQuery($tsql)
        Write-Host "Created: $name" -ForegroundColor Green
        $created.Add($name)
    }
    catch {
        Write-Warning "Failed creating $name : $($_.Exception.Message)"
    }

    if ($BatchDelayMs -gt 0) { Start-Sleep -Milliseconds $BatchDelayMs }
}

if ($OutputFile -and $created.Count -gt 0) {
    $created | ForEach-Object { [PSCustomObject]@{ database_name = $_ } } |
        Export-Csv -Path $OutputFile -NoTypeInformation -Force
    Write-Host "Created $($created.Count) databases. List saved to: $OutputFile" -ForegroundColor Cyan
}
else {
    Write-Host "Created $($created.Count) databases." -ForegroundColor Cyan
}
