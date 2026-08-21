<#
Requires: pass 2 driver - tests the scripts whose claims are not exactly 'VIEW SERVER STATE'.
Classes:
  EXACT   - claim fully grantable here: verdicts INSUFFICIENT / CORRECT / NONE-ALSO-PASSES
  PARTIAL - claim names sysadmin or an ungrantable component: granted arm = testable subset, recorded only
  GEN     - generator scripts whose claim is 'sysadmin (to run generated DDL); X at job runtime':
            granted arm = X, tests whether GENERATION runs under the job-runtime grant. Recorded only.
  PUBLIC  - no grants; both arms are bare logins
  SKIP    - untestable here, with reason
NONE arm (bare login, CONNECT only) runs for every executed script.
Never loosen a Requires line on a NONE-arm pass: silent under-report is documented behaviour.
#>
param(
    [string]$RepoRoot = 'C:\Users\Peter\my-data\dba-tools',
    [string]$Inv,
    [string]$OutCsv
)
$ErrorActionPreference = 'Stop'
Import-Module SqlServer -DisableNameChecking 3>$null 4>$null
$SI = '.'
$pw = 'L4b-Req-Mtx-2026!x'

function Admin([string]$q, [string]$db = 'master') {
    Invoke-Sqlcmd -ServerInstance $SI -Database $db -TrustServerCertificate -QueryTimeout 120 -Query $q -ErrorAction Stop
}
function KillSessions([string]$login) {
    $s = Admin "SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = '$login'"
    foreach ($r in @($s)) { try { Admin ("KILL " + $r.session_id) } catch {} }
}
function DropLogin([string]$login, [string[]]$dbsTouched) {
    KillSessions $login
    foreach ($d in $dbsTouched) {
        try { Admin "DROP USER IF EXISTS [$login]" $d } catch {}
    }
    try { Admin "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name='$login') DROP LOGIN [$login]" } catch {
        Start-Sleep -Seconds 2; KillSessions $login; Admin "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name='$login') DROP LOGIN [$login]"
    }
}
function RunAs([string]$login, [string]$query) {
    try {
        $null = Invoke-Sqlcmd -ServerInstance $SI -Database master -TrustServerCertificate `
            -Username $login -Password $pw -QueryTimeout 60 -Query $query -OutputAs DataSet -ErrorAction Stop
        return @{ ok = $true; err = '' }
    } catch {
        $m = ($_.Exception.Message) -replace '\s+', ' '
        return @{ ok = $false; err = $m.Substring(0, [Math]::Min(300, $m.Length)) }
    }
}

$scriptInv = Get-Content -LiteralPath $Inv -Raw | ConvertFrom-Json
$allDbs = @((Admin "SELECT name FROM sys.databases WHERE state = 0 AND name NOT IN ('tempdb','model') ORDER BY database_id").name)
Write-Host ("per-db grants will cover: " + ($allDbs -join ', '))

$R = @(
  @{ M='VIEW SERVER STATE'; Class='SKIP'; Note='tested 2026-08-20 (Test-RequiresLine.ps1)' }
  @{ M='db_owner or replmonitor role on the distribution database'; Class='SKIP'; Note='no distributor on this instance; replication cannot be installed (Msg 21028)' }
  @{ M='VIEW SERVER STATE, read access to the XE output folder'; Class='SKIP'; Note='Get-XeSessionActivity unbounded read, open decision with Peter' }
  @{ M='sysadmin, or IMPERSONATE permission on the target login plus VIEW ANY DATABASE'; Class='SKIP'; Note='script RAISERRORs on placeholder @LoginName by design; permission arms indistinguishable from that' }

  @{ M='Public (no elevated permissions required)'; Class='PUBLIC' }
  @{ M='Public (no special permissions required)'; Class='PUBLIC' }

  @{ M='VIEW ANY DATABASE'; Class='EXACT'; Server='VIEW ANY DATABASE' }
  @{ M='VIEW ANY DATABASE, VIEW SERVER STATE'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW SERVER STATE' }
  @{ M='VIEW SERVER STATE, VIEW ANY DATABASE'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW SERVER STATE' }
  @{ M='VIEW ANY DATABASE, VIEW SERVER STATE, VIEW ANY DEFINITION'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW SERVER STATE, VIEW ANY DEFINITION' }
  @{ M='VIEW SERVER STATE, VIEW ANY DEFINITION'; Class='EXACT'; Server='VIEW SERVER STATE, VIEW ANY DEFINITION' }
  @{ M='VIEW ANY DEFINITION'; Class='EXACT'; Server='VIEW ANY DEFINITION' }
  @{ M='VIEW ANY DATABASE, VIEW ANY DEFINITION'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW ANY DEFINITION' }
  @{ M='VIEW ANY DATABASE, VIEW ANY DEFINITION, CONTROL SERVER'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW ANY DEFINITION, CONTROL SERVER' }
  @{ M='VIEW SERVER STATE, CONTROL SERVER (for password_hash column)'; Class='EXACT'; Server='VIEW SERVER STATE, CONTROL SERVER' }
  @{ M='VIEW SERVER STATE, ALTER TRACE (to read trace files)'; Class='EXACT'; Server='VIEW SERVER STATE, ALTER TRACE' }
  @{ M='VIEW SERVER STATE, ALTER TRACE (to read default trace path)'; Class='EXACT'; Server='VIEW SERVER STATE, ALTER TRACE' }
  @{ M='ALTER TRACE or sysadmin (to read default trace path and files)'; Class='EXACT'; Server='ALTER TRACE'; Note='weaker stated alternative tested' }
  @{ M='sysadmin or ALTER ANY LINKED SERVER'; Class='EXACT'; Server='ALTER ANY LINKED SERVER'; Note='weaker stated alternative tested' }
  @{ M='VIEW SERVER STATE to cover all databases'; Prefix=$true; Class='EXACT'; Server='VIEW SERVER STATE' }

  @{ M='db_datareader on msdb'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE db_datareader ADD MEMBER [{L}]') } }
  @{ M='VIEW ANY DATABASE, db_datareader on msdb'; Class='EXACT'; Server='VIEW ANY DATABASE'; DbOps=@{ msdb=@('ALTER ROLE db_datareader ADD MEMBER [{L}]') } }
  @{ M='msdb access (db_datareader on msdb or sysadmin)'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE db_datareader ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='msdb access (SQLAgentReaderRole or sysadmin)'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE SQLAgentReaderRole ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='SQLAgentReaderRole or sysadmin'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE SQLAgentReaderRole ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='msdb access (DatabaseMailUserRole or sysadmin)'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE DatabaseMailUserRole ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='SQLAgentUserRole in msdb (or sysadmin)'; Class='EXACT'; DbOps=@{ msdb=@('ALTER ROLE SQLAgentUserRole ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='VIEW SERVER STATE; membership in sysadmin or SQLAgentOperatorRole in msdb'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ msdb=@('ALTER ROLE SQLAgentOperatorRole ADD MEMBER [{L}]') }; Note='weaker stated alternative tested' }
  @{ M='SELECT on msdb, VIEW ANY DATABASE'; Class='EXACT'; Server='VIEW ANY DATABASE'; DbOps=@{ msdb=@('GRANT SELECT TO [{L}]') } }
  @{ M='VIEW ANY DATABASE, VIEW SERVER STATE, SELECT on msdb'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW SERVER STATE'; DbOps=@{ msdb=@('GRANT SELECT TO [{L}]') } }
  @{ M='VIEW SERVER STATE, SELECT on msdb'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ msdb=@('GRANT SELECT TO [{L}]') } }
  @{ M='VIEW ANY DATABASE, SELECT on msdb.dbo.backupset'; Class='EXACT'; Server='VIEW ANY DATABASE'; DbOps=@{ msdb=@('GRANT SELECT ON dbo.backupset TO [{L}]') } }
  @{ M='VIEW SERVER STATE (DBCC SQLPERF), read on msdb.dbo.backupset'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ msdb=@('GRANT SELECT ON dbo.backupset TO [{L}]') } }
  @{ M='VIEW ANY DATABASE, VIEW SERVER STATE, VIEW ANY DEFINITION; db_datareader on msdb'; Class='EXACT'; Server='VIEW ANY DATABASE, VIEW SERVER STATE, VIEW ANY DEFINITION'; DbOps=@{ msdb=@('ALTER ROLE db_datareader ADD MEMBER [{L}]') } }

  @{ M='SELECT on [DBAMonitor].[collector].[Perfmon]'; Class='EXACT'; DbOps=@{ DBAMonitor=@('GRANT SELECT ON collector.Perfmon TO [{L}]') } }
  @{ M='SELECT on [DBAMonitor].[collector].[StorageIO]'; Class='EXACT'; DbOps=@{ DBAMonitor=@('GRANT SELECT ON collector.StorageIO TO [{L}]') } }
  @{ M='SELECT on [DBAMonitor].[collector].[WaitStats]'; Class='EXACT'; DbOps=@{ DBAMonitor=@('GRANT SELECT ON collector.WaitStats TO [{L}]') } }
  @{ M='SELECT on DBAMonitor.collector.DatabaseGrowthCurrent (and its history table)'; Class='EXACT'; DbOps=@{ DBAMonitor=@('GRANT SELECT ON collector.DatabaseGrowthCurrent TO [{L}]','GRANT SELECT ON collector.DatabaseGrowthHistory TO [{L}]') } }

  @{ M='VIEW DEFINITION'; Class='EXACT'; DbOps=@{ master=@('GRANT VIEW DEFINITION TO [{L}]') }; Note='SCOPE:CurrentDatabase; tested in master' }
  @{ M='VIEW SERVER STATE, EXECUTE on xp_readerrorlog (sysadmin or securityadmin in practice)'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ master=@('GRANT EXECUTE ON sys.xp_readerrorlog TO [{L}]') } }
  @{ M='VIEW SERVER STATE (for xp_readerrorlog via sysadmin or securityadmin)'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ master=@('GRANT EXECUTE ON sys.xp_readerrorlog TO [{L}]') }; Note='tested with direct EXECUTE grant, the narrowest working reading' }
  @{ M='VIEW SERVER STATE (xp_readerrorlog; sysadmin in practice for most instances)'; Class='EXACT'; Server='VIEW SERVER STATE'; DbOps=@{ master=@('GRANT EXECUTE ON sys.xp_readerrorlog TO [{L}]') }; Note='tested with direct EXECUTE grant, the narrowest working reading' }

  @{ M='VIEW SERVER STATE, sysadmin (for LOGINPROPERTY on other logins), EXECUTE on xp_readerrorlog'; Class='PARTIAL'; Server='VIEW SERVER STATE'; DbOps=@{ master=@('GRANT EXECUTE ON sys.xp_readerrorlog TO [{L}]') }; Note='sysadmin component untested; arm = VSS + EXEC xp_readerrorlog' }
  @{ M='VIEW SERVER STATE, sysadmin (for xp_cmdshell value_in_use and registry access)'; Class='PARTIAL'; Server='VIEW SERVER STATE'; Note='sysadmin component untested; arm = VSS only' }
  @{ M='VIEW ANY DATABASE, sysadmin to see LOGINPROPERTY details'; Class='PARTIAL'; Server='VIEW ANY DATABASE'; Note='sysadmin component untested; arm = VAD only' }
  @{ M="VIEW ANY DEFINITION (VIEW SERVER STATE for full detail); CONTROL SERVER to compare password hashes, which are otherwise reported as 'no-permission'"; Class='PARTIAL'; Server='VIEW ANY DEFINITION'; Note='arm = minimum stated (VIEW ANY DEFINITION)' }

  @{ M='VIEW ANY DATABASE, VIEW DATABASE STATE'; Class='EXACT'; Server='VIEW ANY DATABASE'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW DATABASE STATE'; Class='EXACT'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW SERVER STATE, VIEW DATABASE STATE'; Class='EXACT'; Server='VIEW SERVER STATE'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW DATABASE STATE (iterates each user database)'; Class='EXACT'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW DATABASE STATE on each target database'; Class='EXACT'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW DATABASE STATE or membership in db_securityadmin'; Class='EXACT'; PerDbGrant='VIEW DATABASE STATE'; Note='weaker stated alternative tested' }
  @{ M='VIEW DATABASE STATE; VIEW SERVER STATE for sys.dm_database_encryption_keys'; Class='EXACT'; Server='VIEW SERVER STATE'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='VIEW ANY DATABASE, VIEW DEFINITION on each database'; Class='EXACT'; Server='VIEW ANY DATABASE'; PerDbGrant='VIEW DEFINITION' }
  @{ M='VIEW ANY DATABASE, VIEW DEFINITION on each target database'; Class='EXACT'; Server='VIEW ANY DATABASE'; PerDbGrant='VIEW DEFINITION' }
  @{ M='VIEW ANY DATABASE, plus access to each user database it inspects (db_datareader or VIEW DATABASE STATE); it opens every online user database'; Class='EXACT'; Server='VIEW ANY DATABASE'; PerDbGrant='VIEW DATABASE STATE'; Note='VIEW DATABASE STATE arm of the stated either/or' }

  @{ M='sysadmin (to run generated DDL); VIEW SERVER STATE at job runtime'; Class='GEN'; Server='VIEW SERVER STATE' }
  @{ M='sysadmin (to run generated DDL); VIEW SERVER STATE, VIEW DATABASE STATE at job runtime'; Class='GEN'; Server='VIEW SERVER STATE'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='sysadmin (to run generated DDL); VIEW DATABASE STATE per database at job runtime'; Class='GEN'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='sysadmin (to run generated DDL); VIEW ANY DATABASE, VIEW DATABASE STATE at job runtime'; Class='GEN'; Server='VIEW ANY DATABASE'; PerDbGrant='VIEW DATABASE STATE' }
  @{ M='sysadmin (to run generated DDL); SELECT on [DBAMonitor].[collector].* at job runtime'; Class='GEN'; DbOps=@{ DBAMonitor=@('GRANT SELECT ON SCHEMA::collector TO [{L}]') } }
  @{ M='sysadmin (to run generated DDL); VIEW SERVER STATE, EXECUTE xp_readerrorlog at job runtime'; Class='GEN'; Server='VIEW SERVER STATE'; DbOps=@{ master=@('GRANT EXECUTE ON sys.xp_readerrorlog TO [{L}]') } }
)

function FindRecipe([string]$claim) {
    foreach ($r in $R) {
        if ($r.Prefix) { if ($claim.StartsWith($r.M)) { return $r } }
        elseif ($claim -eq $r.M) { return $r }
    }
    return $null
}

$groups = @{}
foreach ($s in $scriptInv) {
    if (-not $s.readonly) { continue }
    if (-not $s.requires) { continue }
    $rec = FindRecipe $s.requires
    if (-not $groups.ContainsKey($s.requires)) { $groups[$s.requires] = @{ Recipe = $rec; Scripts = New-Object System.Collections.Generic.List[object] } }
    $groups[$s.requires].Scripts.Add($s)
}

Write-Host ("inventory: {0} scripts, groups: {1}" -f @($scriptInv).Count, $groups.Count)
if ($groups.Count -eq 0) { throw 'no groups built - aborting' }

$noneLogin = 'sqldba_req_none_b'
DropLogin $noneLogin @()
Admin "CREATE LOGIN [$noneLogin] WITH PASSWORD = '$pw', CHECK_POLICY = OFF"

$rows = New-Object System.Collections.Generic.List[object]
$gi = 0
foreach ($claim in ($groups.Keys | Sort-Object)) {
    $g = $groups[$claim]; $rec = $g.Recipe
    if (-not $rec) {
        foreach ($s in $g.Scripts) { $rows.Add([pscustomobject]@{ Path=$s.path; Claim=$claim; Class='UNMAPPED'; Verdict='UNMAPPED'; GrantedOk=$null; NoneOk=$null; GrantedError=''; NoneError=''; Note='no recipe' }) }
        Write-Host "UNMAPPED: $claim"; continue
    }
    if ($rec.Class -eq 'SKIP') {
        foreach ($s in $g.Scripts) { $rows.Add([pscustomobject]@{ Path=$s.path; Claim=$claim; Class='SKIP'; Verdict='SKIP'; GrantedOk=$null; NoneOk=$null; GrantedError=''; NoneError=''; Note=$rec.Note }) }
        continue
    }
    $gi++
    $login = 'sqldba_req_g{0:d2}' -f $gi
    $touched = New-Object System.Collections.Generic.List[string]
    DropLogin $login $allDbs
    Admin "CREATE LOGIN [$login] WITH PASSWORD = '$pw', CHECK_POLICY = OFF"
    if ($rec.Server) { Admin "GRANT $($rec.Server) TO [$login]" }
    if ($rec.DbOps) {
        foreach ($db in @($rec.DbOps.Keys)) {
            Admin "CREATE USER [$login] FOR LOGIN [$login]" $db
            $touched.Add($db)
            foreach ($op in $rec.DbOps[$db]) { Admin ($op -replace '\{L\}', $login) $db }
        }
    }
    if ($rec.PerDbGrant) {
        foreach ($db in $allDbs) {
            if (-not $touched.Contains($db)) { Admin "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='$login') CREATE USER [$login] FOR LOGIN [$login]" $db; $touched.Add($db) }
            Admin "GRANT $($rec.PerDbGrant) TO [$login]" $db
        }
    }
    Write-Host ("[{0}] {1}  ({2} scripts, class {3})" -f $login, $claim, $g.Scripts.Count, $rec.Class)
    foreach ($s in $g.Scripts) {
        $text = Get-Content -LiteralPath (Join-Path (Join-Path $RepoRoot 'sql') $s.path) -Raw
        $ga = RunAs $login $text
        $na = RunAs $noneLogin $text
        $verdict = switch ($rec.Class) {
            'EXACT'   { if (-not $ga.ok) { 'INSUFFICIENT' } elseif ($na.ok) { 'NONE-ALSO-PASSES' } else { 'CORRECT' } }
            'PUBLIC'  { if ($ga.ok) { 'CORRECT' } else { 'INSUFFICIENT' } }
            'PARTIAL' { if ($ga.ok) { 'PARTIAL-OK' } else { 'PARTIAL-FAIL' } }
            'GEN'     { if ($ga.ok) { 'GEN-OK' } else { 'GEN-FAIL' } }
        }
        $rows.Add([pscustomobject]@{ Path=$s.path; Claim=$claim; Class=$rec.Class; Verdict=$verdict; GrantedOk=$ga.ok; NoneOk=$na.ok; GrantedError=$ga.err; NoneError=$na.err; Note=[string]$rec.Note })
        Write-Host ('    {0,-18} {1}' -f $verdict, $s.path)
    }
    DropLogin $login $touched
}
DropLogin $noneLogin @()

$left = Admin "SELECT name FROM sys.server_principals WHERE name LIKE 'sqldba_req%'"
if (@($left).Count -gt 0) { Write-Host ("WARNING: leftover logins: " + (@($left).name -join ', ')) } else { Write-Host "teardown clean: no sqldba_req% logins remain" }

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
$rows | Group-Object Verdict | Sort-Object Count -Descending | ForEach-Object { Write-Host ("{0,-18} {1}" -f $_.Name, $_.Count) }
Write-Host "wrote $OutCsv"
