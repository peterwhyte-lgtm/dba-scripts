<#
Tests the `Requires:` header line for real, by running each script as a login granted exactly
what the header claims - and as a login granted nothing at all.

Two arms:
  GRANTED : CONNECT SQL + VIEW SERVER STATE.  A failure means the stated requirement is
            INSUFFICIENT: a DBA grants what we told them to and the script still does not run.
  NONE    : CONNECT SQL only.  A success means the stated requirement is OVER-BROAD: we are
            telling a DBA to grant more privilege than the script needs.

Only scripts whose header declares -- SAFE:ReadOnly are executed. Logins are dropped at the end.
#>
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$OutDir,
    [string]$ServerInstance = '.',
    [string]$Claim = 'VIEW SERVER STATE'
)
$ErrorActionPreference = 'Stop'
Import-Module SqlServer -DisableNameChecking 3>$null 4>$null

$pw = 'L4b-Req-Test-2026!x'
$logins = @{ granted = 'sqldba_req_granted'; none = 'sqldba_req_none' }

function AdminSql([string]$q) {
    Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -TrustServerCertificate `
        -QueryTimeout 60 -Query $q -ErrorAction Stop
}

# --- setup -------------------------------------------------------------------
foreach ($k in $logins.Keys) {
    $l = $logins[$k]
    AdminSql "IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = '$l') DROP LOGIN [$l];"
    AdminSql "CREATE LOGIN [$l] WITH PASSWORD = '$pw', CHECK_POLICY = OFF;"
}
AdminSql "GRANT $Claim TO [$($logins.granted)];"
Write-Host "created $($logins.granted) (CONNECT SQL + $Claim) and $($logins.none) (CONNECT SQL only)"

# --- pick the scripts whose header claims exactly $Claim ---------------------
$files = Get-ChildItem -Path (Join-Path $RepoRoot 'sql') -Filter *.sql -Recurse -File | Sort-Object FullName
$targets = @()
foreach ($f in $files) {
    $t = Get-Content -LiteralPath $f.FullName -Raw
    if ($t -notmatch '(?im)^\s*--\s*SAFE:\s*ReadOnly') { continue }
    if ($t -match "(?im)^\s*Requires\s*:\s*$([regex]::Escape($Claim))\s*$") {
        $targets += [pscustomobject]@{ Path = $f.FullName.Substring($RepoRoot.Length).TrimStart('\'); Text = $t }
    }
}
Write-Host ("scripts claiming exactly '{0}' and marked ReadOnly: {1}" -f $Claim, $targets.Count)

function RunAs([string]$login, [string]$query) {
    try {
        $null = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database master -TrustServerCertificate `
            -Username $login -Password $pw -QueryTimeout 60 -Query $query -ErrorAction Stop
        return @{ ok = $true; err = '' }
    } catch {
        return @{ ok = $false; err = ($_.Exception.Message -replace '\s+', ' ') }
    }
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $g = RunAs $logins.granted $t.Text
    $n = RunAs $logins.none    $t.Text
    $verdict = if (-not $g.ok) { 'INSUFFICIENT' } elseif ($n.ok) { 'OVER-BROAD' } else { 'CORRECT' }
    $rows.Add([pscustomobject]@{
        Path = $t.Path; Verdict = $verdict
        GrantedOk = $g.ok; NoneOk = $n.ok
        GrantedError = $g.err; NoneError = $n.err
    })
    Write-Host ('{0,-13} {1}' -f $verdict, ($t.Path -replace '[^\x20-\x7E]', '?'))
}

# --- teardown ----------------------------------------------------------------
foreach ($k in $logins.Keys) { AdminSql "DROP LOGIN [$($logins[$k])];" }
Write-Host 'logins dropped'

if (-not $OutDir) { $OutDir = $PSScriptRoot }
$csv = Join-Path $OutDir 'requires-check.csv'
$rows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$rows | Group-Object Verdict | ForEach-Object { Write-Host ("{0,-13} {1}" -f $_.Name, $_.Count) }
Write-Host "wrote $csv"
