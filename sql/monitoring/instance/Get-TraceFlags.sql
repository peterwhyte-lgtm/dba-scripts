/*
Script Name : Get-TraceFlags
Category    : monitoring
Purpose     : Active global and session trace flags, what each one does, and whether it still
              does anything on a modern instance. Reveals undocumented tuning decisions and
              flags inherited from previous DBAs.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-trace-flags-and-resource-governor/)
Requires    : VIEW SERVER STATE
Notes       : current_status is the column that matters on an inherited server. Roughly half the
              flags described here do NOTHING on SQL Server 2016 and later - the behaviour they
              used to control became the default, or moved to a database scoped configuration or
              a query hint. DBCC TRACESTATUS still reports them as ON, which is how they survive
              upgrade after upgrade.

              BLIND SPOT: this cannot tell you HOW a global flag was set. A flag set with
              DBCC TRACEON (n, -1) disappears at the next restart; the same flag set as a -T
              startup parameter comes back. TRACEOFF will appear to work in both cases. Check
              the startup parameters in SQL Server Configuration Manager before concluding a
              flag is gone for good.

              Descriptions follow the Microsoft trace flag reference:
              https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-traceon-trace-flags-transact-sql
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
        WHEN 272 THEN 'Superseded - SQL 2017+ IDENTITY_CACHE database scoped configuration'
        WHEN 460 THEN 'No effect at compatibility level 150+ (2628 is the default there)'
        WHEN 610 THEN 'Not required on SQL 2016+ - minimal logging is on by default'
        WHEN 834 THEN 'Active - Microsoft advise against it unless measured, and never with columnstore'
        WHEN 845 THEN 'DO NOT USE - default for Standard SKUs since SQL 2012'
        WHEN 902 THEN 'DO NOT USE in steady state - troubleshooting a failed upgrade only'
        WHEN 1117 THEN 'No effect on SQL 2016+ - ALTER DATABASE MODIFY FILEGROUP AUTOGROW_ALL_FILES'
        WHEN 1118 THEN 'No effect on SQL 2016+ - ALTER DATABASE SET MIXED_PAGE_ALLOCATION'
        WHEN 1204 THEN 'Active - Microsoft advise against it on deadlock-heavy systems'
        WHEN 1211 THEN 'Active - Microsoft recommend 1224 instead'
        WHEN 1222 THEN 'Active - Microsoft advise against it on deadlock-heavy systems'
        WHEN 1224 THEN 'Active'
        WHEN 2312 THEN 'Superseded - SQL 2016 SP1+ USE HINT FORCE_DEFAULT_CARDINALITY_ESTIMATION'
        WHEN 2335 THEN 'Active - test before production'
        WHEN 2371 THEN 'No effect on SQL 2016+ at compatibility level 130+'
        WHEN 2453 THEN 'No effect on SQL 2019+ - table variable deferred compilation replaced it'
        WHEN 2528 THEN 'Active - SQL 2014 SP2+ offers a MAXDOP option on the DBCC instead'
        WHEN 3023 THEN 'Superseded - SQL 2014+ backup checksum default configuration option'
        WHEN 3042 THEN 'Active'
        WHEN 3226 THEN 'Active'
        WHEN 3625 THEN 'Active'
        WHEN 4199 THEN 'Superseded - SQL 2016+ QUERY_OPTIMIZER_HOTFIXES scoped configuration'
        WHEN 4616 THEN 'Active'
        WHEN 6498 THEN 'No effect on SQL 2014 SP2 / 2016+ - the engine controls this'
        WHEN 7412 THEN 'No effect on SQL 2019+ - lightweight profiling is on by default'
        WHEN 7745 THEN 'Active - risks losing unflushed Query Store data on shutdown'
        WHEN 7752 THEN 'No effect on SQL 2019+ - the engine controls this'
        WHEN 8032 THEN 'Active - can starve the buffer pool'
        WHEN 8048 THEN 'No effect on SQL 2014 SP2 / 2016+ - now dynamic'
        WHEN 8075 THEN 'No effect on SQL 2016+ - the engine controls this'
        WHEN 9024 THEN 'No effect on SQL 2012 SP3 / 2014 SP1+ - the engine controls this'
        WHEN 9347 THEN 'Active'
        WHEN 9348 THEN 'Active'
        WHEN 9389 THEN 'Active'
        WHEN 10316 THEN 'Active - not listed in the documented trace flag reference'
        ELSE 'Unknown - not in this description list'
    END AS current_status,
    CASE tf.TraceFlag
        WHEN 272 THEN 'Disables identity preallocation, so identity values do not jump after an unexpected restart or failover'
        WHEN 460 THEN 'Replaces string truncation error 8152 with 2628, which names the offending column'
        WHEN 610 THEN 'Controls minimally logged inserts into indexed tables'
        WHEN 834 THEN 'Large page allocations for ALL SQLOS memory, not only the buffer pool. Needs 64-bit, Lock Pages in Memory and Enterprise, and can stop the instance starting if memory is fragmented'
        WHEN 845 THEN 'Locked pages in memory on Standard SKUs, where the service account holds the Lock Pages in Memory right'
        WHEN 902 THEN 'Bypasses the database upgrade script during a CU or Service Pack install'
        WHEN 1117 THEN 'When one file in a filegroup hits its autogrow threshold, every file in that filegroup grows'
        WHEN 1118 THEN 'Allocates new objects from uniform extents rather than mixed extents, easing SGAM contention'
        WHEN 1204 THEN 'Writes the resources and lock types involved in a deadlock to the error log'
        WHEN 1211 THEN 'Disables lock escalation completely, including under memory pressure, which can exhaust lock memory'
        WHEN 1222 THEN 'Writes the full deadlock graph to the error log in XML'
        WHEN 1224 THEN 'Disables lock escalation based on lock count, but memory pressure can still escalate'
        WHEN 2312 THEN 'Forces the SQL 2014 (120) cardinality estimator whatever the database compatibility level'
        WHEN 2335 THEN 'Makes the optimizer assume a fixed memory size when max server memory is set very high. It does not cap the grant at execution time'
        WHEN 2371 THEN 'Changes the automatic update statistics threshold from a fixed row count to a linear one'
        WHEN 2453 THEN 'Lets a table variable trigger a recompile once enough rows change'
        WHEN 2528 THEN 'Disables parallel object checking in DBCC CHECKDB, CHECKFILEGROUP and CHECKTABLE'
        WHEN 3023 THEN 'Makes CHECKSUM the default for BACKUP'
        WHEN 3042 THEN 'Skips backup compression preallocation so the backup file grows only as needed'
        WHEN 3226 THEN 'Suppresses successful backup AND restore entries in the error log'
        WHEN 3625 THEN 'Masks parameters in some error messages for anyone who is not a sysadmin'
        WHEN 4199 THEN 'Enables Query Optimizer fixes shipped after RTM. Without it, QO changes still apply from compatibility level 130'
        WHEN 4616 THEN 'Makes server-level metadata visible to application roles'
        WHEN 6498 THEN 'Lets more than one large query compile through the large gateway when memory allows'
        WHEN 7412 THEN 'Enables the lightweight query execution statistics profiling infrastructure'
        WHEN 7745 THEN 'Stops Query Store flushing to disk on database shutdown'
        WHEN 7752 THEN 'Loads Query Store asynchronously instead of synchronously during recovery'
        WHEN 8032 THEN 'Reverts plan cache limits to the SQL 2005 setting, allowing larger caches'
        WHEN 8048 THEN 'Converts NUMA-partitioned memory objects into CPU-partitioned ones'
        WHEN 8075 THEN 'Reduces virtual address space fragmentation behind low-VAS out of memory errors'
        WHEN 9024 THEN 'Converts the global log pool memory object into a NUMA node partitioned one'
        WHEN 9347 THEN 'Disables batch mode for the sort operator'
        WHEN 9348 THEN 'Uses cardinality estimates to decide whether a clustered columnstore load uses BULK INSERT, at a 102400 row threshold'
        WHEN 9389 THEN 'Grants batch mode operators extra memory dynamically to avoid spilling to tempdb'
        WHEN 10316 THEN 'Allows extra indexes on the memory-optimized internal history table of a temporal table'
        ELSE 'No description on file - check the Microsoft trace flag reference for flag ' + CAST(tf.TraceFlag AS VARCHAR(10))
    END AS description
FROM #trace_flags AS tf
ORDER BY tf.Global DESC, tf.TraceFlag;
-- 0 rows = no active trace flags set on this instance

DROP TABLE #trace_flags;
