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
.pie-select{background:#0d1117;border:1px solid #30363d;color:#c9d1d9;border-radius:6px;padding:5px 10px;font-size:.82rem}
.pie-select:focus{outline:none;border-color:#58a6ff}
.chart-wrap canvas{max-height:400px}
'@

# ── page wrapper ───────────────────────────────────────────────────────────────

function Wrap-Page([string]$title, [string]$body, [string]$q='', [string]$active='scripts') {
    $qEsc = Html-Escape $q
    $navScripts = if ($active -eq 'scripts') { "class='active'" } else { '' }
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

init();
</script>
"@
    Wrap-Page $name $body '' 'csvs'
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
            '/api/csv'  {
                $contentType = 'application/json; charset=utf-8'
                $p = $qs['p'] ?? ''
                $fp = Join-Path $repoRoot $p
                if (Test-Path $fp) { ConvertTo-Json2 (Get-CsvJson $fp) }
                else { '{"error":"not found"}' }
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
