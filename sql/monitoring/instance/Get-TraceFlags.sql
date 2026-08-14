/*
Script Name : Get-TraceFlags
Category    : monitoring
Purpose     : Active global and session trace flags with descriptions. Reveals undocumented
              tuning decisions and flags inherited from previous DBAs.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-trace-flags-and-resource-governor/)
Requires    : VIEW SERVER STATE
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

CREATE TABLE #trace_flags (
    TraceFlag INT,
    Status SMALLINT,
    Global SMALLINT,
    Session SMALLINT
);

INSERT INTO #trace_flags
EXEC ('DBCC TRACESTATUS(-1) WITH NO_INFOMSGS');

SELECT
    tf.TraceFlag AS trace_flag,
    CASE tf.Global WHEN 1 THEN 'Yes' ELSE 'No' END AS is_global,
    CASE tf.Session WHEN 1 THEN 'Yes' ELSE 'No' END AS is_session,
    CASE tf.Status WHEN 1 THEN 'ON' ELSE 'OFF' END AS status,
    CASE tf.TraceFlag
        WHEN 272 THEN 'Disables increment-by-1 identity behaviour; reverts to pre-2012 non-caching behaviour'
        WHEN 460 THEN 'Replaces string-truncation error 8152 with 2628 (includes column name); default in SQL 2019+'
        WHEN 610 THEN 'Minimally logged inserts into indexed tables (pre-2016 SQL)'
        WHEN 834 THEN 'Large page allocations for buffer pool (Enterprise only; can cause startup issues)'
        WHEN 845 THEN 'Enable large pages for Standard Edition buffer pool'
        WHEN 902 THEN 'Bypasses execution of database upgrade script during CU/SP install'
        WHEN 1117 THEN 'Grows all files in filegroup equally when autogrowth triggers (default in SQL 2016+ per filegroup)'
        WHEN 1118 THEN 'Forces uniform extent allocations for all databases (default in SQL 2016+)'
        WHEN 1204 THEN 'Returns resources and types of locks participating in deadlock'
        WHEN 1211 THEN 'Disables lock escalation based on memory pressure or number of locks'
        WHEN 1222 THEN 'Returns resources, types, and lock graph of deadlock (XML format; preferred over 1204)'
        WHEN 1224 THEN 'Disables lock escalation based on number of locks'
        WHEN 2312 THEN 'Forces new CE (SQL 2014 70+) in older compat levels'
        WHEN 2335 THEN 'Generates more conservative memory grants'
        WHEN 2371 THEN 'Changes auto-update stats threshold to dynamic (pre-2016 default was 20%)'
        WHEN 2453 THEN 'Allows table variables to trigger recompile on row count changes'
        WHEN 2528 THEN 'Disables parallel DBCC checks'
        WHEN 3023 THEN 'Enables CHECKSUM backup option when not set as default'
        WHEN 3042 THEN 'Disables default pre-growth backup compression algorithm'
        WHEN 3226 THEN 'Suppresses successful backup messages in SQL errorlog'
        WHEN 3625 THEN 'Limits amount of info returned in error messages to sysadmin only'
        WHEN 4199 THEN 'Enables QO hotfixes post-RTM (default ON in SQL 2017+ compat 140+)'
        WHEN 4616 THEN 'Makes server-level metadata visible to application roles'
        WHEN 6498 THEN 'Enables more than one large query compilation to gain access to the big gateway'
        WHEN 7412 THEN 'Enables lightweight query execution statistics profiling infrastructure'
        WHEN 7745 THEN 'Forces QS not to flush data to disk on database shutdown'
        WHEN 7752 THEN 'Enables async load of QS on database startup'
        WHEN 8032 THEN 'Reverts cache limit parameters to SQL 2005 RTM setting'
        WHEN 8048 THEN 'Converts NUMA node memory objects to CPU-partitioned objects'
        WHEN 8075 THEN 'Reduces VAS fragmentation when receiving 8193/8198 memory errors (x64)'
        WHEN 9024 THEN 'Converts global log pool memory object to NUMA node partitioned object'
        WHEN 9347 THEN 'Disables batch mode for sort operator'
        WHEN 9348 THEN 'Sets row limit for bulk insert via set-based ops based on cardinality estimate'
        WHEN 9389 THEN 'Enables dynamic memory grant for batch mode operators'
        WHEN 10316 THEN 'Enables temporal tables to have additional indexes on hidden period columns'
        ELSE 'No description on file — check docs.microsoft.com for trace flag ' + CAST(tf.TraceFlag AS VARCHAR(10))
    END AS description
FROM #trace_flags AS tf
ORDER BY tf.Global DESC, tf.TraceFlag;
-- 0 rows = no active trace flags set on this instance

DROP TABLE #trace_flags;
