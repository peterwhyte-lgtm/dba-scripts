<#
.SYNOPSIS
Adds the standard SQL script header comment to SQL files that are missing it.

.DESCRIPTION
Scans dba-scripts/sql and prepends a standard header block of the form:
/*
Script Name : <file name>
Description : Returns information for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

This is intended to standardize script metadata across the repo.
#>

function Get-ScriptDescription {
    param([string]$FileName)

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    $title = [regex]::Replace($name, '([A-Z]+)([A-Z][a-z])', '$1 $2')
    $title = [regex]::Replace($title, '([a-z0-9])([A-Z])', '$1 $2')
    $title = $title -replace '[-_]', ' '
    $title = $title -replace '\bGet\b', ''
    $title = $title -replace '\s+', ' '
    $title = $title.Trim()

    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = 'database information'
    }

    return "Returns $title for DBA review and troubleshooting."
}

$root = Resolve-Path (Join-Path $PSScriptRoot '..\sql')
$files = Get-ChildItem -Path $root -Recurse -Filter '*.sql' | Where-Object {
    $_.FullName -notmatch '\\docs\\'
}

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $description = Get-ScriptDescription -FileName $file.Name

    if ($text -match 'Script Name\s*:\s*' -and $text -match 'Description\s*:\s*' -and $text -match 'Author\s*:\s*') {
        $text = $text -replace 'Description\s*:\s*.*(?=\r?\nAuthor\s*:\s*)', "Description : $description"
    }
    else {
        $header = @"
/*
Script Name : $name
Description : $description
Author      : Peter Whyte (https://sqldba.blog)
*/

"@
        $text = $header + $text
    }

    Set-Content -LiteralPath $file.FullName -Value $text -Encoding UTF8
    Write-Host "Updated: $($file.FullName)" -ForegroundColor Green
}
