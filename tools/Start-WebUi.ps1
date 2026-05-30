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
param([int]$Port = 8787)

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

function Get-ScriptPurpose([string]$path) {
    try {
        foreach ($line in (Get-Content $path -TotalCount 10)) {
            if ($line -match 'Purpose\s*:\s*(.+)') { return $Matches[1].Trim() }
        }
    } catch {}
    return ''
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
h2{font-size:1rem;font-weight:600;color:#e6edf3;margin-bottom:12px;padding-bottom:6px;border-bottom:1px solid #21262d}
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
.table-wrap{overflow-x:auto;border:1px solid #30363d;border-radius:8px}
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
                $html += "<div class='card'><span class='badge $badgeClass'>$typeName</span><a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
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
    $content  = Get-Content $fullPath -Raw -Encoding UTF8
    $name     = [IO.Path]::GetFileNameWithoutExtension($relPath)
    $category = Split-Path (Split-Path $relPath -Parent) -Leaf
    $purpose  = Get-ScriptPurpose $fullPath
    $metaParts = @($category, ([IO.Path]::GetExtension($relPath).TrimStart('.').ToUpper()))
    if ($purpose) { $metaParts = @($purpose) + $metaParts }

    $body = @"
<div class='back'><a href='/'>← all scripts</a></div>
<div class='script-title'>$(Html-Escape $name)</div>
<div class='script-meta'>$(Html-Escape ($metaParts -join ' · '))</div>
<pre>$(Html-Escape $content)</pre>
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
        $html += "<div class='card'><span class='badge $badgeClass'>$($s.Type)</span><a href='/view?p=$relEnc'>$(Html-Escape $s.Name)</a>$purposeHtml</div>"
    }
    $html += '</div>'
    Wrap-Page "Search: $q" $html $q 'scripts'
}

function Build-CsvListPage {
    $csvs = @(Get-ChildItem "$repoRoot\output-files" -Recurse -Filter '*.csv' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike '*.tmp.csv' } |
        Sort-Object LastWriteTime -Descending)

    if (-not $csvs) {
        return Wrap-Page 'Output CSVs' "<h2>Output CSVs</h2><p class='empty'>No CSV files in output-files/ yet. Run a script first.</p>" '' 'csvs'
    }

    $grouped = $csvs | Group-Object { $_.Directory.FullName.Replace($repoRoot,'').TrimStart('\') }
    $html    = "<h2>Output CSVs ($($csvs.Count) files)</h2>"

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

    $body = @"
<div class='back'><a href='/csvs'>← output CSVs</a></div>
<div class='script-title'>$(Html-Escape $name)</div>
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

let chart=null,data=null,type='bar',pieCol='';
const active=new Set();
let sortCol=null,sortDir=1,visRows=[];

const isPie=()=>type==='pie'||type==='doughnut';

async function init(){
  data=await fetch('/api/csv?p=$relEnc').then(r=>r.json());
  if(!data.rows||!data.rows.length){
    document.getElementById('mode-badge').textContent='No data rows in this file.';
    return;
  }
  visRows=[...data.rows];
  const chartable=data.numericCols.length>=2;
  document.getElementById('mode-badge').textContent=chartable
    ?data.rows.length+' rows · '+data.numericCols.length+' numeric columns · chart + table'
    :data.rows.length+' rows · '+data.headers.length+' columns · table view';
  if(chartable){
    document.getElementById('chart-panel').style.display='';
    pieCol=data.numericCols[0]||'';
    data.numericCols.slice(0,4).forEach(c=>active.add(c));
    buildControls();renderChart();
  }
  renderTable();
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
    chart=new Chart(ctx,{type:type==='bar'?'bar':'line',data:{labels,datasets},options:{responsive:true,
      plugins:{legend:{labels:{color:'#c9d1d9'}}},
      scales:{x:{ticks:{color:'#8b949e',maxRotation:45},grid:{color:'#21262d'}},
              y:{ticks:{color:'#8b949e'},grid:{color:'#21262d'}}}}});
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
  html+=visRows.map(r=>'<tr>'+h.map(col=>'<td>'+fmtCell(r[col]??'')+'</td>').join('')+'</tr>').join('');
  document.getElementById('tbl').innerHTML=html+'</tbody>';
}

function fmtCell(val){
  const s=String(val);
  if(s===''||s==='NULL')return '<span class="null-val">—</span>';
  const k=s.toLowerCase().trim();
  if(SV[k])return '<span class="sv sv-'+SV[k]+'">'+esc(s)+'</span>';
  if(s.length>120)return '<span class="cell-long" onclick="this.classList.toggle(\'expanded\')" title="Click to expand">'+esc(s)+'</span>';
  return esc(s);
}
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

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
"@
    Wrap-Page $name $body '' 'csvs'
}

# ── health check review dashboard ──────────────────────────────────────────────

function Build-ReviewPage([string]$folder) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'
    if (-not $folder) {
        if (Test-Path $hcRoot) {
            $latest = Get-ChildItem -LiteralPath $hcRoot -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $folder = $latest.FullName }
        }
    }

    $folderEnc = Html-Escape ($folder ?? '')
    $html = @"
<form class='folder-row' method='get' action='/review'>
  <label>Healthcheck folder:</label>
  <input class='folder-input' name='folder' value='$folderEnc' placeholder='Leave blank for most recent…'>
  <button type='submit' class='folder-btn'>Load</button>
</form>
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
    foreach ($row in $backups) {
        $db = $row.database_name
        if (-not $row.last_full_backup -or $row.last_full_backup -eq '') { Add-F 'CRITICAL' 'Backup' $db 'No full backup on record' }
        elseif ([double]::TryParse($row.full_backup_age_hours,[ref]($h=0.0))) {
            if ($h -gt 25) { Add-F 'WARNING' 'Backup' $db "Full backup $([Math]::Round($h,1))h old (threshold 25h)" }
        }
        if ($row.recovery_model_desc -in @('FULL','BULK_LOGGED')) {
            if (-not $row.last_log_backup -or $row.last_log_backup -eq '') { Add-F 'WARNING' 'Backup' $db "$($row.recovery_model_desc) recovery but no log backup — log will grow unbounded" }
            elseif ([double]::TryParse($row.log_backup_age_hours,[ref]($lh=0.0)) -and $lh -gt 4) {
                Add-F 'WARNING' 'Backup' $db "Log backup $([Math]::Round($lh,1))h old (threshold 4h)"
            }
        }
    }
    foreach ($row in $tlogs) {
        $pctCol = if ($row.PSObject.Properties['log_used_pct']) { $row.log_used_pct } else { $row.log_used_percent }
        if ([double]::TryParse($pctCol,[ref]($pct=0.0)) -and $pct -gt 80) {
            Add-F 'WARNING' 'Transaction Log' $row.database_name "Log $pct% used ($($row.log_used_mb) MB of $($row.log_size_mb) MB)"
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
    foreach ($row in $checkdb) {
        if (-not $row.last_good_checkdb -or $row.last_good_checkdb -eq '') { Add-F 'WARNING' 'DBCC CHECKDB' $row.database_name 'No CHECKDB on record' }
        elseif ([int]::TryParse($row.days_since_checkdb,[ref]($d=0)) -and $d -gt 7) {
            Add-F 'WARNING' 'DBCC CHECKDB' $row.database_name "Last good CHECKDB $d days ago (threshold 7)"
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
    foreach ($row in $waits) {
        if ($cWaits.ContainsKey($row.wait_type) -and [double]::TryParse($row.pct_total_wait,[ref]($pct=0.0)) -and $pct -gt 10) {
            Add-F 'WARNING' 'Wait Statistics' $row.wait_type "$([Math]::Round($pct,1))% of wait time — $($cWaits[$row.wait_type])"
        }
    }
    foreach ($row in $memConfig) {
        if ([long]::TryParse($row.max_server_memory_mb,[ref]($mm=0L)) -and $mm -ge 2147483647) {
            Add-F 'WARNING' 'Memory Config' 'max server memory' 'Unconfigured (SQL Server default) — may consume all available RAM'
        }
    }
    foreach ($row in $dbSizes) {
        if ([double]::TryParse($row.data_free_pct,[ref]($fp=0.0)) -and $fp -lt 10) {
            Add-F 'WARNING' 'Disk Space' $row.database_name "Data files $fp% free ($($row.data_free_mb) MB free of $($row.data_size_mb) MB)"
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
    $html += "<h2>Findings</h2>"
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

    # ── instance & OS ───────────────────────────────────────────────────────────
    if ($svrInfo.Count -gt 0 -or $osHw.Count -gt 0) {
        $html += "<h2>Instance</h2><div class='info-card-grid'>"
        $instFields = @('sql_version','edition','product_level','server_name','is_clustered','is_hadr_enabled')
        foreach ($fld in ($instFields | Where-Object { $svrInfo.Count -gt 0 -and $svrInfo[0].PSObject.Properties[$_] })) {
            $html += "<div class='info-card'><div class='info-label'>$($fld -replace '_',' ')</div><div class='info-val'>$(Html-Escape $svrInfo[0].$fld)</div></div>"
        }
        $hwFields = @('os_version','cpu_count','physical_memory_mb','sqlserver_start_time')
        foreach ($fld in ($hwFields | Where-Object { $osHw.Count -gt 0 -and $osHw[0].PSObject.Properties[$_] })) {
            $html += "<div class='info-card'><div class='info-label'>$($fld -replace '_',' ')</div><div class='info-val'>$(Html-Escape $osHw[0].$fld)</div></div>"
        }
        $html += "</div>"
    }

    # ── databases ──────────────────────────────────────────────────────────────
    if ($dbHealth.Count -gt 0) {
        $html += "<h2>Databases ($($dbHealth.Count))</h2><div class='table-wrap'><table>"
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
        $html += "<h2>Backup Status</h2><div class='table-wrap'><table>"
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

    # ── wait statistics ─────────────────────────────────────────────────────────
    if ($waits.Count -gt 0) {
        $topWaits = @($waits | Sort-Object { [double]($_.pct_total_wait ?? 0) } -Descending | Select-Object -First 12)
        $html += "<h2>Top Wait Types</h2><div class='table-wrap'><table>"
        $html += "<thead><tr><th>Wait Type</th><th>Total Wait (ms)</th><th>Avg Wait (ms)</th><th>Count</th><th>% of Total</th></tr></thead><tbody>"
        foreach ($w in $topWaits) {
            $pct=0.0; [double]::TryParse($w.pct_total_wait,[ref]$pct) | Out-Null
            $concern = $cWaits.ContainsKey($w.wait_type)
            $wCls = if ($concern -and $pct -gt 10) { 'sv sv-orange' } elseif ($concern) { 'sv sv-blue' } else { '' }
            $wDisp = if ($wCls) { "<span class='$wCls'>$(Html-Escape $w.wait_type)</span>" } else { Html-Escape $w.wait_type }
            $bar = "<span class='mini-bar-track'><span class='mini-bar-fill $(if ($pct -gt 10 -and $concern) { 'bar-warn' } elseif ($pct -gt 30) { 'bar-crit' } else { 'bar-ok' })' style='width:$([ Math]::Min($pct*2,100))%'></span></span>"
            $html += "<tr><td>$wDisp</td><td>$($w.total_wait_ms)</td><td>$($w.avg_wait_ms)</td><td>$($w.waiting_tasks_count)</td><td>$([Math]::Round($pct,1))% $bar</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── active sessions ─────────────────────────────────────────────────────────
    if ($sessions.Count -gt 0) {
        $blkCount = $blkSess.Count
        $runCount = @($sessions | Where-Object { $_.status -eq 'running' }).Count
        $html += "<h2>Active Sessions ($($sessions.Count))</h2>"
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
            foreach ($s in ($sessions | Sort-Object { [int]($_.session_id ?? 0) })) {
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

    Wrap-Page 'Health Check' $html '' 'review'
}

# ── disk dashboard ─────────────────────────────────────────────────────────────

function Build-DiskPage([string]$folder) {
    $hcRoot = Join-Path $repoRoot 'output-files\healthcheck'

    if (-not $folder) {
        if (Test-Path $hcRoot) {
            $latest = Get-ChildItem -LiteralPath $hcRoot -Directory |
                      Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $folder = $latest.FullName }
        }
    }

    $folderEnc = Html-Escape ($folder ?? '')

    $html = @"
<form class='folder-row' method='get' action='/disk'>
  <label>Healthcheck folder:</label>
  <input class='folder-input' name='folder' value='$folderEnc' placeholder='Leave blank for most recent…'>
  <button type='submit' class='folder-btn'>Load</button>
</form>
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

    $drives     = Read-DiskCsv 'disk-space'
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
        foreach ($d in ($drives | Sort-Object { [double]$_.free_pct })) {
            $freePct = [double]($d.free_pct)
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
    <span><strong>$($d.total_gb) GB</strong> total</span>
    <span><strong>$($d.used_gb) GB</strong> used ($usedPct%)</span>
    <span><strong>$($d.free_gb) GB</strong> free ($freePct%)</span>
  </div>
</div>
"@
        }
        $html += "</div>"
    }

    # ── Database file space ───────────────────────────────────────────────────
    $html += "<h2>Database File Space</h2>"
    if (-not $dbSizes) {
        $html += "<p class='no-data'>No <code>database-sizes.csv</code> in this folder.</p>"
    } else {
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Data (MB)</th><th>Data Free</th><th>Log (MB)</th><th>Log Free</th></tr></thead><tbody>"
        foreach ($db in $dbSizes) {
            $dfp = [double]($db.data_free_pct)
            $lfp = [double]($db.log_free_pct)
            $dbc = if ($dfp -lt 10) { 'bar-crit' } elseif ($dfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $lbc = if ($lfp -lt 10) { 'bar-crit' } elseif ($lfp -lt 20) { 'bar-warn' } else { 'bar-ok' }
            $dfCell = "$($db.data_free_mb) MB ($dfp%)<span class='mini-bar-track'><span class='mini-bar-fill $dbc' style='width:${dfp}%'></span></span>"
            $lfCell = "$($db.log_free_mb) MB ($lfp%)<span class='mini-bar-track'><span class='mini-bar-fill $lbc' style='width:${lfp}%'></span></span>"
            $html += "<tr><td>$(Html-Escape $db.database_name)</td><td>$($db.data_size_mb)</td><td>$dfCell</td><td>$($db.log_size_mb)</td><td>$lfCell</td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── Transaction log usage ─────────────────────────────────────────────────
    $html += "<h2>Transaction Log Usage</h2>"
    if (-not $tlogs) {
        $html += "<p class='no-data'>No <code>tlog-usage.csv</code> in this folder.</p>"
    } else {
        $sorted = @($tlogs | Sort-Object { [double]$_.log_used_pct } -Descending)
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Recovery</th><th>Log Size (MB)</th><th>Used (MB)</th><th>Free (MB)</th><th>Used %</th></tr></thead><tbody>"
        foreach ($t in $sorted) {
            $pct = [double]($t.log_used_pct)
            $svCls = if ($pct -gt 80) { 'sv-red' } elseif ($pct -gt 50) { 'sv-orange' } else { 'sv-green' }
            $html += "<tr><td>$(Html-Escape $t.database_name)</td><td>$($t.recovery_model_desc)</td><td>$($t.log_size_mb)</td><td>$($t.log_used_mb)</td><td>$($t.log_free_mb)</td><td><span class='sv $svCls'>$pct%</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── File growth risk ──────────────────────────────────────────────────────
    $html += "<h2>File Growth Risk</h2>"
    if (-not $growthRisk) {
        $html += "<p class='no-data'>No <code>growth-risk.csv</code> here — re-run healthcheck with the updated collection script.</p>"
    } else {
        $html += "<div class='table-wrap'><table><thead><tr><th>Database</th><th>Data (MB)</th><th>Log (MB)</th><th>Total (MB)</th><th>Limit (MB)</th><th>Status</th></tr></thead><tbody>"
        foreach ($g in ($growthRisk | Sort-Object { [double]$_.total_mb } -Descending)) {
            $sCls = switch ($g.growth_status) {
                'AT_LIMIT'   { 's-crit' }
                'NEAR_LIMIT' { 's-warn' }
                'UNLIMITED'  { 's-gray' }
                default      { 's-ok'   }
            }
            $limitCell = if ([double]($g.growth_limit_mb) -eq 0) { '<span class="null-val">—</span>' } else { $g.growth_limit_mb }
            $html += "<tr><td>$(Html-Escape $g.database_name)</td><td>$($g.data_mb)</td><td>$($g.log_mb)</td><td>$($g.total_mb)</td><td>$limitCell</td><td><span class='status-badge $sCls'>$(Html-Escape $g.growth_status)</span></td></tr>"
        }
        $html += "</tbody></table></div>"
    }

    # ── Drive → file mapping ──────────────────────────────────────────────────
    if ($dbFiles) {
        $byDrive = $dbFiles | Group-Object drive_letter | Sort-Object Name
        if ($byDrive) {
            $html += "<h2>Files by Drive</h2>"
            $html += "<div class='table-wrap'><table><thead><tr><th>Drive</th><th>Database</th><th>Type</th><th>Size (MB)</th><th>Max (MB)</th><th>Autogrowth</th><th>Path</th></tr></thead><tbody>"
            foreach ($dg in $byDrive) {
                foreach ($f in ($dg.Group | Sort-Object database_name, file_type)) {
                    $maxCell = if ($f.max_size_mb -and $f.max_size_mb -ne '') { $f.max_size_mb } else { '<span class="null-val">unlimited</span>' }
                    $growthWarn = if ($f.growth_is_percent -in @('True','1','true','YES')) { " <span class='sv sv-orange'>%</span>" } else { '' }
                    $html += "<tr><td>$(Html-Escape $f.drive_letter)</td><td>$(Html-Escape $f.database_name)</td><td>$($f.file_type)</td><td>$($f.current_size_mb)</td><td>$maxCell</td><td>$(Html-Escape $f.auto_growth)$growthWarn</td><td title='$(Html-Escape $f.physical_path)'>$(Html-Escape ([System.IO.Path]::GetFileName($f.physical_path)))</td></tr>"
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
        $body = switch ($url) {
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
            default     { Wrap-Page '404' "<p class='empty'>Not found.</p>" }
        }

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $res.ContentType     = $contentType
        $res.ContentLength64 = $bytes.Length
        $res.StatusCode      = 200
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    $listener.Dispose()
}
