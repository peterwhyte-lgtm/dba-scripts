<#
Creates multiple SQL Server databases with randomized names and specified initial sizes.
- Uses SMO when available, falls back to `sqlcmd`/`Invoke-Sqlcmd` to determine default paths.
- Defaults: 25 MB data file, 10 MB log file.

Example:
  powershell -ExecutionPolicy Bypass -File .\MSSQL\create-multiple-databases.ps1 -ServerInstance localhost -DatabaseCount 3000 -Prefix migdb

Note: Run as a user with sufficient SQL Server privileges. Creating thousands of databases can take time and disk space.
#>

param(
    [Parameter(Mandatory=$false)] [string] $ServerInstance = ".",
    [Parameter(Mandatory=$true)]  [int] $DatabaseCount,
    [Parameter(Mandatory=$false)] [string] $Prefix = "migdb",
    [Parameter(Mandatory=$false)] [int] $InitialSizeMB = 25,
    [Parameter(Mandatory=$false)] [int] $LogSizeMB = 10,
    [Parameter(Mandatory=$false)] [int] $RandomSuffixLength = 8,
    [Parameter(Mandatory=$false)] [int] $StartIndex = 1,
    [Parameter(Mandatory=$false)] [string] $OutputFile = "$PWD\created_databases.csv",
    [Parameter(Mandatory=$false)] [int] $BatchDelayMs = 10
)

function Get-DefaultPaths-SMO {
    try {
        [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
        $svr = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance
        $data = $svr.Settings.DefaultFile
        $log  = $svr.Settings.DefaultLog
        if ($data -and $log) { return @{ Data=$data; Log=$log }
        return $null
    } catch {
        return $null
    }
}

function Get-DefaultPaths-Registry {
    # Uses xp_instance_regread to read default data/log paths from registry. Requires rights to run xp_instance_regread.
    $q = @"
SET NOCOUNT ON;
DECLARE @d nvarchar(260), @l nvarchar(260);
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\\Microsoft\\MSSQLServer\\MSSQLServer', N'DefaultData', @d OUTPUT;
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\\Microsoft\\MSSQLServer\\MSSQLServer', N'DefaultLog', @l OUTPUT;
SELECT @d as DataPath, @l as LogPath;
"@

    if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        try {
            $res = Invoke-Sqlcmd -ServerInstance $ServerInstance -Query $q -QueryTimeout 60
            if ($res) { return @{ Data=$res.DataPath.Trim(); Log=$res.LogPath.Trim() } }
        } catch { }
    }
    # fallback to sqlcmd
    try {
        $sqlcmd = "sqlcmd -S $ServerInstance -Q \"$($q.Replace('"','\"'))\" -h -1 -W"
        $out = & cmd /c $sqlcmd 2>$null
        if ($out) {
            $parts = $out -split "\s+"
            if ($parts.Length -ge 2) { return @{ Data=$parts[0].Trim(); Log=$parts[1].Trim() } }
        }
    } catch { }
    return $null
}

function New-RandomSuffix($len) {
    $chars = ([char[]](48..57 + 97..122))
    -join (1..$len | ForEach-Object { $chars | Get-Random })
}

# Get default paths
$paths = Get-DefaultPaths-SMO
if (-not $paths) { $paths = Get-DefaultPaths-Registry }
if (-not $paths) {
    Write-Warning "Unable to determine SQL Server default data/log paths. Script will attempt creation without explicit file paths; files will be created in SQL Server default locations."
}

[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
$server = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance

$created = New-Object System.Collections.Generic.List[string]
$endIndex = $StartIndex + $DatabaseCount - 1

for ($i = $StartIndex; $i -le $endIndex; $i++) {
    $suffix = New-RandomSuffix -len $RandomSuffixLength
    $name = "${Prefix}_${i}_${suffix}"

    if ($server.Databases[$name]) {
        Write-Host "Skipping existing database: $name"
        continue
    }

    if ($paths) {
        $dataPath = $paths.Data.TrimEnd('\')
        $logPath  = $paths.Log.TrimEnd('\')
        $mdf = Join-Path $dataPath "${name}.mdf"
        $ldf = Join-Path $logPath  "${name}_log.ldf"

        $tsql = @"
CREATE DATABASE [$name]
ON PRIMARY (NAME = N'${name}_Data', FILENAME = N'${mdf}', SIZE = ${InitialSizeMB}MB, FILEGROWTH = 10MB)
LOG ON (NAME = N'${name}_Log', FILENAME = N'${ldf}', SIZE = ${LogSizeMB}MB, FILEGROWTH = 10MB);
"@
    } else {
        # rely on SQL Server default locations; specify sizes via the CREATE syntax without explicit file paths
        $tsql = "CREATE DATABASE [$name] (NAME = N'${name}_Data', SIZE = ${InitialSizeMB}MB)"
    }

    try {
        $server.ConnectionContext.ExecuteNonQuery($tsql)
        Write-Host "Created: $name"
        $created.Add($name) | Out-Null
    } catch {
        Write-Warning "Failed creating $name : $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds $BatchDelayMs
}

if ($OutputFile) {
    try {
        $created | Export-Csv -Path $OutputFile -NoTypeInformation -Force
        Write-Host "Created database list exported to: $OutputFile"
    } catch {
        Write-Warning "Failed to export created database list: $($_.Exception.Message)"
    }
}

Write-Host "Done. Total created: $($created.Count)"
