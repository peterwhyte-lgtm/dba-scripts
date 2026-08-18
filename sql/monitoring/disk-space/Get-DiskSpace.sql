/*
Script Name : Get-DiskSpace
Category    : storage-capacity-management
Purpose     : Show free and used space per volume that hosts SQL Server database files.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-disk-space/)
Requires    : VIEW SERVER STATE
Notes       : Uses sys.dm_os_volume_stats — shows only volumes with at least one database
              file. For OS-level disk summary across all drives use Get-DiskSpaceSummary.ps1.
HealthCheck : Yes
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

-- Group on the volume identity only: total/available bytes can change between file
-- samples mid-query, which duplicated volume rows when they were in the GROUP BY.
SELECT
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(MAX(vs.total_bytes)     / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS total_gb,
    CAST(MIN(vs.available_bytes) / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS free_gb,
    CAST((MAX(vs.total_bytes) - MIN(vs.available_bytes)) / 1024.0 / 1024 / 1024
         AS DECIMAL(10,2))                                                AS used_gb,
    CAST(100.0 * MIN(vs.available_bytes) / NULLIF(MAX(vs.total_bytes), 0)
         AS DECIMAL(5,1))                                                 AS free_pct
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
GROUP BY vs.volume_mount_point, vs.logical_volume_name
ORDER BY free_pct ASC;
