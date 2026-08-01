<#
.SYNOPSIS
Tests DNS resolution and TCP port connectivity for a SQL Server instance.

.DESCRIPTION
Run this before connecting to a remote server to diagnose network issues.
Always tests port 1433. Identifies whether a failure is DNS, firewall, or SQL.
Named instances use dynamic ports by default, so when no explicit port is given
the SQL Browser service (UDP 1434) is queried to resolve the instance's actual
TCP port, and that port is tested too.
Use -AgCluster or -FciCluster to add the Windows cluster port set to the check.
Local targets (. / (local) / localhost) skip DNS and check the SQL Server
service status instead, since a stopped service is the usual local failure.

.NOTES
ScriptType  : runner
TargetScope : single server
RiskLevel   : SAFE
Purpose     : Pre-flight network check — DNS resolution and port reachability.

.PARAMETER ServerInstance
SQL Server instance name. Accepts any format: SERVER, SERVER\INST, SERVER,1434.

.PARAMETER AdditionalPorts
Extra TCP ports to test. Add your own alongside the defaults.

.PARAMETER AgCluster
Also test the Availability Group port set: AG/mirroring endpoint (5022 default),
RPC endpoint mapper (135), SMB (445, file share witness), WSFC cluster service (3343).
If your AG endpoint uses a custom port, add it with -AdditionalPorts.

.PARAMETER FciCluster
Also test the Failover Cluster Instance port set: RPC endpoint mapper (135),
SMB (445), WSFC cluster service (3343). FCIs have no 5022 endpoint — that is AG/mirroring only.

.PARAMETER TimeoutMs
TCP connection timeout per port in milliseconds. Default: 2000.

.EXAMPLE
.\tools\local-sql\Test-ServerNetwork.ps1 -ServerInstance MYSERVER
.\tools\local-sql\Test-ServerNetwork.ps1 -ServerInstance MYSERVER\SQL2019
.\tools\local-sql\Test-ServerNetwork.ps1 -ServerInstance MYSERVER -AgCluster
.\tools\local-sql\Test-ServerNetwork.ps1 -ServerInstance MYSERVER -FciCluster
.\tools\local-sql\Test-ServerNetwork.ps1 -ServerInstance MYSERVER -AdditionalPorts 5023,14330
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ServerInstance,

    [int[]]$AdditionalPorts = @(),

    [switch]$AgCluster,

    [switch]$FciCluster,

    [int]$TimeoutMs = 2000
)

# Parse host and explicit port from ServerInstance
# Handles: SERVER  /  SERVER\INSTANCE  /  SERVER,PORT  /  SERVER\INSTANCE,PORT
$hostName     = $ServerInstance -replace '\\.*$', '' -replace ',.*$', ''
$explicitPort = if ($ServerInstance -match ',(\d+)') { [int]$Matches[1] } else { $null }
$instanceName = if ($ServerInstance -match '\\([^,]+)') { $Matches[1] } else { $null }

# Local aliases (. / (local) / localhost / own computer name) are not DNS names —
# the useful check for a local target is the SQL Server service, not the network.
$isLocal = $hostName -in @('.', '(local)', 'localhost', '') -or $hostName -ieq $env:COMPUTERNAME
if ($isLocal) { $hostName = 'localhost' }

$portsToTest = New-Object 'System.Collections.Generic.List[int]'
$portsToTest.Add(1433)
if ($explicitPort -and $explicitPort -ne 1433) { $portsToTest.Add($explicitPort) }
foreach ($p in $AdditionalPorts)               { if ($p -notin $portsToTest) { $portsToTest.Add($p) } }
if ($AgCluster) {
    foreach ($p in @(5022, 135, 445, 3343)) { if ($p -notin $portsToTest) { $portsToTest.Add($p) } }
}
if ($FciCluster) {
    foreach ($p in @(135, 445, 3343)) { if ($p -notin $portsToTest) { $portsToTest.Add($p) } }
}
$portsToTest = $portsToTest | Sort-Object

$portLabels = @{
    1433 = 'SQL Server default'
    1434 = 'DAC (note: SQL Browser is UDP 1434, not tested here)'
    5022 = 'AG / mirroring endpoint (default)'
    135  = 'RPC endpoint mapper (WSFC, DTC)'
    445  = 'SMB (file share witness, UNC backups)'
    3343 = 'WSFC cluster service'
}

Write-Host ''
Write-Host ('[network] ' + ('─' * 55)) -ForegroundColor DarkCyan
Write-Host "[network] Target  : $ServerInstance" -ForegroundColor Cyan
Write-Host "[network] Host    : $hostName" -ForegroundColor Cyan
Write-Host ('[network] ' + ('─' * 55)) -ForegroundColor DarkCyan

# ── Local service check ───────────────────────────────────────────────────────
if ($isLocal) {
    $serviceName = if ($instanceName) { "MSSQL`$$instanceName" } else { 'MSSQLSERVER' }
    Write-Host ''
    Write-Host "[network] Local target — checking service '$serviceName'..." -ForegroundColor DarkGray

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "[network] Service : NOT FOUND ($serviceName)" -ForegroundColor Red
        Write-Host '[network]           No SQL Server service with this name exists on this machine.' -ForegroundColor Yellow
        Write-Host '[network]           Check the instance name, or list instances with: Get-Service MSSQL*' -ForegroundColor DarkGray
        Write-Host ''
        exit 1
    }
    if ($svc.Status -ne 'Running') {
        Write-Host "[network] Service : $($svc.Status.ToString().ToUpper())" -ForegroundColor Red
        Write-Host '[network]           SQL Server is installed but not running — this is the connection failure cause.' -ForegroundColor Yellow
        Write-Host "[network]           Start it with: Start-Service $serviceName" -ForegroundColor DarkGray
        Write-Host ''
        exit 1
    }
    Write-Host '[network] Service : RUNNING' -ForegroundColor Green
    Write-Host '[network]           Note: local connections can use shared memory, so a closed TCP port below' -ForegroundColor DarkGray
    Write-Host '[network]           does not necessarily block local access.' -ForegroundColor DarkGray
}

# ── DNS resolution ────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[network] Resolving DNS...' -ForegroundColor DarkGray

try {
    $addresses = [System.Net.Dns]::GetHostAddresses($hostName)
    $ipList    = ($addresses | ForEach-Object { $_.IPAddressToString }) -join ', '
    Write-Host "[network] DNS     : OK  →  $ipList" -ForegroundColor Green
} catch {
    Write-Host "[network] DNS     : FAILED" -ForegroundColor Red
    Write-Host "[network]           '$hostName' could not be resolved." -ForegroundColor Yellow
    Write-Host "[network]           Check the server name, domain, or DNS configuration." -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}

# ── SQL Browser lookup (named instances) ─────────────────────────────────────
# Named instances listen on dynamic ports by default, so testing 1433 alone is
# not conclusive. SQL Browser (UDP 1434, SSRP protocol) resolves the instance
# name to its current TCP port — query it and test the real port too.
if ($instanceName -and -not $explicitPort) {
    Write-Host ''
    Write-Host "[network] Named instance '$instanceName' — querying SQL Browser (UDP 1434)..." -ForegroundColor DarkGray

    $ssrpResponse = $null
    $udp = [System.Net.Sockets.UdpClient]::new()
    try {
        $udp.Client.ReceiveTimeout = $TimeoutMs
        # SSRP CLNT_UCAST_INST: 0x04 + instance name
        $request = [byte[]](@(0x04) + [System.Text.Encoding]::ASCII.GetBytes($instanceName))
        $null    = $udp.Send($request, $request.Length, $hostName, 1434)
        $remote  = [System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any, 0)
        $reply   = $udp.Receive([ref]$remote)
        # SVR_RESP: 0x05 + 2-byte length + "ServerName;X;InstanceName;Y;...;tcp;PORT;;"
        if ($reply.Length -gt 3) {
            $ssrpResponse = [System.Text.Encoding]::ASCII.GetString($reply, 3, $reply.Length - 3)
        }
    } catch {
        # No reply — browser stopped, UDP 1434 blocked, or instance unknown
    } finally {
        $udp.Close()
    }

    if ($ssrpResponse -match ';tcp;(\d+)') {
        $resolvedPort = [int]$Matches[1]
        Write-Host "[network] Browser : OK  →  instance '$instanceName' is on TCP $resolvedPort" -ForegroundColor Green
        if ($resolvedPort -notin $portsToTest) {
            $portLabels[$resolvedPort] = "resolved port for $instanceName"
            $portsToTest = @($portsToTest) + $resolvedPort | Sort-Object
        }
    } else {
        Write-Host '[network] Browser : NO RESPONSE' -ForegroundColor Yellow
        Write-Host '[network]           Cannot resolve the named instance port. Causes: SQL Browser service' -ForegroundColor DarkGray
        Write-Host '[network]           stopped, UDP 1434 blocked by firewall, or wrong instance name.' -ForegroundColor DarkGray
        Write-Host '[network]           Named instances use dynamic ports by default — 1433 below can be CLOSED' -ForegroundColor DarkGray
        Write-Host '[network]           even when the instance is fine. Test directly with SERVER\INSTANCE,PORT.' -ForegroundColor DarkGray
        if ($isLocal) {
            $browserSvc = Get-Service -Name SQLBrowser -ErrorAction SilentlyContinue
            if ($browserSvc -and $browserSvc.Status -ne 'Running') {
                Write-Host "[network]           Local SQL Browser service is $($browserSvc.Status.ToString().ToUpper()) — start it with: Start-Service SQLBrowser" -ForegroundColor DarkGray
            }
        }
    }
}

# ── Port checks ───────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '[network] Checking ports...' -ForegroundColor DarkGray
Write-Host ''

$anyFailed = $false

foreach ($port in $portsToTest) {
    $label   = if ($portLabels.ContainsKey($port)) { "  # $($portLabels[$port])" } else { '' }
    $tcp     = [System.Net.Sockets.TcpClient]::new()
    $isOpen  = $false

    try {
        $conn = $tcp.BeginConnect($hostName, $port, $null, $null)
        $wait = $conn.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.EndConnect($conn)
            $isOpen = $true
        }
    } catch {
        # Connection error — port closed or unreachable
    } finally {
        $tcp.Close()
    }

    if ($isOpen) {
        Write-Host ("[network] Port {0,-6}: OPEN{1}" -f $port, $label) -ForegroundColor Green
    } else {
        Write-Host ("[network] Port {0,-6}: CLOSED or filtered{1}" -f $port, $label) -ForegroundColor Red
        $anyFailed = $true

        switch ($port) {
            1433 {
                Write-Host '[network]              → SQL Server is not reachable on this port.' -ForegroundColor Yellow
                Write-Host '[network]                Possible causes: SQL Server is not running, firewall is blocking 1433,' -ForegroundColor DarkGray
                Write-Host '[network]                or this is a named instance using a dynamic port (check SQL Browser).' -ForegroundColor DarkGray
            }
            5022 {
                Write-Host '[network]              → AG / mirroring endpoint not reachable.' -ForegroundColor Yellow
                Write-Host '[network]                Required for AG replica sync and failover.' -ForegroundColor DarkGray
            }
            135  {
                Write-Host '[network]              → RPC endpoint mapper not reachable.' -ForegroundColor Yellow
                Write-Host '[network]                May affect cluster communication and some management tools.' -ForegroundColor DarkGray
            }
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('[network] ' + ('─' * 55)) -ForegroundColor DarkCyan

if ($anyFailed) {
    Write-Host '[network] Result  : One or more ports unreachable.' -ForegroundColor Yellow
    Write-Host '[network]           Resolve network or firewall issues before running scripts.' -ForegroundColor DarkGray
} else {
    Write-Host '[network] Result  : All ports reachable.' -ForegroundColor Green
    Write-Host '[network]           Network path looks good — try Test-SqlConnectivity next.' -ForegroundColor DarkGray
}

Write-Host ('[network] ' + ('─' * 55)) -ForegroundColor DarkCyan
Write-Host ''
