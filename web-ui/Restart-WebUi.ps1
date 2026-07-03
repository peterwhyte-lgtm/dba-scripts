<#
.SYNOPSIS
    Restart the local web UI (Start-WebUi.ps1).
.DESCRIPTION
    Stops any PowerShell process that is currently hosting the web UI on the
    given port, then relaunches Start-WebUi.ps1 in a new background window.
.PARAMETER Port
    Port the web UI listens on (default 8787). Must match the running instance.
.EXAMPLE
    .\tools\Restart-WebUi.ps1
    .\tools\Restart-WebUi.ps1 -Port 9090
#>
param([int]$Port = 8787)

$ErrorActionPreference = 'Stop'

# ── stop any PowerShell process running Start-WebUi.ps1 ───────────────────────

# Match only processes LAUNCHED as the web UI (-File ...\Start-WebUi.ps1). Anything looser
# (substring / path match) also hits shells whose command TEXT merely mentions the file —
# including this script's own caller — and kills them mid-run.
$webUiProcs = @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'" |
    Where-Object { $_.ProcessId -ne $PID -and
                   $_.CommandLine -match '-File\s+"?[^"]*[\\/]Start-WebUi\.ps1' })

if ($webUiProcs) {
    foreach ($p in $webUiProcs) {
        Write-Host "Stopping PID $($p.ProcessId) on port $Port..."
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    # Wait for HTTP.sys to release the URL prefix
    Start-Sleep -Milliseconds 800
} else {
    Write-Host "No Start-WebUi process found — starting fresh."
}

# ── relaunch ──────────────────────────────────────────────────────────────────

$script = Join-Path $PSScriptRoot 'Start-WebUi.ps1'
Start-Process pwsh -ArgumentList "-NoExit", "-File", "`"$script`"", "-Port", $Port, "-Inline"
Write-Host "Web UI starting on http://localhost:$Port"
