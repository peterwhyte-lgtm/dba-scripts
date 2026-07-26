/*
Script Name : Get-XeSessionActivity
Category    : traces
Purpose     : Reads and summarises Extended Events file target data for a named session.
              Returns unique caller combinations (login, hostname, app, database) with occurrence counts and time range.
              Primary use: reviewing DecommissionAudit or LoginActivity session output to determine if a database or server is still in active use.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-xe-session-activity/)
Requires    : VIEW SERVER STATE, read access to the XE output folder
*/
-- Blog: https://sqldba.blog/dba-scripts-get-xe-session-activity/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* ── Configuration ───────────────────────────────────────────────────────── */
DECLARE @SessionName NVARCHAR(128) = N'DecommissionAudit';
/* ─────────────────────────────────────────────────────────────────────────── */

/* Locate the file target path from the running session metadata */
DECLARE @FilePath NVARCHAR(500);

SELECT @FilePath =
    CAST(
        CAST(t.target_data AS XML).value(
            '(EventFileTarget/File/@name)[1]', 'nvarchar(500)')
    AS NVARCHAR(500))
FROM sys.dm_xe_sessions        s
JOIN sys.dm_xe_session_targets t ON t.event_session_address = s.address
WHERE s.name        = @SessionName
  AND t.target_name = 'event_file';

IF @FilePath IS NULL
BEGIN
    /* Session stopped but definition still exists — get path from session fields */
    SELECT @FilePath = CONVERT(NVARCHAR(500), f.value)
    FROM sys.server_event_sessions          ses
    JOIN sys.server_event_session_targets   t ON t.event_session_id = ses.event_session_id
                                             AND t.name = 'event_file'
    JOIN sys.server_event_session_fields    f ON f.event_session_id = ses.event_session_id
                                             AND f.object_id = t.target_id
                                             AND f.name = 'filename'
    WHERE ses.name = @SessionName;
END;

IF @FilePath IS NULL
BEGIN
    RAISERROR('Session "%s" not found. Check the session name and ensure it has been created.', 16, 1, @SessionName);
    RETURN;
END;

/* Build wildcard pattern: extract folder + session name + *.xel */
DECLARE @Folder  NVARCHAR(500) = LEFT(@FilePath, LEN(@FilePath) - CHARINDEX(N'\', REVERSE(@FilePath)));
DECLARE @Pattern NVARCHAR(500) = @Folder + N'\' + @SessionName + N'*.xel';

/* Read, shred, and summarise */
;WITH raw AS (
    SELECT
        e.value('(event/@name)[1]',                                'nvarchar(128)') AS event_name,
        e.value('(event/action[@name="database_name"]/value)[1]',  'nvarchar(128)') AS database_name,
        e.value('(event/action[@name="username"]/value)[1]',       'nvarchar(128)') AS username,
        e.value('(event/action[@name="nt_username"]/value)[1]',    'nvarchar(128)') AS nt_username,
        e.value('(event/action[@name="client_hostname"]/value)[1]','nvarchar(128)') AS client_hostname,
        e.value('(event/action[@name="client_app_name"]/value)[1]','nvarchar(256)') AS client_app_name,
        CAST(e.value('(event/@timestamp)[1]', 'nvarchar(30)')      AS DATETIME2)    AS event_time
    FROM (
        SELECT CAST(event_data AS XML) AS e
        FROM sys.fn_xe_file_target_read_file(@Pattern, NULL, NULL, NULL)
    ) AS src
)
SELECT
    event_name,
    COALESCE(database_name, '(server-level)')   AS database_name,
    COALESCE(nt_username, username)              AS login_name,
    client_hostname,
    client_app_name,
    COUNT(*)                                     AS occurrences,
    MIN(event_time)                              AS first_seen,
    MAX(event_time)                              AS last_seen,
    DATEDIFF(HOUR, MIN(event_time), MAX(event_time)) AS span_hours
FROM raw
GROUP BY event_name, database_name, nt_username, username, client_hostname, client_app_name
ORDER BY occurrences DESC, database_name, login_name;
