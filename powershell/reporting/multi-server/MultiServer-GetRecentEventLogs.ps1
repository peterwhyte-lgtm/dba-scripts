﻿<#
Script Name : MultiServer-GetRecentEventLogs
Category    : multi-server-scripts/powershell
Purpose     : Pull recent Error and Warning events from Windows Event Logs on multiple remote hosts.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : Remote Event Log access via RPC. RemoteRegistry service running on targets.
Params      : -Servers "SVR01,SVR02"        Required. Comma-separated hostnames or IPs.
              -LogName "Application,System"  Logs to read (comma-separated). Default: Application,System.
              -Level "Error,Warning"         Severity filter. Options: Error,Warning,Information,Critical.
              -Hours 24                      How far back to look. Default: 24.
              -MaxPerServer 50               Max events per server per log. Default: 50.
              -Credential                    Alternate PSCredential.
              -Parallel                      Run all servers simultaneously (PS7+).
Output      : Server, Log, TimeUtc, Level, Source, EventId, Message
Example     : .\MultiServer-GetRecentEventLogs.ps1 -Servers "SVR01,SVR02" -Hours 48 -Level Error
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Servers,

    [string]$LogName = 'Application,System',
    [string]$Level = 'Error,Warning',
    [int]$Hours = 24,
    [int]$MaxPerServer = 50,
    [PSCredential]$Credential,
    [switch]$Parallel
)

$ErrorActionPreference = 'Stop'
$serverList = $Servers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$logNames   = $LogName -split ','  | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

# Map string level names to WinEvent level values
$levelMap = @{ Error=2; Warning=3; Information=4; Critical=1 }
$levelNums = $Level -split ',' | ForEach-Object { $_.Trim() } | ForEach-Object {
    if ($levelMap.ContainsKey($_)) { $levelMap[$_] } else { Write-Warning "Unknown level '$_' - skipping"; $null }
} | Where-Object { $null -ne $_ }

if ($levelNums.Count -eq 0) {
    Write-Error "No valid event levels specified. Use Error, Warning, Information, or Critical."
    exit 1
}

$since = (Get-Date).AddHours(-$Hours)

$results = [System.Collections.Generic.List[object]]::new()

function Get-EventsFromHost([string]$server) {
    foreach ($log in $logNames) {
        try {
            $filter = @{
                LogName   = $log
                Level     = $levelNums
                StartTime = $since
            }
            $params = @{ FilterHashtable = $filter; MaxEvents = $MaxPerServer; ErrorAction = 'Stop' }
            if ($server -ne '.') { $params.ComputerName = $server }
            if ($Credential)     { $params.Credential   = $Credential }

            $events = Get-WinEvent @params -ErrorAction SilentlyContinue
            foreach ($e in $events) {
                [PSCustomObject]@{
                    Server    = $server
                    Log       = $log
                    TimeUtc   = $e.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')
                    Level     = $e.LevelDisplayName
                    Source    = $e.ProviderName
                    EventId   = $e.Id
                    Message   = ($e.Message -split "`n")[0].Trim()  # first line only
                    Error     = ''
                }
            }
        } catch [System.Exception] {
            if ($_.Exception.Message -match 'No events') { continue }
            [PSCustomObject]@{
                Server = $server; Log = $log; TimeUtc = ''; Level = 'ERROR'; Source = '';
                EventId = 0; Message = $_.Exception.Message; Error = $_.Exception.Message
            }
        }
    }
}

if ($Parallel) {
    Write-Host "Querying $($serverList.Count) server(s) in parallel..." -ForegroundColor Cyan
    $serverList | ForEach-Object -Parallel {
        $srv   = $_
        $logs  = $using:logNames
        $lvls  = $using:levelNums
        $since = $using:since
        $max   = $using:MaxPerServer
        $cr    = $using:Credential
        foreach ($log in $logs) {
            try {
                $filter = @{ LogName = $log; Level = $lvls; StartTime = $since }
                $params = @{ FilterHashtable = $filter; MaxEvents = $max; ErrorAction = 'SilentlyContinue' }
                if ($srv -ne '.') { $params.ComputerName = $srv }
                if ($cr)          { $params.Credential   = $cr }
                $events = Get-WinEvent @params
                foreach ($e in $events) {
                    [PSCustomObject]@{ Server = $srv; Log = $log; TimeUtc = $e.TimeCreated.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss');
                        Level = $e.LevelDisplayName; Source = $e.ProviderName; EventId = $e.Id;
                        Message = ($e.Message -split "`n")[0].Trim(); Error = '' }
                }
            } catch {
                if ($_.Exception.Message -notmatch 'No events') {
                    [PSCustomObject]@{ Server = $srv; Log = $log; TimeUtc = ''; Level = 'ERROR'; Source = '';
                        EventId = 0; Message = $_.Exception.Message; Error = $_.Exception.Message }
                }
            }
        }
    } -ThrottleLimit 10 | ForEach-Object { $results.Add($_) }
} else {
    foreach ($server in $serverList) {
        Write-Host "`n→ $server" -ForegroundColor Cyan
        $rows = @(Get-EventsFromHost $server)
        if ($rows.Count -eq 0) {
            Write-Host "  (no matching events in the last $Hours hours)" -ForegroundColor DarkGray
        } else {
            foreach ($r in $rows) {
                $clr = switch ($r.Level) { 'Error' { 'Red' } 'Critical' { 'Magenta' } 'Warning' { 'Yellow' } default { 'Gray' } }
                Write-Host ("  [{0}] {1}  {2} #{3}  {4}" -f $r.Level, $r.TimeUtc, $r.Source, $r.EventId, $r.Message.Substring(0, [Math]::Min(80, $r.Message.Length))) -ForegroundColor $clr
                $results.Add($r)
            }
        }
    }
}

if ($results.Count -gt 0) {
    Write-Host "`n── All events ───────────────────────────────────────────" -ForegroundColor DarkGray
    $results | Sort-Object Server, TimeUtc -Descending |
        Format-Table Server, Log, TimeUtc, Level, Source, EventId, Message -AutoSize
} else {
    Write-Host "`nNo matching events found on any server in the last $Hours hours." -ForegroundColor Green
}