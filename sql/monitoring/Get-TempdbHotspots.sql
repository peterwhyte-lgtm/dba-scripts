/*
Script Name : Get-TempdbHotspots
Category    : maintenance-and-reliability
Purpose     : Identify sessions consuming the most TempDB space for contention and spill triage.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    ssu.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    DB_NAME(r.database_id)                                                         AS active_database,
    CAST(ssu.user_objects_alloc_page_count      * 8.0 / 1024 AS DECIMAL(10,2))    AS user_objects_mb,
    CAST(ssu.internal_objects_alloc_page_count  * 8.0 / 1024 AS DECIMAL(10,2))    AS internal_objects_mb,
    CAST((ssu.user_objects_alloc_page_count
        + ssu.internal_objects_alloc_page_count) * 8.0 / 1024 AS DECIMAL(10,2))   AS total_tempdb_mb,
    r.wait_type,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,1))               AS elapsed_sec
FROM sys.dm_db_session_space_usage    AS ssu
JOIN sys.dm_exec_sessions              AS s   ON ssu.session_id = s.session_id
LEFT JOIN sys.dm_exec_requests         AS r   ON ssu.session_id = r.session_id
WHERE ssu.session_id > 50
  AND (ssu.user_objects_alloc_page_count + ssu.internal_objects_alloc_page_count) > 0
ORDER BY total_tempdb_mb DESC;
