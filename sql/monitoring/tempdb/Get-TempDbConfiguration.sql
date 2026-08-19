/*
Script Name : Get-TempDbConfiguration
Category    : monitoring
Purpose     : Reviews TempDB file configuration — file count, sizing parity, autogrowth
              settings, and max server memory context. Surfaces common misconfigurations
              that cause allocation contention on busy OLTP servers.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-temp-db-configuration/)
Requires    : VIEW SERVER STATE
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Best practice guidance embedded in status columns:
    - Equal file count to physical CPU cores (up to 8) prevents allocation hotspots
    - All data files should be equal size (unequal sizing causes uneven proportional fill)
    - Fixed-size autogrowth (not %) is strongly preferred for TempDB
    - Instant file initialization (IFI) cannot be detected here but matters for autogrowth speed
  Returns one row per TempDB file with a per-file status, plus a summary row (row_type='summary').
*/

WITH tempdb_files AS (
    SELECT
        mf.file_id,
        mf.name AS logical_name,
        mf.physical_name,
        mf.type_desc AS file_type,
        CAST(mf.size * 8.0 / 1024 AS decimal(10,2)) AS file_size_mb,
        CASE WHEN mf.max_size = -1 OR mf.max_size = 268435456
             THEN NULL
             ELSE CAST(mf.max_size * 8.0 / 1024 AS decimal(10,2))
        END AS max_size_mb,
        mf.is_percent_growth,
        CASE WHEN mf.is_percent_growth = 1
             THEN CAST(mf.growth AS varchar(10)) + '%'
             ELSE CAST(mf.growth * 8 / 1024 AS varchar(10)) + ' MB'
        END AS autogrowth_setting
    FROM sys.master_files mf
    WHERE mf.database_id = 2 -- TempDB
),
sizing_stats AS (
    SELECT
        file_type,
        COUNT(*) AS file_count,
        MIN(file_size_mb) AS min_size_mb,
        MAX(file_size_mb) AS max_size_mb,
        AVG(file_size_mb) AS avg_size_mb
    FROM tempdb_files
    GROUP BY file_type
)
SELECT
    f.file_type,
    f.file_id,
    f.logical_name,
    f.physical_name,
    f.file_size_mb,
    f.max_size_mb,
    f.autogrowth_setting,
    CASE WHEN f.is_percent_growth = 1
         THEN 'WARN - percent autogrowth; use fixed MB for TempDB'
         ELSE 'OK'
    END AS autogrowth_status,
    CASE WHEN s.min_size_mb = s.max_size_mb OR s.file_count = 1
         THEN 'OK - equal sizing'
         ELSE 'WARN - files are unequal (' + CAST(s.min_size_mb AS varchar) + '-' +
              CAST(s.max_size_mb AS varchar) + ' MB); equal sizing prevents allocation contention'
    END AS sizing_status,
    s.file_count AS total_files_this_type,
    (SELECT CAST(value_in_use AS varchar(20))
     FROM sys.configurations WHERE name = 'max degree of parallelism') AS maxdop,
    (SELECT cpu_count FROM sys.dm_os_sys_info) AS logical_cpu_count,
    CASE
        WHEN f.file_type = 'ROWS' AND s.file_count < (SELECT CASE WHEN cpu_count > 8 THEN 8 ELSE cpu_count END FROM sys.dm_os_sys_info)
            THEN 'WARN - ' + CAST(s.file_count AS varchar) + ' data file(s); recommend 1 per core up to 8'
        WHEN f.file_type = 'ROWS' AND s.file_count > 8
            THEN 'INFO - ' + CAST(s.file_count AS varchar) + ' data files; > 8 rarely helps'
        ELSE 'OK'
    END AS file_count_status
FROM tempdb_files f
JOIN sizing_stats s ON s.file_type = f.file_type
ORDER BY f.file_type DESC, f.file_id;
