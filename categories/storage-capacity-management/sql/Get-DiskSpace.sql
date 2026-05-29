/*
Script Name : Check Disk Space on SQL Server
Description : Returns Disk Space for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/

SELECT
    vs.volume_mount_point,
    vs.logical_volume_name,
    CAST(vs.total_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18,2)) AS total_size_gb,
    CAST(vs.available_bytes / 1024.0 / 1024 / 1024 AS DECIMAL(18,2)) AS free_space_gb,
    CAST(100.0 * vs.available_bytes / NULLIF(vs.total_bytes, 0) AS DECIMAL(5,2)) AS free_percent
FROM sys.master_files AS mf
CROSS APPLY sys.dm_os_volume_stats(mf.database_id, mf.file_id) AS vs
GROUP BY vs.volume_mount_point, vs.logical_volume_name, vs.total_bytes, vs.available_bytes
ORDER BY free_percent ASC;



