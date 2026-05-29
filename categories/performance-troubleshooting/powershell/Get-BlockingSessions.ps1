<#
.SYNOPSIS
Returns current blocking sessions and wait information.
#>

param(
    [string]$SqlInstance = '.',
    [string]$DatabaseName = 'master'
)

$connectionString = "Server=$SqlInstance;Database=$DatabaseName;Integrated Security=True;TrustServerCertificate=True"

$sql = @'
SELECT
    r.session_id,
    r.status,
    r.blocking_session_id,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.logical_reads,
    r.reads,
    r.writes,
    s.host_name,
    s.program_name,
    s.login_name,
    t.text AS current_statement
FROM sys.dm_exec_requests r
LEFT JOIN sys.dm_exec_sessions s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0
   OR r.wait_type IS NOT NULL
ORDER BY r.blocking_session_id, r.session_id;
'@

Add-Type -AssemblyName System.Data
$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$command = New-Object System.Data.SqlClient.SqlCommand($sql, $connection)
$connection.Open()
$reader = $command.ExecuteReader()
$results = New-Object System.Collections.Generic.List[object]

while ($reader.Read()) {
    $results.Add([PSCustomObject]@{
        SessionId = [int]$reader['session_id']
        Status = [string]$reader['status']
        BlockingSessionId = [int]$reader['blocking_session_id']
        WaitType = [string]$reader['wait_type']
        WaitTimeMs = [int]$reader['wait_time']
        CPUTimeMs = [int]$reader['cpu_time']
        LogicalReads = [int]$reader['logical_reads']
        HostName = [string]$reader['host_name']
        ProgramName = [string]$reader['program_name']
        LoginName = [string]$reader['login_name']
        CurrentStatement = [string]$reader['current_statement']
    })
}

$connection.Close()

$results | Format-Table -AutoSize
