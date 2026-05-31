<#
.SYNOPSIS
    Local web UI for browsing scripts and visualising output CSVs.
.DESCRIPTION
    Starts an HTTP listener on localhost:8787. No external dependencies for the server;
    Chart.js is loaded from CDN on the CSV chart page (requires internet for that page only).
    Press Ctrl+C to stop.
.EXAMPLE
    .\tools\Start-WebUi.ps1
    .\tools\Start-WebUi.ps1 -Port 9090
#>
param([int]$Port = 8787, [switch]$Inline)

if (-not $Inline) {
    Start-Process pwsh -ArgumentList "-NoExit", "-File", "`"$PSCommandPath`"", "-Port", $Port, "-Inline"
    return
}

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# ── data helpers ───────────────────────────────────────────────────────────────

function Get-AllScripts {
    $sql = Get-ChildItem "$repoRoot\sql" -Recurse -Filter '*.sql' -File |
        Select-Object FullName,
            @{n='Name';    e={ $_.BaseName }},
            @{n='Category';e={ $_.Directory.Name }},
            @{n='Type';    e={ 'SQL' }},
            @{n='RelPath'; e={ $_.FullName.Replace($repoRoot,'').TrimStart('\') }}

    $ps = Get-ChildItem "$repoRoot\powershell" -Recurse -Filter '*.ps1' -File |
        Select-Object FullName,
            @{n='Name';    e={ $_.BaseName }},
            @{n='Category';e={ $_.Directory.Name }},
            @{n='Type';    e={ 'PS1' }},
            @{n='RelPath'; e={ $_.FullName.Replace($repoRoot,'').TrimStart('\') }}

    @($sql) + @($ps)
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
.disk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px;margin-bottom:28px}
.disk-card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px}
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
.sev-strip{display:flex;gap:8px;margin-bottom:24px;flex-wrap:wrap;align-items:center}
.sev-chip{display:inline-block;padding:5px 16px;border-radius:20px;font-size:.85rem;font-weight:600;border:1px solid}
.sev-chip.s-crit{background:#3a1a1a;color:#f78166;border-color:#f78166}
.sev-chip.s-warn{background:#3a2a1a;color:#ffa657;border-color:#ffa657}
.sev-chip.s-info{background:#1a2a3a;color:#58a6ff;border-color:#58a6ff}
.sev-chip.s-ok{background:#1a3a2a;color:#3fb950;border-color:#3fb950}
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
'@

# ── page wrapper ───────────────────────────────────────────────────────────────

function Wrap-Page([string]$title, [string]$body, [string]$q='', [string]$active='scripts') {
    $qEsc = Html-Escape $q
    $navScripts = if ($active -eq 'scripts') { "class='active'" } else { '' }
    $navReview  = if ($active -eq 'review')  { "class='active'" } else { '' }
    $navDisk    = if ($active -eq 'disk')    { "class='active'" } else { '' }
    $navCsvs    = if ($active -eq 'csvs')    { "class='active'" } else { '' }
    @"
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title — dba-scripts</title>
<style>$CSS</style></head><body>
<header>
  <h1>dba-scripts</h1>
  <nav>
    <a href="/" $navScripts>Scripts</a>
    <a href="/review" $navReview>Health Check</a>
    <a href="/disk" $navDisk>Disk Space</a>
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

function Build-HomePage {
    $scripts  = Get-AllScripts
    $byType   = $scripts | Group-Object Type
    $html     = ''

    foreach ($typeGroup in ($byType | Sort-Object Name -Descending)) {
        $typeName  = $typeGroup.Name
        $badgeClass = if ($typeName -eq 'SQL') { 'badge-sql' } else { 'badge-ps' }
        $html += "<h2>$typeName scripts ($($typeGroup.Count))</h2>"

        foreach ($cat in ($typeGroup.Group | Group-Object Category | Sort-Object Name)) {
            $html += "<div class='cat-label'>$($cat.Name)</div><div class='grid'>"
            foreach ($s in ($cat.Group | Sort-Object Name)) {
                $purpose    = Get-ScriptPurpose $s.FullName
                $purposeHtml = if ($purpose) { "<div class='purpose'>$(Html-Escape $purpose)</div>" } else { '' }
                $relEnc     = [Uri]::EscapeDataString($s.RelPath)
                $safety     = Get-ScriptSafety $s.FullName
                $sBadge     = "<span class='safe-badge $(Resolve-SafetyClass $safety)'>$(Resolve-SafetyLabel $safety)</span>"
                $html += "<div class='card'><span class='badge $badgeClass'>$typeName</span>$sBadge<a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
            }
            $html += '</div>'
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
    $category  = Split-Path (Split-Path $relPath -Parent) -Leaf
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

    # Determine if this script can be run through the web UI
    $isRunnable = $false
    if ($ext -eq '.sql' -and $relPath -match '(^|[\\/])sql[\\/]') {
        $isRunnable = $true
    } elseif ($ext -eq '.ps1' -and $relPath -match '(^|[\\/])powershell[\\/]') {
        $isRunnable = ($content -match 'OutputFormat') -and ($content -match 'OutputPath')
    }

    $relEnc      = [Uri]::EscapeDataString($relPath)
    $defaultSrv  = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint     = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $dryRunToggle = if ($isWrites -and $isRunnable) { "<div class='dryrun-wrap'><input type='checkbox' id='dryrun' checked><label for='dryrun'>Dry Run</label></div>" } else { '' }

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
    $scripts = Get-AllScripts
    $results = @($scripts | Where-Object {
        $_.Name -like "*$q*" -or $_.Category -like "*$q*" -or
        (Get-ScriptPurpose $_.FullName) -like "*$q*"
    })

    if (-not $results) {
        return Wrap-Page "Search: $q" "<h2>Search: $(Html-Escape $q)</h2><p class='empty'>No scripts matched.</p>" $q 'scripts'
    }

    $html = "<h2>Search: $(Html-Escape $q) ($($results.Count) results)</h2><div class='grid'>"
    foreach ($s in ($results | Sort-Object Name)) {
        $purpose    = Get-ScriptPurpose $s.FullName
        $purposeHtml = if ($purpose) { "<div class='purpose'>$(Html-Escape $purpose)</div>" } else { '' }
        $relEnc     = [Uri]::EscapeDataString($s.RelPath)
        $badgeClass  = if ($s.Type -eq 'SQL') { 'badge-sql' } else { 'badge-ps' }
        $safety      = Get-ScriptSafety $s.FullName
        $sBadge      = "<span class='safe-badge $(Resolve-SafetyClass $safety)'>$(Resolve-SafetyLabel $safety)</span>"
        $html += "<div class='card'><span class='badge $badgeClass'>$($s.Type)</span>$sBadge<a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
    }
    $html += '</div>'
    Wrap-Page "Search: $q" $html $q 'scripts'
}

function Build-CsvListPage {
    $csvs = @(Get-ChildItem "$repoRoot\output-files" -Recurse -Filter '*.csv' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.tmp.csv' } |
        Sort-Object LastWriteTime -Descending)

    $clearBtn = "<button class='clear-btn' id='clear-btn' onclick='clearOutput()'>Clear All Output</button>
<script>
async function clearOutput(){
  if(!confirm('Delete all files in output-files/?\\n\\nThis removes all CSVs, logs, and generated scripts. Cannot be undone.'))return;
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

    foreach ($g in ($grouped | Sort-Object Name)) {
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
    $sqlMatch     = Get-ChildItem "$repoRoot\sql"        -Recurse -Filter "$scriptBase.sql" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $ps1Match     = Get-ChildItem "$repoRoot\powershell" -Recurse -Filter "$scriptBase.ps1" -File -ErrorAction SilentlyContinue | Select-Object -First 1
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
  'Get-DatabaseIoUsage':             {type:'bar',h:false, prefer:['reads_mb','writes_mb','read_latency_ms','write_latency_ms']},
  'Get-TransactionLogSizeAndUsage':  {type:'bar',h:false, prefer:['log_size_mb','log_used_mb']},
  'Get-BackupCoverage':              {type:'bar',h:false, prefer:['full_backup_age_hours','diff_backup_age_hours']},
  'Get-LastDatabaseBackupTimes':     {type:'bar',h:false, prefer:['full_backup_age_hours','log_backup_age_hours']},
  // Doughnut — proportional / used vs free
  'Get-DiskSpace':                   {type:'doughnut',    prefer:['used_gb','free_gb']},
  'Get-TempdbUsage':                 {type:'doughnut',    prefer:['used_mb','free_mb']},
  'Get-MemoryConfigurationAndUsage': {type:'doughnut',    prefer:['sql_memory_mb','available_mb']},
};

const COLORS=['#58a6ff','#3fb950','#f78166','#d2a8ff','#ffa657','#79c0ff','#56d364','#ff7b72',
              '#e3b341','#a5d6ff','#7ee787','#ffa8a8'];
const SV={
  online:'green',running:'green',complete:'green',completed:'green',success:'green',succeeded:'green',
  yes:'green',pass:'green',enabled:'green',ok:'green',healthy:'green',available:'green',
  offline:'red',failed:'red',fail:'red',error:'red',suspect:'red',no:'red',
  missing:'red',critical:'red',unavailable:'red',
  restoring:'orange',warning:'orange',pending:'orange',recovering:'orange',
  disabled:'gray','n/a':'gray',none:'gray',
  'read-only':'blue',writes:'blue'
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
    document.getElementById('mode-badge').textContent='No results returned.';
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

function applyHint(){
  const hint=CHART_HINTS[SCRIPT_NAME];
  active.clear();
  horizontal=false;
  if(hint){
    type=hint.type||'bar';
    horizontal=hint.h||false;
    const pref=(hint.prefer||[]).map(p=>
      data.numericCols.find(c=>c.toLowerCase()===p.toLowerCase())
    ).filter(Boolean);
    const cols=pref.length>0?pref:data.numericCols.slice(0,4);
    cols.slice(0,4).forEach(c=>active.add(c));
    pieCol=(type==='pie'||type==='doughnut')?(cols[0]||data.numericCols[0]||''):(data.numericCols[0]||'');
  } else {
    pieCol=data.numericCols[0]||'';
    data.numericCols.slice(0,4).forEach(c=>active.add(c));
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

function renderChart(){
  if(chart)chart.destroy();
  const ctx=document.getElementById('chart').getContext('2d');
  const labels=data.rows.map(r=>String(r[data.labelCol]??''));
  if(isPie()){
    chart=new Chart(ctx,{type:type,data:{labels,datasets:[{label:pieCol,
      data:data.rows.map(r=>parseFloat(r[pieCol])||0),
      backgroundColor:data.rows.map((_,i)=>COLORS[i%COLORS.length]+'cc'),
      borderColor:data.rows.map((_,i)=>COLORS[i%COLORS.length]),borderWidth:1}]},
      options:{responsive:true,maintainAspectRatio:true,
        plugins:{legend:{position:'right',labels:{color:'#c9d1d9',boxWidth:14,padding:12}}}}});
  } else {
    const datasets=data.numericCols.filter(c=>active.has(c)).map(col=>{
      const i=data.numericCols.indexOf(col);
      return{label:col,data:data.rows.map(r=>parseFloat(r[col])||0),
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
  if(/^-?\d+(\.\d+)?$/.test(s.trim())){
    const n=parseFloat(s);
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

function Build-ReviewPage([string]$folder) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    # Resolve bare folder name (e.g. ".-20260531-095824") to full path
    if ($folder -and -not [System.IO.Path]::IsPathRooted($folder)) {
        $folder = Join-Path $hcRoot $folder
    }
    if (-not $folder) {
        if (Test-Path $hcRoot) {
            $latest = Get-ChildItem -LiteralPath $hcRoot -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $folder = $latest.FullName }
        }
    }

    $folderEnc  = Html-Escape ($folder ?? '')
    $defaultSrv = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $html = @"
<div style='display:flex;align-items:flex-start;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:16px'>
  <form class='folder-row' style='margin:0;flex:1;min-width:0' method='get' action='/review'>
    <label>Folder:</label>
    <input class='folder-input' name='folder' value='$folderEnc' placeholder='Leave blank for most recent…'>
    <button type='submit' class='folder-btn'>Load</button>
  </form>
  <div class='run-bar' style='flex-shrink:0'>
    <label>Server:</label>
    <input id='hc-srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off'>
    <button id='hc-run-btn' class='run-btn' onclick='runHealthcheck("review")'>Run Health Check &#9654;</button>
  </div>
</div>
<div id='hc-run-err' class='run-error' style='display:none;margin-bottom:10px'></div>
<div id='hc-overlay' class='run-overlay'>
  <div class='run-spinner'></div>
  <div class='run-spinner-label'>Running health check — collecting 19 scripts, please wait…</div>
</div>
<script>
async function runHealthcheck(page){
  const srv=document.getElementById('hc-srv').value.trim()||'.';
  const btn=document.getElementById('hc-run-btn');
  const err=document.getElementById('hc-run-err');
  document.getElementById('hc-overlay').style.display='flex';
  btn.disabled=true;err.style.display='none';
  try{
    const r=await fetch('/api/run-healthcheck?server='+encodeURIComponent(srv)+'&page='+page);
    const d=await r.json();
    if(d.ok){window.location.href=d.url;return;}
    err.textContent=d.error||'Unknown error';err.style.display='';
  }catch(e){err.textContent='Request failed: '+e.message;err.style.display='';}
  document.getElementById('hc-overlay').style.display='none';
  btn.disabled=false;
}
</script>
"@

    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
        $html += "<p class='no-data'>No healthcheck folder found. Run <code>Invoke-HealthCheckCollection.ps1</code> first.</p>"
        return Wrap-Page 'Health Check' $html '' 'review'
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
    $missingIdx  = Read-RvwCsv 'missing-indexes'

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
            if ([double]::TryParse($row.full_backup_age_hours,[ref]$h) -and $h -gt 25) {
                Add-F 'WARNING' 'Backup' $db "Full backup $([Math]::Round($h,1))h old (threshold 25h)"
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
        if (-not $row.last_good_checkdb -or $row.last_good_checkdb -eq '') { Add-F 'WARNING' 'DBCC CHECKDB' $row.database_name 'No CHECKDB on record' }
        else {
            $d = 0
            if ([int]::TryParse($row.days_since_checkdb,[ref]$d) -and $d -gt 7) {
                Add-F 'WARNING' 'DBCC CHECKDB' $row.database_name "Last good CHECKDB $d days ago (threshold 7)"
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
        $html += "<h2>Instance</h2><div class='info-card-grid'>"
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
        $html += "</div>"
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
    $bkpCls  = if ($worstBkpHours -gt 25) { 'v-crit' } elseif ($worstBkpHours -gt 12) { 'v-warn' } else { 'v-ok' }
    $bkpDisp = if ($backups.Count -eq 0) { '—' } else { "$([Math]::Round($worstBkpHours,1))h" }

    $worstCheckRow = $checkdb | Sort-Object { [int]($_.days_since_checkdb -as [int]) } -Descending | Select-Object -First 1
    $worstCheckDays = $worstCheckRow.days_since_checkdb -as [int]
    $chkCls  = if ($null -eq $worstCheckDays -or -not $worstCheckRow.last_good_checkdb) { 'v-crit' } elseif ($worstCheckDays -gt 7) { 'v-warn' } else { 'v-ok' }
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

    $html += "<p class='vital-row-label'>Right now</p><div class='vital-grid'>"
    $html += "<div class='vital-card $sessCls'><div class='vital-label'>Sessions</div><div class='vital-val'>$vSessions</div><div class='vital-sub'>$sessSub</div></div>"
    $html += "<div class='vital-card $waitCls'><div class='vital-label'>Top Wait</div><div class='vital-val' style='font-size:.82rem'>$(Html-Escape $vWaitName)</div><div class='vital-sub'>$(Fmt-Pct $vWaitPct)% of waits</div></div>"
    $html += "<div class='vital-card $tlogCls'><div class='vital-label'>T-Log Pressure</div><div class='vital-val'>$tlogDisp</div><div class='vital-sub'>$tlogSub</div></div>"
    $html += "<div class='vital-card $tempCls'><div class='vital-label'>TempDB</div><div class='vital-val'>$tempDisp</div><div class='vital-sub'>worst file used %</div></div>"
    $html += "</div>"
    $vMissingHigh = @($missingIdx | Where-Object { ($_.impact_score -as [double]) -gt 100000 }).Count
    $vMissingAll  = $missingIdx.Count
    $missCls  = if ($vMissingHigh -gt 5) { 'v-crit' } elseif ($vMissingHigh -gt 0) { 'v-warn' } elseif ($vMissingAll -gt 0) { 'v-blue' } else { 'v-ok' }
    $missDisp = if ($vMissingAll -eq 0) { '—' } else { $vMissingAll }
    $missSub  = if ($vMissingHigh -gt 0) { "$vMissingHigh high-impact" } elseif ($vMissingAll -gt 0) { 'low impact only' } else { 'none detected' }

    $html += "<p class='vital-row-label'>Keeping up</p><div class='vital-grid'>"
    $html += "<div class='vital-card $bkpCls'><div class='vital-label'>Oldest Backup</div><div class='vital-val'>$bkpDisp</div><div class='vital-sub'>worst full backup age</div></div>"
    $html += "<div class='vital-card $chkCls'><div class='vital-label'>DBCC CHECKDB</div><div class='vital-val'>$chkDisp</div><div class='vital-sub'>worst days since check</div></div>"
    $html += "<div class='vital-card $diskCls'><div class='vital-label'>Disk (worst)</div><div class='vital-val'>$diskDisp</div><div class='vital-sub'>$diskSub</div></div>"
    $html += "<div class='vital-card $missCls'><div class='vital-label'>Missing Indexes</div><div class='vital-val'>$missDisp</div><div class='vital-sub'>$missSub</div></div>"
    $html += "</div>"

    # severity summary chips
    $critN = @($findings | Where-Object Severity -eq 'CRITICAL').Count
    $warnN = @($findings | Where-Object Severity -eq 'WARNING').Count
    $infoN = @($findings | Where-Object Severity -eq 'INFO').Count
    $html += "<div class='sev-strip'>"
    if ($critN -gt 0) { $html += "<span class='sev-chip s-crit'>$critN Critical</span>" }
    if ($warnN -gt 0) { $html += "<span class='sev-chip s-warn'>$warnN Warning</span>" }
    if ($infoN -gt 0) { $html += "<span class='sev-chip s-info'>$infoN Info</span>" }
    if ($findings.Count -eq 0) { $html += "<span class='sev-chip s-ok'>All thresholds healthy</span>" }
    $html += "</div>"

    # ── findings list ───────────────────────────────────────────────────────────
    $html += "<hr class='section-sep'><h2>Findings</h2>"
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

    # ── databases ──────────────────────────────────────────────────────────────
    if ($dbHealth.Count -gt 0) {
        $html += "<hr class='section-sep'><h2>Databases ($($dbHealth.Count))</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>State</th><th>Recovery</th><th>Auto-Shrink</th><th>Auto-Close</th></tr></thead><tbody>"
        foreach ($db in ($dbHealth | Sort-Object database_name)) {
            $stCls  = if ($db.state_desc -ne 'ONLINE') { 'sv sv-red' } else { 'sv sv-green' }
            $shCls  = if ($db.is_auto_shrink_on -in @('True','1','YES')) { 'sv sv-orange' } else { 'sv sv-green' }
            $clCls  = if ($db.is_auto_close_on  -in @('True','1','YES')) { 'sv sv-orange' } else { 'sv sv-green' }
            $shTxt  = if ($db.is_auto_shrink_on -in @('True','1','YES')) { 'ON' } else { 'OFF' }
            $clTxt  = if ($db.is_auto_close_on  -in @('True','1','YES')) { 'ON' } else { 'OFF' }
            $html += "<tr><td>$(Html-Escape $db.database_name)</td><td><span class='$stCls'>$($db.state_desc)</span></td><td>$($db.recovery_model_desc)</td><td><span class='$shCls'>$shTxt</span></td><td><span class='$clCls'>$clTxt</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── backup status ───────────────────────────────────────────────────────────
    if ($backups.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>Backup Status</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Recovery</th><th>Last Full</th><th>Full Age (h)</th><th>Last Log</th><th>Log Age (h)</th></tr></thead><tbody>"
        foreach ($b in ($backups | Sort-Object database_name)) {
            $fh=0.0; [double]::TryParse($b.full_backup_age_hours,[ref]$fh) | Out-Null
            $lh=0.0; [double]::TryParse($b.log_backup_age_hours, [ref]$lh) | Out-Null
            $fCls = if (-not $b.last_full_backup -or $b.last_full_backup -eq '') { 'sv sv-red' } elseif ($fh -gt 25) { 'sv sv-orange' } else { 'sv sv-green' }
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
        $html += "</tbody></table></div>"
    }

    # ── transaction log usage ──────────────────────────────────────────────────
    if ($tlogs.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>Transaction Log Usage</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Recovery</th><th>Log Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($t in ($tlogs | Sort-Object { [double]($_.log_used_pct -as [double]) } -Descending)) {
            $lp = [double]($t.log_used_pct -as [double])
            $lpCls = if ($lp -gt 80) { 'sv sv-red' } elseif ($lp -gt 50) { 'sv sv-orange' } else { 'sv sv-green' }
            $html += "<tr><td>$(Html-Escape $t.database_name)</td><td>$($t.recovery_model_desc)</td><td>$(Fmt-Mb $t.log_size_mb)</td><td>$(Fmt-Mb $t.log_used_mb)</td><td>$(Fmt-Mb $t.log_free_mb)</td><td><span class='$lpCls'>$(Fmt-Pct $lp)%</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── wait statistics ─────────────────────────────────────────────────────────
    if ($waits.Count -gt 0) {
        $topWaits = @($waits | Sort-Object { [double]($_.pct_total_wait -as [double]) } -Descending | Select-Object -First 12)
        $html += "<hr class='section-sep'><h2>Top Wait Types</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Wait Type</th><th>Total Wait (ms)</th><th>Avg Wait (ms)</th><th>Count</th><th>% of Total</th></tr></thead><tbody>"
        foreach ($w in $topWaits) {
            $pct=0.0; [double]::TryParse($w.pct_total_wait,[ref]$pct) | Out-Null
            $concern = $cWaits.ContainsKey($w.wait_type)
            $wCls = if ($concern -and $pct -gt 10) { 'sv sv-orange' } elseif ($concern) { 'sv sv-blue' } else { '' }
            $wDisp = if ($wCls) { "<span class='$wCls'>$(Html-Escape $w.wait_type)</span>" } else { Html-Escape $w.wait_type }
            $bar = "<span class='mini-bar-track'><span class='mini-bar-fill $(if ($pct -gt 10 -and $concern) { 'bar-warn' } elseif ($pct -gt 30) { 'bar-crit' } else { 'bar-ok' })' style='width:$([Math]::Min($pct*2,100))%'></span></span>"
            $html += "<tr><td>$wDisp</td><td>$($w.total_wait_ms)</td><td>$($w.avg_wait_ms)</td><td>$($w.waiting_tasks_count)</td><td>$([Math]::Round($pct,1))% $bar</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── active sessions ─────────────────────────────────────────────────────────
    if ($sessions.Count -gt 0) {
        $blkCount = $blkSess.Count
        $runCount = @($sessions | Where-Object { $_.status -eq 'running' }).Count
        $html += "<hr class='mini-sep'><h2>Active Sessions ($($sessions.Count))</h2>"
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
                    $v = $s.$c ?? ''
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
    }

    # ── tempdb usage ───────────────────────────────────────────────────────────
    if ($tempdb.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>TempDB File Usage</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>File</th><th>Type</th><th>Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>User Obj (MB)</th><th>Version Store (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($tf in ($tempdb | Sort-Object { [double]($_.pct_used -as [double]) } -Descending)) {
            $tp = [double]($tf.pct_used -as [double])
            $tpCls = if ($tp -gt 80) { 'sv sv-red' } elseif ($tp -gt 60) { 'sv sv-orange' } else { 'sv sv-green' }
            $html += "<tr><td>$(Html-Escape $tf.logical_name)</td><td>$($tf.file_type)</td><td>$(Fmt-Mb $tf.size_mb)</td><td>$(Fmt-Mb $tf.used_mb)</td><td>$(Fmt-Mb $tf.free_mb)</td><td>$(Fmt-Mb $tf.user_objects_mb)</td><td>$(Fmt-Mb $tf.version_store_mb)</td><td><span class='$tpCls'>$(Fmt-Pct $tp)%</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── job failures ───────────────────────────────────────────────────────────
    if ($jobs.Count -gt 0) {
        $html += "<hr class='section-sep'><h2>Job Failures — Last 7 Days ($($jobs.Count) rows)</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Job</th><th>Step</th><th>Run Time</th><th>Duration</th><th>Message</th></tr></thead><tbody>"
        foreach ($j in $jobs) {
            $msgShort = if ($j.message.Length -gt 200) { $j.message.Substring(0,200) + '…' } else { $j.message }
            $html += "<tr><td>$(Html-Escape $j.job_name)</td><td>$(Html-Escape $j.step_name)</td><td>$(($j.run_datetime -replace '\.\d+$',''))</td><td>$(Html-Escape $j.run_duration)</td><td style='font-size:.75rem;color:#8b949e'>$(Html-Escape $msgShort)</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── DBCC CHECKDB ───────────────────────────────────────────────────────────
    if ($checkdb.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>DBCC CHECKDB</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>Last Good CHECKDB</th><th>Days Ago</th><th>Status</th></tr></thead><tbody>"
        foreach ($c in ($checkdb | Sort-Object { [int]($_.days_since_checkdb -as [int]) } -Descending)) {
            $days = $c.days_since_checkdb -as [int]
            $dayCls = if ($null -eq $days -or -not $c.last_good_checkdb -or $c.last_good_checkdb -eq '') { 'sv sv-red' } `
                      elseif ($days -gt 7) { 'sv sv-orange' } else { 'sv sv-green' }
            $daysDisp = if ($null -eq $days) { '—' } else { $days }
            $lastDisp = if (-not $c.last_good_checkdb -or $c.last_good_checkdb -eq '') { '<span class="sv sv-red">NEVER</span>' } `
                        else { Html-Escape ($c.last_good_checkdb -replace '\.\d+$','') }
            $html += "<tr><td>$(Html-Escape $c.database_name)</td><td>$lastDisp</td><td><span class='$dayCls'>$daysDisp</span></td><td>$(Html-Escape $c.checkdb_status)</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── suspect pages ──────────────────────────────────────────────────────────
    if ($suspects.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>Suspect Pages ($($suspects.Count))</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Database</th><th>File</th><th>Page</th><th>Event Type</th><th>Error Count</th><th>Last Update</th></tr></thead><tbody>"
        foreach ($sp in $suspects) {
            $evCls = if ($sp.event_type -match 'Restored|Repaired|Deallocated') { 'sv sv-gray' } else { 'sv sv-red' }
            $html += "<tr><td>$(Html-Escape $sp.database_name)</td><td>$($sp.file_id)</td><td>$($sp.page_id)</td><td><span class='$evCls'>$(Html-Escape $sp.event_type)</span></td><td>$($sp.error_count)</td><td>$(($sp.last_update_date -replace '\.\d+$',''))</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── I/O stats ──────────────────────────────────────────────────────────────
    if ($ioStats.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>I/O Usage (since SQL Server restart)</h2><div class='table-wrap'><table>"
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
        $html += "</tbody></table></div>"
    }

    # ── missing indexes ────────────────────────────────────────────────────────
    if ($missingIdx.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>Missing Index Candidates ($($missingIdx.Count))</h2>"
        $html += "<p class='no-data' style='margin-bottom:12px'>Impact scores reset on SQL Server restart. Review carefully — creating every suggestion causes index bloat and write overhead.</p>"
        $html += "<div class='table-wrap'><table><thead><tr><th>Table</th><th>Impact Score</th><th>Improvement %</th><th>Seeks</th><th>Equality Cols</th><th>Inequality Cols</th><th>Include Cols</th><th>Suggested Statement</th></tr></thead><tbody>"
        foreach ($ix in ($missingIdx | Sort-Object { [double]($_.impact_score -as [double]) } -Descending)) {
            $imp  = [double]($ix.impact_score -as [double])
            $impCls = if ($imp -gt 100000) { 'sv sv-orange' } else { '' }
            $impDisp = if ($impCls) { "<span class='$impCls'>$([Math]::Round($imp,0).ToString('N0'))</span>" } else { [Math]::Round($imp,0).ToString('N0') }
            $stmtShort = if ($ix.suggested_statement.Length -gt 80) { $ix.suggested_statement.Substring(0,80) + '…' } else { $ix.suggested_statement }
            $html += "<tr><td>$(Html-Escape $ix.table_name)</td><td>$impDisp</td><td>$(Fmt-Pct ($ix.avg_improvement_pct -as [double]))%</td><td>$($ix.user_seeks)</td><td style='font-size:.75rem'>$(Html-Escape $ix.equality_columns)</td><td style='font-size:.75rem'>$(Html-Escape $ix.inequality_columns)</td><td style='font-size:.75rem'>$(Html-Escape $ix.included_columns)</td><td><code style='font-size:.7rem;color:#8b949e;word-break:break-all'>$(Html-Escape $stmtShort)</code></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── security — weak logins ──────────────────────────────────────────────────
    if ($logins.Count -gt 0) {
        $html += "<hr class='section-sep'><h2>Login Security</h2><div class='table-wrap'><table>"
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
        $html += "</tbody></table></div>"
    }

    # ── memory config ──────────────────────────────────────────────────────────
    if ($memConfig.Count -gt 0) {
        $mc = $memConfig[0]
        $html += "<hr class='mini-sep'><h2>Memory Configuration</h2><div class='info-card-grid'>"
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
        $html += "</div>"
    }

    # ── error log ──────────────────────────────────────────────────────────────
    if ($errors.Count -gt 0) {
        $html += "<hr class='mini-sep'><h2>Error Log — Last 24h ($($errors.Count) entries)</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Time</th><th>Source</th><th>Message</th></tr></thead><tbody>"
        foreach ($e in $errors) {
            $msgShort = if ($e.log_text.Length -gt 300) { $e.log_text.Substring(0,300) + '…' } else { $e.log_text }
            $html += "<tr><td style='white-space:nowrap'>$(($e.log_date -replace '\.\d+$',''))</td><td>$(Html-Escape $e.process_info)</td><td style='font-size:.75rem'>$(Html-Escape $msgShort)</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    Wrap-Page 'Health Check' $html '' 'review'
}

# ── disk dashboard ─────────────────────────────────────────────────────────────

function Build-DiskPage([string]$folder) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'

    # Resolve bare folder name (e.g. ".-20260531-095824") to full path
    if ($folder -and -not [System.IO.Path]::IsPathRooted($folder)) {
        $folder = Join-Path $hcRoot $folder
    }
    if (-not $folder) {
        if (Test-Path $hcRoot) {
            $latest = Get-ChildItem -LiteralPath $hcRoot -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $folder = $latest.FullName }
        }
    }

    $folderEnc  = Html-Escape ($folder ?? '')
    $defaultSrv = if ($env:DBASCRIPTS_SERVER) { Html-Escape $env:DBASCRIPTS_SERVER } else { '' }
    $srvHint    = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { 'local ( . )' }
    $html = @"
<div style='display:flex;align-items:flex-start;justify-content:space-between;flex-wrap:wrap;gap:10px;margin-bottom:16px'>
  <form class='folder-row' style='margin:0;flex:1;min-width:0' method='get' action='/disk'>
    <label>Folder:</label>
    <input class='folder-input' name='folder' value='$folderEnc' placeholder='Leave blank for most recent…'>
    <button type='submit' class='folder-btn'>Load</button>
  </form>
  <div class='run-bar' style='flex-shrink:0'>
    <label>Server:</label>
    <input id='hc-srv' class='server-input' placeholder='$srvHint' value='$defaultSrv' autocomplete='off'>
    <button id='hc-run-btn' class='run-btn' onclick='runHealthcheck("disk")'>Run Disk Check &#9654;</button>
  </div>
</div>
<div id='hc-run-err' class='run-error' style='display:none;margin-bottom:10px'></div>
<div id='hc-overlay' class='run-overlay'>
  <div class='run-spinner'></div>
  <div class='run-spinner-label'>Collecting disk and storage data…</div>
</div>
<script>
async function runHealthcheck(page){
  const srv=document.getElementById('hc-srv').value.trim()||'.';
  const btn=document.getElementById('hc-run-btn');
  const err=document.getElementById('hc-run-err');
  document.getElementById('hc-overlay').style.display='flex';
  btn.disabled=true;err.style.display='none';
  try{
    const r=await fetch('/api/run-healthcheck?server='+encodeURIComponent(srv)+'&page='+page);
    const d=await r.json();
    if(d.ok){window.location.href=d.url;return;}
    err.textContent=d.error||'Unknown error';err.style.display='';
  }catch(e){err.textContent='Request failed: '+e.message;err.style.display='';}
  document.getElementById('hc-overlay').style.display='none';
  btn.disabled=false;
}
</script>
"@

    if (-not $folder -or -not (Test-Path -LiteralPath $folder)) {
        $html += "<p class='no-data'>No healthcheck folder found. Run <code>Invoke-HealthCheckCollection.ps1</code> first.</p>"
        return Wrap-Page 'Disk Space' $html '' 'disk'
    }

    $html += "<p class='mode-badge'>Folder: $(Html-Escape $folder)</p>"

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
        $html += "<div class='disk-grid'>"
        foreach ($d in ($drives | Sort-Object { [double]($_.free_pct -as [double]) })) {
            $freePct = [double]($d.free_pct -as [double])
            $usedPct = [Math]::Round(100.0 - $freePct, 1)
            $cardCls = if ($freePct -lt 10) { 'crit' } elseif ($freePct -lt 20) { 'warn' } else { '' }
            $barCls  = if ($freePct -lt 10) { 'bar-crit' } elseif ($freePct -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $volName = if ($d.logical_volume_name -and $d.logical_volume_name.Trim() -ne '') {
                           Html-Escape $d.logical_volume_name } else { '' }
            $html += @"
<div class='disk-card $cardCls'>
  <div class='disk-mount'>$(Html-Escape $d.volume_mount_point)</div>
  <div class='disk-vol'>$volName</div>
  <div class='bar-track'><div class='bar-fill $barCls' style='width:${usedPct}%'></div></div>
  <div class='disk-stats'>
    <span><strong>$([Math]::Round(($d.total_gb -as [double]),2)) GB</strong> total</span>
    <span><strong>$([Math]::Round(($d.used_gb  -as [double]),2)) GB</strong> used ($(Fmt-Pct $usedPct)%)</span>
    <span><strong>$([Math]::Round(($d.free_gb  -as [double]),2)) GB</strong> free ($(Fmt-Pct $freePct)%)</span>
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
        # Build chart data — top 12 by data size, remainder bucketed as "Other"
        $MAX_SLICES = 12
        $byDataSize = @($dbSizes | Sort-Object { [double]($_.data_size_mb -as [double]) } -Descending)
        $chartRows  = if ($byDataSize.Count -le $MAX_SLICES) { $byDataSize } else {
            $main  = @($byDataSize | Select-Object -First $MAX_SLICES)
            $rest  = @($byDataSize | Select-Object -Skip  $MAX_SLICES)
            $oData = [Math]::Round(($rest | Measure-Object { [double]($_.data_size_mb -as [double]) } -Sum).Sum, 1)
            $oLog  = [Math]::Round(($rest | Measure-Object { [double]($_.log_size_mb  -as [double]) } -Sum).Sum, 1)
            $oFree = [Math]::Round(($rest | Measure-Object { [double]($_.data_free_mb -as [double]) } -Sum).Sum, 1)
            $oLFr  = [Math]::Round(($rest | Measure-Object { [double]($_.log_free_mb  -as [double]) } -Sum).Sum, 1)
            @($main) + @([PSCustomObject]@{
                database_name = '(Other '+$rest.Count+' DBs)'
                data_size_mb  = $oData; log_size_mb  = $oLog
                data_free_mb  = $oFree; log_free_mb  = $oLFr
                data_free_pct = 0;      log_free_pct = 0
            })
        }
        $cLabels    = ($chartRows | ForEach-Object { $_.database_name | ConvertTo-Json }) -join ','
        $cDataMb    = ($chartRows | ForEach-Object { [Math]::Round(($_.data_size_mb -as [double]),1) }) -join ','
        $cLogMb     = ($chartRows | ForEach-Object { [Math]::Round(($_.log_size_mb  -as [double]),1) }) -join ','
        $cUsedMb    = ($chartRows | ForEach-Object {
            [Math]::Round([Math]::Max(($_.data_size_mb -as [double]) - ($_.data_free_mb -as [double]), 0), 1)
        }) -join ','
        $cFreeMb    = ($chartRows | ForEach-Object { [Math]::Round(($_.data_free_mb -as [double]),1) }) -join ','
        $cLogUsedMb = ($chartRows | ForEach-Object {
            [Math]::Round([Math]::Max(($_.log_size_mb -as [double]) - ($_.log_free_mb -as [double]), 0), 1)
        }) -join ','
        $cLogFreeMb = ($chartRows | ForEach-Object { [Math]::Round(($_.log_free_mb -as [double]),1) }) -join ','

        $html += @"
<script src='https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'></script>
<div style='display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:14px'>
  <div class='chart-wrap'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px'>Data File Sizes (MB)</div>
    <canvas id='ch-data' style='max-height:260px'></canvas>
  </div>
  <div class='chart-wrap'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px'>Log File Sizes (MB)</div>
    <canvas id='ch-log' style='max-height:260px'></canvas>
  </div>
</div>
<div style='display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:20px'>
  <div class='chart-wrap'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px'>Data Files — Used vs Free (MB)</div>
    <canvas id='ch-bar-data' style='max-height:280px'></canvas>
  </div>
  <div class='chart-wrap'>
    <div style='font-size:.75rem;color:#8b949e;font-weight:600;text-transform:uppercase;letter-spacing:.05em;margin-bottom:10px'>Log Files — Used vs Free (MB)</div>
    <canvas id='ch-bar-log' style='max-height:280px'></canvas>
  </div>
</div>
<script>
(function(){
const L=[$cLabels],DM=[$cDataMb],LM=[$cLogMb],UM=[$cUsedMb],FM=[$cFreeMb],LUM=[$cLogUsedMb],LFM=[$cLogFreeMb];
const C=['#58a6ff','#3fb950','#f78166','#d2a8ff','#ffa657','#79c0ff','#56d364','#ff7b72','#e3b341','#a5d6ff','#7ee787','#ffa8a8','#ff9e64'];
const dOpts={responsive:true,maintainAspectRatio:true,plugins:{legend:{position:'right',
  labels:{color:'#c9d1d9',boxWidth:11,padding:9,font:{size:11}}}}};
const bOpts=()=>({responsive:true,indexAxis:'y',
  plugins:{legend:{labels:{color:'#c9d1d9'}}},
  scales:{x:{stacked:true,ticks:{color:'#8b949e'},grid:{color:'#21262d'}},
          y:{stacked:true,ticks:{color:'#8b949e'},grid:{color:'#21262d'}}}});
new Chart(document.getElementById('ch-data'),{type:'doughnut',
  data:{labels:L,datasets:[{data:DM,backgroundColor:C.map(c=>c+'cc'),borderColor:C,borderWidth:1}]},options:dOpts});
new Chart(document.getElementById('ch-log'),{type:'doughnut',
  data:{labels:L,datasets:[{data:LM,backgroundColor:C.map(c=>c+'cc'),borderColor:C,borderWidth:1}]},options:dOpts});
new Chart(document.getElementById('ch-bar-data'),{type:'bar',
  data:{labels:L,datasets:[
    {label:'Used (MB)',data:UM,backgroundColor:'#58a6ffbb',borderColor:'#58a6ff',borderWidth:1},
    {label:'Free (MB)',data:FM,backgroundColor:'#3fb95055',borderColor:'#3fb950',borderWidth:1}]},
  options:bOpts()});
new Chart(document.getElementById('ch-bar-log'),{type:'bar',
  data:{labels:L,datasets:[
    {label:'Used (MB)',data:LUM,backgroundColor:'#d2a8ffbb',borderColor:'#d2a8ff',borderWidth:1},
    {label:'Free (MB)',data:LFM,backgroundColor:'#3fb95055',borderColor:'#3fb950',borderWidth:1}]},
  options:bOpts()});
})();
</script>
"@

        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Data (MB)</th><th>Data Free</th><th>Log (MB)</th><th>Log Free</th></tr></thead><tbody>"
        foreach ($db in $dbSizes) {
            $dfp = [double]($db.data_free_pct -as [double])
            $lfp = [double]($db.log_free_pct  -as [double])
            $dbc = if ($dfp -lt 10) { 'bar-crit' } elseif ($dfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $lbc = if ($lfp -lt 10) { 'bar-crit' } elseif ($lfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $dfCell = "$(Fmt-Mb $db.data_free_mb) MB ($(Fmt-Pct $dfp)%)<span class='mini-bar-track'><span class='mini-bar-fill $dbc' style='width:${dfp}%'></span></span>"
            $lfCell = "$(Fmt-Mb $db.log_free_mb) MB ($(Fmt-Pct $lfp)%)<span class='mini-bar-track'><span class='mini-bar-fill $lbc' style='width:${lfp}%'></span></span>"
            $html += "<tr><td>$(Html-Escape $db.database_name)</td><td>$(Fmt-Mb $db.data_size_mb)</td><td>$dfCell</td><td>$(Fmt-Mb $db.log_size_mb)</td><td>$lfCell</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── Transaction log usage ─────────────────────────────────────────────────
    $html += "<hr class='mini-sep'><h2>Transaction Log Usage</h2>"
    if (-not $tlogs) {
        $html += "<p class='no-data'>No <code>tlog-usage.csv</code> in this folder.</p>"
    } else {
        $sorted = @($tlogs | Sort-Object { [double]($_.log_used_pct -as [double]) } -Descending)
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Recovery</th><th>Log Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($t in $sorted) {
            $pct = [double]($t.log_used_pct -as [double])
            $svCls = if ($pct -gt 80) { 'sv-red' } elseif ($pct -gt 50) { 'sv-orange' } else { 'sv-green' }
            $html += "<tr><td>$(Html-Escape $t.database_name)</td><td>$($t.recovery_model_desc)</td><td>$(Fmt-Mb $t.log_size_mb)</td><td>$(Fmt-Mb $t.log_used_mb)</td><td>$(Fmt-Mb $t.log_free_mb)</td><td><span class='sv $svCls'>$(Fmt-Pct $pct)%</span></td></tr>"
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
$listener.Start()

Write-Host "dba-scripts UI  →  http://localhost:$Port/"
Write-Host "Press Ctrl+C to stop."

try {
    while ($listener.IsListening) {
        $ctx  = $listener.GetContext()
        $req  = $ctx.Request
        $res  = $ctx.Response
        $url  = $req.Url.AbsolutePath
        $qs   = [System.Web.HttpUtility]::ParseQueryString($req.Url.Query)

        $contentType = 'text/html; charset=utf-8'
        $statusCode  = 200
        $body = try { switch ($url) {
            '/'         { Build-HomePage }
            '/search'   { Build-SearchPage ($qs['q'] ?? '') }
            '/view'     { Build-ViewPage   ($qs['p'] ?? '') }
            '/csvs'     { Build-CsvListPage }
            '/csv'      { Build-CsvViewPage ($qs['p'] ?? '') }
            '/review'   { Build-ReviewPage  ($qs['folder'] ?? '') }
            '/disk'     { Build-DiskPage    ($qs['folder'] ?? '') }
            '/api/csv'  {
                $contentType = 'application/json; charset=utf-8'
                $p = $qs['p'] ?? ''
                $fp = Join-Path $repoRoot $p
                if (Test-Path $fp) { ConvertTo-Json2 (Get-CsvJson $fp) }
                else { '{"error":"not found"}' }
            }
            '/api/run' {
                $contentType = 'application/json; charset=utf-8'
                $p      = $qs['p']      ?? ''
                $svr    = ($qs['server'] ?? '').Trim()
                $dryRun = $qs['dryrun'] -eq '1'
                if (-not $svr) { $svr = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' } }

                $fullRunPath = Join-Path $repoRoot $p
                if (-not (Test-Path -LiteralPath $fullRunPath)) {
                    "{`"ok`":false,`"error`":`"Script not found: $(($p -replace '"','\"'))`"}"
                    break
                }

                $sName  = [IO.Path]::GetFileNameWithoutExtension($fullRunPath)
                $sExt   = [IO.Path]::GetExtension($fullRunPath).ToLower()
                $cat    = if ($p -match '(^|[\\/])sql[\\/]([^\\/]+)[\\/]')            { $Matches[2] }
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
                        # For DDL-generator SQL files (Generate-*), route to the matching PS wrapper
                        # so MaxCharLength and single-cell CSV are handled correctly.
                        $psWrapper = $null
                        if ($sName -match '^Generate-') {
                            $psWrapper = Get-ChildItem -Path (Join-Path $repoRoot 'powershell') `
                                -Recurse -Filter "$sName.ps1" -File -ErrorAction SilentlyContinue |
                                Select-Object -First 1
                        }
                        if ($psWrapper) {
                            & $psWrapper.FullName -ServerInstance $svr -OutputFormat 'Csv' `
                                                  -OutputPath $csvPath -ErrorAction Stop
                        } else {
                            $runner = Join-Path $repoRoot 'helpers\local-sql\Invoke-RepoSql.ps1'
                            & $runner -ScriptPath $scriptToRun -ServerInstance $svr -Database 'master' `
                                      -OutputFormat 'Csv' -OutputPath $csvPath -ErrorAction Stop
                        }
                    } else {
                        & $scriptToRun -ServerInstance $svr -OutputFormat 'Csv' -OutputPath $csvPath -ErrorAction Stop
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
                    $errMsg = ($_.Exception.Message -replace '"','\"' -replace '\r?\n',' ')
                    "{`"ok`":false,`"error`":`"$errMsg`"}"
                } finally {
                    $env:DBASCRIPTS_BATCH = $null
                    if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -ErrorAction SilentlyContinue }
                }
            }
            '/api/run-healthcheck' {
                $contentType = 'application/json; charset=utf-8'
                $svr  = ($qs['server'] ?? '').Trim()
                $page = $qs['page']   ?? 'review'
                if (-not $svr) { $svr = if ($env:DBASCRIPTS_SERVER) { $env:DBASCRIPTS_SERVER } else { '.' } }
                $collScript = Join-Path $repoRoot 'powershell\reporting\Invoke-HealthCheckCollection.ps1'
                if (-not (Test-Path $collScript)) {
                    '{"ok":false,"error":"Invoke-HealthCheckCollection.ps1 not found"}'; break
                }
                try {
                    & $collScript -ServerInstance $svr -ErrorAction Stop
                    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
                    $latest = Get-ChildItem -LiteralPath $hcRoot -Directory -ErrorAction SilentlyContinue |
                              Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($latest) {
                        # Redirect to the page with no folder param — the page auto-picks the
                        # most recent folder, which is exactly the one just collected.
                        # Avoids all URL encoding / query-string parsing edge cases.
                        "{`"ok`":true,`"url`":`"/$page`"}"
                    } else {
                        '{"ok":false,"error":"Collection finished but no output folder found."}'
                    }
                } catch {
                    $errMsg = $_.Exception.Message -replace '"','\"' -replace '\r?\n',' '
                    "{`"ok`":false,`"error`":`"$errMsg`"}"
                }
            }
            '/api/clear-output' {
                $contentType = 'application/json; charset=utf-8'
                if ($req.HttpMethod -ne 'POST') { '{"ok":false,"error":"POST required"}'; break }
                try {
                    $outDir  = Join-Path $repoRoot 'output-files'
                    $deleted = 0
                    if (Test-Path $outDir) {
                        $files = Get-ChildItem -Path $outDir -Recurse -File -ErrorAction SilentlyContinue |
                                 Where-Object { $_.Name -ne '.gitkeep' }
                        $deleted = $files.Count
                        $files | Remove-Item -Force -ErrorAction SilentlyContinue
                        # Remove empty subdirectories deepest-first
                        Get-ChildItem -Path $outDir -Recurse -Directory -ErrorAction SilentlyContinue |
                            Sort-Object FullName -Descending |
                            Where-Object { @(Get-ChildItem $_.FullName -ErrorAction SilentlyContinue).Count -eq 0 } |
                            Remove-Item -Force -ErrorAction SilentlyContinue
                    }
                    "{`"ok`":true,`"deleted`":$deleted}"
                } catch {
                    $errMsg = $_.Exception.Message -replace '"','\"' -replace '\r?\n',' '
                    "{`"ok`":false,`"error`":`"$errMsg`"}"
                }
            }
            '/api/save-png' {
                $contentType = 'application/json; charset=utf-8'
                try {
                    $reader  = [System.IO.StreamReader]::new($req.InputStream, [System.Text.Encoding]::UTF8)
                    $payload = $reader.ReadToEnd() | ConvertFrom-Json
                    $reader.Dispose()
                    $csvFull = Join-Path $repoRoot $payload.relPath
                    $pngFull = [System.IO.Path]::ChangeExtension($csvFull, '.png')
                    $b64     = $payload.imageData -replace '^data:image/png;base64,', ''
                    [System.IO.File]::WriteAllBytes($pngFull, [Convert]::FromBase64String($b64))
                    $shortName = [System.IO.Path]::GetFileName($pngFull)
                    "{`"ok`":true,`"file`":`"$shortName`"}"
                } catch {
                    "{`"ok`":false,`"error`":`"$($_.Exception.Message)`"}"
                }
            }
            default     { $statusCode = 404; Wrap-Page '404' "<p class='empty'>Page not found: $(Html-Escape $url)</p>" }
        } } catch {
            $statusCode  = 500
            $contentType = 'text/html; charset=utf-8'
            Wrap-Page 'Error' "<h2>Error</h2><pre style='color:#f78166'>$(Html-Escape $_.Exception.Message)`n$(Html-Escape $_.ScriptStackTrace)</pre>"
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $res.ContentType     = $contentType
        $res.ContentLength64 = $bytes.Length
        $res.StatusCode      = $statusCode
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    $listener.Dispose()
}
