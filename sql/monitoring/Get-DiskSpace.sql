/*
Script Name : Get-DiskSpace
Category    : storage-capacity-management
Purpose     : Show free and used space per volume that hosts SQL Server database files.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
Notes       : Uses sys.dm_os_volume_stats — shows only volumes with at least one database
              file. For OS-level disk summary across all drives use Get-DiskSpaceSummary.ps1.
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(vs.total_bytes     / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS total_gb,
    CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(10,2)) AS free_gb,
    CAST((vs.total_bytes - vs.available_bytes) / 1024.0 / 1024 / 1024
         AS DECIMAL(10,2))                                             AS used_gb,
    CAST(100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0)
         AS DECIMAL(5,1))                                              AS free_pct
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
GROUP BY vs.volume_mount_point, vs.logical_volume_name,
         vs.total_bytes, vs.available_bytes
ORDER BY free_pct ASC;
