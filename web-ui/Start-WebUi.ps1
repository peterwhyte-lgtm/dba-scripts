<#
.SYNOPSIS
    Local web UI for browsing scripts and visualising output CSVs.
.DESCRIPTION
    Starts an HTTP listener on localhost:8787. No external dependencies for the server;
    Chart.js is loaded from CDN on the CSV chart page (requires internet for that page only).
    Press Ctrl+C to stop.
.EXAMPLE
    .\web-ui\Start-WebUi.ps1
    .\web-ui\Start-WebUi.ps1 -Port 9090
#>
param([int]$Port = 8787, [switch]$Inline)

if (-not $Inline) {
    Start-Process pwsh -ArgumentList "-NoExit", "-File", "`"$PSCommandPath`"", "-Port", $Port, "-Inline"
    return
}

$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = "dba-tools web UI — localhost:$Port"
$repoRoot = Split-Path $PSScriptRoot -Parent

$script:enrichedCache       = $null
$script:enrichedCacheExpiry = [DateTime]::MinValue

# ── data helpers ───────────────────────────────────────────────────────────────

function Get-AllScripts {
    $sql = Get-ChildItem "$repoRoot\sql" -Recurse -Filter '*.sql' -File |
        Select-Object FullName,
            @{n='Name';    e={ $_.BaseName }},
            @{n='Category';e={
                $rel = $_.FullName.Replace($repoRoot.ToString(),'').TrimStart('\').Replace('\','/')
                if ($rel -match '^sql/([^/]+)/([^/]+)/') { $Matches[1] }
                else { $_.Directory.Name }
            }},
            @{n='Type';    e={ 'SQL' }},
            @{n='RelPath'; e={ $_.FullName.Replace($repoRoot,'').TrimStart('\') }}

    $ps = Get-ChildItem "$repoRoot\powershell" -Recurse -Filter '*.ps1' -File |
        Select-Object FullName,
            @{n='Name';    e={ $_.BaseName }},
            @{n='Category';e={ $_.Directory.Name }},
            @{n='Type';    e={ 'PS1' }},
            @{n='RelPath'; e={ $_.FullName.Replace($repoRoot,'').TrimStart('\') }}

    # Multi-server scripts — browsable and copyable, not runnable via the web UI
    $msq = Get-ChildItem "$repoRoot\powershell\reporting\multi-server" -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object FullName,
            @{n='Name';    e={ $_.BaseName }},
            @{n='Category';e={ 'multi-server' }},
            @{n='Type';    e={ 'PS1' }},
            @{n='RelPath'; e={ $_.FullName.Replace($repoRoot,'').TrimStart('\') }}

    @($sql) + @($ps) + @($msq)
}

function Get-AllScriptsCached {
    $now = [DateTime]::UtcNow
    if ($script:enrichedCache -and $now -lt $script:enrichedCacheExpiry) {
        return $script:enrichedCache
    }
    $raw = Get-AllScripts
    $enriched = @($raw | ForEach-Object {
        $fp = $_.FullName
        $_ | Select-Object *,
            @{n='Purpose';      e={ Get-ScriptPurpose $fp }},
            @{n='Safety';       e={ Get-ScriptSafety  $fp }},
            @{n='IsHealthCheck';e={
                $_.Type -eq 'SQL' -and
                ((Get-Content $fp -Raw -EA SilentlyContinue) -match '(?m)HealthCheck\s*:\s*Yes')
            }},
            @{n='IsWrapper'; e={
                # Thin wrapper = has a matching SQL file AND delegates to Invoke-RepoSql.
                # Orchestrators (e.g. Invoke-HealthCheckCollection) also call Invoke-RepoSql
                # but have no matching SQL file, so they correctly appear as workflows.
                # Generate-* scripts have a matching SQL file but call Invoke-Sqlcmd directly,
                # so they also correctly appear as workflows.
                if ($_.Type -ne 'PS1') { $false }
                else {
                    $base          = [System.IO.Path]::GetFileNameWithoutExtension($fp)
                    $hasMatchingSql = $null -ne (
                        Get-ChildItem "$repoRoot\sql" -Recurse -Filter "$base.sql" -File -EA SilentlyContinue |
                        Select-Object -First 1
                    )
                    if (-not $hasMatchingSql) {
                        $hasMatchingSql = $null -ne (
                            Get-ChildItem "$repoRoot\sql\migration" -Filter "$base.sql" -File -EA SilentlyContinue |
                            Select-Object -First 1
                        )
                    }
                    $callsRunner   = (Get-Content $fp -Raw -EA SilentlyContinue) -match 'Invoke-RepoSql'
                    $hasMatchingSql -and $callsRunner
                }
            }}
    })
    $script:enrichedCache       = $enriched
    $script:enrichedCacheExpiry = $now.AddSeconds(30)
    return $enriched
}

# Production-DBA category order — what a DBA reaches for first comes first.
# Applied wherever categories are grouped/listed; unknown categories sort after known ones.
$script:SqlCategoryOrder = @('performance','monitoring','backups','security','high-availability','inventory','maintenance','migration','collectors','traces','lab')
$script:PsCategoryOrder  = @('diagnostics','reporting','multi-server','disk-space','migration','patching','sql','ssms','installation','maintenance','lab')
function Get-CategoryRank([string]$name, [string[]]$order) {
    $i = [Array]::IndexOf($order, $name.ToLower())
    if ($i -ge 0) { $i } else { $order.Count }
}

function Html-Escape([string]$s) {
    $s.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

function Fmt-Mb([object]$v) {
    $n = $v -as [double]
    if ($null -eq $n) { return $(if ($v) { $v } else { '—' }) }
    [Math]::Round($n, 0)
}

function Fmt-Pct([object]$v) {
    $n = $v -as [double]
    if ($null -eq $n) { return $(if ($v) { $v } else { '—' }) }
    [Math]::Round($n, 1)
}

function Get-ScriptPurpose([string]$path) {
    try {
        foreach ($line in (Get-Content $path -TotalCount 10)) {
            if ($line -match 'Purpose\s*:\s*(.+)') { return $Matches[1].Trim() }
        }
    } catch {}
    return ''
}

function Get-ScriptSafety([string]$path) {
    try {
        foreach ($line in (Get-Content $path -TotalCount 20)) {
            if ($line -match '--\s*SAFE\s*:\s*(\S+)')       { return $Matches[1] }
            if ($line -match '\bSafe\s*:\s*(.+)')            { return $Matches[1].Trim() }
            # PS header convention: RiskLevel : SAFE | MEDIUM | HIGH IMPACT
            if ($line -match '\bRiskLevel\s*:\s*(.+)')       { return $Matches[1].Trim() }
        }
    } catch {}
    # Fallback: infer from script name verb
    $name = [System.IO.Path]::GetFileNameWithoutExtension($path)
    if ($name -match '^(Get|Show|Find|Test|Export|Quick|Generate|Review|Invoke|Run|Check)-') { return 'Read-only' }
    if ($name -match '^(Restore|Install|New|Create|Remove|Drop|Rebuild)-')                   { return 'Creates objects' }
    if ($name -match '^(Backup|Set|Update|Clear|Fix|Repair|Apply|Write|Send)-')              { return 'Writes data' }
    return 'Unknown'
}

function Resolve-SafetyClass([string]$safety) {
    if ($safety -match 'Read' -or $safety -eq 'SAFE') { return 'safe-readonly' }
    if ($safety -match 'Writ' -or $safety -match 'MEDIUM') { return 'safe-writes' }
    if ($safety -match 'Creat' -or $safety -match 'IMPACT' -or $safety -match 'HIGH') { return 'safe-creates' }
    return 'safe-unknown'
}

function Resolve-SafetyLabel([string]$safety) {
    if ($safety -match 'Read' -or $safety -eq 'SAFE') { return 'Read-Only' }
    if ($safety -match 'Creat' -or $safety -match 'IMPACT' -or $safety -match 'HIGH') { return 'Creates' }
    if ($safety -match 'Writ' -or $safety -match 'MEDIUM') { return 'Writes' }
    return '?'
}

function Get-CsvJson([string]$fullPath) {
    $raw = @(Import-Csv $fullPath -ErrorAction SilentlyContinue)
    if (-not $raw) { return @{ headers=@(); rows=@(); labelCol=''; numericCols=@() } }

    $headers = @($raw[0].PSObject.Properties.Name)

    # Drop sqlcmd separator rows (any cell is all dashes)
    $data = @($raw | Where-Object {
        $row = $_
        -not ($headers | Where-Object { $row.$_ -match '^-+$' })
    })

    # Classify columns: first all-numeric column(s) → numericCols; first text col → labelCol
    $numericCols = @()
    $labelCol    = ''
    foreach ($h in $headers) {
        $vals = @($data | ForEach-Object { $_.$h } | Where-Object { $_ -ne '' -and $_ -ne $null })
        $numericCount = @($vals | Where-Object { $_ -as [double] -ne $null -or $_ -eq '0' }).Count
        if ($vals.Count -gt 0 -and $numericCount -eq $vals.Count) {
            $numericCols += $h
        } elseif (-not $labelCol) {
            $labelCol = $h
        }
    }

    # Drop continuation rows: sqlcmd writes multiline cell values (e.g. current_statement)
    # as raw newlines, producing extra rows where every numeric column is empty.
    if ($numericCols.Count -gt 0) {
        $data = @($data | Where-Object {
            $row = $_
            foreach ($nc in $numericCols) {
                if ($row.$nc -ne '' -and $null -ne $row.$nc) { return $true }
            }
            return $false
        })
    }

    # Detect single-column DDL / script output and reassemble split rows
    $ddlColNames = @('ddl','script','sql_script','sql','statement','definition','sql_text','code','t_sql','tsql')
    $isDdl = $headers.Count -eq 1 -and ($ddlColNames -contains $headers[0].ToLower().Trim())
    if ($isDdl) {
        $ddlText = ($data | ForEach-Object { $_.($headers[0]) }) -join "`n"
        return @{
            headers     = $headers
            rows        = @()
            labelCol    = ''
            numericCols = @()
            isDdl       = $true
            ddlText     = $ddlText
        }
    }

    # Build rows as ordered hashtables (serialises to JSON object, not array)
    $rowsArray = @($data | ForEach-Object {
        $row  = $_
        $dict = [ordered]@{}
        foreach ($h in $headers) { $dict[$h] = $row.$h }
        $dict
    })

    return @{
        headers     = $headers
        rows        = $rowsArray
        labelCol    = $labelCol
        numericCols = $numericCols
        isDdl       = $false
        ddlText     = ''
    }
}

# Error JSON for the /api/* handlers. ConvertTo-Json handles every JSON string escape
# (quotes, backslashes, control characters) — hand-rolled -replace chains missed tabs
# and control chars in SQL error text, producing unparseable JSON.
function ConvertTo-JsonError([string]$message) {
    $msg = ($message -replace '\r?\n', ' ').Trim()
    "{`"ok`":false,`"error`":$($msg | ConvertTo-Json)}"
}

function ConvertTo-Json2([object]$obj) {
    # Thin wrapper to ensure Depth is sufficient
    $obj | ConvertTo-Json -Depth 6 -Compress
}

# ── CSS ────────────────────────────────────────────────────────────────────────

$CSS = @'
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:"Segoe UI",system-ui,sans-serif;background:#0f1117;color:#c9d1d9;line-height:1.5}
a{color:#58a6ff;text-decoration:none}a:hover{text-decoration:underline}
header{background:#161b22;border-bottom:1px solid #30363d;padding:12px 28px;display:flex;align-items:center;gap:16px}
header h1{font-size:1rem;font-weight:600;color:#e6edf3;white-space:nowrap}
nav{display:flex;gap:4px}
nav a{font-size:.85rem;padding:5px 12px;border-radius:6px;color:#8b949e;transition:background .15s,color .15s}
nav a:hover,nav a.active{background:#21262d;color:#e6edf3;text-decoration:none}
.search-bar{margin-left:auto}
.search-bar input{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:6px 12px;width:240px;font-size:.85rem}
.search-bar input:focus{outline:none;border-color:#58a6ff}
main{max-width:1100px;margin:28px auto;padding:0 20px}
h2{font-size:1rem;font-weight:600;color:#e6edf3;margin:10px 0 14px;padding-bottom:6px;border-bottom:1px solid #21262d}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:10px;margin-bottom:28px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:14px 16px;transition:border-color .15s}
.card:hover{border-color:#58a6ff}
.card a{display:block;font-weight:500;color:#e6edf3;font-size:.9rem}
.card .purpose{font-size:.78rem;color:#8b949e;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.badge{display:inline-block;font-size:.7rem;padding:1px 7px;border-radius:10px;margin-bottom:4px;font-weight:600}
.badge-sql{background:#1f3a4a;color:#58a6ff}
.badge-ps{background:#2d2a4a;color:#a78bfa}
.badge-top{background:#1a3a2a;color:#3fb950}
.badge-hc{background:#3a2a0a;color:#e3a530}
.cat-label{font-size:.75rem;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px;font-weight:600}
pre{background:#0d1117;border:1px solid #21262d;border-radius:8px;padding:20px;overflow:auto;font-size:.82rem;color:#c9d1d9;tab-size:4;white-space:pre-wrap}
.code-wrap{position:relative}
.copy-btn{position:absolute;top:8px;right:8px;background:#21262d;border:1px solid #30363d;color:#8b949e;border-radius:6px;padding:4px 12px;font-size:.75rem;font-weight:600;cursor:pointer;transition:background .15s,color .15s,border-color .15s}
.copy-btn:hover{background:#2d333b;color:#e6edf3}
.copy-btn.copied{background:#1a3a2a;border-color:#3fb950;color:#3fb950}
.back{margin-bottom:14px;font-size:.85rem}
.script-title{font-size:1.2rem;font-weight:600;color:#e6edf3;margin-bottom:4px}
.script-meta{font-size:.8rem;color:#8b949e;margin-bottom:16px}
.empty{color:#8b949e;font-size:.9rem;padding:20px 0}
.chart-controls{display:flex;align-items:flex-start;gap:20px;flex-wrap:wrap;margin-bottom:16px;padding:14px 16px;background:#161b22;border:1px solid #30363d;border-radius:8px}
.col-checkboxes{display:flex;flex-wrap:wrap;gap:10px;flex:1}
.col-checkboxes label{font-size:.82rem;cursor:pointer;display:flex;align-items:center;gap:5px}
.type-btns{display:flex;gap:6px;align-items:flex-start;white-space:nowrap}
.type-btns button{background:#21262d;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:5px 12px;font-size:.82rem;cursor:pointer;transition:background .15s,border-color .15s}
.type-btns button:hover{background:#2d333b}
.type-btns button.active{background:#1f3a4a;border-color:#58a6ff;color:#58a6ff}
.chart-wrap{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px;margin-bottom:24px}
table{width:100%;border-collapse:collapse;font-size:.82rem;margin-top:4px}
th{text-align:left;padding:7px 10px;border-bottom:2px solid #30363d;color:#8b949e;font-weight:600;white-space:nowrap}
th.sortable{cursor:pointer;user-select:none}
th.sortable:hover{color:#e6edf3}
th.sort-asc::after{content:' ↑';color:#58a6ff}
th.sort-desc::after{content:' ↓';color:#58a6ff}
td{padding:6px 10px;border-bottom:1px solid #21262d;color:#c9d1d9;max-width:400px}
tr:hover td{background:#161b22}
.table-wrap{overflow-x:auto;border:1px solid #30363d;border-radius:8px;margin-bottom:6px}
.table-toolbar{display:flex;align-items:center;gap:12px;margin-bottom:10px}
.table-filter{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:6px 12px;font-size:.85rem;flex:1}
.table-filter:focus{outline:none;border-color:#58a6ff}
.row-count{font-size:.8rem;color:#8b949e;white-space:nowrap}
.mode-badge{font-size:.78rem;color:#8b949e;margin-bottom:16px}
.sv{display:inline-block;padding:1px 9px;border-radius:10px;font-size:.75rem;font-weight:600}
.sv-green{background:#1a3a2a;color:#3fb950}
.sv-red{background:#3a1a1a;color:#f78166}
.sv-orange{background:#3a2a1a;color:#ffa657}
.sv-gray{background:#21262d;color:#8b949e}
.sv-blue{background:#1a2a3a;color:#58a6ff}
.null-val{color:#444}
.cell-long{display:block;max-width:380px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer;color:#8b949e}
.cell-long:hover{color:#c9d1d9}
.cell-long.expanded{white-space:pre-wrap;word-break:break-all;overflow:visible}
.save-png-btn{background:#1a3a2a;border:1px solid #3fb950;color:#3fb950;border-radius:6px;padding:5px 14px;font-size:.82rem;cursor:pointer;transition:background .15s}
.save-png-btn:hover{background:#1f4a30}
.save-png-btn:disabled{opacity:.4;cursor:default}
.clear-btn{background:#1a0e0e;border:1px solid #f78166;color:#f78166;border-radius:6px;padding:5px 16px;font-size:.82rem;font-weight:600;cursor:pointer;transition:background .15s,border-color .15s}
.clear-btn:hover{background:#2d1515;border-color:#ff9b8e}
.clear-btn:disabled{opacity:.4;cursor:default}
.save-confirm{font-size:.78rem;color:#3fb950;margin-left:8px;opacity:0;transition:opacity .4s}
.save-confirm.show{opacity:1}
.pie-select{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:5px 10px;font-size:.82rem}
.pie-select:focus{outline:none;border-color:#58a6ff}
.chart-wrap canvas{max-height:400px}
.disk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(235px,1fr));gap:12px;margin-bottom:28px}
.disk-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:13px 14px}
.disk-summary{font-size:.85rem;color:#8b949e;margin-bottom:12px}
.disk-summary b{color:#e6edf3}
.disk-card.warn{border-color:#e3b341}.disk-card.crit{border-color:#f78166}
.disk-mount{font-size:1.05rem;font-weight:600;color:#e6edf3}.disk-vol{font-size:.78rem;color:#8b949e;margin-bottom:10px}
.bar-track{height:10px;background:#21262d;border-radius:5px;overflow:hidden;margin:8px 0}
.bar-fill{height:100%;border-radius:5px}.bar-ok{background:#3fb950}.bar-warn{background:#e3b341}.bar-crit{background:#f78166}
.disk-stats{display:flex;gap:16px;font-size:.78rem;color:#8b949e;flex-wrap:wrap;margin-top:6px}
.disk-stats strong{color:#c9d1d9}
.mini-bar-track{display:inline-block;width:52px;height:6px;background:#21262d;border-radius:3px;vertical-align:middle;margin-left:5px;overflow:hidden}
.mini-bar-fill{height:100%;border-radius:3px}
.folder-row{display:flex;align-items:center;gap:10px;margin-bottom:20px;flex-wrap:wrap}
.folder-row label{font-size:.82rem;color:#8b949e;white-space:nowrap}
.folder-input{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:6px 12px;font-size:.82rem;flex:1;min-width:300px}
.folder-input:focus{outline:none;border-color:#58a6ff}
.folder-btn{background:#21262d;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:6px 14px;font-size:.82rem;cursor:pointer;white-space:nowrap}
.folder-btn:hover{background:#2d333b}
.no-data{color:#8b949e;font-size:.85rem;padding:10px 0}
.status-badge{display:inline-block;padding:1px 9px;border-radius:10px;font-size:.75rem;font-weight:600}
.s-ok{background:#1a3a2a;color:#3fb950}.s-warn{background:#3a2a1a;color:#ffa657}.s-crit{background:#3a1a1a;color:#f78166}.s-gray{background:#21262d;color:#8b949e}
.hc-meta{display:flex;gap:20px;font-size:.82rem;color:#8b949e;margin-bottom:16px;flex-wrap:wrap}
.hc-meta strong{color:#c9d1d9}
.section-sep{border:none;border-top:2px solid #30363d;margin:36px 0 0}
.mini-sep{border:none;border-top:1px solid #21262d;margin:26px 0 0}
.vital-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:10px;margin-bottom:24px}
.vital-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px 14px;border-left:3px solid #30363d}
.vital-card.v-ok{border-left-color:#3fb950}.vital-card.v-warn{border-left-color:#ffa657}.vital-card.v-crit{border-left-color:#f78166}.vital-card.v-blue{border-left-color:#58a6ff}
.vital-row-label{font-size:.72rem;color:#8b949e;text-transform:uppercase;letter-spacing:.06em;font-weight:600;margin:14px 0 6px}
.vital-label{font-size:.7rem;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px}
.vital-val{font-size:1.1rem;font-weight:600;color:#e6edf3}
.vital-sub{font-size:.72rem;color:#8b949e;margin-top:2px}
.data-strip{display:flex;align-items:center;flex-wrap:wrap;gap:10px;background:#161b22;border:1px solid #30363d;border-radius:8px;padding:10px 14px;margin-bottom:16px;font-size:.85rem;color:#8b949e}
.data-strip b{color:#e6edf3}
.ds-select{background:#0d1117;border:1px solid #30363d;border-radius:6px;color:#e6edf3;font-size:.82rem;padding:5px 8px;max-width:280px}
.ds-spacer{flex:1}
.md-body{max-width:900px;line-height:1.55}
.md-body h1{font-size:1.35rem;margin:6px 0 4px;border-bottom:1px solid #30363d;padding-bottom:8px}
.md-body h2{font-size:1.05rem;margin:22px 0 8px;color:#58a6ff}
.md-body h3{font-size:.95rem;margin:16px 0 6px}
.md-body p,.md-body li{font-size:.88rem;color:#c9d1d9}
.md-body ul{padding-left:22px;margin:6px 0}
.md-body code{background:#21262d;border-radius:4px;padding:1px 5px;font-size:.82rem}
.md-body pre{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:12px;overflow-x:auto}
.md-body table{border-collapse:collapse;margin:10px 0}
.md-body th,.md-body td{border:1px solid #30363d;padding:5px 10px;font-size:.82rem}
.ai-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px 14px;margin-bottom:10px}
.ai-card .purpose{font-size:.8rem;color:#8b949e;margin-top:4px}
.badge-ai-cc{background:#1f3a2a;color:#3fb950}
.badge-ai-api{background:#1a2f47;color:#58a6ff}
.vital-card.clickable{cursor:pointer;transition:border-color .15s,background .15s}
.vital-card.clickable:hover{border-color:#58a6ff;background:#1c2128}
.drill-row{cursor:pointer}
.drill-row:hover{background:#1c2128}
.row-detail>td{background:#0d1117 !important;padding:10px 14px !important}
.rd-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:4px 18px;margin-bottom:8px}
.rd-k{color:#8b949e;font-size:.72rem;margin-right:8px}
.rd-v{font-size:.78rem;color:#e6edf3;word-break:break-word}
.rd-fix-label{font-size:.7rem;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;margin:6px 0 4px}
.rd-fix{background:#161b22;border:1px solid #30363d;border-radius:6px;padding:8px 10px;font-size:.78rem;color:#7ee787;white-space:pre-wrap;margin:0}
.score-chip{display:inline-block;border:1px solid #30363d;border-radius:14px;padding:3px 12px;margin:0 6px 6px 0;font-size:.78rem;cursor:pointer;background:#161b22;color:#c9d1d9}
.score-chip.active{border-color:#58a6ff;color:#58a6ff}
.score-chip .n{font-weight:700}
.sc-crit{border-left:3px solid #f78166}.sc-warn{border-left:3px solid #ffa657}.sc-info{border-left:3px solid #58a6ff}
.delta-new{color:#f78166;font-weight:600}.delta-res{color:#3fb950;font-weight:600}
.tri-row{display:flex;align-items:center;gap:6px}
.tri-row .triage-link{flex:1}
.tri-run{font-size:.7rem;padding:2px 9px;flex-shrink:0}
.tri-result{margin:4px 0 8px;border:1px solid #30363d;border-radius:8px;padding:8px;background:#0d1117;overflow-x:auto;display:none}
.tri-result table{border-collapse:collapse;width:100%}
.tri-result th,.tri-result td{border:1px solid #21262d;padding:3px 8px;font-size:.72rem;text-align:left;color:#c9d1d9;white-space:nowrap;max-width:340px;overflow:hidden;text-overflow:ellipsis}
.tri-result th{color:#8b949e}
.chip-row{margin:8px 0 2px}
.chip-row-cats{margin:2px 0 4px;padding-top:8px;border-top:1px dashed #21262d}
.chip-row-cats .score-chip{font-size:.72rem;padding:2px 10px}
.chip-row-label{font-size:.68rem;color:#8b949e;text-transform:uppercase;letter-spacing:.06em;margin-right:8px}
.score-chip:hover{border-color:#58a6ff}
.ai-card:hover{border-color:#58a6ff}
.donut{width:70px;height:70px;border-radius:50%;flex-shrink:0;position:relative;background:conic-gradient(var(--dc) calc(var(--p)*1%), #21262d 0)}
.donut::after{content:attr(data-label);position:absolute;inset:11px;background:#161b22;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:.76rem;font-weight:600;color:#e6edf3}
.donut-sub{font-size:.66rem;color:#8b949e;text-align:center;margin-top:4px;text-transform:uppercase;letter-spacing:.05em}
.disk-flex{display:flex;gap:16px;align-items:center}
.name-cell{position:relative;min-width:190px}
.name-cell .name-bar{position:absolute;left:2px;top:18%;height:64%;background:#262d38;border-radius:3px;z-index:0;max-width:calc(100% - 4px)}
.name-cell .name-txt{position:relative;z-index:1}
.sev-strip{display:flex;gap:8px;margin-bottom:24px;flex-wrap:wrap;align-items:center}
.sev-chip{display:inline-block;padding:5px 16px;border-radius:20px;font-size:.85rem;font-weight:600;border:1px solid}
.sev-chip.s-crit{background:#3a1a1a;color:#f78166;border-color:#f78166}
.sev-chip.s-warn{background:#3a2a1a;color:#ffa657;border-color:#ffa657}
.sev-chip.s-info{background:#1a2a3a;color:#58a6ff;border-color:#58a6ff}
.sev-chip.s-ok{background:#1a3a2a;color:#3fb950;border-color:#3fb950}
details.rv-section{margin:0}
details.rv-section>summary{font-size:1rem;font-weight:600;color:#e6edf3;margin:10px 0 14px;padding-bottom:6px;border-bottom:1px solid #21262d;cursor:pointer;list-style:none;display:flex;align-items:center;gap:8px}
details.rv-section>summary::-webkit-details-marker{display:none}
details.rv-section>summary::before{content:'\25be';font-size:.75rem;color:#8b949e;flex-shrink:0;font-family:monospace}
details.rv-section:not([open])>summary::before{content:'\25b8'}
.find-pills{margin-left:auto;display:flex;gap:6px;align-items:center;flex-shrink:0}
.sev-filter-btn{padding:3px 12px;border-radius:20px;font-size:.8rem;font-weight:600;border:1px solid;cursor:pointer;background:transparent;transition:opacity .15s}
.sev-filter-btn.s-crit{color:#f78166;border-color:#f78166}.sev-filter-btn.s-crit.active{background:#3a1a1a}
.sev-filter-btn.s-warn{color:#ffa657;border-color:#ffa657}.sev-filter-btn.s-warn.active{background:#3a2a1a}
.sev-filter-btn.s-info{color:#58a6ff;border-color:#58a6ff}.sev-filter-btn.s-info.active{background:#1a2a3a}
.sev-filter-btn:hover{opacity:.8}
.findings-list{display:flex;flex-direction:column;gap:5px;margin-bottom:28px}
.finding-row{padding:9px 14px;border-radius:6px;border-left:3px solid;display:grid;grid-template-columns:90px 170px 1fr;align-items:start;gap:4px 12px}
.finding-row .find-detail{grid-column:2/4;font-size:.78rem;color:#8b949e;margin-top:2px}
.f-crit{background:#1a0e0e;border-color:#f78166}
.f-warn{background:#120f06;border-color:#ffa657}
.f-info{background:#0b1220;border-color:#58a6ff}
.find-cat{font-size:.75rem;color:#8b949e;padding-top:2px}
.find-subj{font-size:.85rem;color:#e6edf3;font-weight:500}
.info-card-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:10px;margin-bottom:24px}
.info-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:12px 14px}
.info-label{font-size:.72rem;color:#8b949e;text-transform:uppercase;letter-spacing:.04em;margin-bottom:4px}
.info-val{font-size:.88rem;color:#e6edf3;font-weight:500;word-break:break-word}
.view-toolbar{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:14px;flex-wrap:wrap}
.view-toolbar-left{flex:1;min-width:0}
.run-bar{display:flex;align-items:center;gap:8px;flex-shrink:0;flex-wrap:wrap;justify-content:flex-end}
.run-bar label{font-size:.78rem;color:#8b949e;white-space:nowrap}
.server-input{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:5px 10px;font-size:.82rem;width:180px}
.server-input:focus{outline:none;border-color:#58a6ff}
.run-btn{background:#1f6feb;border:1px solid #388bfd;color:#e6edf3;border-radius:6px;padding:5px 16px;font-size:.85rem;font-weight:600;cursor:pointer;white-space:nowrap;transition:background .15s}
.run-btn:hover{background:#388bfd}.run-btn:disabled{opacity:.5;cursor:default}
.safe-badge{display:inline-block;font-size:.7rem;padding:2px 9px;border-radius:10px;font-weight:600;vertical-align:middle}
.safe-readonly{background:#1a3a2a;color:#3fb950}
.safe-writes{background:#3a1f00;color:#ffa657}
.safe-creates{background:#3a1a1a;color:#f78166}
.safe-unknown{background:#21262d;color:#8b949e}
.dryrun-wrap{display:flex;align-items:center;gap:5px;font-size:.78rem;color:#8b949e;white-space:nowrap;border:1px solid #30363d;border-radius:6px;padding:4px 10px;background:#0d1117}
.dryrun-wrap input[type=checkbox]{accent-color:#ffa657;cursor:pointer}
.dryrun-wrap label{cursor:pointer;user-select:none}
.dryrun-banner{background:#1a0f00;border:1px solid #ffa657;border-radius:6px;padding:8px 14px;font-size:.82rem;color:#ffa657;margin-bottom:14px}
.run-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.65);z-index:200;align-items:center;justify-content:center;flex-direction:column;gap:14px}
.run-spinner{width:44px;height:44px;border:3px solid #30363d;border-top-color:#58a6ff;border-radius:50%;animation:spin 1s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}
.run-spinner-label{color:#c9d1d9;font-size:.9rem}
.run-error{color:#f78166;font-size:.82rem;margin-top:6px;padding:8px 12px;background:#1a0e0e;border:1px solid #f78166;border-radius:6px}
.triage-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:12px;margin-bottom:28px}
.triage-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px 18px}
.triage-title{font-size:.92rem;font-weight:600;color:#e6edf3;margin-bottom:5px}
.triage-when{font-size:.76rem;color:#8b949e;margin-bottom:12px;line-height:1.45}
.triage-links{display:flex;flex-direction:column;gap:0}
.triage-link{display:flex;align-items:center;gap:8px;font-size:.82rem;color:#c9d1d9;padding:5px 0;border-bottom:1px solid #1a1f27;text-decoration:none}
.triage-link:last-child{border-bottom:none}
.triage-link:hover{color:#58a6ff;text-decoration:none}
.triage-fix-tag{font-size:.68rem;padding:1px 6px;border-radius:8px;background:#1a3a2a;color:#3fb950;margin-left:auto;white-space:nowrap;font-weight:600}
.info-banner{background:#0b1220;border:1px solid #1f3a4a;border-radius:6px;padding:8px 14px;font-size:.82rem;color:#58a6ff;margin-bottom:14px}
.empty-state{background:#0b1220;border:1px solid #1f3a4a;border-radius:8px;padding:32px 24px;text-align:center;margin-bottom:16px}
.empty-state-title{color:#58a6ff;font-size:.92rem;font-weight:600;margin-bottom:6px}
.empty-state-sub{color:#8b949e;font-size:.78rem;line-height:1.5}
details.cat-group{margin-bottom:20px}
details.cat-group>summary{cursor:pointer;list-style:none;display:flex;align-items:center;gap:8px;padding:7px 2px;font-size:.75rem;color:#8b949e;text-transform:uppercase;letter-spacing:.05em;font-weight:600;user-select:none;border-bottom:1px solid #21262d;margin-bottom:10px}
details.cat-group>summary::-webkit-details-marker{display:none}
details.cat-group>summary::marker{display:none}
details.cat-group>summary::before{content:'▶';font-size:.55rem;color:#58a6ff;transition:transform .15s;flex-shrink:0}
details.cat-group[open]>summary::before{transform:rotate(90deg)}
.cat-count{margin-left:auto;font-size:.72rem;color:#444c56;font-weight:400;text-transform:none;letter-spacing:0}
'@

# ── page wrapper ───────────────────────────────────────────────────────────────

function Wrap-Page([string]$title, [string]$body, [string]$q='', [string]$active='scripts') {
    $qEsc = Html-Escape $q
    $navTriage   = if ($active -eq 'triage')   { "class='active'" } else { '' }
    $navScripts  = if ($active -eq 'scripts')  { "class='active'" } else { '' }
    $navReview   = if ($active -eq 'review')   { "class='active'" } else { '' }
    $navSecurity = if ($active -eq 'security') { "class='active'" } else { '' }
    $navDisk     = if ($active -eq 'disk')     { "class='active'" } else { '' }
    $navAi       = if ($active -eq 'ai')       { "class='active'" } else { '' }
    $navCsvs     = if ($active -eq 'csvs')     { "class='active'" } else { '' }
    @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title — dba-tools</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Cellipse cx='8' cy='4' rx='6' ry='2.6' fill='%2358a6ff'/%3E%3Cpath d='M2 4v8.2c0 1.4 2.7 2.6 6 2.6s6-1.2 6-2.6V4' fill='none' stroke='%2358a6ff' stroke-width='1.8'/%3E%3Cpath d='M2 8.2c0 1.4 2.7 2.6 6 2.6s6-1.2 6-2.6' fill='none' stroke='%2358a6ff' stroke-width='1.2' opacity='.6'/%3E%3C/svg%3E">
<style>$CSS</style></head><body>
<header>
  <h1>dba-tools</h1>
  <nav>
    <a href="/triage" $navTriage>Triage</a>
    <a href="/" $navScripts>Scripts</a>
    <a href="/review" $navReview>Health Check</a>
    <a href="/security" $navSecurity>Security</a>
    <a href="/disk" $navDisk>Disk Space</a>
    <a href="/ai" $navAi>AI Assessment</a>
    <a href="/csvs" $navCsvs>Output CSVs</a>
  </nav>
  <form class="search-bar" action="/search" method="get">
    <input name="q" placeholder="Search scripts…" value="$qEsc" autocomplete="off">
  </form>
</header>
<main>$body</main>
</body></html>
"@
}

# ── page builders ──────────────────────────────────────────────────────────────

function Script-Card([object]$s, [string]$typeName, [string]$badgeClass) {
    $purpose     = $s.Purpose
    $purposeHtml = if ($purpose) { "<div class='purpose'>$(Html-Escape $purpose)</div>" } else { '' }
    $relEnc      = [Uri]::EscapeDataString($s.RelPath)
    $sBadge      = "<span class='safe-badge $(Resolve-SafetyClass $s.Safety)'>$(Resolve-SafetyLabel $s.Safety)</span>"
    "<div class='card'><span class='badge $badgeClass'>$typeName</span>$sBadge<a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
}

function Build-HomePage {
    $scripts = Get-AllScriptsCached

    $sqlScripts = @($scripts | Where-Object { $_.Type -eq 'SQL' })

    # PS scripts that are standalone tools/workflows — not thin SQL wrappers, not lab
    $workflowScripts = @($scripts | Where-Object {
        $_.Type -eq 'PS1' -and -not $_.IsWrapper -and
        $_.RelPath -notmatch '[\\/]lab[\\/]'
    })

    # ── Top scripts for production DBA ────────────────────────────────────────
    $topDefs = @(
        [ordered]@{P='sql\performance\Get-WaitStatistics.sql';             Desc='Ranked wait types — first stop for unexplained slowness'}
        [ordered]@{P='sql\performance\blocking-locking\Get-BlockingChains.sql';             Desc='Who is blocking whom — head-blocker tree'}
        [ordered]@{P='sql\performance\active-sessions\Get-ActiveRequests.sql';             Desc='Queries running right now — incident first look'}
        [ordered]@{P='sql\performance\queries\Get-TopCpuQueries.sql';              Desc='Highest CPU queries from plan cache'}
        [ordered]@{P='sql\performance\indexes\Get-MissingIndexes.sql';             Desc='High-impact missing index recommendations'}
        [ordered]@{P='sql\monitoring\disk-space\Get-DatabaseFreeSpaceSummary.sql';    Desc='All databases — allocated, used, and free space ordered by free space'}
        [ordered]@{P='sql\backups\Get-BackupCoverage.sql';                 Desc='Backup currency across all databases'}
        [ordered]@{P='sql\monitoring\jobs\Get-SqlAgentJobFailureSummary.sql';   Desc='Recent job failures and duration outliers'}
        [ordered]@{P='sql\performance\indexes\Get-IndexFragmentation.sql';          Desc='Index fragmentation — maintenance candidate list'}
        [ordered]@{P='sql\monitoring\instance\Get-InstanceConfigurationScore.sql';  Desc='Best-practice configuration score for this instance'}
    )

    $topCards = ''
    foreach ($t in $topDefs) {
        $fp = Join-Path $repoRoot $t.P
        if (-not (Test-Path -LiteralPath $fp)) { continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($t.P)
        $enc  = [Uri]::EscapeDataString($t.P)
        $topCards += "<div class='card'><span class='badge badge-top'>Top</span><a href='/view?p=$enc'>$(Html-Escape $name)</a><div class='purpose'>$(Html-Escape $t.Desc)</div></div>"
    }
    $html = ''
    if ($topCards) {
        $html += "<h2>Start here</h2><div class='grid'>$topCards</div><hr class='section-sep' style='margin-bottom:28px'>"
    }

    # ── Health Check Suite ────────────────────────────────────────────────────
    $hcScripts = @($sqlScripts | Where-Object { $_.IsHealthCheck })
    if ($hcScripts.Count -gt 0) {
        $hcCards = ''
        foreach ($s in $hcScripts) {
            $relEnc  = [Uri]::EscapeDataString($s.RelPath)
            $purpose = if ($s.Purpose) { "<div class='purpose'>$(Html-Escape $s.Purpose)</div>" } else { '' }
            $hcCards += "<div class='card'><span class='badge badge-hc'>HC</span><a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purpose</div>"
        }
        $html += "<details class='cat-group'><summary><span>Health Check Suite</span><span class='cat-count'>$($hcScripts.Count) scripts — run daily via Invoke-HealthCheckCollection</span></summary><div class='grid'>$hcCards</div></details>"
        $html += "<hr class='section-sep' style='margin-bottom:24px'>"
    }

    # ── SQL scripts — collapsible per category, expanded by default ───────────
    $html += "<h2>SQL Scripts ($($sqlScripts.Count))</h2>"
    $catIdx = 0
    foreach ($cat in ($sqlScripts | Group-Object Category | Sort-Object { Get-CategoryRank $_.Name $script:SqlCategoryOrder }, Name)) {
        $count   = $cat.Group.Count
        $catName = Html-Escape $cat.Name
        $plural  = if ($count -ne 1) { 's' } else { '' }
        # only the top categories start expanded — keeps Start Here + Health Check on the first screen
        $open    = if ($catIdx -lt 2) { ' open' } else { '' }
        $catIdx++
        $html += "<details class='cat-group'$open><summary><span>$catName</span><span class='cat-count'>$count script$plural</span></summary><div class='grid'>"
        foreach ($s in ($cat.Group | Sort-Object Name)) {
            $html += Script-Card $s 'SQL' 'badge-sql'
        }
        $html += '</div></details>'
    }

    # ── Workflows & Tools — same collapsible pattern, grouped by subcategory ──
    if ($workflowScripts.Count -gt 0) {
        $html += "<hr class='section-sep' style='margin-top:32px'><h2 style='margin-top:28px'>Workflows &amp; Tools ($($workflowScripts.Count))</h2>"
        $wfIdx = 0
        foreach ($cat in ($workflowScripts | Group-Object Category | Sort-Object { Get-CategoryRank $_.Name $script:PsCategoryOrder }, Name)) {
            $count   = $cat.Group.Count
            $catName = Html-Escape $cat.Name
            $plural  = if ($count -ne 1) { 's' } else { '' }
            $open    = if ($wfIdx -lt 2) { ' open' } else { '' }
            $wfIdx++
            $html += "<details class='cat-group'$open><summary><span>$catName</span><span class='cat-count'>$count script$plural</span></summary><div class='grid'>"
            foreach ($s in ($cat.Group | Sort-Object Name)) {
                $html += Script-Card $s 'PS1' 'badge-ps'
            }
            $html += '</div></details>'
        }
    }

    Wrap-Page 'Home' $html '' 'scripts'
}

function Build-ViewPage([string]$relPath) {
    $fullPath = Join-Path $repoRoot $relPath
    if (-not (Test-Path $fullPath)) {
        return Wrap-Page 'Not found' "<p class='empty'>File not found: $(Html-Escape $relPath)</p>"
    }
    $content   = Get-Content $fullPath -Raw -Encoding UTF8
    $name      = [IO.Path]::GetFileNameWithoutExtension($relPath)
    $category  = if ($relPath -match '^sql[\\/]([^\\/]+)[\\/]([^\\/]+)[\\/]') { "$($Matches[1])/$($Matches[2])" }
               elseif ($relPath -match '^sql[\\/]([^\\/]+)[\\/]') { $Matches[1] }
               else { Split-Path (Split-Path $relPath -Parent) -Leaf }
    $purpose   = Get-ScriptPurpose $fullPath
    $ext       = [IO.Path]::GetExtension($relPath).ToLower()
    $metaParts = @($category, $ext.TrimStart('.').ToUpper())
    if ($purpose) { $metaParts = @($purpose) + $metaParts }

    # Safety classification
    $safety    = Get-ScriptSafety $fullPath
    $isWrites  = $safety -match 'Writ'
    $safeCls   = Resolve-SafetyClass $safety
    $safeLabel = Resolve-SafetyLabel $safety
    $safeBadgeHtml = "<span class='safe-badge $safeCls'>$safeLabel</span>"

    # Determine if this script can be run through the web UI.
    # Manual-only: lab scripts that contain a GOTO safety gate or an explicit LAB:ManualOnly tag.
    # These require multiple SSMS windows or deliberate human review before execution.
    $isLab        = $relPath -match '(^|[\\/])sql[\\/]lab[\\/]'
    $isManualOnly = $isLab -and (
        ($content -match 'GOTO\s+CannotRunAsFullScript') -or
        ($content -match '--\s*LAB\s*:\s*ManualOnly')
    )
    $isRunnable = $false
    if ($ext -eq '.sql' -and $relPath -match '^sql[\\/]' -and -not $isManualOnly) {
        $isRunnable = $true
    } elseif ($ext -eq '.ps1' -and $relPath -match '^powershell[\\/]wrappers[\\/]') {
        $isRunnable = ($content -match 'OutputFormat') -and ($content -match 'OutputPath')
    }

    $relEnc      = [Uri]::EscapeDataString($relPath)
    $defaultSrv  = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint     = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $dryRunToggle = if ($isWrites -and $isRunnable) { "<div class='dryrun-wrap'><input type='checkbox' id='dryrun' checked><label for='dryrun'>Dry Run</label></div>" } else { '' }
    $labBanner   = if ($isManualOnly) { "<div class='dryrun-banner'>&#9888;&nbsp; <strong>Run this script manually in SSMS</strong> — it is a multi-step lab demo that requires two open query windows and cannot be automated from the web UI. Copy the code and follow the instructions in the script header.</div>" } else { '' }
    $scopeBanner = if (($content -match '--\s*SCOPE\s*:\s*CurrentDatabase') -and $isRunnable) { "<div class='info-banner'>&#9432;&nbsp; This script runs against the <strong>currently connected database</strong>. From the web UI that is <strong>master</strong>, which will return empty or limited results. For meaningful output, copy the script and run it in SSMS against the target user database.</div>" } else { '' }

    $runControls = ''
    if ($isRunnable) {
        $runControls = @"
  <div class='run-bar'>
    <label>Server:</label>
    <input id='srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off'>
    $dryRunToggle
    <button id='run-btn' class='run-btn' onclick='runScript("$relEnc")'>Run &#9654;</button>
  </div>
"@
    }

    $overlayHtml = if ($isRunnable) { @"
<div id='run-overlay' class='run-overlay'>
  <div class='run-spinner'></div>
  <div class='run-spinner-label' id='run-label'>Running $name…</div>
</div>
"@ } else { '' }

    $isWritesJs = if ($isWrites) { 'true' } else { 'false' }
    $runJs = if ($isRunnable) { @"
<script>
async function runScript(path) {
  const srv = document.getElementById('srv').value.trim() || '.';
  const btn = document.getElementById('run-btn');
  const err = document.getElementById('run-err');
  const isWrites = $isWritesJs;
  const dryrunEl = document.getElementById('dryrun');
  const dryrun = isWrites && dryrunEl && dryrunEl.checked ? '1' : '0';
  document.getElementById('run-overlay').style.display = 'flex';
  btn.disabled = true;
  err.style.display = 'none';
  try {
    const r = await fetch('/api/run?p=' + path + '&server=' + encodeURIComponent(srv) + '&dryrun=' + dryrun);
    const d = await r.json();
    if (d.ok) { window.location.href = d.url; return; }
    err.textContent = d.error || 'Unknown error';
    err.style.display = '';
  } catch(e) {
    err.textContent = 'Request failed: ' + e.message;
    err.style.display = '';
  }
  document.getElementById('run-overlay').style.display = 'none';
  btn.disabled = false;
}
</script>
"@ } else { '' }

    $errDiv = if ($isRunnable) { "<div id='run-err' class='run-error' style='display:none'></div>" } else { '' }

    $body = @"
<div class='back'><a href='/'>&#8592; all scripts</a></div>
<div class='view-toolbar'>
  <div class='view-toolbar-left'>
    <div class='script-title'>$(Html-Escape $name)</div>
    <div class='script-meta'>$(Html-Escape ($metaParts -join ' · ')) $safeBadgeHtml</div>
  </div>
  $runControls
</div>
$errDiv
$labBanner
$scopeBanner
<div class='code-wrap'>
  <button id='copy-btn' class='copy-btn' onclick='copyCode()'>Copy</button>
  <pre id='code-block'>$(Html-Escape $content)</pre>
</div>
<script>
async function copyCode() {
  const btn = document.getElementById('copy-btn');
  try {
    await navigator.clipboard.writeText(document.getElementById('code-block').textContent);
    btn.textContent = 'Copied!'; btn.classList.add('copied');
    setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 2000);
  } catch(e) {
    btn.textContent = 'Failed'; setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
  }
}
</script>
$overlayHtml
$runJs
"@
    Wrap-Page $name $body '' 'scripts'
}

function Build-SearchPage([string]$q) {
    $scripts = Get-AllScriptsCached
    $results = @($scripts | Where-Object {
        $_.Name -like "*$q*" -or $_.Category -like "*$q*" -or
        $_.Purpose -like "*$q*"
    })

    if (-not $results) {
        return Wrap-Page "Search: $q" "<h2>Search: $(Html-Escape $q)</h2><p class='empty'>No scripts matched.</p>" $q 'scripts'
    }

    $html = "<h2>Search: $(Html-Escape $q) ($($results.Count) results)</h2><div class='grid'>"
    foreach ($s in ($results | Sort-Object Name)) {
        $purpose     = $s.Purpose
        $purposeHtml = if ($purpose) { "<div class='purpose'>$(Html-Escape $purpose)</div>" } else { '' }
        $relEnc      = [Uri]::EscapeDataString($s.RelPath)
        $badgeClass  = if ($s.Type -eq 'SQL') { 'badge-sql' } else { 'badge-ps' }
        $safety      = $s.Safety
        $sBadge      = "<span class='safe-badge $(Resolve-SafetyClass $safety)'>$(Resolve-SafetyLabel $safety)</span>"
        $html += "<div class='card'><span class='badge $badgeClass'>$($s.Type)</span>$sBadge<a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
    }
    $html += '</div>'
    Wrap-Page "Search: $q" $html $q 'scripts'
}

function Build-TriagePage {
    $groups = @(
        [ordered]@{ Title='Right Now'; When='First stop during any active incident — see what is running, waiting, or blocked this moment'; Scripts=@(
            [ordered]@{P='sql\performance\active-sessions\Get-ActiveRequests.sql';                T='SQL'}
            [ordered]@{P='sql\performance\active-sessions\Get-ActiveRequestsWithPlan.sql';        T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-OpenTransactions.sql';              T='SQL'}
            [ordered]@{P='sql\performance\active-sessions\Get-WorkerThreadsAndActiveSessions.sql';T='SQL'}
            [ordered]@{P='sql\performance\Get-BackupRestoreProgress.sql';         T='SQL'}
            [ordered]@{P='sql\monitoring\tempdb\Get-TempdbHotspots.sql';                 T='SQL'}
        )}
        [ordered]@{ Title='Blocking & Locks'; When='Users timing out, SSMS hanging, head blocker suspected, long-running transactions'; Scripts=@(
            [ordered]@{P='sql\performance\blocking-locking\Get-BlockingChains.sql';        T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-BlockingChainsWithPlan.sql';T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-BlockingSessions.sql';      T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-BlockingSummary.sql';       T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-DeadlockSummary.sql';       T='SQL'}
            [ordered]@{P='sql\performance\blocking-locking\Get-ContentionAnalysis.sql';    T='SQL'}
        )}
        [ordered]@{ Title='Slow Queries & High CPU'; When='CPU high, specific queries regressed, plan cache pollution, IO pressure, parameter sniffing suspected, slow stored procedures'; Scripts=@(
            [ordered]@{P='sql\performance\queries\Get-TopCpuQueries.sql';              T='SQL'}
            [ordered]@{P='sql\performance\queries\Get-TopIoQueries.sql';               T='SQL'}
            [ordered]@{P='sql\performance\active-sessions\Get-LongRunningQueries.sql';         T='SQL'}
            [ordered]@{P='sql\performance\queries\Get-QueryVariance.sql';              T='SQL'}
            [ordered]@{P='sql\performance\queries\Get-StoredProcedurePerformance.sql'; T='SQL'}
            [ordered]@{P='sql\performance\queries\Get-SlowQueriesFromCache.sql';       T='SQL'}
            [ordered]@{P='sql\performance\Get-DatabaseIoUsage.sql';            T='SQL'}
            [ordered]@{P='sql\performance\query-store\Get-QueryStoreTopQueries.sql';       T='SQL'}
        )}
        [ordered]@{ Title='Wait Statistics'; When='Unexplained slowness — identify the bottleneck category before digging deeper into queries'; Scripts=@(
            [ordered]@{P='sql\performance\Get-WaitStatistics.sql'; T='SQL'}
        )}
        [ordered]@{ Title='Index & Statistics Health'; When='Queries slowing over time, fragmentation suspected, missing index warnings, heap tables'; Scripts=@(
            [ordered]@{P='sql\performance\indexes\Get-IndexFragmentation.sql';           T='SQL'}
            [ordered]@{P='sql\performance\indexes\Get-IndexUsageStats.sql';             T='SQL'}
            [ordered]@{P='sql\performance\indexes\Get-MissingIndexes.sql';              T='SQL'; Fix=$true}
            [ordered]@{P='sql\performance\indexes\Get-UnusedIndexes.sql';               T='SQL'}
            [ordered]@{P='sql\performance\indexes\Get-Heaps.sql';                       T='SQL'}
            [ordered]@{P='sql\performance\queries\Get-StatisticsHealth.sql';            T='SQL'; Fix=$true}
            [ordered]@{P='sql\maintenance\Generate-IndexMaintenanceScript.sql'; T='SQL'; Fix=$true}
        )}
        [ordered]@{ Title='Disk & Space'; When='Disk alerts, databases growing unexpectedly, transaction log filling up, autogrowth events, filegroup pressure, forgotten snapshots'; Scripts=@(
            [ordered]@{P='sql\monitoring\disk-space\Get-DiskSpace.sql';                  T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-DatabaseFreeSpaceSummary.sql';   T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-FilegroupSpace.sql';             T='SQL'}
            [ordered]@{P='sql\inventory\Get-DatabaseSnapshotInventory.sql';  T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-DatabaseSizesAndFreeSpace.sql';  T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-TransactionLogSizeAndUsage.sql'; T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-VlfCount.sql';                   T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-AutogrowthHistory.sql';          T='SQL'}
            [ordered]@{P='sql\monitoring\disk-space\Get-DatabaseGrowthRisk.sql';         T='SQL'}
        )}
        [ordered]@{ Title='Backups'; When='Verifying coverage, investigating a missed backup, planning or scripting a restore, validating DR restore tests, sizing backup storage'; Scripts=@(
            [ordered]@{P='sql\backups\Get-BackupCoverage.sql';          T='SQL'}
            [ordered]@{P='sql\backups\Get-LastDatabaseBackupTimes.sql'; T='SQL'}
            [ordered]@{P='sql\backups\Get-LastRestoreHistory.sql';      T='SQL'}
            [ordered]@{P='sql\backups\Get-BackupSizeTrend.sql';         T='SQL'}
            [ordered]@{P='sql\backups\Get-DatabaseBackupHistory.sql';   T='SQL'}
            [ordered]@{P='sql\backups\Generate-FullBackupScript.sql';   T='SQL'; Fix=$true}
            [ordered]@{P='sql\backups\Generate-RestoreScript.sql';      T='SQL'; Fix=$true}
        )}
        [ordered]@{ Title='Jobs & Errors'; When='Agent job failures, unexpected error log entries, maintenance jobs not running on schedule, silent duration creep, error pattern analysis'; Scripts=@(
            [ordered]@{P='sql\monitoring\error-log\Get-ErrorLogPatterns.sql';          T='SQL'}
            [ordered]@{P='sql\monitoring\jobs\Get-SqlAgentJobFailureSummary.sql'; T='SQL'}
            [ordered]@{P='sql\monitoring\jobs\Get-JobDurationTrends.sql';         T='SQL'}
            [ordered]@{P='sql\monitoring\error-log\Get-RecentErrorLogEntries.sql';     T='SQL'}
            [ordered]@{P='sql\monitoring\jobs\Get-SqlAgentJobOverview.sql';       T='SQL'}
            [ordered]@{P='sql\monitoring\error-log\Get-SchemaChangeHistory.sql';       T='SQL'}
        )}
        [ordered]@{ Title='Security'; When='Permissions audit, sysadmin membership review, orphaned users, weak password policy, expiring certificates, login activity review'; Scripts=@(
            [ordered]@{P='sql\security\access\Get-SysadminMembers.sql';            T='SQL'}
            [ordered]@{P='sql\security\access\Get-LoginLastActivity.sql';         T='SQL'}
            [ordered]@{P='sql\security\access\Get-WeakLoginSettings.sql';          T='SQL'}
            [ordered]@{P='sql\security\access\Get-UserPermissionsAudit.sql';       T='SQL'}
            [ordered]@{P='sql\security\access\Get-OrphanedUsers.sql';              T='SQL'}
            [ordered]@{P='sql\security\encryption\Get-CertificateExpiryWarnings.sql';  T='SQL'}
        )}
        [ordered]@{ Title='Instance Configuration'; When='New server review, performance baseline, best practice settings check, integrity, TempDB configuration, linked servers'; Scripts=@(
            [ordered]@{P='sql\inventory\Get-Databases.sql';                   T='SQL'}
            [ordered]@{P='sql\monitoring\instance\Get-InstanceConfigurationScore.sql';  T='SQL'}
            [ordered]@{P='sql\monitoring\tempdb\Get-TempDbFileBalance.sql';           T='SQL'}
            [ordered]@{P='sql\monitoring\features\Get-CollationConflicts.sql';          T='SQL'}
            [ordered]@{P='sql\monitoring\Get-LinkedServerConnectivity.sql';    T='SQL'}
            [ordered]@{P='sql\monitoring\instance\Get-MaxdopConfiguration.sql';         T='SQL'}
            [ordered]@{P='sql\monitoring\instance\Get-MemoryConfigurationAndUsage.sql'; T='SQL'}
            [ordered]@{P='sql\monitoring\databases\Get-LastDbccCheckdb.sql';             T='SQL'}
            [ordered]@{P='sql\monitoring\databases\Get-SuspectPages.sql';                T='SQL'}
            [ordered]@{P='sql\monitoring\databases\Get-DatabaseHealth.sql';              T='SQL'}
        )}
        [ordered]@{ Title='Decommission & Traces'; When='Retiring a server or database, profiling what stored procedures are being called, auditing who connects and from where — run Get-ActiveConnectionsByDatabase first'; Scripts=@(
            [ordered]@{P='sql\monitoring\Get-ActiveConnectionsByDatabase.sql';  T='SQL'}
            [ordered]@{P='sql\monitoring\features\Get-CrossDatabaseDependencies.sql';    T='SQL'}
            [ordered]@{P='sql\traces\Get-ActiveXeSessions.sql';              T='SQL'}
            [ordered]@{P='sql\traces\Create-DecommissionAuditSession.sql';   T='SQL'}
            [ordered]@{P='sql\traces\Create-LoginActivitySession.sql';       T='SQL'}
            [ordered]@{P='sql\traces\Create-SpExecutionSession.sql';         T='SQL'}
            [ordered]@{P='sql\traces\Get-XeSessionActivity.sql';             T='SQL'}
            [ordered]@{P='sql\traces\Remove-XeSession.sql';                  T='SQL'}
        )}
    )

    # ── Stage 5: live incident cockpit — run scripts here, results render inline ──
    $defaultSrv = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $html  = "<div class='data-strip'><div><b>Incident cockpit</b> <span class='ds-dim'>— Run &#9654; executes against the target and shows results right here. Read-only Get-* scripts only; generators open as source to review first.</span></div>"
    $html += "<div class='ds-spacer'></div><label class='ds-dim'>Target:</label> <input id='tri-srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off'></div>"
    $html += "<h2>What are you investigating?</h2><div class='triage-grid'>"
    $rid = 0
    foreach ($g in $groups) {
        $html += "<div class='triage-card'><div class='triage-title'>$(Html-Escape $g.Title)</div><div class='triage-when'>$(Html-Escape $g.When)</div><div class='triage-links'>"
        foreach ($s in $g.Scripts) {
            $fp = Join-Path $repoRoot $s.P
            if (-not (Test-Path -LiteralPath $fp)) { continue }
            $name   = [IO.Path]::GetFileNameWithoutExtension($s.P)
            $enc    = [Uri]::EscapeDataString($s.P)
            $bdgCls = if ($s.T -eq 'SQL') { 'badge-sql' } else { 'badge-ps' }
            $fixTag = if ($s.Fix) { "<span class='triage-fix-tag'>generates fix</span>" } else { '' }
            $runnable = $name -like 'Get-*'
            $rid++
            $html += "<div class='tri-row'><a href='/view?p=$enc' class='triage-link'><span class='badge $bdgCls'>$($s.T)</span>$(Html-Escape $name)$fixTag</a>"
            if ($runnable) { $html += "<button class='run-btn tri-run' onclick=`"runTriage(this,'$enc','tri-res-$rid')`">Run &#9654;</button>" }
            $html += "</div>"
            if ($runnable) { $html += "<div class='tri-result' id='tri-res-$rid'></div>" }
        }
        $html += "</div></div>"
    }
    $html += "</div>"
    $html += @"
<script>
function triEsc(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
async function runTriage(btn,p,rid){
  const srv=document.getElementById('tri-srv').value.trim()||'.';
  const res=document.getElementById(rid);
  const old=btn.textContent;btn.disabled=true;btn.textContent='running…';
  res.style.display='block';res.innerHTML="<span style='color:#8b949e'>Running against "+triEsc(srv)+"…</span>";
  try{
    const r=await fetch('/api/run?p='+p+'&server='+encodeURIComponent(srv)+'&dryrun=0');
    const d=await r.json();
    if(!d.ok){res.innerHTML="<span style='color:#f78166'>"+triEsc(d.error||'run failed')+"</span>";}
    else{
      const cp=new URL(d.url,location.origin).searchParams.get('p');
      const cr=await fetch('/api/csv?p='+encodeURIComponent(cp));
      const cd=await cr.json();
      renderTriResult(res,cd,d.url);
    }
  }catch(e){res.innerHTML="<span style='color:#f78166'>"+triEsc(e.message)+"</span>";}
  btn.disabled=false;btn.textContent=old;
}
function renderTriResult(el,d,fullUrl){
  if(!d.rows||!d.rows.length){el.innerHTML="<span style='color:#3fb950'>No rows returned — clean.</span> <a href='"+fullUrl+"' style='margin-left:8px'>open CSV view</a>";return;}
  const cols=d.headers.slice(0,8);
  let h="<div style='margin-bottom:6px;color:#8b949e;font-size:.74rem'>"+d.rows.length+" rows — showing first "+Math.min(20,d.rows.length);
  h+=(d.headers.length>8?" ("+(d.headers.length-8)+" more columns in full view)":"");
  h+=" <a href='"+fullUrl+"' style='margin-left:8px'>open full CSV view</a></div><table><thead><tr>";
  cols.forEach(function(c){h+="<th>"+triEsc(c)+"</th>";});h+="</tr></thead><tbody>";
  d.rows.slice(0,20).forEach(function(r){h+="<tr>";cols.forEach(function(c){var v=r[c];h+="<td>"+triEsc(v==null?'':v)+"</td>";});h+="</tr>";});
  h+="</tbody></table>";el.innerHTML=h;
}
</script>
"@
    Wrap-Page 'Triage' $html '' 'triage'
}


function Build-CsvListPage {
    $csvs = @(Get-ChildItem "$repoRoot\output-files" -Recurse -Filter '*.csv' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.tmp.csv' } |
        Sort-Object LastWriteTime -Descending)

    $clearBtn = "<button class='clear-btn' id='clear-btn' onclick='clearOutput()'>Clear All Output</button>
<script>
async function clearOutput(){
  if(!confirm('Delete all files in output-files/?\\n\\nThis removes all CSVs, logs, and generated scripts. AI assessment reports (assessments/) are kept. Cannot be undone.'))return;
  const btn=document.getElementById('clear-btn');
  btn.disabled=true;btn.textContent='Clearing…';
  try{
    const r=await fetch('/api/clear-output',{method:'POST'});
    const d=await r.json();
    if(d.ok){btn.textContent=d.deleted+' file(s) deleted';setTimeout(()=>location.reload(),800);}
    else{alert('Error: '+(d.error||'Unknown error'));btn.disabled=false;btn.textContent='Clear All Output';}
  }catch(e){alert('Request failed: '+e.message);btn.disabled=false;btn.textContent='Clear All Output';}
}
</script>"

    if (-not $csvs) {
        $body = "<div style='display:flex;align-items:center;justify-content:space-between;margin-bottom:4px'><h2 style='margin:0;border:none;padding:0'>Output CSVs</h2>$clearBtn</div><p class='empty'>No CSV files in output-files/ yet. Run a script first.</p>"
        return Wrap-Page 'Output CSVs' $body '' 'csvs'
    }

    $grouped = $csvs | Group-Object { $_.Directory.FullName.Replace($repoRoot,'').TrimStart('\') }
    $html    = "<div style='display:flex;align-items:center;justify-content:space-between;margin-bottom:4px'><h2 style='margin:0;border:none;padding:0'>Output CSVs ($($csvs.Count) files)</h2>$clearBtn</div>"

    # freshest output first — the folder you just wrote to is the one you came to look at
    foreach ($g in ($grouped | Sort-Object { ($_.Group | Measure-Object LastWriteTime -Maximum).Maximum } -Descending)) {
        $html += "<div class='cat-label'>$(Html-Escape $g.Name)</div><div class='grid'>"
        foreach ($f in $g.Group) {
            $rel    = $f.FullName.Replace($repoRoot,'').TrimStart('\')
            $relEnc = [Uri]::EscapeDataString($rel)
            $size   = if ($f.Length -gt 1024) { "$([Math]::Round($f.Length/1024,1)) KB" } else { "$($f.Length) B" }
            $age    = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            $html  += "<div class='card'><a href='/csv?p=$relEnc'>$(Html-Escape $f.BaseName)</a><div class='purpose'>$age · $size</div></div>"
        }
        $html += '</div>'
    }
    Wrap-Page 'Output CSVs' $html '' 'csvs'
}

function Build-CsvViewPage([string]$relPath) {
    $fullPath = Join-Path $repoRoot $relPath
    if (-not (Test-Path $fullPath)) {
        return Wrap-Page 'Not found' "<p class='empty'>File not found.</p>" '' 'csvs'
    }

    $name   = [IO.Path]::GetFileNameWithoutExtension($relPath)
    $relEnc = [Uri]::EscapeDataString($relPath)

    # ── find the source script by stripping the timestamp suffix ──────────────
    $scriptBase   = $name -replace '-\d{8}-\d{6}$', ''
    $sqlMatch     = Get-ChildItem "$repoRoot\sql" -Recurse -Filter "$scriptBase.sql" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $sqlMatch) {
        $sqlMatch = Get-ChildItem "$repoRoot\sql\migration" -Filter "$scriptBase.sql" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $ps1Match     = Get-ChildItem "$repoRoot\powershell" -Recurse -Filter "$scriptBase.ps1" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $ps1Match) {
        $ps1Match = Get-ChildItem "$repoRoot\powershell\migration" -Filter "$scriptBase.ps1" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    $srcFile      = if ($sqlMatch) { $sqlMatch } elseif ($ps1Match) { $ps1Match } else { $null }
    $srcScriptRel = if ($srcFile) { $srcFile.FullName.Replace($repoRoot.ToString(), '').TrimStart('\') } else { '' }
    $srcScriptEnc = if ($srcScriptRel) { [Uri]::EscapeDataString($srcScriptRel) } else { '' }

    $defaultSrv = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }

    $rerunBar = if ($srcScriptRel) { @"
  <div class='run-bar'>
    <label>Server:</label>
    <input id='srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off'>
    <button id='run-btn' class='run-btn' onclick='rerunScript("$srcScriptEnc")'>Rerun &#9654;</button>
    <a href='/view?p=$srcScriptEnc' style='font-size:.78rem;color:#58a6ff;white-space:nowrap'>view script</a>
  </div>
"@ } else { '' }

    $rerunOverlay = if ($srcScriptRel) { @"
<div id='run-overlay' class='run-overlay'>
  <div class='run-spinner'></div>
  <div class='run-spinner-label'>Running $(Html-Escape $scriptBase)…</div>
</div>
"@ } else { '' }

    $rerunJs = if ($srcScriptRel) { @"
<script>
async function rerunScript(path) {
  const srv = document.getElementById('srv').value.trim() || '.';
  const btn = document.getElementById('run-btn');
  const err = document.getElementById('run-err');
  document.getElementById('run-overlay').style.display = 'flex';
  btn.disabled = true; err.style.display = 'none';
  try {
    const r = await fetch('/api/run?p=' + path + '&server=' + encodeURIComponent(srv));
    const d = await r.json();
    if (d.ok) { window.location.href = d.url; return; }
    err.textContent = d.error || 'Unknown error'; err.style.display = '';
  } catch(e) { err.textContent = 'Request failed: ' + e.message; err.style.display = ''; }
  document.getElementById('run-overlay').style.display = 'none';
  btn.disabled = false;
}
</script>
"@ } else { '' }

    $errDiv    = if ($srcScriptRel) { "<div id='run-err' class='run-error' style='display:none;margin-bottom:8px'></div>" } else { '' }
    $isDryRun  = $relPath -replace '\\','/' -like '*/dry-runs/*'
    $dryBanner = if ($isDryRun) { "<div class='dryrun-banner'>&#9888; Dry run result — this output was produced inside a transaction that was rolled back. No changes were committed to the database.</div>" } else { '' }

    $body = @"
<div class='back'><a href='/csvs'>← output CSVs</a></div>
<div class='view-toolbar'>
  <div class='view-toolbar-left'>
    <div class='script-title'>$(Html-Escape $name)</div>
  </div>
  $rerunBar
</div>
$dryBanner
$errDiv
<div class='mode-badge' id='mode-badge'>Loading…</div>

<!-- Chart panel — only shown when data has 2+ numeric columns -->
<div id='chart-panel' style='display:none'>
  <div class='chart-controls'>
    <div class='col-checkboxes' id='col-boxes'></div>
    <div class='type-btns'>
      <button onclick='setType("bar")'      id='btn-bar'      class='active'>Bar</button>
      <button onclick='setType("line")'     id='btn-line'>Line</button>
      <button onclick='setType("pie")'      id='btn-pie'>Pie</button>
      <button onclick='setType("doughnut")' id='btn-doughnut'>Doughnut</button>
      <button onclick='savePng()' class='save-png-btn' id='btn-save-png'>Save PNG</button>
      <span class='save-confirm' id='save-confirm'>Saved ✓</span>
    </div>
  </div>
  <div class='chart-wrap'><canvas id='chart'></canvas></div>
</div>

<!-- Table always shown — sortable, filterable, colour-coded -->
<div class='table-toolbar'>
  <input class='table-filter' id='tbl-filter' placeholder='Filter rows…' oninput='applyFilter(this.value)' autocomplete='off'>
  <span class='row-count' id='row-count'></span>
</div>
<div class='table-wrap'><table id='tbl'></table></div>

<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'></script>
<script>
const SCRIPT_NAME='$scriptBase';
const CHART_HINTS={
  // Horizontal bar — ranked performance lists (label on Y axis, value on X)
  'Get-WaitStatistics':              {type:'bar',h:true,  prefer:['pct_total_wait','wait_time_ms','avg_wait_ms']},
  'Get-IndexFragmentation':          {type:'bar',h:true,  prefer:['fragmentation_pct','page_count']},
  'Get-IndexFragmentationAcrossDatabases':{type:'bar',h:true,prefer:['avg_fragmentation_percent','page_count']},
  'Get-MissingIndexes':              {type:'bar',h:true,  prefer:['impact_score','user_seeks','avg_improvement_pct']},
  'Get-TopCpuQueries':               {type:'bar',h:true,  prefer:['total_worker_time_ms','avg_worker_time_ms','execution_count']},
  'Get-TopIoQueries':                {type:'bar',h:true,  prefer:['total_logical_reads','avg_logical_reads']},
  'Get-SlowQueriesFromCache':        {type:'bar',h:true,  prefer:['avg_elapsed_ms','total_elapsed_ms','execution_count']},
  'Get-BlockingSummary':             {type:'bar',h:true,  prefer:['blocked_session_count','max_wait_sec','total_wait_sec']},
  'Get-LongRunningQueries':          {type:'bar',h:true,  prefer:['elapsed_sec','cpu_time','logical_reads']},
  // Vertical bar — per-database comparisons
  'Get-DatabaseSizesAndFreeSpace':   {type:'bar',h:false, prefer:['data_size_mb','log_size_mb','free_space_mb']},
  'Get-DatabaseFreeSpaceSummary':    {type:'bar',h:true,  prefer:['TotalAllocMB','TotalUsedMB','TotalFreeMB']},
  'Get-DatabaseIoUsage':             {type:'bar',h:false, prefer:['reads_mb','writes_mb','read_latency_ms','write_latency_ms']},
  'Get-TransactionLogSizeAndUsage':  {type:'bar',h:false, prefer:['log_size_mb','log_used_mb']},
  'Get-BackupCoverage':              {type:'bar',h:false, prefer:['full_backup_age_hours','diff_backup_age_hours']},
  'Get-LastDatabaseBackupTimes':     {type:'bar',h:false, prefer:['full_backup_age_hours','log_backup_age_hours']},
  // Doughnut — proportional / used vs free
  'Get-DiskSpace':                   {type:'doughnut',    prefer:['used_gb','free_gb']},
  'Get-TempdbUsage':                 {type:'doughnut',    prefer:['used_mb','free_mb']},
  'Get-MemoryConfigurationAndUsage': {type:'doughnut',    prefer:['sql_memory_mb','available_mb']},
  // Monitoring additions
  'Get-JobDurationTrends':           {type:'bar',h:true,  prefer:['last_run_sec','avg_sec_30d','max_sec_30d']},
  'Get-TempDbFileBalance':           {type:'bar',h:false, prefer:['size_mb']},
  'Get-FilegroupSpace':              {type:'bar',h:true,  prefer:['used_mb','free_mb']},
  'Get-CertificateExpiryWarnings':   {type:'bar',h:true,  prefer:['days_until_expiry']},
  'Get-CollationConflicts':          {type:'bar',h:false, prefer:['database_id']},
  'Get-DatabaseSnapshotInventory':   {type:'bar',h:true,  prefer:['allocated_mb','age_days']},
  'Get-LinkedServerConnectivity':    {type:'bar',h:true,  prefer:[]},
  'Get-CompressionCandidates':       {type:'bar',h:true,  prefer:['reserved_mb','row_count']},
  // Traces
  'Get-XeSessionActivity':           {type:'bar',h:true,  prefer:['occurrences']},
  'Get-ActiveXeSessions':            {type:'bar',h:false, prefer:['running_hours','buffer_size_mb']},
  // Batch 3
  'Get-LastRestoreHistory':          {type:'bar',h:true,  prefer:['days_since_restore','backup_age_at_restore_days']},
  'Get-ActiveConnectionsByDatabase': {type:'bar',h:true,  prefer:['total_sessions','active_requests','open_transactions']},
  'Get-QueryVariance':               {type:'bar',h:true,  prefer:['max_to_min_ratio','variance_ms','max_ms']},
  'Get-BackupSizeTrend':             {type:'bar',h:false, prefer:['avg_size_gb','avg_compressed_gb']},
  // Batch 4
  'Get-ErrorLogPatterns':            {type:'doughnut',    prefer:['occurrences']},
  'Get-SchemaChangeHistory':         {type:'bar',h:false, prefer:[]},
  'Get-LoginLastActivity':           {type:'bar',h:true,  prefer:['active_sessions']},
  'Get-OpenTransactions':            {type:'bar',h:true,  prefer:['tran_age_sec','log_used_mb']},
  'Get-StoredProcedurePerformance':  {type:'bar',h:true,  prefer:['total_elapsed_ms','avg_ms','execution_count']},
  'Get-CrossDatabaseDependencies':   {type:'bar',h:false, prefer:[]},
};

const COLORS=['#58a6ff','#3fb950','#f78166','#d2a8ff','#ffa657','#79c0ff','#56d364','#ff7b72',
              '#e3b341','#a5d6ff','#7ee787','#ffa8a8'];
const SV={
  online:'green',running:'green',complete:'green',completed:'green',success:'green',succeeded:'green',
  yes:'green',pass:'green',enabled:'green',ok:'green',healthy:'green',available:'green',
  offline:'red',failed:'red',fail:'red',error:'red',suspect:'red',no:'red',
  missing:'red',critical:'red',high:'red',unavailable:'red',
  // backup_status values from Get-BackupCoverage
  'no_full_backup':'red','stale_full':'orange','full_recovery_no_log':'red','stale_log':'orange',
  // growth_status values from Get-DatabaseGrowthRisk
  'at_limit':'red','near_limit':'orange','unlimited':'gray',
  restoring:'orange',warning:'orange',warn:'orange',medium:'orange',pending:'orange',recovering:'orange',
  low:'blue',info:'blue',
  disabled:'gray','n/a':'gray',none:'gray',
  'read-only':'blue',writes:'blue',
  // certificate expiry status (Get-CertificateExpiryWarnings)
  expired:'red',
  // job trend status (Get-JobDurationTrends)
  spike:'red',growing:'orange',
  // collation & TempDB balance flags
  mismatch:'red',imbalanced:'red','too_few':'orange',excess:'orange','pct_growth':'orange',
  // linked server connectivity
  reachable:'green',unreachable:'red',untested:'gray',
  // XE session status
  running:'green',dropped:'gray',
};

let chart=null,data=null,type='bar',pieCol='',horizontal=false;
const active=new Set();
let sortCol=null,sortDir=1,visRows=[];

const isPie=()=>type==='pie'||type==='doughnut';

async function init(){
  data=await fetch('/api/csv?p=$relEnc').then(r=>r.json());

  if(data.isDdl){
    document.querySelector('.table-toolbar').style.display='none';
    if(!data.ddlText||!data.ddlText.trim()){
      document.getElementById('mode-badge').textContent='No results returned.';
      document.getElementById('tbl').closest('.table-wrap').style.display='none';
    } else {
      document.getElementById('mode-badge').textContent='Script / DDL output';
      document.getElementById('tbl').closest('.table-wrap').outerHTML=
        "<div class='code-wrap'><button id='ddl-copy' class='copy-btn' onclick='copyDdl()'>Copy</button><pre id='ddl-block' style='max-height:72vh;overflow:auto'>"+esc(data.ddlText)+"</pre></div>";
    }
    return;
  }

  if(!data.rows||!data.rows.length){
    document.getElementById('mode-badge').innerHTML=
      '<div class="empty-state"><div class="empty-state-title">No results returned</div>' +
      '<div class="empty-state-sub">The query ran successfully but matched zero rows on this server.<br>' +
      'If this script is database-scoped, run it in SSMS against the target database for meaningful results.</div></div>';
    document.querySelector('.table-toolbar').style.display='none';
    document.getElementById('tbl').closest('.table-wrap').style.display='none';
    return;
  }
  visRows=[...data.rows];
  const chartable=data.numericCols.length>=2;
  document.getElementById('mode-badge').textContent=chartable
    ?data.rows.length+' rows · '+data.numericCols.length+' numeric columns · chart + table'
    :data.rows.length+' rows · '+data.headers.length+' columns · table view';
  if(chartable){
    document.getElementById('chart-panel').style.display='';
    applyHint();
    buildControls();renderChart();
  }
  renderTable();
}

function inferChartDefaults(d){
  const numCols=d.numericCols, rows=d.rows, labelCol=d.labelCol;
  // Classify columns by name pattern — drives column preference order
  const pctCols  = numCols.filter(c=>/pct|percent|ratio/i.test(c));
  const timeCols = numCols.filter(c=>/_ms$|_sec|elapsed|duration|wait/i.test(c));
  const sizeCols = numCols.filter(c=>/_mb$|_gb$|_kb$|size|space|bytes/i.test(c));
  const ageCols  = numCols.filter(c=>/age|_hours$|_days$/i.test(c));
  const preferCols=(pctCols.length?pctCols:timeCols.length?timeCols:sizeCols.length?sizeCols:ageCols.length?ageCols:numCols).slice(0,4);
  // Few rows = proportional comparison → doughnut
  if(rows.length<=3&&numCols.length>=2)
    return{type:'doughnut',horizontal:false,preferCols,pieCol:preferCols[0]||numCols[0]};
  // Long labels or many rows → horizontal bar reads better
  const avgLabelLen=rows.slice(0,10).reduce((s,r)=>s+String(r[labelCol]??'').length,0)/Math.min(rows.length,10);
  const horiz=avgLabelLen>15||rows.length>12;
  return{type:'bar',horizontal:horiz,preferCols,pieCol:preferCols[0]||numCols[0]};
}

function applyHint(){
  const named=CHART_HINTS[SCRIPT_NAME];
  const inferred=inferChartDefaults(data);
  active.clear();
  horizontal=false;
  if(named){
    type=named.type||'bar';
    horizontal=named.h||false;
    const pref=(named.prefer||[]).map(p=>data.numericCols.find(c=>c.toLowerCase()===p.toLowerCase())).filter(Boolean);
    const cols=pref.length>0?pref:data.numericCols.slice(0,4);
    cols.slice(0,4).forEach(c=>active.add(c));
    pieCol=(type==='pie'||type==='doughnut')?(cols[0]||data.numericCols[0]||''):(data.numericCols[0]||'');
  } else {
    type=inferred.type;
    horizontal=inferred.horizontal;
    inferred.preferCols.forEach(c=>active.add(c));
    pieCol=inferred.pieCol||data.numericCols[0]||'';
  }
  document.querySelectorAll('.type-btns button').forEach(b=>b.classList.remove('active'));
  const btn=document.getElementById('btn-'+type);
  if(btn)btn.classList.add('active');
}

function buildControls(){
  const wrap=document.getElementById('col-boxes');
  if(isPie()){
    const opts=data.numericCols.map(c=>'<option value="'+c+'"'+(c===pieCol?' selected':'')+'>'+c+'</option>').join('');
    wrap.innerHTML='<label style="font-size:.82rem;color:#8b949e">Column: <select class="pie-select" onchange="setPieCol(this.value)">'+opts+'</select></label>';
  } else {
    wrap.innerHTML=data.numericCols.map((col,i)=>{
      const color=COLORS[i%COLORS.length],chk=active.has(col)?'checked':'';
      return '<label style="color:'+color+'"><input type="checkbox" '+chk+' style="accent-color:'+color+'" onchange="toggle(\''+col+'\')"> '+col+'</label>';
    }).join('');
  }
}

function toggle(col){active.has(col)?active.delete(col):active.add(col);renderChart();}
function setPieCol(col){pieCol=col;renderChart();}

function setType(t){
  type=t;
  horizontal=false;
  document.querySelectorAll('.type-btns button').forEach(b=>b.classList.remove('active'));
  document.getElementById('btn-'+t).classList.add('active');
  buildControls();renderChart();
}

// ── Threshold constants — edit here to tune all visual markers ────────────
const CHART_MAX        = 15;   // chart rows before Others aggregation
const FULL_BKUP_STALE  = 25;   // full_backup_age_hours → red
const FULL_BKUP_WARN   = 12;   // full_backup_age_hours → orange
const LOG_BKUP_STALE   = 4;    // log_backup_age_hours  → red
const LOG_BKUP_WARN    = 2;    // log_backup_age_hours  → orange
const LOG_USED_CRIT    = 80;   // log_used_pct %        → red
const LOG_USED_WARN    = 60;   // log_used_pct %        → orange
const FREE_SPACE_CRIT  = 10;   // free_pct %            → red  (low free = bad)
const FREE_SPACE_WARN  = 20;   // free_pct %            → orange
const FRAG_CRIT        = 30;   // fragmentation %       → red
const FRAG_WARN        = 10;   // fragmentation %       → orange
const VLF_CRIT         = 1000; // vlf_count             → red
const VLF_WARN         = 200;  // vlf_count             → orange
const LATENCY_CRIT_MS  = 100;  // io latency ms         → red
const LATENCY_WARN_MS  = 50;   // io latency ms         → orange
const MOD_PCT_CRIT     = 20;   // modification_pct %    → red  (stale stats)
const MOD_PCT_WARN     = 10;   // modification_pct %    → orange

function getChartRows(){
  if(data.rows.length<=CHART_MAX)return{rows:data.rows,capped:false};
  // Sort by primary active metric descending so "top N" are the most significant
  const primary=isPie()?pieCol:([...active][0]||data.numericCols[0]||'');
  const sorted=primary
    ?[...data.rows].sort((a,b)=>(parseFloat(b[primary])||0)-(parseFloat(a[primary])||0))
    :data.rows;
  const top=sorted.slice(0,CHART_MAX);
  const rest=sorted.slice(CHART_MAX);
  // Aggregate remainder into a single "Others" row (sum numeric cols)
  const othersRow={};
  othersRow[data.labelCol]='Others ('+rest.length+')';
  for(const col of data.numericCols){
    othersRow[col]=rest.reduce((s,r)=>s+(parseFloat(r[col])||0),0);
  }
  return{rows:[...top,othersRow],capped:true};
}

function renderChart(){
  if(chart)chart.destroy();
  const ctx=document.getElementById('chart').getContext('2d');
  const {rows:chartRows,capped}=getChartRows();
  // Show/hide the summary note
  let note=document.getElementById('chart-cap-note');
  if(capped){
    if(!note){
      note=document.createElement('p');
      note.id='chart-cap-note';
      note.style.cssText='font-size:.75rem;color:#8b949e;margin-bottom:8px';
      document.getElementById('chart-panel').insertBefore(note,document.querySelector('.chart-wrap'));
    }
    note.textContent='Chart shows top '+CHART_MAX+' of '+data.rows.length+' rows by primary metric — table below shows all results.';
  } else if(note){ note.remove(); }
  const labels=chartRows.map(r=>String(r[data.labelCol]??''));
  if(isPie()){
    chart=new Chart(ctx,{type:type,data:{labels,datasets:[{label:pieCol,
      data:chartRows.map(r=>parseFloat(r[pieCol])||0),
      backgroundColor:chartRows.map((_,i)=>COLORS[i%COLORS.length]+'cc'),
      borderColor:chartRows.map((_,i)=>COLORS[i%COLORS.length]),borderWidth:1}]},
      options:{responsive:true,maintainAspectRatio:true,
        plugins:{legend:{position:'right',labels:{color:'#c9d1d9',boxWidth:14,padding:12}}}}});
  } else {
    const datasets=data.numericCols.filter(c=>active.has(c)).map(col=>{
      const i=data.numericCols.indexOf(col);
      return{label:col,data:chartRows.map(r=>parseFloat(r[col])||0),
        backgroundColor:COLORS[i%COLORS.length]+'bb',borderColor:COLORS[i%COLORS.length],borderWidth:1};
    });
    const opts={responsive:true,
      plugins:{legend:{labels:{color:'#c9d1d9'}}},
      scales:{x:{ticks:{color:'#8b949e',maxRotation:horizontal?0:45},grid:{color:'#21262d'}},
              y:{ticks:{color:'#8b949e'},grid:{color:'#21262d'}}}};
    if(horizontal)opts.indexAxis='y';
    chart=new Chart(ctx,{type:type==='bar'?'bar':'line',data:{labels,datasets},options:opts});
  }
}

function applyFilter(text){
  const t=text.toLowerCase();
  visRows=t?data.rows.filter(r=>Object.values(r).some(v=>String(v??'').toLowerCase().includes(t))):[...data.rows];
  if(sortCol)doSort();else renderTable();
}

function sortBy(col){
  if(sortCol===col)sortDir*=-1;else{sortCol=col;sortDir=1;}
  doSort();
}
function doSort(){
  visRows.sort((a,b)=>{
    const av=a[sortCol]??'',bv=b[sortCol]??'';
    const an=parseFloat(av),bn=parseFloat(bv);
    return(!isNaN(an)&&!isNaN(bn))?(an-bn)*sortDir:String(av).localeCompare(String(bv))*sortDir;
  });
  renderTable();
}

function renderTable(){
  const h=data.headers;
  document.getElementById('row-count').textContent=
    visRows.length===data.rows.length?visRows.length+' rows':visRows.length+' of '+data.rows.length+' rows';
  let html='<thead><tr>'+h.map(col=>{
    const cls='sortable'+(sortCol===col?(sortDir===1?' sort-asc':' sort-desc'):'');
    return '<th class="'+cls+'" onclick="sortBy(\''+col+'\')">'+col+'</th>';
  }).join('')+'</tr></thead><tbody>';
  html+=visRows.map(r=>'<tr>'+h.map(col=>'<td>'+fmtCell(r[col]??'',col)+'</td>').join('')+'</tr>').join('');
  document.getElementById('tbl').innerHTML=html+'</tbody>';
}

function fmtCell(val,col){
  const s=String(val);
  const c=(col||'').toLowerCase();
  if(s===''||s==='NULL'){
    // Columns where NULL means something critical never happened → flag red
    const critical=/backup|checkdb|last_good|restore_date|last_sync/.test(c);
    return critical
      ? '<span class="sv sv-red">NONE</span>'
      : '<span class="null-val">—</span>';
  }
  const k=s.toLowerCase().trim();
  if(SV[k])return '<span class="sv sv-'+SV[k]+'">'+esc(s)+'</span>';
  // Boolean True/False — colour direction is column-semantic, not universal
  if(k==='true'||k==='false'){
    const t=(k==='true');
    // True = problem (red when on, green when off)
    if(/auto_shrink|auto_close|is_suspended|is_damaged|growth_is_percent|is_percent_growth|is_locked|has_incomplete|is_heap/.test(c))
      return '<span class="sv sv-'+(t?'red':'green')+'">'+esc(s)+'</span>';
    // True = good (green when on, orange when off)
    if(/is_encrypted|tde_enabled|sb_enabled|is_state_enabled|ifi_enabled/.test(c))
      return '<span class="sv sv-'+(t?'green':'orange')+'">'+esc(s)+'</span>';
    // All other booleans: neutral badge — informational, no strong signal
    return '<span class="sv sv-gray">'+esc(s)+'</span>';
  }
  // Prefix-based match for multi-word status columns (autogrowth_status, sizing_status, etc.)
  if(/_status$|_risk$/.test(c)){
    if(k.startsWith('ok'))   return '<span class="sv sv-green">'+esc(s)+'</span>';
    if(k.startsWith('warn')) return '<span class="sv sv-orange">'+esc(s)+'</span>';
    if(k.startsWith('info')) return '<span class="sv sv-blue">'+esc(s)+'</span>';
    if(k.startsWith('pass')) return '<span class="sv sv-green">'+esc(s)+'</span>';
    if(k.startsWith('fail')||k.startsWith('error')) return '<span class="sv sv-red">'+esc(s)+'</span>';
  }
  if(/^-?\d+(\.\d+)?$/.test(s.trim())){
    const n=parseFloat(s);
    // Backup age thresholds — match the same thresholds used in Get-BackupCoverage.sql
    if(/full_backup_age/.test(c)){
      const cl=n>FULL_BKUP_STALE?'red':n>FULL_BKUP_WARN?'orange':'green';
      return '<span class="sv sv-'+cl+'">'+n.toFixed(0)+'h</span>';
    }
    if(/log_backup_age/.test(c)){
      const cl=n>LOG_BKUP_STALE?'red':n>LOG_BKUP_WARN?'orange':'green';
      return '<span class="sv sv-'+cl+'">'+n.toFixed(0)+'h</span>';
    }
    if(/log_used_pct|pct_used|_used_pct/.test(c)){
      const cl=n>=LOG_USED_CRIT?'red':n>=LOG_USED_WARN?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toFixed(1)+'%</span>':esc(n.toFixed(1)+'%');
    }
    if(/free_pct|data_free_pct|log_free_pct|^free %$/.test(c)){
      const cl=n<FREE_SPACE_CRIT?'red':n<FREE_SPACE_WARN?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toFixed(1)+'%</span>':esc(n.toFixed(1)+'%');
    }
    if(/fragmentation/.test(c)){
      const cl=n>=FRAG_CRIT?'red':n>=FRAG_WARN?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toFixed(1)+'%</span>':esc(n.toFixed(1)+'%');
    }
    if(/vlf_count/.test(c)){
      const cl=n>=VLF_CRIT?'red':n>=VLF_WARN?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toLocaleString()+'</span>':esc(n.toLocaleString());
    }
    if(/latency_ms/.test(c)){
      const cl=n>=LATENCY_CRIT_MS?'red':n>=LATENCY_WARN_MS?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+Math.round(n).toLocaleString()+'ms</span>':esc(Math.round(n).toLocaleString()+'ms');
    }
    if(/modification_pct/.test(c)){
      const cl=n>=MOD_PCT_CRIT?'red':n>=MOD_PCT_WARN?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toFixed(1)+'%</span>':esc(n.toFixed(1)+'%');
    }
    if(/days_until_expiry/.test(c)){
      const cl=n<0?'red':n<=30?'red':n<=90?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n+'d</span>':esc(n+'d');
    }
    if(/pct_vs_avg/.test(c)){
      const cl=n>=100?'red':n>=25?'orange':'';
      return cl?'<span class="sv sv-'+cl+'">'+n.toFixed(1)+'%</span>':esc(n.toFixed(1)+'%');
    }
    // Generic formatting (no threshold)
    if(/_mb$/.test(c)) return esc(String(Math.round(n)));
    if(/_kb$/.test(c)) return esc(String(Math.round(n)));
    if(/_gb$/.test(c)) return esc(n.toFixed(2));
    if(/^pct_|_pct$|_pct_|_percent$/.test(c)) return esc(n.toFixed(1));
    if(/_ms$/.test(c)) return esc(Math.round(n).toLocaleString());
  }
  // Strip trailing .000 from timestamps; keep non-zero ms
  const ts=s.replace(/(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2})\.0+(\s*)$/,'$1$2');
  if(ts!==s)return esc(ts);
  if(s.length>120)return '<span class="cell-long" onclick="this.classList.toggle(\'expanded\')" title="Click to expand">'+esc(s)+'</span>';
  return esc(s);
}
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function copyDdl(){
  const btn=document.getElementById('ddl-copy');
  navigator.clipboard.writeText(document.getElementById('ddl-block').textContent)
    .then(()=>{btn.textContent='Copied!';btn.classList.add('copied');setTimeout(()=>{btn.textContent='Copy';btn.classList.remove('copied');},2000);})
    .catch(()=>{btn.textContent='Failed';setTimeout(()=>{btn.textContent='Copy';},1500);});
}

async function savePng(){
  if(!chart)return;
  const btn=document.getElementById('btn-save-png');
  const confirm=document.getElementById('save-confirm');
  btn.disabled=true;
  try{
    const imageData=chart.toBase64Image('image/png',1);
    const resp=await fetch('/api/save-png',{
      method:'POST',
      headers:{'Content-Type':'application/json'},
      body:JSON.stringify({relPath:decodeURIComponent('$relEnc'),imageData})
    });
    const result=await resp.json();
    if(result.ok){
      confirm.textContent='Saved: '+result.file+' ✓';
      confirm.classList.add('show');
      setTimeout(()=>confirm.classList.remove('show'),3000);
    } else {
      alert('Save failed: '+(result.error||'unknown error'));
    }
  } catch(e){ alert('Save failed: '+e); }
  finally{ btn.disabled=false; }
}

init();
</script>
$rerunOverlay
$rerunJs
"@
    Wrap-Page $name $body '' 'csvs'
}

# ── health check review dashboard ──────────────────────────────────────────────

# ── Shared collection-folder helpers (data strip) ──────────────────────────────

# Script count derived from the collection script itself — it went 32→39 in one week;
# a literal here silently drifts the next time the collection expands.
$script:HcScriptCount = $null
function Get-HcScriptCount {
    if ($script:HcScriptCount) { return $script:HcScriptCount }
    $coll = Join-Path $repoRoot 'powershell\reporting\Invoke-HealthCheckCollection.ps1'
    $n = 0
    if (Test-Path -LiteralPath $coll) {
        $n = ([regex]::Matches((Get-Content -LiteralPath $coll -Raw), '(?m)^\s*Paths\s*=')).Count
    }
    $script:HcScriptCount = if ($n -gt 0) { $n } else { 39 }
    $script:HcScriptCount
}

function Resolve-HcFolder([string]$folder) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    if ($folder -and -not [System.IO.Path]::IsPathRooted($folder)) { $folder = Join-Path $hcRoot $folder }
    if (-not $folder -and (Test-Path $hcRoot)) {
        $latest = Get-ChildItem -LiteralPath $hcRoot -Directory |
                  Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $folder = $latest.FullName }
    }
    $folder
}

function Get-HcFolderAge([System.IO.FileSystemInfo]$dir) {
    $stamp = if ($dir.Name -match '-(\d{8})-(\d{6})$') {
        try { [datetime]::ParseExact($Matches[1] + $Matches[2], 'yyyyMMddHHmmss', $null) } catch { $dir.LastWriteTime }
    } else { $dir.LastWriteTime }
    $span = (Get-Date) - $stamp
    $age  = if ($span.TotalMinutes -lt 60) { "{0:N0}m ago" -f $span.TotalMinutes }
            elseif ($span.TotalHours -lt 48) { "{0:N1}h ago" -f $span.TotalHours }
            else { "{0:N0}d ago" -f $span.TotalDays }
    [PSCustomObject]@{ Stamp = $stamp; Age = $age }
}

# One collect action, many lenses: every collection-driven page (review/security/disk/ai)
# renders this strip instead of its own run button. The dropdown switches which collection
# folder the page analyses; Collect fresh runs the full collection once for all pages.
function Build-DataStrip([string]$folder, [string]$page) {
    $hcRoot     = Join-Path $repoRoot 'output-files\healthcheck'
    $defaultSrv = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }

    $info = "Data: <span class='ds-dim'>no collection yet</span>"
    $historyOpts = ''
    if (Test-Path $hcRoot) {
        $dirs = @(Get-ChildItem -LiteralPath $hcRoot -Directory | Sort-Object LastWriteTime -Descending)
        foreach ($d in $dirs) {
            $meta = Get-HcFolderAge $d
            $sel  = if ($folder -and ($d.FullName -eq $folder)) { ' selected' } else { '' }
            $historyOpts += "<option value='$(Html-Escape $d.Name)'$sel>$(Html-Escape $d.Name) &middot; $($meta.Age)</option>"
        }
    }
    if ($folder -and (Test-Path -LiteralPath $folder)) {
        $dir      = Get-Item -LiteralPath $folder
        $meta     = Get-HcFolderAge $dir
        $csvCount = @(Get-ChildItem -LiteralPath $folder -Filter '*.csv' |
                      Where-Object { $_.Name -notin 'manifest.csv', 'findings.csv' }).Count
        $svrLabel = ($dir.Name -replace '-\d{8}-\d{6}$', '')
        $siCsv    = Join-Path $folder 'server-info.csv'
        if (Test-Path -LiteralPath $siCsv) {
            $row  = Import-Csv -LiteralPath $siCsv -EA SilentlyContinue | Select-Object -First 1
            $prop = if ($row) { $row.PSObject.Properties | Where-Object { $_.Name -match 'server' } | Select-Object -First 1 }
            if ($prop -and $prop.Value) { $svrLabel = $prop.Value }
        }
        $info = "Data: <b>$(Html-Escape $svrLabel)</b> &middot; collected $($meta.Stamp.ToString('dd MMM HH:mm')) <span class='ds-dim'>($($meta.Age))</span> &middot; $csvCount CSVs"
    }

    $historySel = if ($historyOpts) {
        "<select class='ds-select' onchange=`"if(this.value)window.location='/$page?folder='+encodeURIComponent(this.value)`">$historyOpts</select>"
    } else { '' }

    @"
<div class='data-strip'>
  <div>$info</div>
  $historySel
  <div class='ds-spacer'></div>
  <input id='hc-srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off' title='Server to collect from'>
  <button id='hc-run-btn' class='run-btn' onclick='runHealthcheck("$page")'>Collect fresh &#9654;</button>
</div>
<div id='hc-run-err' class='run-error' style='display:none;margin-bottom:10px'></div>
<div id='hc-progress' style='display:none;margin-bottom:12px;padding:10px 14px;background:#161b22;border:1px solid #30363d;border-radius:8px'>
  <div id='hc-progress-label' style='font-size:.82rem;color:#8b949e;margin-bottom:7px'>Starting collection…</div>
  <div style='height:8px;background:#21262d;border-radius:4px;overflow:hidden'>
    <div id='hc-progress-bar' style='height:100%;width:0%;background:#3fb950;transition:width .6s'></div>
  </div>
</div>
<script>
var hcTimer=null;
function hcShowProgress(msg){
  document.getElementById('hc-progress').style.display='';
  document.getElementById('hc-progress-label').textContent=msg;
  document.getElementById('hc-run-btn').disabled=true;
}
function hcFail(msg){
  if(hcTimer){clearInterval(hcTimer);hcTimer=null;}
  document.getElementById('hc-progress').style.display='none';
  var err=document.getElementById('hc-run-err');
  err.textContent=msg;err.style.display='';
  document.getElementById('hc-run-btn').disabled=false;
}
function hcPoll(folder,page){
  var waits=0;
  hcTimer=setInterval(async function(){
    try{
      const r=await fetch('/api/status?folder='+encodeURIComponent(folder));
      const d=await r.json();
      if(!d.ok){hcFail(d.error||'Status check failed');return;}
      if(d.waiting){
        if(++waits>60){hcFail('Collection never started — check the terminal running the web UI.');}
        return;
      }
      var pct=d.total?Math.round(100*d.done/d.total):0;
      document.getElementById('hc-progress-bar').style.width=pct+'%';
      var msg=d.done+'/'+d.total+' collected';
      if(d.running){msg+=' — running '+d.running+'…';}
      if(d.failed>0){msg+=' ('+d.failed+' failed)';}
      if(!d.complete&&d.ageSeconds>180){msg+=' — no progress for '+d.ageSeconds+'s, collection may have stalled';}
      document.getElementById('hc-progress-label').textContent=msg;
      if(d.complete){
        clearInterval(hcTimer);hcTimer=null;
        document.getElementById('hc-progress-label').textContent=d.done+'/'+d.total+' collected — loading results…';
        window.location.href='/'+page+'?folder='+encodeURIComponent(folder);
      }
    }catch(e){/* transient poll failure — keep trying */}
  },1500);
}
async function runHealthcheck(page){
  const srv=document.getElementById('hc-srv').value.trim()||'.';
  document.getElementById('hc-run-err').style.display='none';
  hcShowProgress('Starting collection of $(Get-HcScriptCount) scripts — feeds Health Check, Security, Disk, and AI pages…');
  try{
    const r=await fetch('/api/run-healthcheck?server='+encodeURIComponent(srv));
    const d=await r.json();
    if(d.ok){hcPoll(d.folder,page);return;}
    hcFail(d.error||'Unknown error');
  }catch(e){hcFail('Request failed: '+e.message);}
}
// Resume progress display if the selected folder is a collection still in flight
// (covers terminal-launched collections and navigating between pages mid-collect)
(async function(){
  const folder='$(if ($folder) { Html-Escape (Split-Path -Leaf $folder) })';
  if(!folder)return;
  try{
    const r=await fetch('/api/status?folder='+encodeURIComponent(folder));
    const d=await r.json();
    if(d.ok&&!d.waiting&&!d.complete){
      hcShowProgress('Collection in progress…');
      hcPoll(folder,'$page');
    }
  }catch(e){}
})();
</script>
"@
}

# ── AI Assessment page ─────────────────────────────────────────────────────────

function Build-AiPage([string]$folder, [string]$report) {
    $folder    = Resolve-HcFolder $folder
    $assessDir = Join-Path $repoRoot 'output-files\assessments'
    $html      = Build-DataStrip $folder 'ai'

    # ── single report view ─────────────────────────────────────────────────────
    if ($report) {
        $reportPath = Join-Path $assessDir ([System.IO.Path]::GetFileName($report))
        if (-not (Test-Path -LiteralPath $reportPath)) {
            $html += "<p class='no-data'>Report not found: $(Html-Escape $report)</p>"
            return Wrap-Page 'AI Assessment' $html '' 'ai'
        }
        $md = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8
        $rendered = try { (ConvertFrom-Markdown -InputObject $md).Html } catch { "<pre>$(Html-Escape $md)</pre>" }
        $html += "<div class='back'><a href='/ai'>&#8592; all assessments</a></div>"
        $html += "<div class='md-body'>$rendered</div>"
        return Wrap-Page 'AI Assessment' $html '' 'ai'
    }

    # ── run panel ──────────────────────────────────────────────────────────────
    $hasKey    = [bool]$env:ANTHROPIC_API_KEY
    $folderArg = if ($folder) { Html-Escape (Split-Path $folder -Leaf) } else { '' }
    $runBtns   = "<button class='run-btn' onclick='runAi(1)' title='Builds the exact prompt to a preview file without calling any API'>Preview prompt (DryRun)</button>"
    if ($hasKey) {
        $runBtns += " <button class='run-btn' onclick='runAi(0)'>Run AI Assessment &#9654;</button>"
        $keyNote  = "<span class='ds-dim'>ANTHROPIC_API_KEY detected &middot; model claude-opus-4-8 &middot; typically under `$1 per run</span>"
    } else {
        $keyNote  = "<span class='ds-dim'>No ANTHROPIC_API_KEY set — live runs disabled. Ask a Claude Code session to write the assessment instead, or see <a href='/view?p=docs%5Cai-assessment.md'>docs/ai-assessment.md</a> for key setup (home) and gateway repointing (work).</span>"
    }
    $html += @"
<div class='data-strip' style='margin-top:-6px'>
  <div>AI assessment of the selected collection: $runBtns</div>
  <div class='ds-spacer'></div>
  $keyNote
</div>
<div id='ai-run-err' class='run-error' style='display:none;margin-bottom:10px'></div>
<div id='ai-overlay' class='run-overlay'>
  <div class='run-spinner'></div>
  <div class='run-spinner-label' id='ai-overlay-label'>Running AI assessment — this can take a few minutes…</div>
</div>
<script>
async function runAi(dry){
  const err=document.getElementById('ai-run-err');
  document.getElementById('ai-overlay-label').textContent = dry ? 'Building prompt preview…' : 'Running AI assessment — this can take a few minutes…';
  document.getElementById('ai-overlay').style.display='flex';
  err.style.display='none';
  try{
    const r=await fetch('/api/run-ai?folder=$folderArg&dryrun='+dry);
    const d=await r.json();
    if(d.ok){window.location.href='/ai';return;}
    err.textContent=d.error||'Unknown error';err.style.display='';
  }catch(e){err.textContent='Request failed: '+e.message;err.style.display='';}
  document.getElementById('ai-overlay').style.display='none';
}
</script>
"@

    # ── reports list ───────────────────────────────────────────────────────────
    $reports = if (Test-Path $assessDir) {
        @(Get-ChildItem -LiteralPath $assessDir -Filter '*.md' | Sort-Object LastWriteTime -Descending)
    } else { @() }

    if (-not $reports) {
        $html += "<p class='no-data'>No assessments yet. Collect a healthcheck above, then run the AI assessment — or ask a Claude Code session for one.</p>"
    } else {
        $html += "<div class='vital-row-label'>Assessments ($($reports.Count))</div>"
        foreach ($r in $reports) {
            $isCc  = $r.BaseName -match '-claude-code$'
            $badge = if ($isCc) { "<span class='badge badge-ai-cc'>Claude Code</span>" } else { "<span class='badge badge-ai-api'>API</span>" }
            $meta  = Get-HcFolderAge $r
            # Verdict excerpt: first paragraph under '## Verdict'
            $verdict = ''
            $lines = Get-Content -LiteralPath $r.FullName -TotalCount 40 -Encoding UTF8
            $vIdx  = [Array]::IndexOf(($lines | ForEach-Object { $_.Trim() }), '## Verdict')
            if ($vIdx -ge 0) {
                $para = $lines[($vIdx+1)..([Math]::Min($vIdx+8, $lines.Count-1))] | Where-Object { $_.Trim() } | Select-Object -First 3
                $verdict = (($para -join ' ') -replace '\*\*','').Trim()
                if ($verdict.Length -gt 260) { $verdict = $verdict.Substring(0, 260) + '…' }
            }
            $enc = [Uri]::EscapeDataString($r.Name)
            $html += "<div class='ai-card'>$badge <a href='/ai?report=$enc'>$(Html-Escape $r.BaseName)</a> <span class='ds-dim' style='font-size:.75rem'>&middot; $($meta.Age)</span>"
            if ($verdict) { $html += "<div class='purpose'>$(Html-Escape $verdict)</div>" }
            $html += "</div>"
        }
    }

    # prompt previews (dry runs)
    $previews = if (Test-Path $assessDir) {
        @(Get-ChildItem -LiteralPath $assessDir -Filter 'prompt-preview-*.txt' | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
    } else { @() }
    if ($previews) {
        $html += "<div class='vital-row-label'>Prompt previews (what a run would send)</div>"
        foreach ($p in $previews) {
            $rel = "output-files\assessments\$($p.Name)"
            $enc = [Uri]::EscapeDataString($rel)
            $html += "<div class='ai-card'><a href='/view?p=$enc'>$(Html-Escape $p.BaseName)</a> <span class='ds-dim' style='font-size:.75rem'>&middot; $([Math]::Round($p.Length/1kb)) KB</span></div>"
        }
    }

    Wrap-Page 'AI Assessment' $html '' 'ai'
}

function Build-ReviewPage([string]$folder) {
    $folder = Resolve-HcFolder $folder
    $html   = Build-DataStrip $folder 'review'

    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
        $html += "<p class='no-data'>No healthcheck folder found. Run <code>Invoke-HealthCheckCollection.ps1</code> first.</p>"
        return Wrap-Page 'Health Check' $html '' 'review'
    }

    # ── Stage 4: rules-engine scorecard + delta vs previous collection ─────────
    function Get-FindingsRows([string]$hcFolder) {
        $fp = Join-Path $hcFolder 'findings.csv'
        if (-not (Test-Path -LiteralPath $fp)) {
            $rvw = Join-Path $repoRoot 'powershell\reporting\Review-HealthCheckOutput.ps1'
            if (Test-Path $rvw) { try { & $rvw -FolderPath $hcFolder -OutputFormat Csv *> $null } catch {} }
        }
        if (Test-Path -LiteralPath $fp) { @(Import-Csv -LiteralPath $fp -EA SilentlyContinue) } else { @() }
    }

    $fx = Get-FindingsRows $folder
    if ($fx.Count -gt 0) {
        $nCrit = @($fx | Where-Object Severity -eq 'CRITICAL').Count
        $nWarn = @($fx | Where-Object Severity -eq 'WARNING').Count
        $nInfo = @($fx | Where-Object Severity -eq 'INFO').Count

        # delta vs the previous collection of the SAME server — folders from other
        # servers would make every uncollected finding look new/resolved
        $deltaHtml = ''
        $hcRootD   = Join-Path $repoRoot 'output-files\healthcheck'
        $curPrefix = (Split-Path -Leaf $folder) -replace '-\d{8}-\d{6}$', ''
        $allDirs   = @(Get-ChildItem -LiteralPath $hcRootD -Directory |
                       Where-Object { ($_.Name -replace '-\d{8}-\d{6}$', '') -eq $curPrefix } |
                       Sort-Object LastWriteTime -Descending)
        $curIdx   = [Array]::FindIndex($allDirs, [Predicate[object]]{ param($d) $d.FullName -eq $folder })
        if ($curIdx -ge 0 -and $curIdx + 1 -lt $allDirs.Count) {
            $prevDir  = $allDirs[$curIdx + 1]
            $px       = Get-FindingsRows $prevDir.FullName
            if ($px.Count -gt 0) {
                $keyOf    = { "$($args[0].Severity)|$($args[0].Category)|$($args[0].Subject)|$($args[0].Detail)" }
                $prevKeys = [System.Collections.Generic.HashSet[string]]::new([string[]]@($px | ForEach-Object { & $keyOf $_ }))
                $curKeys  = [System.Collections.Generic.HashSet[string]]::new([string[]]@($fx | ForEach-Object { & $keyOf $_ }))
                $newF     = @($fx | Where-Object { -not $prevKeys.Contains((& $keyOf $_)) })
                $resF     = @($px | Where-Object { -not $curKeys.Contains((& $keyOf $_)) })
                $deltaHtml = "<span class='delta-box ds-dim'>vs $(Html-Escape $prevDir.Name): <span class='delta-new'>&#9650; $($newF.Count) new</span> &middot; <span class='delta-res'>&#9660; $($resF.Count) resolved</span></span>"
                if ($newF.Count -gt 0) {
                    $deltaHtml += "<details style='margin-top:6px'><summary style='font-size:.78rem;color:#f78166;cursor:pointer'>New findings since previous collection</summary><div class='findings-list'>"
                    foreach ($f in ($newF | Select-Object -First 30)) { $deltaHtml += "<div class='finding-row f-crit'><span class='sv sv-red'>NEW</span><span class='find-cat'>$(Html-Escape $f.Category)</span><span class='find-subj'>$(Html-Escape $f.Subject)</span><div class='find-detail'>$(Html-Escape $f.Detail)</div></div>" }
                    if ($newF.Count -gt 30) { $deltaHtml += "<p class='no-data'>…and $($newF.Count - 30) more.</p>" }
                    $deltaHtml += "</div></details>"
                }
                if ($resF.Count -gt 0) {
                    $deltaHtml += "<details style='margin-top:6px'><summary style='font-size:.78rem;color:#3fb950;cursor:pointer'>Resolved since previous collection</summary><div class='findings-list'>"
                    foreach ($f in ($resF | Select-Object -First 30)) { $deltaHtml += "<div class='finding-row'><span class='sv sv-green'>GONE</span><span class='find-cat'>$(Html-Escape $f.Category)</span><span class='find-subj'>$(Html-Escape $f.Subject)</span><div class='find-detail'>$(Html-Escape $f.Detail)</div></div>" }
                    if ($resF.Count -gt 30) { $deltaHtml += "<p class='no-data'>…and $($resF.Count - 30) more.</p>" }
                    $deltaHtml += "</div></details>"
                }
            }
        }

        $sevChips  = "<span class='chip-row-label'>Severity</span>"
        $sevChips += "<span class='score-chip sc-crit' data-fx='sev:CRITICAL' onclick='fxChip(this)'><span class='n'>$nCrit</span> Critical</span>"
        $sevChips += "<span class='score-chip sc-warn' data-fx='sev:WARNING' onclick='fxChip(this)'><span class='n'>$nWarn</span> Warning</span>"
        $sevChips += "<span class='score-chip sc-info' data-fx='sev:INFO' onclick='fxChip(this)'><span class='n'>$nInfo</span> Info</span>"
        $catChips  = "<span class='chip-row-label'>Category</span>"
        foreach ($cat in (@($fx | Group-Object Category | Sort-Object Count -Descending))) {
            $catChips += "<span class='score-chip' data-fx='cat:$(Html-Escape $cat.Name)' onclick='fxChip(this)'><span class='n'>$($cat.Count)</span> $(Html-Escape $cat.Name)</span>"
        }

        # one-line verdict first — the 5-second answer before any drill-down
        $topCat  = @($fx | Group-Object Category | Sort-Object Count -Descending | Select-Object -First 1)
        $sumBits = @()
        $sumBits += if ($nCrit -gt 0) { "<span class='sv sv-red'>$nCrit CRITICAL</span>" } else { "<span class='sv sv-green'>0 critical</span>" }
        if ($nWarn -gt 0) { $sumBits += "<span class='sv sv-orange'>$nWarn WARNING</span>" }
        if ($nInfo -gt 0) { $sumBits += "$nInfo info" }
        if ($topCat)      { $sumBits += "top category: <b>$(Html-Escape $topCat.Name)</b> ($($topCat.Count))" }
        $html += "<div class='disk-summary'><b>$($fx.Count)</b> finding$(if ($fx.Count -ne 1) {'s'}) &middot; $($sumBits -join ' &middot; ')</div>"

        $html += "<details class='rv-section' open><summary>Scorecard — Rules Engine ($($fx.Count) findings)</summary>"
        $html += "<div class='chip-row'>$sevChips</div><div class='chip-row chip-row-cats'>$catChips</div>$deltaHtml"
        $html += "<div class='findings-list' id='fx-list' style='margin-top:10px'>"
        $ordF = @{ CRITICAL = 0; WARNING = 1; INFO = 2 }
        foreach ($f in ($fx | Sort-Object { $ordF[$_.Severity] }, Category, Subject)) {
            $tagCls = switch ($f.Severity) { 'CRITICAL' {'sv sv-red'} 'WARNING' {'sv sv-orange'} default {'sv sv-blue'} }
            $html  += "<div class='finding-row fx-row' data-sev='$($f.Severity)' data-cat='$(Html-Escape $f.Category)'><span class='$tagCls'>$($f.Severity)</span><span class='find-cat'>$(Html-Escape $f.Category)</span><span class='find-subj'>$(Html-Escape $f.Subject)</span><div class='find-detail'>$(Html-Escape $f.Detail)</div></div>"
        }
        $html += "</div></details><script>
function fxChip(el){
  var f=el.getAttribute('data-fx');var on=el.classList.contains('active');
  document.querySelectorAll('.score-chip').forEach(function(c){c.classList.remove('active')});
  document.querySelectorAll('.fx-row').forEach(function(r){r.style.display=''});
  if(on)return;
  el.classList.add('active');
  var kind=f.split(':')[0],val=f.substring(f.indexOf(':')+1);
  document.querySelectorAll('.fx-row').forEach(function(r){
    var m=(kind==='sev')?(r.getAttribute('data-sev')===val):(r.getAttribute('data-cat')===val);
    if(!m)r.style.display='none';
  });
}
</script>"
    }

    function Read-RvwCsv([string]$name) {
        $p = Join-Path $folder "$name.csv"
        if (Test-Path -LiteralPath $p) { @(Import-Csv -LiteralPath $p -EA SilentlyContinue) } else { @() }
    }

    $svrInfo   = Read-RvwCsv 'server-info'
    $osHw      = Read-RvwCsv 'os-hardware'
    $dbHealth  = Read-RvwCsv 'database-health'
    $backups   = Read-RvwCsv 'backup-times'
    $tlogs     = Read-RvwCsv 'tlog-usage'
    $dbFiles   = Read-RvwCsv 'database-files'
    $jobs      = Read-RvwCsv 'job-failures'
    $sessions  = Read-RvwCsv 'active-sessions'
    $errors    = Read-RvwCsv 'recent-errors'
    $checkdb   = Read-RvwCsv 'dbcc-checkdb'
    $suspects  = Read-RvwCsv 'suspect-pages'
    $ioStats   = Read-RvwCsv 'io-usage'
    $logins    = Read-RvwCsv 'weak-logins'
    $waits     = Read-RvwCsv 'wait-stats'
    $memConfig = Read-RvwCsv 'memory-config'
    $dbSizes   = Read-RvwCsv 'database-sizes'
    $tempdb      = Read-RvwCsv 'tempdb-usage'
    $diskSpc     = Read-RvwCsv 'disk-space'
    $missingIdx   = Read-RvwCsv 'missing-indexes'
    $failedLogins = Read-RvwCsv 'failed-logins'
    $qsStatus     = Read-RvwCsv 'query-store-status'
    $xeSessions   = Read-RvwCsv 'extended-events'
    $cdcCt        = Read-RvwCsv 'cdc-and-ct'
    $svcBroker    = Read-RvwCsv 'service-broker'

    # ── findings rules (mirrors Review-HealthCheckOutput.ps1) ──────────────────
    $findings = [System.Collections.Generic.List[PSObject]]::new()
    function Add-F([string]$Sev,[string]$Cat,[string]$Subj,[string]$Detail) {
        $findings.Add([PSCustomObject]@{ Severity=$Sev; Category=$Cat; Subject=$Subj; Detail=$Detail })
    }

    foreach ($row in $dbHealth) {
        if ($row.state_desc -and $row.state_desc -ne 'ONLINE') { Add-F 'CRITICAL' 'Database State' $row.database_name "Database is $($row.state_desc)" }
        if ($row.is_auto_shrink_on -in @('True','1','YES'))     { Add-F 'WARNING'  'Auto-Shrink'    $row.database_name 'AUTO_SHRINK enabled — fragmentation and random I/O spikes' }
        if ($row.is_auto_close_on  -in @('True','1','YES'))     { Add-F 'WARNING'  'Auto-Close'     $row.database_name 'AUTO_CLOSE enabled — overhead on every new connection' }
    }
    $h = 0.0; $lh = 0.0; $pct = 0.0
    foreach ($row in $backups) {
        $db = $row.database_name
        if (-not $row.last_full_backup -or $row.last_full_backup -eq '') { Add-F 'CRITICAL' 'Backup' $db 'No full backup on record' }
        else {
            $h = 0.0
            if ([double]::TryParse($row.full_backup_age_hours,[ref]$h) -and $h -gt 24) {
                Add-F 'CRITICAL' 'Backup' $db "Full backup $([Math]::Round($h,1))h old (threshold 24h)"
            }
        }
        if ($row.recovery_model_desc -in @('FULL','BULK_LOGGED')) {
            if (-not $row.last_log_backup -or $row.last_log_backup -eq '') { Add-F 'WARNING' 'Backup' $db "$($row.recovery_model_desc) recovery but no log backup — log will grow unbounded" }
            else {
                $lh = 0.0
                if ([double]::TryParse($row.log_backup_age_hours,[ref]$lh) -and $lh -gt 4) {
                    Add-F 'WARNING' 'Backup' $db "Log backup $([Math]::Round($lh,1))h old (threshold 4h)"
                }
            }
        }
    }
    foreach ($row in $tlogs) {
        $pctCol = if ($row.PSObject.Properties['log_used_pct']) { $row.log_used_pct } else { $row.log_used_percent }
        $pct = 0.0
        if ([double]::TryParse($pctCol,[ref]$pct) -and $pct -gt 80) {
            Add-F 'WARNING' 'Transaction Log' $row.database_name "Log $(Fmt-Pct $pct)% used ($(Fmt-Mb $row.log_used_mb) MB of $(Fmt-Mb $row.log_size_mb) MB)"
        }
    }
    foreach ($row in $dbFiles) {
        if ($row.growth_is_percent -in @('True','1','YES','true')) {
            Add-F 'WARNING' 'Autogrowth' "$($row.database_name) / $($row.logical_name)" "Percent-based autogrowth ($($row.auto_growth)) on $($row.file_type)"
        }
    }
    foreach ($jName in ($jobs | Select-Object -ExpandProperty job_name -Unique)) {
        $n = @($jobs | Where-Object job_name -eq $jName).Count
        Add-F 'WARNING' 'SQL Agent' $jName "$n failure(s) in last 7 days"
    }
    $blkSess = @($sessions | Where-Object { $n=0; $v=$_.blocking_session_id; $v -and [int]::TryParse($v,[ref]$n) -and $n -gt 0 })
    if ($blkSess.Count -gt 0) {
        Add-F 'INFO' 'Blocking' 'Active sessions' "$($blkSess.Count) session(s) blocked: spid $( ($blkSess|Select-Object -Exp session_id) -join ', ' )"
    }
    $openTxSess = @($sessions | Where-Object { $n=0; [int]::TryParse($_.open_transaction_count,[ref]$n) -and $n -gt 0 })
    if ($openTxSess.Count -gt 0) { Add-F 'INFO' 'Open Transactions' 'Active sessions' "$($openTxSess.Count) session(s) with open transactions" }
    if ($errors.Count -gt 0)     { Add-F 'INFO' 'Error Log' 'SQL Server error log' "$($errors.Count) non-routine entries in last 24h" }
    $d = 0
    foreach ($row in $checkdb) {
        if (-not $row.last_good_checkdb -or $row.last_good_checkdb -eq '') { Add-F 'CRITICAL' 'DBCC CHECKDB' $row.database_name 'No CHECKDB ever recorded — integrity unknown' }
        else {
            $d = 0
            if ([int]::TryParse($row.days_since_checkdb,[ref]$d)) {
                if ($d -gt 14)     { Add-F 'CRITICAL' 'DBCC CHECKDB' $row.database_name "CHECKDB overdue — $d days since last integrity check (run immediately)" }
                elseif ($d -gt 7)  { Add-F 'WARNING'  'DBCC CHECKDB' $row.database_name "CHECKDB stale — $d days since last integrity check (run soon)" }
            }
        }
    }
    $actSusp = @($suspects | Where-Object { $_.event_type -notmatch 'Restored|Repaired|Deallocated' })
    if ($actSusp.Count -gt 0) {
        Add-F 'CRITICAL' 'Suspect Pages' 'msdb.dbo.suspect_pages' "$($actSusp.Count) active suspect page(s) — DBCC CHECKDB immediately on: $(($actSusp|Select-Object -Exp database_name -Unique) -join ', ')"
    }
    foreach ($row in $ioStats) {
        $rl=0.0; $wl=0.0
        [double]::TryParse($row.read_latency_ms,[ref]$rl)  | Out-Null
        [double]::TryParse($row.write_latency_ms,[ref]$wl) | Out-Null
        if ($rl -gt 50) { Add-F 'WARNING' 'I/O Latency' $row.database_name "Read latency $([Math]::Round($rl,1)) ms (>50ms)" }
        if ($wl -gt 50) { Add-F 'WARNING' 'I/O Latency' $row.database_name "Write latency $([Math]::Round($wl,1)) ms (>50ms)" }
    }
    foreach ($login in $logins) {
        if (-not $login.risk_flag -or $login.risk_flag -eq 'OK') { continue }
        $sev = if ($login.risk_flag -eq 'SA_ENABLED') { 'CRITICAL' } else { 'WARNING' }
        Add-F $sev 'Security' $login.login_name "Risk flag: $($login.risk_flag)"
    }
    $cWaits = @{ PAGEIOLATCH_SH='Data read I/O bottleneck'; PAGEIOLATCH_EX='Data write I/O bottleneck'; WRITELOG='Log write bottleneck'; RESOURCE_SEMAPHORE='Memory grant pressure'; CXPACKET='Parallelism waits'; CXCONSUMER='Parallelism waits'; LCK_M_X='Exclusive lock waits'; ASYNC_NETWORK_IO='Client network waits' }
    $pct = 0.0
    foreach ($row in $waits) {
        $pct = 0.0
        if ($cWaits.ContainsKey($row.wait_type) -and [double]::TryParse($row.pct_total_wait,[ref]$pct) -and $pct -gt 10) {
            Add-F 'WARNING' 'Wait Statistics' $row.wait_type "$([Math]::Round($pct,1))% of wait time — $($cWaits[$row.wait_type])"
        }
    }
    $mm = 0L
    foreach ($row in $memConfig) {
        $mm = 0L
        if ([long]::TryParse($row.max_server_memory_mb,[ref]$mm) -and $mm -ge 2147483647) {
            Add-F 'WARNING' 'Memory Config' 'max server memory' 'Unconfigured (SQL Server default) — may consume all available RAM'
        }
    }
    $fp = 0.0
    foreach ($row in $dbSizes) {
        $fp = 0.0
        if ([double]::TryParse($row.data_free_pct,[ref]$fp) -and $fp -lt 10) {
            Add-F 'WARNING' 'Disk Space' $row.database_name "Data files $(Fmt-Pct $fp)% free ($(Fmt-Mb $row.data_free_mb) MB free of $(Fmt-Mb $row.data_size_mb) MB)"
        }
    }
    $highImpactIdx = @($missingIdx | Where-Object { ($_.impact_score -as [double]) -gt 100000 })
    if ($highImpactIdx.Count -gt 0) {
        Add-F 'WARNING' 'Missing Indexes' "$($highImpactIdx.Count) high-impact index(es)" "Top: $(Html-Escape $highImpactIdx[0].table_name) — $(Fmt-Pct ($highImpactIdx[0].avg_improvement_pct -as [double]))% estimated improvement"
    } elseif ($missingIdx.Count -gt 0) {
        Add-F 'INFO' 'Missing Indexes' "$($missingIdx.Count) candidate(s) identified" "Top impact score: $([Math]::Round(($missingIdx[0].impact_score -as [double]),0).ToString('N0'))"
    }
    foreach ($row in $failedLogins) {
        $loginName = if ($null -ne $row.login_name) { $row.login_name } else { '(unknown)' }
        if ($row.is_currently_locked -in @('1','True','true')) {
            Add-F 'CRITICAL' 'Failed Logins' $loginName 'Login is currently locked out'
        }
        if ($row.status -like 'CRITICAL*') {
            Add-F 'CRITICAL' 'Failed Logins' $loginName "$($row.failure_count) failures in error log — likely brute-force or app misconfiguration"
        } elseif ($row.status -like 'WARN*') {
            Add-F 'WARNING' 'Failed Logins' $loginName "$($row.failure_count) repeated failures in error log"
        }
    }
    foreach ($row in $qsStatus) {
        if ($row.qs_state -eq 'READ_ONLY' -and $row.qs_desired_state -in @('READ_WRITE','AUTO')) {
            $fp = if ($row.fill_pct -and $row.fill_pct -ne '') { " ($(Fmt-Pct ([double]$row.fill_pct))% full)" } else { '' }
            Add-F 'WARNING' 'Query Store' $row.database_name "QS switched to READ_ONLY$fp — storage full or error; plan history is paused"
        }
    }

    # ── header bar ─────────────────────────────────────────────────────────────
    $folderLeaf = Split-Path -Leaf $folder
    $collectedAt = ''
    if ($folderLeaf -match '(\d{8}-\d{6})$') {
        try { $collectedAt = ([DateTime]::ParseExact($Matches[1],'yyyyMMdd-HHmmss',$null)).ToString('yyyy-MM-dd HH:mm') } catch {}
    }
    $svrName = if ($svrInfo -and $svrInfo[0].PSObject.Properties['server_name']) { $svrInfo[0].server_name } `
               else { $folderLeaf -replace '-\d{8}-\d{6}$','' }

    $html += "<div class='hc-meta'>"
    $html += "<span><strong>Server</strong> $(Html-Escape $svrName)</span>"
    if ($collectedAt) { $html += "<span><strong>Collected</strong> $collectedAt</span>" }
    $html += "<span><strong>Reviewed</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm')</span>"
    $html += "</div>"

    # ── instance & OS ───────────────────────────────────────────────────────────
    if ($svrInfo.Count -gt 0 -or $osHw.Count -gt 0) {
        $html += "<details class='rv-section' open><summary>Instance</summary><div class='info-card-grid'>"
        if ($svrInfo.Count -gt 0) {
            $sqlNames = @{ '8'='SQL Server 2000';'9'='SQL Server 2005';'10'='SQL Server 2008';
                           '11'='SQL Server 2012';'12'='SQL Server 2014';'13'='SQL Server 2016';
                           '14'='SQL Server 2017';'15'='SQL Server 2019';'16'='SQL Server 2022';
                           '17'='SQL Server 2025' }
            $pv      = $svrInfo[0].product_version
            $pl      = $svrInfo[0].product_level
            $major   = ($pv -split '\.')[0]
            $relName = if ($sqlNames.ContainsKey($major)) { $sqlNames[$major] } else { "SQL Server (v$major)" }
            $verParts = @($relName)
            if ($pv) { $verParts += $pv }
            if ($pl) { $verParts += $pl }
            $ver = $verParts -join ' &nbsp;·&nbsp; '
            $html += "<div class='info-card'><div class='info-label'>version</div><div class='info-val'>$ver</div></div>"
        }
        $instFields = @('edition','server_name','machine_name','is_clustered')
        foreach ($fld in ($instFields | Where-Object { $svrInfo.Count -gt 0 -and $svrInfo[0].PSObject.Properties[$_] })) {
            $html += "<div class='info-card'><div class='info-label'>$($fld -replace '_',' ')</div><div class='info-val'>$(Html-Escape $svrInfo[0].$fld)</div></div>"
        }
        $hwFields = @('os_version','cpu_count','physical_memory_mb','sqlserver_start_time')
        foreach ($fld in ($hwFields | Where-Object { $osHw.Count -gt 0 -and $osHw[0].PSObject.Properties[$_] })) {
            $raw  = $osHw[0].$fld
            $disp = if ($fld -like '*_mb') { Fmt-Mb $raw } else { $raw -replace '\.\d{3,}$','' }
            $html += "<div class='info-card'><div class='info-label'>$($fld -replace '_',' ')</div><div class='info-val'>$(Html-Escape $disp)</div></div>"
        }
        $html += "</div></details>"
    }

    if ($memConfig.Count -gt 0) {
        $mc = $memConfig[0]
        $html += "<details class='rv-section' open><summary>Memory Configuration</summary><div class='info-card-grid'>"
        $mcFields = @(
            @{ f='min_server_memory_mb';   l='Min Server Memory (MB)' }
            @{ f='max_server_memory_mb';   l='Max Server Memory (MB)' }
            @{ f='server_physical_memory_gb'; l='Physical RAM (GB)' }
            @{ f='sql_memory_in_use_mb';   l='SQL Memory In Use (MB)' }
            @{ f='sql_committed_mb';       l='SQL Committed (MB)' }
        )
        foreach ($mf in $mcFields) {
            if ($mc.PSObject.Properties[$mf.f]) {
                $v = $mc.($mf.f)
                $disp = if ($mf.f -like '*_mb') { Fmt-Mb $v } else { [Math]::Round(($v -as [double]),2) }
                $html += "<div class='info-card'><div class='info-label'>$($mf.l)</div><div class='info-val'>$(Html-Escape $disp)</div></div>"
            }
        }
        $maxMb = 0L; [long]::TryParse($mc.max_server_memory_mb,[ref]$maxMb) | Out-Null
        if ($maxMb -ge 2147483647) {
            $html += "<div class='info-card' style='border-color:#ffa657'><div class='info-label'>Warning</div><div class='info-val' style='color:#ffa657'>Max memory unconfigured</div></div>"
        }
        $html += "</div></details>"
    }
    # ── features (compact cards, shown when HC has feature data) ───────────────
    if (($qsStatus.Count + $xeSessions.Count + $cdcCt.Count + $svcBroker.Count) -gt 0) {
        $html += "<details class='rv-section' open><summary>Features</summary><div class='vital-grid'>"

        if ($qsStatus.Count -gt 0) {
            $qsOn  = @($qsStatus | Where-Object { $_.qs_desired_state -notin @('OFF','') }).Count
            $qsROW = @($qsStatus | Where-Object { $_.qs_state -eq 'READ_ONLY' -and $_.qs_desired_state -in @('READ_WRITE','AUTO') }).Count
            $qsCls = if ($qsROW -gt 0) { 'v-warn' } elseif ($qsOn -gt 0) { 'v-ok' } else { 'v-blue' }
            $qsVal = if ($qsOn -gt 0) { "$qsOn of $($qsStatus.Count)" } else { 'Off' }
            $qsSub = if ($qsROW -gt 0) { "$qsROW DB(s) READ_ONLY" } elseif ($qsOn -gt 0) { 'databases enabled' } else { 'not enabled' }
            $html += "<div class='vital-card $qsCls'><div class='vital-label'>Query Store</div><div class='vital-val'>$qsVal</div><div class='vital-sub'>$qsSub</div></div>"
        }

        if ($xeSessions.Count -gt 0) {
            $sysXE  = @('system_health','telemetry_xevents','AlwaysOn_health','hkenginexesession','FaultReporting')
            $userXE = @($xeSessions | Where-Object { $_.session_name -notin $sysXE })
            $xeCls  = if ($userXE.Count -gt 0) { 'v-blue' } else { 'v-ok' }
            $xeSub  = if ($userXE.Count -gt 0) { "$($userXE.Count) user session(s)" } else { 'system only' }
            $html += "<div class='vital-card $xeCls'><div class='vital-label'>Extended Events</div><div class='vital-val'>$($xeSessions.Count)</div><div class='vital-sub'>$xeSub</div></div>"
        }

        if ($cdcCt.Count -gt 0) {
            $cdcDBs = @($cdcCt | Where-Object { $_.feature -eq 'CDC'             -and $_.feature_enabled -in @('1','True','true') }).Count
            $ctDBs  = @($cdcCt | Where-Object { $_.feature -eq 'CHANGE_TRACKING' }).Count
            $cdcWrn = @($cdcCt | Where-Object { $_.status -like 'WARN*' }).Count
            $cdcAny = $cdcDBs + $ctDBs
            $cdcCls = if ($cdcWrn -gt 0) { 'v-warn' } elseif ($cdcAny -gt 0) { 'v-blue' } else { 'v-ok' }
            $cdcVal = if ($cdcAny -gt 0) { $cdcAny } else { 'None' }
            $cdcSub = if ($cdcAny -gt 0) { "CDC: $cdcDBs  CT: $ctDBs" } else { 'not in use' }
            $html += "<div class='vital-card $cdcCls'><div class='vital-label'>CDC / Change Tracking</div><div class='vital-val'>$cdcVal</div><div class='vital-sub'>$cdcSub</div></div>"
        }

        if ($svcBroker.Count -gt 0) {
            $sbOn  = @($svcBroker | Where-Object { $_.sb_enabled -in @('1','True','true') }).Count
            $sbWrn = @($svcBroker | Where-Object { $_.status -like 'CRITICAL*' -or $_.status -like 'WARN*' }).Count
            $sbCls = if ($sbWrn -gt 0) { 'v-warn' } elseif ($sbOn -gt 0) { 'v-blue' } else { 'v-ok' }
            $sbVal = if ($sbOn -gt 0) { $sbOn } else { 'None' }
            $sbSub = if ($sbOn -gt 0) { 'databases enabled' } else { 'not in use' }
            $html += "<div class='vital-card $sbCls'><div class='vital-label'>Service Broker</div><div class='vital-val'>$sbVal</div><div class='vital-sub'>$sbSub</div></div>"
        }

        $html += "</div></details>"
    }

    # ── vital signs bar ────────────────────────────────────────────────────────
    $vSessions = $sessions.Count
    $vBlocked  = $blkSess.Count
    $vRunning  = @($sessions | Where-Object { $_.status -eq 'running' }).Count
    $sessCls   = if ($vBlocked -gt 0) { 'v-crit' } elseif ($vRunning -gt 0) { 'v-ok' } else { 'v-blue' }
    $sessSub   = "$vBlocked blocked · $vRunning running"

    $topWaitRow = $waits | Sort-Object { [double]($_.pct_total_wait -as [double]) } -Descending | Select-Object -First 1
    $vWaitPct  = [double]($topWaitRow.pct_total_wait -as [double])
    $vWaitName = if ($topWaitRow) { $topWaitRow.wait_type } else { '—' }
    $waitCls   = if ($topWaitRow -and $cWaits.ContainsKey($vWaitName) -and $vWaitPct -gt 10) { 'v-warn' } else { 'v-ok' }

    $worstBkpHours = [double](($backups | Sort-Object { [double]($_.full_backup_age_hours -as [double]) } -Descending | Select-Object -First 1).full_backup_age_hours -as [double])
    $bkpCls  = if ($worstBkpHours -gt 24) { 'v-crit' } elseif ($worstBkpHours -gt 12) { 'v-warn' } else { 'v-ok' }
    $bkpDisp = if ($backups.Count -eq 0) { '—' } else { "$([Math]::Round($worstBkpHours,1))h" }

    $worstCheckRow = $checkdb | Sort-Object { [int]($_.days_since_checkdb -as [int]) } -Descending | Select-Object -First 1
    $worstCheckDays = $worstCheckRow.days_since_checkdb -as [int]
    $chkCls  = if ($null -eq $worstCheckDays -or -not $worstCheckRow.last_good_checkdb) { 'v-crit' } elseif ($worstCheckDays -gt 14) { 'v-crit' } elseif ($worstCheckDays -gt 7) { 'v-warn' } else { 'v-ok' }
    $chkDisp = if ($checkdb.Count -eq 0) { '—' } elseif ($null -eq $worstCheckDays) { 'NEVER' } else { "${worstCheckDays}d" }

    $worstTlogRow = $tlogs | Sort-Object { [double]($_.log_used_pct -as [double]) } -Descending | Select-Object -First 1
    $worstTlogPct = [double]($worstTlogRow.log_used_pct -as [double])
    $tlogCls = if ($worstTlogPct -gt 80) { 'v-crit' } elseif ($worstTlogPct -gt 50) { 'v-warn' } else { 'v-ok' }
    $tlogDisp = if ($tlogs.Count -eq 0) { '—' } else { "$(Fmt-Pct $worstTlogPct)%" }
    $tlogSub  = if ($worstTlogRow) { Html-Escape $worstTlogRow.database_name } else { '' }

    $worstDiskRow = $diskSpc | Group-Object volume_mount_point | ForEach-Object { $_.Group[0] } | Sort-Object { [double]($_.free_pct -as [double]) } | Select-Object -First 1
    $worstDiskPct = [double]($worstDiskRow.free_pct -as [double])
    $diskCls  = if ($diskSpc.Count -eq 0) { 'v-blue' } elseif ($worstDiskPct -lt 10) { 'v-crit' } elseif ($worstDiskPct -lt 20) { 'v-warn' } else { 'v-ok' }
    $diskDisp = if ($diskSpc.Count -eq 0) { '—' } else { "$(Fmt-Pct $worstDiskPct)% free" }
    $diskSub  = if ($worstDiskRow) { Html-Escape $worstDiskRow.volume_mount_point } else { '' }

    $worstTempRow = $tempdb | Sort-Object { [double]($_.pct_used -as [double]) } -Descending | Select-Object -First 1
    $worstTempPct = [double]($worstTempRow.pct_used -as [double])
    $tempCls  = if ($tempdb.Count -eq 0) { 'v-blue' } elseif ($worstTempPct -gt 80) { 'v-crit' } elseif ($worstTempPct -gt 60) { 'v-warn' } else { 'v-ok' }
    $tempDisp = if ($tempdb.Count -eq 0) { '—' } else { "$(Fmt-Pct $worstTempPct)% used" }

    $html += "<details class='rv-section' open><summary>Right now</summary><div class='vital-grid'>"
    $html += "<div class='vital-card $sessCls'><div class='vital-label'>Sessions</div><div class='vital-val'>$vSessions</div><div class='vital-sub'>$sessSub</div></div>"
    $html += "<div class='vital-card $waitCls'><div class='vital-label'>Top Wait</div><div class='vital-val' style='font-size:.82rem'>$(Html-Escape $vWaitName)</div><div class='vital-sub'>$(Fmt-Pct $vWaitPct)% of waits</div></div>"
    $html += "<div class='vital-card $tlogCls'><div class='vital-label'>T-Log Pressure</div><div class='vital-val'>$tlogDisp</div><div class='vital-sub'>$tlogSub</div></div>"
    $html += "<div class='vital-card $tempCls'><div class='vital-label'>TempDB</div><div class='vital-val'>$tempDisp</div><div class='vital-sub'>worst file used %</div></div>"
    $html += "</div></details>"
    $vMissingHigh = @($missingIdx | Where-Object { ($_.impact_score -as [double]) -gt 100000 }).Count
    $vMissingAll  = $missingIdx.Count
    $missCls  = if ($vMissingHigh -gt 5) { 'v-crit' } elseif ($vMissingHigh -gt 0) { 'v-warn' } elseif ($vMissingAll -gt 0) { 'v-blue' } else { 'v-ok' }
    $missDisp = if ($vMissingAll -eq 0) { '—' } else { $vMissingAll }
    $missSub  = if ($vMissingHigh -gt 0) { "$vMissingHigh high-impact" } elseif ($vMissingAll -gt 0) { 'low impact only' } else { 'none detected' }

    $html += "<details class='rv-section' open><summary>Keeping up</summary><div class='vital-grid'>"
    $html += "<div class='vital-card $bkpCls'><div class='vital-label'>Oldest Backup</div><div class='vital-val'>$bkpDisp</div><div class='vital-sub'>worst full backup age</div></div>"
    $html += "<div class='vital-card $chkCls'><div class='vital-label'>DBCC CHECKDB</div><div class='vital-val'>$chkDisp</div><div class='vital-sub'>worst days since check</div></div>"
    $html += "<div class='vital-card $diskCls'><div class='vital-label'>Disk (worst)</div><div class='vital-val'>$diskDisp</div><div class='vital-sub'>$diskSub</div></div>"
    $html += "<div class='vital-card $missCls'><div class='vital-label'>Missing Indexes</div><div class='vital-val'>$missDisp</div><div class='vital-sub'>$missSub</div></div>"
    $html += "</div></details>"

    # ── findings ────────────────────────────────────────────────────────────────
    $critN = @($findings | Where-Object Severity -eq 'CRITICAL').Count
    $warnN = @($findings | Where-Object Severity -eq 'WARNING').Count
    $infoN = @($findings | Where-Object Severity -eq 'INFO').Count
    $sevPills = ''
    if ($critN -gt 0) { $sevPills += "<button class='sev-filter-btn s-crit' data-sev='crit' onclick='filterFindings(this)'>$critN Critical</button>" }
    if ($warnN -gt 0) { $sevPills += "<button class='sev-filter-btn s-warn' data-sev='warn' onclick='filterFindings(this)'>$warnN Warning</button>" }
    if ($infoN -gt 0) { $sevPills += "<button class='sev-filter-btn s-info' data-sev='info' onclick='filterFindings(this)'>$infoN Info</button>" }
    if ($findings.Count -eq 0) { $sevPills = "<span class='sev-chip s-ok'>All clear</span>" }
    $html += "<hr class='section-sep'><details class='rv-section' open><summary>Findings <span class='find-pills'>$sevPills</span></summary>"
    if ($findings.Count -eq 0) {
        $html += "<p class='no-data'>No findings — all checked thresholds look healthy.</p>"
    } else {
        $ord = @{ CRITICAL=0; WARNING=1; INFO=2 }
        $html += "<div class='findings-list'>"
        foreach ($f in ($findings | Sort-Object { $ord[$_.Severity] }, Category, Subject)) {
            $rowCls = switch ($f.Severity) { 'CRITICAL' {'f-crit'} 'WARNING' {'f-warn'} default {'f-info'} }
            $tagCls = switch ($f.Severity) { 'CRITICAL' {'sv sv-red'} 'WARNING' {'sv sv-orange'} default {'sv sv-blue'} }
            $html += "<div class='finding-row $rowCls'><span class='$tagCls'>$($f.Severity)</span><span class='find-cat'>$(Html-Escape $f.Category)</span><span class='find-subj'>$(Html-Escape $f.Subject)</span><div class='find-detail'>$(Html-Escape $f.Detail)</div></div>"
        }
        $html += "</div>"
    }
    $html += "</details>"

    # ── active sessions ─────────────────────────────────────────────────────────
    if ($sessions.Count -gt 0) {
        $blkCount = $blkSess.Count
        $runCount = @($sessions | Where-Object { $_.status -eq 'running' }).Count
        $html += "<hr class='section-sep'><details class='rv-section' open><summary>Active Sessions ($($sessions.Count))</summary>"
        $html += "<div class='info-card-grid'>"
        $html += "<div class='info-card'><div class='info-label'>Total connected</div><div class='info-val'>$($sessions.Count)</div></div>"
        $html += "<div class='info-card'><div class='info-label'>Blocked</div><div class='info-val'>$(if ($blkCount -gt 0) { "<span class='sv sv-red'>$blkCount</span>" } else { "<span class='sv sv-green'>0</span>" })</div></div>"
        $html += "<div class='info-card'><div class='info-label'>Running requests</div><div class='info-val'>$runCount</div></div>"
        $html += "<div class='info-card'><div class='info-label'>Open transactions</div><div class='info-val'>$($openTxSess.Count)</div></div>"
        $html += "</div>"
        $cols = @('session_id','login_name','database_name','status','blocking_session_id','open_transaction_count','command','wait_type')
        $avail = @($cols | Where-Object { $sessions[0].PSObject.Properties[$_] })
        if ($avail.Count -gt 0) {
            $html += "<div class='table-wrap'><table><thead><tr>"
            foreach ($c in $avail) { $html += "<th>$c</th>" }
            $html += "</tr></thead><tbody>"
            foreach ($s in ($sessions | Sort-Object { [int]($_.session_id -as [int]) })) {
                $html += "<tr>"
                foreach ($c in $avail) {
                    $v = if ($null -ne $s.$c) { $s.$c } else { '' }
                    if ($c -eq 'blocking_session_id') {
                        $n=0; $html += if ($v -and [int]::TryParse($v,[ref]$n) -and $n -gt 0) { "<td><span class='sv sv-red'>$v</span></td>" } else { "<td><span class='null-val'>—</span></td>" }
                    } elseif ($c -eq 'status') {
                        $sCls = switch ($v) { 'running'{'sv sv-green'} 'sleeping'{'sv sv-gray'} default{''} }
                        $html += if ($sCls) { "<td><span class='$sCls'>$v</span></td>" } else { "<td>$v</td>" }
                    } else { $html += "<td>$(Html-Escape $v)</td>" }
                }
                $html += "</tr>"
            }
            $html += "</tbody></table></div>"
        }
        $html += "</details>"
    }

    # ── databases ──────────────────────────────────────────────────────────────
    if ($dbHealth.Count -gt 0) {
        $html += "<hr class='section-sep'><details class='rv-section' open><summary>Databases ($($dbHealth.Count))</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>State</th><th>Recovery</th><th>Auto-Shrink</th><th>Auto-Close</th></tr></thead><tbody>"
        foreach ($db in ($dbHealth | Sort-Object database_name)) {
            $stCls  = if ($db.state_desc -ne 'ONLINE') { 'sv sv-red' } else { 'sv sv-green' }
            $shCls  = if ($db.is_auto_shrink_on -in @('True','1','YES')) { 'sv sv-orange' } else { 'sv sv-green' }
            $clCls  = if ($db.is_auto_close_on  -in @('True','1','YES')) { 'sv sv-orange' } else { 'sv sv-green' }
            $shTxt  = if ($db.is_auto_shrink_on -in @('True','1','YES')) { 'ON' } else { 'OFF' }
            $clTxt  = if ($db.is_auto_close_on  -in @('True','1','YES')) { 'ON' } else { 'OFF' }
            $html += "<tr><td>$(Html-Escape $db.database_name)</td><td><span class='$stCls'>$($db.state_desc)</span></td><td>$($db.recovery_model_desc)</td><td><span class='$shCls'>$shTxt</span></td><td><span class='$clCls'>$clTxt</span></td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── backup status ───────────────────────────────────────────────────────────
    if ($backups.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Backup Status</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Recovery</th><th>Last Full</th><th>Full Age (h)</th><th>Last Log</th><th>Log Age (h)</th></tr></thead><tbody>"
        foreach ($b in ($backups | Sort-Object database_name)) {
            $fh=0.0; [double]::TryParse($b.full_backup_age_hours,[ref]$fh) | Out-Null
            $lh=0.0; [double]::TryParse($b.log_backup_age_hours, [ref]$lh) | Out-Null
            $fCls = if ((-not $b.last_full_backup -or $b.last_full_backup -eq '') -or $fh -gt 24) { 'sv sv-red' } else { 'sv sv-green' }
            $fDisp = if (-not $b.last_full_backup -or $b.last_full_backup -eq '') { '<span class="sv sv-red">NONE</span>' } else { Html-Escape $b.last_full_backup }
            if ($b.recovery_model_desc -eq 'SIMPLE') {
                $lDisp = '<span class="null-val">—</span>'; $lhDisp = '<span class="null-val">—</span>'
            } else {
                $lDisp  = if (-not $b.last_log_backup -or $b.last_log_backup -eq '') { '<span class="sv sv-red">NONE</span>' } else { Html-Escape $b.last_log_backup }
                $lhCls  = if (-not $b.last_log_backup -or $b.last_log_backup -eq '' -or $lh -gt 4) { 'sv sv-orange' } else { 'sv sv-green' }
                $lhDisp = "<span class='$lhCls'>$([Math]::Round($lh,1))</span>"
            }
            $html += "<tr><td>$(Html-Escape $b.database_name)</td><td>$($b.recovery_model_desc)</td><td>$fDisp</td><td><span class='$fCls'>$([Math]::Round($fh,1))</span></td><td>$lDisp</td><td>$lhDisp</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── transaction log usage ──────────────────────────────────────────────────
    if ($tlogs.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Transaction Log Usage</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Recovery</th><th>Log Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($t in ($tlogs | Sort-Object { [double]($_.log_used_pct -as [double]) } -Descending)) {
            $lp = [double]($t.log_used_pct -as [double])
            $lpCls = if ($lp -gt 80) { 'sv sv-red' } elseif ($lp -gt 50) { 'sv sv-orange' } else { 'sv sv-green' }
            $html += "<tr><td>$(Html-Escape $t.database_name)</td><td>$($t.recovery_model_desc)</td><td>$(Fmt-Mb $t.log_size_mb)</td><td>$(Fmt-Mb $t.log_used_mb)</td><td>$(Fmt-Mb $t.log_free_mb)</td><td><span class='$lpCls'>$(Fmt-Pct $lp)%</span></td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── wait statistics ─────────────────────────────────────────────────────────
    if ($waits.Count -gt 0) {
        $topWaits = @($waits | Sort-Object { [double]($_.pct_total_wait -as [double]) } -Descending | Select-Object -First 12)
        $html += "<hr class='section-sep'><details class='rv-section' open><summary>Top Wait Types</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Wait Type</th><th>Total Wait (ms)</th><th>Avg Wait (ms)</th><th>Count</th><th>% of Total</th></tr></thead><tbody>"
        foreach ($w in $topWaits) {
            $pct=0.0; [double]::TryParse($w.pct_total_wait,[ref]$pct) | Out-Null
            $concern = $cWaits.ContainsKey($w.wait_type)
            $wCls = if ($concern -and $pct -gt 10) { 'sv sv-orange' } elseif ($concern) { 'sv sv-blue' } else { '' }
            $wDisp = if ($wCls) { "<span class='$wCls'>$(Html-Escape $w.wait_type)</span>" } else { Html-Escape $w.wait_type }
            $bar = "<span class='mini-bar-track'><span class='mini-bar-fill $(if ($pct -gt 10 -and $concern) { 'bar-warn' } elseif ($pct -gt 30) { 'bar-crit' } else { 'bar-ok' })' style='width:$([Math]::Min($pct*2,100))%'></span></span>"
            $html += "<tr><td>$wDisp</td><td>$($w.total_wait_ms)</td><td>$($w.avg_wait_ms)</td><td>$($w.waiting_tasks_count)</td><td>$([Math]::Round($pct,1))% $bar</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── tempdb usage ───────────────────────────────────────────────────────────
    if ($tempdb.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>TempDB File Usage</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>File</th><th>Type</th><th>Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>User Obj (MB)</th><th>Version Store (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($tf in ($tempdb | Sort-Object { [double]($_.pct_used -as [double]) } -Descending)) {
            $tp = [double]($tf.pct_used -as [double])
            $tpCls = if ($tp -gt 80) { 'sv sv-red' } elseif ($tp -gt 60) { 'sv sv-orange' } else { 'sv sv-green' }
            $html += "<tr><td>$(Html-Escape $tf.logical_name)</td><td>$($tf.file_type)</td><td>$(Fmt-Mb $tf.size_mb)</td><td>$(Fmt-Mb $tf.used_mb)</td><td>$(Fmt-Mb $tf.free_mb)</td><td>$(Fmt-Mb $tf.user_objects_mb)</td><td>$(Fmt-Mb $tf.version_store_mb)</td><td><span class='$tpCls'>$(Fmt-Pct $tp)%</span></td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── job failures ───────────────────────────────────────────────────────────
    if ($jobs.Count -gt 0) {
        $html += "<hr class='section-sep'><details class='rv-section' open><summary>Job Failures — Last 7 Days ($($jobs.Count) rows)</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Job</th><th>Step</th><th>Run Time</th><th>Duration</th><th>Message</th></tr></thead><tbody>"
        foreach ($j in $jobs) {
            $msgShort = if ($j.message.Length -gt 200) { $j.message.Substring(0,200) + '…' } else { $j.message }
            $html += "<tr><td>$(Html-Escape $j.job_name)</td><td>$(Html-Escape $j.step_name)</td><td>$(($j.run_datetime -replace '\.\d+$',''))</td><td>$(Html-Escape $j.run_duration)</td><td style='font-size:.75rem;color:#8b949e'>$(Html-Escape $msgShort)</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── DBCC CHECKDB ───────────────────────────────────────────────────────────
    if ($checkdb.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>DBCC CHECKDB</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Last Good CHECKDB</th><th>Days Ago</th><th>Status</th></tr></thead><tbody>"
        foreach ($c in ($checkdb | Sort-Object { [int]($_.days_since_checkdb -as [int]) } -Descending)) {
            $days = $c.days_since_checkdb -as [int]
            $dayCls = if ($null -eq $days -or -not $c.last_good_checkdb -or $c.last_good_checkdb -eq '') { 'sv sv-red' } `
                      elseif ($days -gt 14) { 'sv sv-red' } elseif ($days -gt 7) { 'sv sv-orange' } else { 'sv sv-green' }
            $daysDisp = if ($null -eq $days) { '—' } else { $days }
            $lastDisp = if (-not $c.last_good_checkdb -or $c.last_good_checkdb -eq '') { '<span class="sv sv-red">NEVER</span>' } `
                        else { Html-Escape ($c.last_good_checkdb -replace '\.\d+$','') }
            $html += "<tr><td>$(Html-Escape $c.database_name)</td><td>$lastDisp</td><td><span class='$dayCls'>$daysDisp</span></td><td>$(Html-Escape $c.checkdb_status)</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── suspect pages ──────────────────────────────────────────────────────────
    if ($suspects.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Suspect Pages ($($suspects.Count))</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>File</th><th>Page</th><th>Event Type</th><th>Error Count</th><th>Last Update</th></tr></thead><tbody>"
        foreach ($sp in $suspects) {
            $evCls = if ($sp.event_type -match 'Restored|Repaired|Deallocated') { 'sv sv-gray' } else { 'sv sv-red' }
            $html += "<tr><td>$(Html-Escape $sp.database_name)</td><td>$($sp.file_id)</td><td>$($sp.page_id)</td><td><span class='$evCls'>$(Html-Escape $sp.event_type)</span></td><td>$($sp.error_count)</td><td>$(($sp.last_update_date -replace '\.\d+$',''))</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── I/O stats ──────────────────────────────────────────────────────────────
    if ($ioStats.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>I/O Usage (since SQL Server restart)</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>MB Read</th><th>MB Written</th><th>Read Stall (ms)</th><th>Read Stall %</th><th>Write Stall (ms)</th><th>Write Stall %</th></tr></thead><tbody>"
        foreach ($io in ($ioStats | Sort-Object { [double]($_.pct_total_write_stall -as [double]) } -Descending)) {
            $rStall = [double]($io.pct_total_read_stall  -as [double])
            $wStall = [double]($io.pct_total_write_stall -as [double])
            $rCls = if ($rStall -gt 20) { 'sv sv-orange' } else { '' }
            $wCls = if ($wStall -gt 20) { 'sv sv-orange' } else { '' }
            $rDisp = if ($rCls) { "<span class='$rCls'>$(Fmt-Pct $rStall)%</span>" } else { "$(Fmt-Pct $rStall)%" }
            $wDisp = if ($wCls) { "<span class='$wCls'>$(Fmt-Pct $wStall)%</span>" } else { "$(Fmt-Pct $wStall)%" }
            $html += "<tr><td>$(Html-Escape $io.database_name)</td><td>$(Fmt-Mb $io.total_mb_read)</td><td>$(Fmt-Mb $io.total_mb_written)</td><td>$(Fmt-Mb $io.total_read_stall_ms)</td><td>$rDisp</td><td>$(Fmt-Mb $io.total_write_stall_ms)</td><td>$wDisp</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── missing indexes ────────────────────────────────────────────────────────
    if ($missingIdx.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Missing Index Candidates ($($missingIdx.Count))</summary>"
        $html += "<p class='no-data' style='margin-bottom:12px'>Impact scores reset on SQL Server restart. Review carefully — creating every suggestion causes index bloat and write overhead.</p>"
        $html += "<div class='table-wrap'><table><thead><tr><th>Table</th><th>Impact Score</th><th>Improvement %</th><th>Seeks</th><th>Equality Cols</th><th>Inequality Cols</th><th>Include Cols</th><th>Suggested Statement</th></tr></thead><tbody>"
        foreach ($ix in ($missingIdx | Sort-Object { [double]($_.impact_score -as [double]) } -Descending)) {
            $imp  = [double]($ix.impact_score -as [double])
            $impCls = if ($imp -gt 100000) { 'sv sv-orange' } else { '' }
            $impDisp = if ($impCls) { "<span class='$impCls'>$([Math]::Round($imp,0).ToString('N0'))</span>" } else { [Math]::Round($imp,0).ToString('N0') }
            $stmtShort = if ($ix.suggested_statement.Length -gt 80) { $ix.suggested_statement.Substring(0,80) + '…' } else { $ix.suggested_statement }
            $html += "<tr><td>$(Html-Escape $ix.table_name)</td><td>$impDisp</td><td>$(Fmt-Pct ($ix.avg_improvement_pct -as [double]))%</td><td>$($ix.user_seeks)</td><td style='font-size:.75rem'>$(Html-Escape $ix.equality_columns)</td><td style='font-size:.75rem'>$(Html-Escape $ix.inequality_columns)</td><td style='font-size:.75rem'>$(Html-Escape $ix.included_columns)</td><td><code style='font-size:.7rem;color:#8b949e;word-break:break-all'>$(Html-Escape $stmtShort)</code></td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── security — weak logins ──────────────────────────────────────────────────
    if ($logins.Count -gt 0) {
        $html += "<hr class='section-sep'><details class='rv-section' open><summary>Login Security</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Login</th><th>Risk</th><th>Locked</th><th>Must Change Pwd</th><th>Password Last Set</th></tr></thead><tbody>"
        foreach ($l in ($logins | Sort-Object risk_flag, login_name)) {
            $rCls = switch ($l.risk_flag) {
                'SA_ENABLED'   { 'sv sv-red'    }
                'OK'           { 'sv sv-green'  }
                default        { 'sv sv-orange' }
            }
            $lkCls = if ($l.is_locked   -in @('1','True','true')) { 'sv sv-orange' } else { 'sv sv-green' }
            $mcCls = if ($l.must_change_password -in @('1','True','true')) { 'sv sv-orange' } else { 'sv sv-green' }
            $pwdDisp = if ($l.password_last_set -and $l.password_last_set -ne '') { $l.password_last_set -replace '\.\d+$','' } else { '—' }
            $html += "<tr><td>$(Html-Escape $l.login_name)</td><td><span class='$rCls'>$(Html-Escape $l.risk_flag)</span></td><td><span class='$lkCls'>$($l.is_locked)</span></td><td><span class='$mcCls'>$($l.must_change_password)</span></td><td>$pwdDisp</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    # ── failed logins ──────────────────────────────────────────────────────────
    if ($failedLogins.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Failed Logins ($($failedLogins.Count))</summary>"
        $html += "<p class='no-data' style='margin-bottom:12px;font-size:.8rem'>From current error log (xp_readerrorlog). Resets on SQL Server restart or when the error log cycles.</p>"
        $html += "<div class='table-wrap'><table><thead><tr><th>Login</th><th>Client</th><th>Failures</th><th>Error</th><th>First Seen</th><th>Last Seen</th><th>Locked</th><th>Status</th></tr></thead><tbody>"
        foreach ($fl in ($failedLogins | Sort-Object { [int]($_.failure_count -as [int]) } -Descending)) {
            $stCls = switch -Wildcard ($fl.status) {
                'CRITICAL*' { 'sv sv-red'    }
                'WARN*'     { 'sv sv-orange' }
                default     { 'sv sv-blue'   }
            }
            $lockedDisp = if ($fl.is_currently_locked -in @('1','True','true')) {
                "<span class='sv sv-red'>YES</span>"
            } elseif ($fl.is_currently_locked -in @('0','False','false')) {
                "<span class='sv sv-green'>no</span>"
            } else { '<span class="null-val">—</span>' }
            $stShort = $fl.status -replace '^(CRITICAL|WARN|INFO) — ',''
            $clientHost = if ($null -ne $fl.client_host) { $fl.client_host } else { '—' }
            $html += "<tr>"
            $html += "<td>$(Html-Escape $fl.login_name)</td>"
            $html += "<td style='font-size:.75rem'>$(Html-Escape $clientHost)</td>"
            $html += "<td><strong>$($fl.failure_count)</strong></td>"
            $html += "<td style='font-size:.75rem'>$(Html-Escape $fl.error_description)</td>"
            $html += "<td style='white-space:nowrap;font-size:.75rem'>$(($fl.first_failure_approx -replace '\.\d+$',''))</td>"
            $html += "<td style='white-space:nowrap;font-size:.75rem'>$(($fl.last_failure_approx -replace '\.\d+$',''))</td>"
            $html += "<td>$lockedDisp</td>"
            $html += "<td><span class='$stCls'>$(Html-Escape $stShort)</span></td>"
            $html += "</tr>"
        }
        $html += "</tbody></table></div></details>"
    } elseif ($failedLogins.Count -eq 0 -and (Test-Path (Join-Path $folder 'failed-logins.csv'))) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Failed Logins</summary><p class='no-data'>No failed login attempts in the current error log.</p></details>"
    }

    # ── error log ──────────────────────────────────────────────────────────────
    if ($errors.Count -gt 0) {
        $html += "<hr class='mini-sep'><details class='rv-section' open><summary>Error Log — Last 24h ($($errors.Count) entries)</summary><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Time</th><th>Source</th><th>Message</th></tr></thead><tbody>"
        foreach ($e in $errors) {
            $msgShort = if ($e.log_text.Length -gt 300) { $e.log_text.Substring(0,300) + '…' } else { $e.log_text }
            $html += "<tr><td style='white-space:nowrap'>$(($e.log_date -replace '\.\d+$',''))</td><td>$(Html-Escape $e.process_info)</td><td style='font-size:.75rem'>$(Html-Escape $msgShort)</td></tr>"
        }
        $html += "</tbody></table></div></details>"
    }

    $html += "<script>
function filterFindings(btn){
  var sev=btn.getAttribute('data-sev');
  var isActive=btn.classList.contains('active');
  document.querySelectorAll('.sev-filter-btn').forEach(function(b){b.classList.remove('active')});
  document.querySelectorAll('.finding-row').forEach(function(r){r.style.display=''});
  if(!isActive){
    btn.classList.add('active');
    document.querySelectorAll('.finding-row').forEach(function(r){
      if(!r.classList.contains('f-'+sev))r.style.display='none';
    });
  }
}
</script>"
    Wrap-Page 'Health Check' $html '' 'review'
}

# ── drill-down table (Stage 3): section → sortable table → row detail + fix ────

function Build-DrillTable {
    param(
        [string]$Id,
        [string]$Title,
        [object[]]$Rows,
        [string[]]$Cols,
        [scriptblock]$Remedy,             # optional: param($row) → suggested T-SQL / action text
        [string]$EmptyNote = 'Nothing found — clean.',
        [switch]$Open
    )
    $openAttr = if ($Open) { ' open' } else { '' }
    $Rows = @($Rows | Where-Object { $null -ne $_ })   # empty CSVs arrive as $null; @($null).Count is 1
    $n   = $Rows.Count
    $out = "<details class='rv-section' id='$Id'$openAttr><summary>$Title ($n)</summary>"
    if ($n -eq 0) { return $out + "<p class='no-data'>$EmptyNote</p></details>" }
    if (-not $Cols) { $Cols = @($Rows[0].PSObject.Properties.Name | Select-Object -First 6) }
    $out += "<p class='no-data' style='margin:2px 0 8px;font-size:.74rem'>Click a row for full detail and the suggested action.</p>"
    $out += "<div class='table-wrap'><table><thead><tr>"
    foreach ($c in $Cols) { $out += "<th>$(Html-Escape (($c -replace '_',' ')))</th>" }
    $out += "</tr></thead><tbody>"
    foreach ($r in $Rows) {
        $out += "<tr class='drill-row' onclick='toggleDetail(this)'>"
        foreach ($c in $Cols) { $out += "<td>$(Html-Escape ([string]$r.$c))</td>" }
        $out += "</tr>"
        $detail = "<div class='rd-grid'>"
        foreach ($p in $r.PSObject.Properties) {
            $detail += "<div><span class='rd-k'>$(Html-Escape ($p.Name -replace '_',' '))</span><span class='rd-v'>$(Html-Escape ([string]$p.Value))</span></div>"
        }
        $detail += "</div>"
        if ($Remedy) {
            $fix = try { & $Remedy $r } catch { $null }
            if ($fix) { $detail += "<div class='rd-fix-label'>Suggested action</div><pre class='rd-fix'>$(Html-Escape $fix)</pre>" }
        }
        $out += "<tr class='row-detail' style='display:none'><td colspan='$($Cols.Count)'>$detail</td></tr>"
    }
    $out + "</tbody></table></div></details>"
}

# Shared JS for drill-down pages (emit once per page that uses Build-DrillTable)
$script:DrillJs = @"
<script>
function toggleDetail(tr){var d=tr.nextElementSibling;if(d&&d.classList.contains('row-detail')){d.style.display=(d.style.display==='none')?'':'none';}}
function drillTo(id){var d=document.getElementById(id);if(d){d.open=true;d.scrollIntoView({behavior:'smooth',block:'start'});}}
</script>
"@

# ── security review page ────────────────────────────────────────────────────────

function Build-SecurityScripts([object[]]$scripts) {
    if (-not $scripts -or $scripts.Count -eq 0) { return '' }
    $out  = "<hr class='section-sep'><details class='rv-section' open><summary>Security Scripts ($($scripts.Count))</summary>"
    $out += "<div class='run-bar' style='margin-bottom:12px'>"
    $out += "<label>Server:</label>"
    $defaultSrv2 = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint2    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $out += "<input id='sec-srv' class='server-input' placeholder='$srvHint2' value='$defaultSrv2' autocomplete='off'>"
    $out += "</div>"
    $out += "<div id='sec-run-err' class='run-error' style='display:none;margin-bottom:8px'></div>"
    $out += "<div class='grid'>"
    foreach ($s in $scripts) {
        $relEnc = [Uri]::EscapeDataString($s.RelPath)
        $purposeText = if ($null -ne $s.Purpose) { $s.Purpose } else { '' }
        $purpose = Html-Escape $purposeText
        $safeTag = if ($s.Safety) { " <span class='sv sv-green'>$(Html-Escape $s.Safety)</span>" } else { '' }
        $out += "<div class='card'>"
        $out += "<div style='display:flex;justify-content:space-between;align-items:flex-start;gap:6px'>"
        $out += "<a href='/view?p=$relEnc' style='flex:1'>$(Html-Escape $s.Name)</a>$safeTag"
        $out += "</div>"
        $out += "<div class='purpose'>$purpose</div>"
        $out += "<div style='margin-top:8px;display:flex;gap:6px'>"
        $out += "<button class='run-btn' style='font-size:.75rem;padding:3px 10px' onclick='runSecScript(`"$relEnc`",false)'>Run &#9654;</button>"
        $out += "</div></div>"
    }
    $out += "</div></details>"
    $out += "<script>
async function runSecScript(path,dryrun){
  const srv=document.getElementById('sec-srv').value.trim()||'.';
  const err=document.getElementById('sec-run-err');
  err.style.display='none';
  try{
    const r=await fetch('/api/run?p='+path+'&server='+encodeURIComponent(srv)+'&dryrun='+(dryrun?'1':'0'));
    const d=await r.json();
    if(d.ok){window.location.href=d.url;return;}
    err.textContent=d.error||'Unknown error';err.style.display='';
  }catch(e){err.textContent='Request failed: '+e.message;err.style.display='';}
}
</script>"
    return $out
}

function Build-SecurityPage([string]$folder) {
    $folder = Resolve-HcFolder $folder
    $html   = Build-DataStrip $folder 'security'

    $secScripts = @(Get-AllScriptsCached | Where-Object { $_.Type -eq 'SQL' -and $_.Category -eq 'security' } | Sort-Object Name)

    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
        $html += "<p class='no-data'>No healthcheck folder found. Run the health check first to see security findings.</p>"
        $html += Build-SecurityScripts $secScripts
        return Wrap-Page 'Security' $html '' 'security'
    }

    function Read-SecCsv([string]$name) {
        $p = Join-Path $folder "$name.csv"
        if (Test-Path -LiteralPath $p) { @(Import-Csv -LiteralPath $p -EA SilentlyContinue) } else { @() }
    }

    $logins       = Read-SecCsv 'weak-logins'
    $failedLogins = Read-SecCsv 'failed-logins'
    $surfaceArea  = Read-SecCsv 'security-surface-area'
    $svrInfo      = Read-SecCsv 'server-info'
    $sysadmins    = Read-SecCsv 'sysadmin-members'
    $orphans      = Read-SecCsv 'orphaned-users'
    $certs        = Read-SecCsv 'certificate-expiry'
    $linkedSec    = Read-SecCsv 'linked-server-security'

    # ── meta bar ────────────────────────────────────────────────────────────────
    $folderLeaf  = Split-Path -Leaf $folder
    $collectedAt = ''
    if ($folderLeaf -match '(\d{8}-\d{6})$') {
        try { $collectedAt = ([DateTime]::ParseExact($Matches[1],'yyyyMMdd-HHmmss',$null)).ToString('yyyy-MM-dd HH:mm') } catch {}
    }
    $svrName = if ($svrInfo -and $svrInfo[0].PSObject.Properties['server_name']) { $svrInfo[0].server_name } `
               else { $folderLeaf -replace '-\d{8}-\d{6}$','' }
    $html += "<div class='hc-meta'>"
    $html += "<span><strong>Server</strong> $(Html-Escape $svrName)</span>"
    if ($collectedAt) { $html += "<span><strong>Collected</strong> $collectedAt</span>" }
    $html += "<span><strong>Reviewed</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm')</span>"
    $html += "</div>"

    # ── surface area vitals ──────────────────────────────────────────────────────
    $xpRow      = $surfaceArea | Where-Object { $_.name -eq 'xp_cmdshell' }         | Select-Object -First 1
    $clrRow     = $surfaceArea | Where-Object { $_.name -eq 'clr enabled' }          | Select-Object -First 1
    $clrStrRow  = $surfaceArea | Where-Object { $_.name -eq 'clr strict security' }  | Select-Object -First 1
    $encRow     = $surfaceArea | Where-Object { $_.name -eq 'force encryption' }      | Select-Object -First 1
    $ntlmRow    = $surfaceArea | Where-Object { $_.name -eq 'ntlm connections' }      | Select-Object -First 1

    $xpEnabled  = $xpRow     -and $xpRow.running_value     -in @('1','True','true')
    $clrEnabled = $clrRow    -and $clrRow.running_value    -in @('1','True','true')
    $clrStrict  = $clrStrRow -and $clrStrRow.running_value -in @('1','True','true')
    $forceEnc   = $encRow    -and $encRow.running_value    -in @('1','True','true')
    $ntlmCount  = [int]($ntlmRow.running_value -as [int])

    $saLoginRow = $logins | Where-Object { $_.risk_flag -eq 'SA_ENABLED' } | Select-Object -First 1
    $saEnabled  = $null -ne $saLoginRow
    $weakCount  = @($logins | Where-Object { $_.risk_flag -ne 'OK' }).Count
    $lockedCount = @($failedLogins | Where-Object { $_.is_currently_locked -in @('1','True','true') }).Count
    $bruteCount  = @($failedLogins | Where-Object { $_.status -like 'CRITICAL*' }).Count

    # weak-policy logins that are also sysadmins — the cross-reference that matters
    $weakNames        = @($logins | Where-Object { $_.risk_flag -ne 'OK' } | ForEach-Object { $_.login_name })
    $weakSysadmins    = @($sysadmins | Where-Object { $weakNames -contains $_.login_name })
    $certWarnCount    = @($certs).Count
    $failedTotal      = @($failedLogins).Count

    # one-line verdict first — SA and xp_cmdshell are the two things a DBA checks before anything else
    $secBits  = @()
    $secBits += if ($saEnabled)  { "SA <span class='sv sv-red'>ENABLED</span>" }  else { "SA <span class='sv sv-green'>disabled</span>" }
    $secBits += if ($xpEnabled)  { "xp_cmdshell <span class='sv sv-red'>ENABLED</span>" } else { "xp_cmdshell <span class='sv sv-green'>off</span>" }
    $secBits += "<b>$(@($sysadmins).Count)</b> sysadmin$(if (@($sysadmins).Count -ne 1) {'s'})$(if ($weakSysadmins.Count -gt 0) { " (<span class='sv sv-red'>$($weakSysadmins.Count) weak</span>)" })"
    $secBits += if ($weakCount -gt 0)   { "<span class='sv sv-orange'>$weakCount weak login$(if ($weakCount -ne 1) {'s'})</span>" } else { 'no weak logins' }
    if ($lockedCount -gt 0)   { $secBits += "<span class='sv sv-red'>$lockedCount locked out</span>" }
    if ($certWarnCount -gt 0) { $secBits += "<span class='sv sv-orange'>$certWarnCount cert warning$(if ($certWarnCount -ne 1) {'s'})</span>" }
    $html += "<div class='disk-summary'>$($secBits -join ' &middot; ')</div>"

    if ($surfaceArea.Count -gt 0) {
        $html += "<details class='rv-section' open><summary>Surface Area <span class='ds-dim' style='font-weight:400;font-size:.75rem'>— click a card to drill down</span></summary><div class='vital-grid'>"
        $xpCls  = if ($xpEnabled)                          { 'v-crit' } else { 'v-ok' }
        $html  += "<div class='vital-card $xpCls clickable' onclick=`"drillTo('sec-surface')`"><div class='vital-label'>xp_cmdshell</div><div class='vital-val'>$(if ($xpEnabled) {'ENABLED'} else {'Off'})</div><div class='vital-sub'>OS command execution</div></div>"
        $clrCls = if ($clrEnabled -and -not $clrStrict)   { 'v-warn' } elseif ($clrEnabled) { 'v-blue' } else { 'v-ok' }
        $clrSub = if ($clrEnabled -and -not $clrStrict)   { 'strict security OFF' } elseif ($clrEnabled) { 'strict security on' } else { 'not enabled' }
        $html  += "<div class='vital-card $clrCls clickable' onclick=`"drillTo('sec-surface')`"><div class='vital-label'>CLR</div><div class='vital-val'>$(if ($clrEnabled) {'Enabled'} else {'Off'})</div><div class='vital-sub'>$clrSub</div></div>"
        $encCls = if ($encRow -and -not $forceEnc)        { 'v-warn' } elseif ($forceEnc) { 'v-ok' } else { 'v-blue' }
        $encSub = if ($forceEnc)                           { 'all connections encrypted' } elseif ($encRow) { 'unencrypted allowed' } else { 'data not collected' }
        $html  += "<div class='vital-card $encCls clickable' onclick=`"drillTo('sec-surface')`"><div class='vital-label'>Force Encryption</div><div class='vital-val'>$(if ($forceEnc) {'Enforced'} elseif ($encRow) {'Optional'} else {'—'})</div><div class='vital-sub'>$encSub</div></div>"
        $ntlmCls = if ($ntlmCount -gt 0)                  { 'v-warn' } else { 'v-ok' }
        $html   += "<div class='vital-card $ntlmCls clickable' onclick=`"drillTo('sec-surface')`"><div class='vital-label'>NTLM Connections</div><div class='vital-val'>$(if ($ntlmCount -gt 0) {$ntlmCount} else {'None'})</div><div class='vital-sub'>$(if ($ntlmCount -gt 0) {'NTLM sessions (prefer Kerberos)'} else {'no NTLM sessions'})</div></div>"
        $html  += "</div></details>"
    }

    $html += "<details class='rv-section' open><summary>Access Risk <span class='ds-dim' style='font-weight:400;font-size:.75rem'>— click a card to drill down</span></summary><div class='vital-grid'>"
    $saCls = if ($saEnabled) { 'v-crit' } else { 'v-ok' }
    $html += "<div class='vital-card $saCls clickable' onclick=`"drillTo('sec-weak')`"><div class='vital-label'>SA Login</div><div class='vital-val'>$(if ($saEnabled) {'ENABLED'} else {'Disabled'})</div><div class='vital-sub'>built-in sysadmin</div></div>"
    $sadCls = if ($weakSysadmins.Count -gt 0) { 'v-crit' } elseif (@($sysadmins).Count -gt 3) { 'v-warn' } else { 'v-blue' }
    $sadSub = if ($weakSysadmins.Count -gt 0) { "$($weakSysadmins.Count) with weak password settings" } else { 'server role members' }
    $html += "<div class='vital-card $sadCls clickable' onclick=`"drillTo('sec-sysadmin')`"><div class='vital-label'>Sysadmin Members</div><div class='vital-val'>$(@($sysadmins).Count)</div><div class='vital-sub'>$sadSub</div></div>"
    $wkCls = if ($weakCount -gt 5) { 'v-crit' } elseif ($weakCount -gt 0) { 'v-warn' } else { 'v-ok' }
    $html += "<div class='vital-card $wkCls clickable' onclick=`"drillTo('sec-weak')`"><div class='vital-label'>Weak Logins</div><div class='vital-val'>$(if ($weakCount -gt 0) {$weakCount} else {'Clean'})</div><div class='vital-sub'>$(if ($weakCount -gt 0) {'weak SQL logins'} else {'no weak logins'})</div></div>"
    $flCls = if ($lockedCount -gt 0 -or $bruteCount -gt 0) { 'v-crit' } elseif ($failedTotal -gt 0) { 'v-warn' } else { 'v-ok' }
    $html += "<div class='vital-card $flCls clickable' onclick=`"drillTo('sec-failed')`"><div class='vital-label'>Failed Logins</div><div class='vital-val'>$(if ($failedTotal -gt 0) {$failedTotal} else {'None'})</div><div class='vital-sub'>$(if ($lockedCount -gt 0) {"$lockedCount locked out"} elseif ($bruteCount -gt 0) {"$bruteCount brute-force pattern(s)"} elseif ($failedTotal -gt 0) {'logins with failures'} else {'error log clean'})</div></div>"
    $orCls = if (@($orphans).Count -gt 0) { 'v-warn' } else { 'v-ok' }
    $html += "<div class='vital-card $orCls clickable' onclick=`"drillTo('sec-orphaned')`"><div class='vital-label'>Orphaned Users</div><div class='vital-val'>$(if (@($orphans).Count -gt 0) {@($orphans).Count} else {'None'})</div><div class='vital-sub'>$(if (@($orphans).Count -gt 0) {'DB users with no login'} else {'all users mapped'})</div></div>"
    $ceCls = if ($certWarnCount -gt 0) { 'v-warn' } else { 'v-ok' }
    $html += "<div class='vital-card $ceCls clickable' onclick=`"drillTo('sec-certs')`"><div class='vital-label'>Cert Expiry</div><div class='vital-val'>$(if ($certWarnCount -gt 0) {$certWarnCount} else {'None'})</div><div class='vital-sub'>$(if ($certWarnCount -gt 0) {'certificates approaching expiry'} else {'no expiry warnings'})</div></div>"
    $html += "</div></details>"

    # ── findings ────────────────────────────────────────────────────────────────
    $findings = [System.Collections.Generic.List[PSObject]]::new()
    function Add-F([string]$Sev,[string]$Cat,[string]$Subj,[string]$Detail) {
        $findings.Add([PSCustomObject]@{ Severity=$Sev; Category=$Cat; Subject=$Subj; Detail=$Detail })
    }

    if ($saEnabled)  { Add-F 'CRITICAL' 'SA Login'     'sa'               'SA login is enabled — rename or disable to reduce attack surface' }
    if ($xpEnabled)  { Add-F 'CRITICAL' 'Surface Area' 'xp_cmdshell'      'xp_cmdshell enabled — allows arbitrary OS command execution from SQL' }
    if ($encRow -and -not $forceEnc) {
        Add-F 'WARNING' 'Encryption' 'force encryption' 'Force encryption disabled — connections may transmit data in plaintext'
    }
    if ($ntlmCount -gt 0) {
        Add-F 'WARNING' 'Authentication' 'NTLM connections' "$ntlmCount active session(s) using NTLM — configure Kerberos (SPN) for stronger auth"
    }
    if ($clrEnabled -and -not $clrStrict) {
        Add-F 'WARNING' 'Surface Area' 'CLR' 'CLR enabled without strict security — allows unsigned assemblies'
    }
    foreach ($login in $logins) {
        if (-not $login.risk_flag -or $login.risk_flag -eq 'OK') { continue }
        $sev    = if ($login.risk_flag -eq 'SA_ENABLED') { 'CRITICAL' } else { 'WARNING' }
        $detail = switch ($login.risk_flag) {
            'PASSWORD_POLICY_OFF' { 'Password policy not enforced' }
            'EXPIRATION_OFF'      { 'Password expiration disabled' }
            default               { "Risk flag: $($login.risk_flag)" }
        }
        Add-F $sev 'Login Settings' $login.login_name $detail
    }
    foreach ($row in $failedLogins) {
        $loginName = if ($null -ne $row.login_name) { $row.login_name } else { '(unknown)' }
        if ($row.is_currently_locked -in @('1','True','true')) {
            Add-F 'CRITICAL' 'Failed Logins' $loginName 'Login is currently locked out'
        }
        if ($row.status -like 'CRITICAL*') {
            Add-F 'CRITICAL' 'Failed Logins' $loginName "$($row.failure_count) failures — likely brute-force or app misconfiguration"
        } elseif ($row.status -like 'WARN*') {
            Add-F 'WARNING'  'Failed Logins' $loginName "$($row.failure_count) repeated failures in error log"
        }
    }

    $critN = @($findings | Where-Object Severity -eq 'CRITICAL').Count
    $warnN = @($findings | Where-Object Severity -eq 'WARNING').Count
    $sevPills = ''
    if ($critN -gt 0) { $sevPills += "<button class='sev-filter-btn s-crit' data-sev='crit' onclick='filterFindings(this)'>$critN Critical</button>" }
    if ($warnN -gt 0) { $sevPills += "<button class='sev-filter-btn s-warn' data-sev='warn' onclick='filterFindings(this)'>$warnN Warning</button>" }
    if ($findings.Count -eq 0) { $sevPills = "<span class='sev-chip s-ok'>All clear</span>" }

    $html += "<hr class='section-sep'><details class='rv-section' open><summary>Findings <span class='find-pills'>$sevPills</span></summary>"
    if ($findings.Count -eq 0) {
        $html += "<p class='no-data'>No security findings detected.</p>"
    } else {
        $ord = @{ CRITICAL=0; WARNING=1; INFO=2 }
        $html += "<div class='findings-list'>"
        foreach ($f in ($findings | Sort-Object { $ord[$_.Severity] }, Category, Subject)) {
            $rowCls = switch ($f.Severity) { 'CRITICAL' {'f-crit'} 'WARNING' {'f-warn'} default {'f-info'} }
            $tagCls = switch ($f.Severity) { 'CRITICAL' {'sv sv-red'} 'WARNING' {'sv sv-orange'} default {'sv sv-blue'} }
            $html  += "<div class='finding-row $rowCls'><span class='$tagCls'>$($f.Severity)</span><span class='find-cat'>$(Html-Escape $f.Category)</span><span class='find-subj'>$(Html-Escape $f.Subject)</span><div class='find-detail'>$(Html-Escape $f.Detail)</div></div>"
        }
        $html += "</div>"
    }
    $html += "</details><script>
function filterFindings(btn){
  var sev=btn.getAttribute('data-sev');
  var isActive=btn.classList.contains('active');
  document.querySelectorAll('.sev-filter-btn').forEach(function(b){b.classList.remove('active')});
  document.querySelectorAll('.finding-row').forEach(function(r){r.style.display=''});
  if(!isActive){btn.classList.add('active');document.querySelectorAll('.finding-row').forEach(function(r){if(!r.classList.contains('f-'+sev))r.style.display='none';});}
}
</script>"

    # ── Stage 3: drill-down sections (vital cards link here) ───────────────────
    $html += "<hr class='section-sep'>"

    $html += Build-DrillTable -Id 'sec-surface' -Title 'Surface Area Configuration' -Rows $surfaceArea `
        -Cols @('name','configured_value','running_value','description') -Remedy {
            param($r)
            switch ($r.name) {
                'xp_cmdshell'       { if ($r.running_value -in @('1','True','true')) { "EXEC sp_configure 'show advanced options', 1; RECONFIGURE;`nEXEC sp_configure 'xp_cmdshell', 0; RECONFIGURE;`n-- Verify nothing depends on it first: search Agent job steps and procs for xp_cmdshell." } }
                'clr enabled'       { if ($r.running_value -in @('1','True','true')) { "-- If CLR is required, keep strict security on:`nEXEC sp_configure 'clr strict security', 1; RECONFIGURE;" } }
                'force encryption'  { if ($r.running_value -notin @('1','True','true')) { "-- Enable via SQL Server Configuration Manager → Protocols → Force Encryption = Yes`n-- Requires a trusted certificate and a service restart. Test client connections first." } }
                'ntlm connections'  { if ([int]($r.running_value -as [int]) -gt 0) { "-- Prefer Kerberos: register SPNs for the service account, then verify:`n-- setspn -S MSSQLSvc/<fqdn>:1433 <domain>\<svcaccount>`nSELECT auth_scheme, COUNT(*) FROM sys.dm_exec_connections GROUP BY auth_scheme;" } }
                'Database Mail XPs' { if ($r.running_value -in @('1','True','true')) { "-- If Database Mail is unused:`nEXEC sp_configure 'Database Mail XPs', 0; RECONFIGURE;" } }
            }
        } -EmptyNote 'No surface-area data in this collection.'

    $html += Build-DrillTable -Id 'sec-sysadmin' -Title 'Sysadmin Members' -Rows $sysadmins -Remedy {
        param($r)
        $extra = if ($weakNames -contains $r.login_name) { "-- ⚠ This login also has weak password settings (see Weak Logins below).`n" } else { '' }
        "$extra-- Review whether this membership is still required; to remove:`nALTER SERVER ROLE [sysadmin] DROP MEMBER [$($r.login_name)];"
    } -EmptyNote 'No sysadmin membership data in this collection (needs the full healthcheck collection).'

    $html += Build-DrillTable -Id 'sec-weak' -Title 'Weak Login Settings' -Rows $logins `
        -Cols @('login_name','risk_flag','is_disabled','is_policy_checked','is_expiration_checked','password_last_set') -Remedy {
            param($r)
            switch ($r.risk_flag) {
                'SA_ENABLED'          { "ALTER LOGIN [sa] DISABLE;`n-- Use a named Windows admin instead; verify no application connects as sa first." }
                'PASSWORD_POLICY_OFF' { "ALTER LOGIN [$($r.login_name)] WITH CHECK_POLICY = ON;`n-- Note: may force a compliant password at next change; coordinate with the app owner." }
                'EXPIRATION_OFF'      { "ALTER LOGIN [$($r.login_name)] WITH CHECK_EXPIRATION = ON;`n-- Only where rotation is operationally possible (interactive users, not service accounts)." }
                default               { $null }
            }
        } -EmptyNote 'No weak login settings — clean.'

    $html += Build-DrillTable -Id 'sec-failed' -Title 'Failed Logins (current error log)' -Rows $failedLogins -Remedy {
        param($r)
        "-- Identify the source at $($r.client_host): app misconfiguration vs probing.`n-- If locked out and legitimate: ALTER LOGIN [$($r.login_name)] WITH PASSWORD = '<new>' UNLOCK;"
    } -EmptyNote 'No failed login attempts in the current error log.'

    $html += Build-DrillTable -Id 'sec-orphaned' -Title 'Orphaned Users' -Rows $orphans -Remedy {
        param($r)
        "USE [$($r.database_name)];`nALTER USER [$($r.user_name)] WITH LOGIN = [$($r.user_name)];  -- if the login exists`n-- or, if genuinely orphaned: DROP USER [$($r.user_name)];"
    } -EmptyNote 'No orphaned users — all database users map to a login.'

    $html += Build-DrillTable -Id 'sec-certs' -Title 'Certificate Expiry Warnings' -Rows $certs -Remedy {
        param($r)
        "-- Renew or rotate before expiry; confirm a backup exists:`n-- BACKUP CERTIFICATE [<name>] TO FILE = ... WITH PRIVATE KEY (...);`n-- TDE certs: an expired cert still works, but restores NEED the cert backup."
    } -EmptyNote 'No certificates approaching expiry.'

    if (@($linkedSec).Count -gt 0) {
        $html += Build-DrillTable -Id 'sec-linked' -Title 'Linked Server Security' -Rows $linkedSec -Remedy {
            param($r)
            "-- Avoid static sysadmin-mapped credentials on linked servers;`n-- map specific logins with least privilege (sp_addlinkedsrvlogin)."
        }
    }

    $html += $script:DrillJs

    $html += Build-SecurityScripts $secScripts
    Wrap-Page 'Security' $html '' 'security'
}

# ── disk dashboard ─────────────────────────────────────────────────────────────

function Build-DiskPage([string]$folder) {
    $folder = Resolve-HcFolder $folder
    $html   = Build-DataStrip $folder 'disk'

    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
        $html += "<p class='no-data'>No healthcheck folder found. Run <code>Invoke-HealthCheckCollection.ps1</code> first.</p>"
        return Wrap-Page 'Disk Space' $html '' 'disk'
    }

    function Read-DiskCsv([string]$name) {
        $p = Join-Path $folder "$name.csv"
        if (Test-Path -LiteralPath $p) { @(Import-Csv -LiteralPath $p -ErrorAction SilentlyContinue) }
        else { @() }
    }

    $drives     = @(Read-DiskCsv 'disk-space' | Group-Object volume_mount_point | ForEach-Object { $_.Group[0] })
    $dbSizes    = Read-DiskCsv 'database-sizes'
    $tlogs      = Read-DiskCsv 'tlog-usage'
    $growthRisk = Read-DiskCsv 'growth-risk'
    $dbFiles    = Read-DiskCsv 'database-files'

    # ── Volume space ─────────────────────────────────────────────────────────
    $html += "<h2>Volume Space</h2>"
    if (-not $drives) {
        $html += "<p class='no-data'>No <code>disk-space.csv</code> here — re-run healthcheck with the updated collection script to include volume data.</p>"
    } else {
        # summary line first — with 4-8 volumes (data/log/tempdb/backups/SAN) this is what a DBA scans for
        $worst    = $drives | Sort-Object { [double]($_.free_pct -as [double]) } | Select-Object -First 1
        $totGb    = [Math]::Round((@($drives | ForEach-Object { [double]($_.total_gb -as [double]) }) | Measure-Object -Sum).Sum, 1)
        $freeGb   = [Math]::Round((@($drives | ForEach-Object { [double]($_.free_gb  -as [double]) }) | Measure-Object -Sum).Sum, 1)
        $worstPct = Fmt-Pct ([double]($worst.free_pct -as [double]))
        $worstCls = if ([double]($worst.free_pct -as [double]) -lt 10) { 'sv sv-red' } elseif ([double]($worst.free_pct -as [double]) -lt 20) { 'sv sv-orange' } else { 'sv sv-green' }
        $html += "<div class='disk-summary'><b>$($drives.Count)</b> volume$(if ($drives.Count -ne 1) {'s'}) &middot; worst: <b>$(Html-Escape $worst.volume_mount_point)</b> <span class='$worstCls'>$worstPct% free</span> &middot; <b>$totGb GB</b> total / <b>$freeGb GB</b> free &middot; sorted worst-first</div>"
        $html += "<div class='disk-grid'>"
        foreach ($d in ($drives | Sort-Object { [double]($_.free_pct -as [double]) })) {
            $freePct = [double]($d.free_pct -as [double])
            $usedPct = [Math]::Round(100.0 - $freePct, 1)
            $cardCls = if ($freePct -lt 10) { 'crit' } elseif ($freePct -lt 20) { 'warn' } else { '' }
            $barCls  = if ($freePct -lt 10) { 'bar-crit' } elseif ($freePct -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $volName = if ($d.logical_volume_name -and $d.logical_volume_name.Trim() -ne '') {
                           Html-Escape $d.logical_volume_name } else { '' }
            $dColor = if ($freePct -lt 10) { '#f78166' } elseif ($freePct -lt 20) { '#ffa657' } else { '#58a6ff' }
            $html += @"
<div class='disk-card $cardCls'>
  <div class='disk-flex'>
    <div>
      <div class='donut' style='--p:$usedPct;--dc:$dColor' data-label='$(Fmt-Pct $usedPct)%'></div>
      <div class='donut-sub'>used</div>
    </div>
    <div style='flex:1;min-width:0'>
      <div class='disk-mount'>$(Html-Escape $d.volume_mount_point)</div>
      <div class='disk-vol'>$volName</div>
      <div class='disk-stats' style='flex-direction:column;align-items:flex-start;gap:2px'>
        <span><strong>$([Math]::Round(($d.total_gb -as [double]),2)) GB</strong> total</span>
        <span><strong>$([Math]::Round(($d.used_gb  -as [double]),2)) GB</strong> used</span>
        <span><strong>$([Math]::Round(($d.free_gb  -as [double]),2)) GB</strong> free ($(Fmt-Pct $freePct)%)</span>
      </div>
    </div>
  </div>
</div>
"@
        }
        $html += "</div>"
    }

    # ── Database file space ───────────────────────────────────────────────────
    $html += "<hr class='mini-sep'><h2>Database File Space</h2>"
    if (-not $dbSizes) {
        $html += "<p class='no-data'>No <code>database-sizes.csv</code> in this folder.</p>"
    } else {
        # Two lenses, two DBA questions — a linear MB chart can't answer either once one
        # multi-TB database shares an instance with many small ones:
        #   % used  — which databases are running out of internal free space (skew-proof, all DBs)
        #   top-N GB — which databases are big (capacity planning, absolute)
        $dbSorted = @($dbSizes | Sort-Object { [double]($_.data_size_mb -as [double]) + [double]($_.log_size_mb -as [double]) } -Descending)

        $pctRows = @($dbSizes | ForEach-Object {
            $dSize = [double]($_.data_size_mb -as [double]); $dFree = [double]($_.data_free_mb -as [double])
            $lSize = [double]($_.log_size_mb  -as [double]); $lFree = [double]($_.log_free_mb  -as [double])
            [PSCustomObject]@{
                Name    = $_.database_name
                DataPct = if ($dSize -gt 0) { [Math]::Round((1 - ($dFree / $dSize)) * 100, 1) } else { 0 }
                LogPct  = if ($lSize -gt 0) { [Math]::Round((1 - ($lFree / $lSize)) * 100, 1) } else { 0 }
                DataMb  = [Math]::Round($dSize, 1)
                LogMb   = [Math]::Round($lSize, 1)
            }
        })
        $pctD = @($pctRows | Sort-Object DataPct -Descending)
        $pctL = @($pctRows | Sort-Object LogPct  -Descending)
        $jDL = ($pctD | ForEach-Object { $_.Name | ConvertTo-Json }) -join ','
        $jDP = ($pctD | ForEach-Object { $_.DataPct }) -join ','
        $jDS = ($pctD | ForEach-Object { $_.DataMb }) -join ','
        $jLL = ($pctL | ForEach-Object { $_.Name | ConvertTo-Json }) -join ','
        $jLP = ($pctL | ForEach-Object { $_.LogPct }) -join ','
        $jLS = ($pctL | ForEach-Object { $_.LogMb }) -join ','

        $TOP_N   = 15
        $capRows = if ($dbSorted.Count -gt $TOP_N) { @($dbSorted[0..($TOP_N-1)]) } else { $dbSorted }
        $capNote = if ($dbSorted.Count -gt $TOP_N) { " &nbsp;·&nbsp; top $TOP_N of $($dbSorted.Count)" } else { '' }
        $jCL = ($capRows | ForEach-Object { $_.database_name | ConvertTo-Json }) -join ','
        $jCD = ($capRows | ForEach-Object { [Math]::Round([double]($_.data_size_mb -as [double]) / 1024, 2) }) -join ','
        $jCG = ($capRows | ForEach-Object { [Math]::Round([double]($_.log_size_mb  -as [double]) / 1024, 2) }) -join ','

        $html += @"
<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'></script>
<div style='display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px'>
  <div class='chart-wrap' style='margin-bottom:0'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px'>Data Files — % Used, Worst First (all $($pctRows.Count))</div>
    <div style='position:relative'><canvas id='ch-db-datapct' style='max-height:none'></canvas></div>
  </div>
  <div class='chart-wrap' style='margin-bottom:0'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px'>Log Files — % Used, Worst First (all $($pctRows.Count))</div>
    <div style='position:relative'><canvas id='ch-db-logpct' style='max-height:none'></canvas></div>
  </div>
</div>
<div class='chart-wrap' style='margin-bottom:20px'>
  <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:8px'>Largest Databases — GB$capNote</div>
  <div style='position:relative'><canvas id='ch-db-size' style='max-height:none'></canvas></div>
</div>
<script>
(function(){
const DL=[$jDL],DP=[$jDP],DS=[$jDS],LL=[$jLL],LP=[$jLP],LS=[$jLS];
function cols(a){return a.map(function(p){return p>=90?'#f78166':p>=80?'#ffa657':'#58a6ff';});}
function fmtMb(mb){return mb>=1048576?(mb/1048576).toFixed(2)+' TB':mb>=1024?(mb/1024).toFixed(1)+' GB':Math.round(mb)+' MB';}
function pctChart(id,labels,pcts,sizes){
  const el=document.getElementById(id);
  el.parentElement.style.height=Math.max(150,labels.length*16+50)+'px';
  new Chart(el,{type:'bar',data:{labels:labels,datasets:[{label:'% used',data:pcts,backgroundColor:cols(pcts),borderWidth:0}]},
    options:{responsive:true,maintainAspectRatio:false,indexAxis:'y',
      plugins:{legend:{display:false},tooltip:{callbacks:{label:function(c){return c.parsed.x+'% used of '+fmtMb(sizes[c.dataIndex]);}}}},
      scales:{x:{min:0,max:100,ticks:{color:'#8b949e',callback:function(v){return v+'%';}},grid:{color:'#21262d'}},
              y:{ticks:{color:'#8b949e',font:{size:11},autoSkip:false},grid:{display:false}}}}});
}
pctChart('ch-db-datapct',DL,DP,DS);
pctChart('ch-db-logpct',LL,LP,LS);
const CL=[$jCL],CD=[$jCD],CG=[$jCG];
const cEl=document.getElementById('ch-db-size');
cEl.parentElement.style.height=Math.max(150,CL.length*22+70)+'px';
new Chart(cEl,{type:'bar',data:{labels:CL,datasets:[
  {label:'Data (GB)',data:CD,backgroundColor:'#58a6ffbb',borderColor:'#58a6ff',borderWidth:1},
  {label:'Log (GB)',data:CG,backgroundColor:'#d2a8ffbb',borderColor:'#d2a8ff',borderWidth:1}
]},options:{responsive:true,maintainAspectRatio:false,indexAxis:'y',
  plugins:{legend:{labels:{color:'#c9d1d9'}}},
  scales:{x:{stacked:true,ticks:{color:'#8b949e'},grid:{color:'#21262d'}},
          y:{stacked:true,ticks:{color:'#8b949e',font:{size:11},autoSkip:false},grid:{display:false}}}}});
})();
</script>
"@

        $html += @"
<div class='table-toolbar'>
  <input class='table-filter' id='dbsz-filter' placeholder='Filter databases…' oninput='dbszFilter(this.value)' autocomplete='off'>
  <span class='row-count' id='dbsz-count'>$($dbSorted.Count) databases</span>
</div>
<div class='table-wrap'><table id='dbsz-tbl'>
<thead><tr>
  <th class='sortable' onclick='dbszSort(0)'>Database</th>
  <th class='sortable' onclick='dbszSort(1)' style='text-align:right'>Data (MB)</th>
  <th>Data Free</th>
  <th class='sortable' onclick='dbszSort(3)' style='text-align:right'>Log (MB)</th>
  <th>Log Free</th>
</tr></thead>
<tbody id='dbsz-tbody'>
"@
        # largest database's total size scales the grey name-bars
        $maxTotalMb = [double](@($dbSorted | ForEach-Object { [double]($_.data_size_mb -as [double]) + [double]($_.log_size_mb -as [double]) } | Measure-Object -Maximum).Maximum)
        if ($maxTotalMb -le 0) { $maxTotalMb = 1 }
        foreach ($db in $dbSorted) {
            $dfp = [double]($db.data_free_pct -as [double])
            $lfp = [double]($db.log_free_pct  -as [double])
            $dbc = if ($dfp -lt 10) { 'bar-crit' } elseif ($dfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $lbc = if ($lfp -lt 10) { 'bar-crit' } elseif ($lfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $dfCell = "$(Fmt-Mb $db.data_free_mb) MB ($(Fmt-Pct $dfp)%)<span class='mini-bar-track'><span class='mini-bar-fill $dbc' style='width:$([Math]::Min($dfp,100))%'></span></span>"
            $lfCell = "$(Fmt-Mb $db.log_free_mb) MB ($(Fmt-Pct $lfp)%)<span class='mini-bar-track'><span class='mini-bar-fill $lbc' style='width:$([Math]::Min($lfp,100))%'></span></span>"
            $totMb  = [double]($db.data_size_mb -as [double]) + [double]($db.log_size_mb -as [double])
            # sqrt scale — keeps small databases visible next to a multi-TB outlier
            $barPct = [Math]::Max([Math]::Round([Math]::Sqrt($totMb / $maxTotalMb) * 100, 1), 1)
            $nameCell = "<td class='name-cell'><span class='name-bar' style='width:$barPct%'></span><span class='name-txt'>$(Html-Escape $db.database_name)</span></td>"
            $html += "<tr>$nameCell<td style='text-align:right'>$(Fmt-Mb $db.data_size_mb)</td><td>$dfCell</td><td style='text-align:right'>$(Fmt-Mb $db.log_size_mb)</td><td>$lfCell</td></tr>`n"
        }
        $html += @"
</tbody></table></div>
<script>
(function(){
const tbody=document.getElementById('dbsz-tbody');
let rows=[...tbody.querySelectorAll('tr')];
let sd={};
window.dbszFilter=function(t){
  t=t.toLowerCase();let v=0;
  rows.forEach(r=>{const s=!t||r.textContent.toLowerCase().includes(t);r.style.display=s?'':'none';if(s)v++;});
  document.getElementById('dbsz-count').textContent=v===rows.length?rows.length+' databases':v+' of '+rows.length+' databases';
};
window.dbszSort=function(ci){
  sd[ci]=(sd[ci]||1)*-1;const dir=sd[ci];
  rows=[...rows].sort((a,b)=>{
    const av=a.cells[ci].textContent.trim(),bv=b.cells[ci].textContent.trim();
    const an=parseFloat(av),bn=parseFloat(bv);
    return(!isNaN(an)&&!isNaN(bn))?(an-bn)*dir:av.localeCompare(bv)*dir;
  });
  rows.forEach(r=>tbody.appendChild(r));
};
})();
</script>
"@
    }

    # ── Transaction log usage ─────────────────────────────────────────────────
    $html += "<hr class='mini-sep'><h2>Transaction Log Usage</h2>"
    if (-not $tlogs) {
        $html += "<p class='no-data'>No <code>tlog-usage.csv</code> in this folder.</p>"
    } else {
        $sorted = @($tlogs | Sort-Object { [double]($_.log_used_pct -as [double]) } -Descending)
        $maxLogMb = [double](@($sorted | ForEach-Object { [double]($_.log_size_mb -as [double]) } | Measure-Object -Maximum).Maximum)
        if ($maxLogMb -le 0) { $maxLogMb = 1 }
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Recovery</th><th>Log Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($t in $sorted) {
            $pct = [double]($t.log_used_pct -as [double])
            $svCls = if ($pct -gt 80) { 'sv-red' } elseif ($pct -gt 50) { 'sv-orange' } else { 'sv-green' }
            $lbPct = [Math]::Max([Math]::Round([Math]::Sqrt([double]($t.log_size_mb -as [double]) / $maxLogMb) * 100, 1), 1)
            $nameCell = "<td class='name-cell'><span class='name-bar' style='width:$lbPct%'></span><span class='name-txt'>$(Html-Escape $t.database_name)</span></td>"
            $html += "<tr>$nameCell<td>$($t.recovery_model_desc)</td><td>$(Fmt-Mb $t.log_size_mb)</td><td>$(Fmt-Mb $t.log_used_mb)</td><td>$(Fmt-Mb $t.log_free_mb)</td><td><span class='sv $svCls'>$(Fmt-Pct $pct)%</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── File growth risk ──────────────────────────────────────────────────────
    $html += "<hr class='mini-sep'><h2>File Growth Risk</h2>"
    if (-not $growthRisk) {
        $html += "<p class='no-data'>No <code>growth-risk.csv</code> here — re-run healthcheck with the updated collection script.</p>"
    } else {
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Data (MB)</th><th>Log (MB)</th><th>Total (MB)</th><th>Limit (MB)</th><th>Status</th></tr></thead><tbody>"
        foreach ($g in ($growthRisk | Sort-Object { [double]($_.total_mb -as [double]) } -Descending)) {
            $sCls = switch ($g.growth_status) {
                'AT_LIMIT'   { 's-crit' }
                'NEAR_LIMIT' { 's-warn' }
                'UNLIMITED'  { 's-gray' }
                default      { 's-ok'   }
            }
            $limitCell = if ([double]($g.growth_limit_mb -as [double]) -eq 0) { '<span class="null-val">—</span>' } else { Fmt-Mb $g.growth_limit_mb }
            $html += "<tr><td>$(Html-Escape $g.database_name)</td><td>$(Fmt-Mb $g.data_mb)</td><td>$(Fmt-Mb $g.log_mb)</td><td>$(Fmt-Mb $g.total_mb)</td><td>$limitCell</td><td><span class='status-badge $sCls'>$(Html-Escape $g.growth_status)</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── Drive → file mapping ──────────────────────────────────────────────────
    if ($dbFiles) {
        $byDrive = $dbFiles | Group-Object drive_letter | Sort-Object Name
        if ($byDrive) {
            $html += "<hr class='mini-sep'><h2>Files by Drive</h2>"
            $html += "<div class='table-wrap'><table><thead><tr><th>Drive</th><th>Database</th><th>Type</th><th>Size (MB)</th><th>Max (MB)</th><th>Autogrowth</th><th>Path</th></tr></thead><tbody>"
            foreach ($dg in $byDrive) {
                foreach ($f in ($dg.Group | Sort-Object database_name, file_type)) {
                    $maxCell = if ($f.max_size_mb -and $f.max_size_mb -ne '') { Fmt-Mb $f.max_size_mb } else { '<span class="null-val">unlimited</span>' }
                    $growthWarn = if ($f.growth_is_percent -in @('True','1','true','YES')) { " <span class='sv sv-orange'>%</span>" } else { '' }
                    $html += "<tr><td>$(Html-Escape $f.drive_letter)</td><td>$(Html-Escape $f.database_name)</td><td>$($f.file_type)</td><td>$(Fmt-Mb $f.current_size_mb)</td><td>$maxCell</td><td>$(Html-Escape $f.auto_growth)$growthWarn</td><td title='$(Html-Escape $f.physical_path)'>$(Html-Escape ([System.IO.Path]::GetFileName($f.physical_path)))</td></tr>"
                }
            }
            $html += "</tbody></table></div>"
        }
    }

    Wrap-Page 'Disk Space' $html '' 'disk'
}

# ── server ─────────────────────────────────────────────────────────────────────

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
try {
    $listener.Start()
} catch {
    if ($_.Exception.Message -match 'conflicts with an existing registration') {
        Write-Host ''
        Write-Host "  Port $Port is already in use — the web UI is probably already running." -ForegroundColor Yellow
        Write-Host "  Open it:            http://localhost:$Port/" -ForegroundColor Cyan
        Write-Host "  Or restart cleanly: .\web-ui\Restart-WebUi.ps1" -ForegroundColor Cyan
        Write-Host "  Or use another port: .\web-ui\Start-WebUi.ps1 -Port 8890" -ForegroundColor DarkGray
        Write-Host ''
        exit 1
    }
    throw
}

Write-Host "dba-tools UI  →  http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop."

try {
    while ($listener.IsListening) {
        $ctx  = $listener.GetContext()
        $req  = $ctx.Request
        $res  = $ctx.Response
        $url  = $req.Url.AbsolutePath
        $qs   = [System.Web.HttpUtility]::ParseQueryString($req.Url.Query)

        # Static assets — serve binary files directly and skip normal response path
        if ($url -like '/assets/*') {
            $assetName = [IO.Path]::GetFileName($url)
            $assetFile = Join-Path $PSScriptRoot "assets\$assetName"
            if (Test-Path -LiteralPath $assetFile) {
                $ext  = [IO.Path]::GetExtension($assetFile).ToLower()
                $mime = switch ($ext) {
                    '.png'  { 'image/png' }
                    '.jpg'  { 'image/jpeg' }
                    '.jpeg' { 'image/jpeg' }
                    '.svg'  { 'image/svg+xml' }
                    '.ico'  { 'image/x-icon' }
                    default { 'application/octet-stream' }
                }
                $imgBytes = [IO.File]::ReadAllBytes($assetFile)
                $res.ContentType     = $mime
                $res.ContentLength64 = $imgBytes.Length
                $res.StatusCode      = 200
                $res.OutputStream.Write($imgBytes, 0, $imgBytes.Length)
                $res.OutputStream.Close()
                continue
            }
            $nb = [Text.Encoding]::UTF8.GetBytes('Not found')
            $res.StatusCode = 404; $res.ContentType = 'text/plain'
            $res.ContentLength64 = $nb.Length
            $res.OutputStream.Write($nb, 0, $nb.Length)
            $res.OutputStream.Close()
            continue
        }

        $contentType = 'text/html; charset=utf-8'
        $statusCode  = 200
        $body = try { switch ($url) {
            '/'         { Build-HomePage }
            '/triage'   { Build-TriagePage }
            '/search'   { Build-SearchPage $(if ($null -ne $qs['q']) { $qs['q'] } else { '' }) }
            '/view'     { Build-ViewPage   $(if ($null -ne $qs['p']) { $qs['p'] } else { '' }) }
            '/csvs'     { Build-CsvListPage }
            '/csv'      { Build-CsvViewPage $(if ($null -ne $qs['p']) { $qs['p'] } else { '' }) }
            '/review'    { Build-ReviewPage   $(if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }) }
            '/security'  { Build-SecurityPage $(if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }) }
            '/disk'      { Build-DiskPage     $(if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }) }
            '/ai'        { Build-AiPage       $(if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }) $(if ($null -ne $qs['report']) { $qs['report'] } else { '' }) }
            '/api/csv'  {
                $contentType = 'application/json; charset=utf-8'
                $p = if ($null -ne $qs['p']) { $qs['p'] } else { '' }
                $fp = Join-Path $repoRoot $p
                $resolvedFp = try { (Resolve-Path -LiteralPath $fp -ErrorAction Stop).Path } catch { $null }
                if ($resolvedFp -and $resolvedFp.StartsWith($repoRoot.ToString(), [StringComparison]::OrdinalIgnoreCase)) {
                    ConvertTo-Json2 (Get-CsvJson $resolvedFp)
                } else { '{"error":"not found"}' }
            }
            '/api/run' {
                $contentType = 'application/json; charset=utf-8'
                $p      = if ($null -ne $qs['p']) { $qs['p'] } else { '' }
                $svrVal = if ($null -ne $qs['server']) { $qs['server'] } else { '' }
                $svr    = "$svrVal".Trim()
                $dryRun = $qs['dryrun'] -eq '1'
                if (-not $svr) { $svr = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' } }

                $fullRunPath = Join-Path $repoRoot $p
                $resolvedRun = try { (Resolve-Path -LiteralPath $fullRunPath -ErrorAction Stop).Path } catch { $null }
                if (-not $resolvedRun -or -not $resolvedRun.StartsWith($repoRoot.ToString(), [StringComparison]::OrdinalIgnoreCase)) {
                    ConvertTo-JsonError "Script not found: $p"
                    break
                }
                $fullRunPath = $resolvedRun

                $sName  = [IO.Path]::GetFileNameWithoutExtension($fullRunPath)
                $sExt   = [IO.Path]::GetExtension($fullRunPath).ToLower()
                $cat    = if ($p -match '(^|[\\/])sql[\\/]([^\\/]+)[\\/]')             { $Matches[2] }
                          elseif ($p -match '(^|[\\/])powershell[\\/]([^\\/]+)[\\/]') { $Matches[2] }
                          else { 'general' }
                $ts      = Get-Date -Format 'yyyyMMdd-HHmmss'
                $csvDir  = Join-Path $repoRoot "output-files\reviews\$cat$(if ($dryRun) {'\dry-runs'} else {''})"
                $csvPath = Join-Path $csvDir "$sName-$ts.csv"
                if (-not (Test-Path $csvDir)) { New-Item -ItemType Directory -Path $csvDir -Force | Out-Null }

                $tmpFile = $null
                $env:DBASCRIPTS_BATCH = '1'
                try {
                    $scriptToRun = $fullRunPath
                    if ($dryRun -and $sExt -eq '.sql') {
                        $origSql = Get-Content $fullRunPath -Raw -Encoding UTF8
                        $wrapped = "-- ============================================================`r`n-- DRY RUN — wrapped in a transaction that will be rolled back`r`n-- No changes will be committed to the database`r`n-- ============================================================`r`nBEGIN TRANSACTION;`r`n`r`n$origSql`r`n`r`nROLLBACK TRANSACTION;`r`n"
                        $tmpFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), "$sName-dryrun-$ts.sql")
                        [IO.File]::WriteAllText($tmpFile, $wrapped, [Text.Encoding]::UTF8)
                        $scriptToRun = $tmpFile
                    }

                    if ($sExt -eq '.sql') {
                        # Route through the matching wrapper if one exists — keeps wrapper logic in the loop.
                        # Derive category: sql/<cat>/ → cat name; sql/migration/ → 'migration'
                        $wrapCategory = if ($p -match '(^|[\\/])sql[\\/]([^\\/]+)[\\/]') { $Matches[2] }
                                        else                                               { $null }
                        $psWrapper = $null
                        if ($wrapCategory) {
                            $psWrapper = Get-ChildItem -Path (Join-Path $repoRoot "powershell\wrappers\$wrapCategory") `
                                -Recurse -Filter "$sName.ps1" -File -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                        }
                        # Generate-* DDL scripts may live in powershell/migration/ or powershell/
                        if (-not $psWrapper -and $sName -match '^Generate-') {
                            $psWrapper = Get-ChildItem -Path (Join-Path $repoRoot 'powershell\migration') `
                                -Filter "$sName.ps1" -File -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                            if (-not $psWrapper) {
                                $psWrapper = Get-ChildItem -Path (Join-Path $repoRoot 'powershell') `
                                    -Recurse -Filter "$sName.ps1" -File -ErrorAction SilentlyContinue |
                                    Select-Object -First 1
                            }
                        }
                        if ($psWrapper) {
                            & $psWrapper.FullName -ServerInstance $svr -OutputFormat 'Csv' `
                                                  -OutputPath $csvPath -ErrorAction Stop
                        } else {
                            $runner = Join-Path $repoRoot 'tools\local-sql\Invoke-RepoSql.ps1'
                            & $runner -ScriptPath $scriptToRun -ServerInstance $svr -Database 'master' `
                                      -OutputFormat 'Csv' -OutputPath $csvPath -ErrorAction Stop
                        }
                    } else {
                        # Direct PS1 run — only pass params the script declares. Reporting and
                        # diagnostics scripts vary; unknown named params would either bind-fail
                        # or silently fall into $args (the run.ps1 alias-mapping bug class).
                        $cmdInfo  = Get-Command $scriptToRun -ErrorAction SilentlyContinue
                        $psParams = @{}
                        if ($cmdInfo -and $cmdInfo.Parameters) {
                            if ($cmdInfo.Parameters.ContainsKey('ServerInstance')) { $psParams.ServerInstance = $svr }
                            if ($cmdInfo.Parameters.ContainsKey('OutputFormat'))   { $psParams.OutputFormat   = 'Csv' }
                            if ($cmdInfo.Parameters.ContainsKey('OutputPath'))     { $psParams.OutputPath     = $csvPath }
                        } else {
                            $psParams = @{ ServerInstance = $svr; OutputFormat = 'Csv'; OutputPath = $csvPath }
                        }
                        & $scriptToRun @psParams -ErrorAction Stop
                    }

                    if (Test-Path -LiteralPath $csvPath) {
                        $relCsv = $csvPath.Replace($repoRoot.ToString(), '').TrimStart('\')
                        $enc    = [Uri]::EscapeDataString($relCsv)
                        "{`"ok`":true,`"url`":`"/csv?p=$enc`",`"dryrun`":$(if ($dryRun){'true'}else{'false'})}"
                    } else {
                        $msg = if ($dryRun) { 'Dry run completed — no output rows (script may not SELECT data).' } else { 'Script completed but produced no output file.' }
                        "{`"ok`":false,`"error`":`"$msg`"}"
                    }
                } catch {
                    ConvertTo-JsonError $_.Exception.Message
                } finally {
                    $env:DBASCRIPTS_BATCH = $null
                    if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -ErrorAction SilentlyContinue }
                }
            }
            '/api/run-healthcheck' {
                $contentType = 'application/json; charset=utf-8'
                $svrVal = if ($null -ne $qs['server']) { $qs['server'] } else { '' }
                $svr = "$svrVal".Trim()
                if (-not $svr) { $svr = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' } }
                $collScript = Join-Path $repoRoot 'powershell\reporting\Invoke-HealthCheckCollection.ps1'
                if (-not (Test-Path $collScript)) {
                    '{"ok":false,"error":"Invoke-HealthCheckCollection.ps1 not found"}'; break
                }
                try {
                    # Non-blocking: pre-compute the folder (same naming as the collector),
                    # launch the collection detached, return immediately. The client polls
                    # /api/status?folder= against the manifest the collector writes.
                    $hcRoot     = Join-Path $repoRoot 'output-files\healthcheck'
                    $safeName   = ($svr -replace '[\\/:*?"<>|]', '-').Trim('-')
                    $folderName = "$safeName-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    $outFolder  = Join-Path $hcRoot $folderName
                    $pwshExe    = (Get-Process -Id $PID).Path
                    Start-Process -FilePath $pwshExe -WindowStyle Hidden -ArgumentList @(
                        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                        '-File', $collScript,
                        '-ServerInstance', $svr,
                        '-OutputFolder', $outFolder,
                        '-Quiet'
                    ) | Out-Null
                    $folderJson = $folderName -replace '\\', '\\\\' -replace '"', '\"'
                    "{`"ok`":true,`"folder`":`"$folderJson`"}"
                } catch {
                    ConvertTo-JsonError $_.Exception.Message
                }
            }
            '/api/status' {
                $contentType = 'application/json; charset=utf-8'
                $stFolderVal = if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }
                $stFolder = "$stFolderVal".Trim()
                if (-not $stFolder) { '{"ok":false,"error":"folder parameter required"}'; break }
                # Default = waiting: covers collector still starting AND transient read races
                # with the collector's atomic manifest replace (the client keeps polling).
                $body = '{"ok":true,"waiting":true}'
                try {
                    $resolved = Resolve-HcFolder $stFolder
                    $mPath    = if ($resolved) { Join-Path $resolved 'manifest.csv' } else { $null }
                    if ($mPath -and (Test-Path -LiteralPath $mPath)) {
                        $rows = @(Import-Csv -LiteralPath $mPath -ErrorAction Stop)
                        if ($rows.Count -gt 0) {
                            $done     = @($rows | Where-Object { $_.Status -in 'OK', 'FAILED', 'SKIPPED' }).Count
                            $nFail    = @($rows | Where-Object Status -eq 'FAILED').Count
                            $running  = ($rows | Where-Object Status -eq 'RUNNING' | Select-Object -First 1).Script
                            $complete = ($done -eq $rows.Count)
                            $ageSec   = [math]::Round(((Get-Date) - (Get-Item -LiteralPath $mPath).LastWriteTime).TotalSeconds)
                            $runJson  = if ($running) { '"' + ($running -replace '"', '\"') + '"' } else { 'null' }
                            $body = "{`"ok`":true,`"total`":$($rows.Count),`"done`":$done,`"failed`":$nFail,`"running`":$runJson,`"complete`":$($complete.ToString().ToLower()),`"ageSeconds`":$ageSec}"
                        }
                    }
                } catch { $null = $_ }
                $body
            }
            '/api/run-ai' {
                $contentType = 'application/json; charset=utf-8'
                $aiFolderVal = if ($null -ne $qs['folder']) { $qs['folder'] } else { '' }
                $aiFolder = "$aiFolderVal".Trim()
                $dryRun   = $qs['dryrun'] -eq '1'
                $aiScript = Join-Path $repoRoot 'powershell\reporting\Invoke-AiAssessment.ps1'
                if (-not (Test-Path $aiScript)) {
                    '{"ok":false,"error":"Invoke-AiAssessment.ps1 not found"}'; break
                }
                if (-not $dryRun -and -not $env:ANTHROPIC_API_KEY) {
                    '{"ok":false,"error":"ANTHROPIC_API_KEY is not set — only DryRun is available. See docs/ai-assessment.md."}'; break
                }
                try {
                    $aiParams = @{}
                    if ($aiFolder) {
                        $resolvedAi = Resolve-HcFolder $aiFolder
                        if (-not $resolvedAi -or -not (Test-Path -LiteralPath $resolvedAi)) { throw "Collection folder not found: $aiFolder" }
                        $aiParams.FolderPath = $resolvedAi
                    }
                    if ($dryRun) { $aiParams.DryRun = $true }
                    & $aiScript @aiParams -ErrorAction Stop | Out-Null
                    '{"ok":true}'
                } catch {
                    ConvertTo-JsonError $_.Exception.Message
                }
            }
            '/api/clear-output' {
                $contentType = 'application/json; charset=utf-8'
                if ($req.HttpMethod -ne 'POST') { '{"ok":false,"error":"POST required"}'; break }
                try {
                    $outDir  = Join-Path $repoRoot 'output-files'
                    # assessments\ holds AI sign-off reports — deliberately survives the wipe
                    $keepDir = Join-Path $outDir 'assessments'
                    $deleted = 0
                    if (Test-Path $outDir) {
                        $files = Get-ChildItem -Path $outDir -Recurse -File -ErrorAction SilentlyContinue |
                                 Where-Object { $_.Name -ne '.gitkeep' -and -not $_.FullName.StartsWith($keepDir, [StringComparison]::OrdinalIgnoreCase) }
                        $deleted = $files.Count
                        $files | Remove-Item -Force -ErrorAction SilentlyContinue
                        # Remove empty subdirectories deepest-first
                        Get-ChildItem -Path $outDir -Recurse -Directory -ErrorAction SilentlyContinue |
                            Sort-Object FullName -Descending |
                            Where-Object { $_.FullName -ne $keepDir -and @(Get-ChildItem $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    "{`"ok`":true,`"deleted`":$deleted}"
                } catch {
                    ConvertTo-JsonError $_.Exception.Message
                }
            }
            '/api/save-png' {
                $contentType = 'application/json; charset=utf-8'
                try {
                    $reader  = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $payload = $reader.ReadToEnd() | ConvertFrom-Json
                    $reader.Dispose()
                    $csvFull = Join-Path $repoRoot $payload.relPath
                    $resolvedCsv = try { (Resolve-Path -LiteralPath $csvFull -ErrorAction Stop).Path } catch { $null }
                    if (-not $resolvedCsv -or -not $resolvedCsv.StartsWith($repoRoot.ToString(), [StringComparison]::OrdinalIgnoreCase)) {
                        throw "Invalid path: must be within the repo's output-files folder"
                    }
                    $pngFull = [System.IO.Path]::ChangeExtension($resolvedCsv, '.png')
                    $b64     = $payload.imageData -replace '^data:image/png;base64,', ''
                    [System.IO.File]::WriteAllBytes($pngFull, [Convert]::FromBase64String($b64))
                    $shortName = [System.IO.Path]::GetFileName($pngFull)
                    "{`"ok`":true,`"file`":`"$shortName`"}"
                } catch {
                    ConvertTo-JsonError $_.Exception.Message
                }
            }
            default     { $statusCode = 404; Wrap-Page '404' "<p class='empty'>Page not found: $(Html-Escape $url)</p>" }
        } } catch {
            $statusCode  = 500
            $contentType = 'text/html; charset=utf-8'
            Wrap-Page 'Error' "<h2>Error</h2><pre style='color:#f78166'>$(Html-Escape $_.Exception.Message)`n$(Html-Escape $_.ScriptStackTrace)</pre>"
        }

        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $res.ContentType     = $contentType
            $res.ContentLength64 = $bytes.Length
            $res.StatusCode      = $statusCode
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.OutputStream.Close()
        } catch {
            # Client disconnected before/while the response was being written (tab closed,
            # navigation aborted an in-flight poll) — drop this response, keep serving
            try { $res.Abort() } catch { $null = $_ }
        }
    }
} finally {
    $listener.Stop()
    $listener.Dispose()
}
