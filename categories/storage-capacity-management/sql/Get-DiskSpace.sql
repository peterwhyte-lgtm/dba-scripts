/*
Script Name : Check Disk Space on SQL Server
Description : Returns volume-level disk space for the SQL Server host.
Use        : Capacity checks, storage reviews, and alert validation.
*/

SELECT
    vs.volume_mount_point,
    vs.logical_volume_name,
    ROUND(CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18,2)), 2) AS total_size_gb,
    ROUND(CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18,2)), 2) AS free_space_gb,
    ROUND(CAST(100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0) AS DECIMAL(5,2)), 2) AS free_percent,
    ROUND(CAST((vs.total_bytes - vs.available_bytes) / 1024.0 / 1024 / 1024 AS DECIMAL(18,2)), 2) AS used_space_gb
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
GROUP BY vs.volume_mount_point, vs.logical_volume_name, vs.total_bytes, vs.available_bytes
ORDER BY free_percent ASC;



