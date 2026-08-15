/*
Script Name : Get-PatchLevel
Category    : monitoring
Purpose     : Reports SQL Server version, Cumulative Update level, edition, and build
              number for patch-level tracking across an estate.
              Run on each server to build a patch compliance inventory.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-patch-level/)
Requires    : Public (no elevated permissions required)
Notes       : product_update_level returns the CU number (e.g. CU12) on SQL 2012+.
              For SQL 2012 RTM this column may be NULL.
              Compare product_version against https://sqlserverupdates.com to determine
              whether the instance is on the latest CU for its major version.
              build_clr_version is included because CLR version changes affect assembly
              compatibility during upgrades.
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

DECLARE @productVersion   varchar(20) = CAST(SERVERPROPERTY('ProductVersion')         AS varchar(20));
DECLARE @majorVer         int         = CAST(PARSENAME(@productVersion, 4)             AS int);

SELECT
    @@SERVERNAME                                                                AS server_name,
    @productVersion                                                             AS product_version,

    CASE @majorVer
        WHEN 17 THEN 'SQL Server 2025'
        WHEN 16 THEN 'SQL Server 2022'
        WHEN 15 THEN 'SQL Server 2019'
        WHEN 14 THEN 'SQL Server 2017'
        WHEN 13 THEN 'SQL Server 2016'
        WHEN 12 THEN 'SQL Server 2014'
        WHEN 11 THEN 'SQL Server 2012'
        ELSE          'SQL Server (ver ' + CAST(@majorVer AS varchar(5)) + ')'
    END                                                                         AS version_friendly,

    CAST(SERVERPROPERTY('ProductLevel')         AS varchar(20))                 AS product_level,
    CAST(SERVERPROPERTY('ProductUpdateLevel')   AS varchar(20))                 AS product_update_level,
    CAST(SERVERPROPERTY('ProductUpdateReference') AS varchar(30))               AS kb_reference,
    CAST(SERVERPROPERTY('Edition')              AS varchar(128))                AS edition,

    CASE CAST(SERVERPROPERTY('EngineEdition') AS int)
        WHEN 1  THEN 'Personal/Desktop'
        WHEN 2  THEN 'Standard'
        WHEN 3  THEN 'Enterprise' -- includes Developer and Evaluation
        WHEN 4  THEN 'Express'
        WHEN 5  THEN 'SQL Database (Azure)'
        WHEN 6  THEN 'Azure Synapse Analytics'
        WHEN 8  THEN 'Azure SQL Managed Instance'
        WHEN 9  THEN 'Azure SQL Edge'
        WHEN 11 THEN 'Azure Synapse serverless SQL pool'
        ELSE        'Unknown'
    END                                                                         AS engine_edition,

    CAST(SERVERPROPERTY('ResourceLastUpdateDateTime') AS datetime)              AS resource_db_updated,
    CAST(SERVERPROPERTY('BuildClrVersion')      AS varchar(20))                 AS clr_version,

    -- Friendly patch summary: e.g. "SQL Server 2019 CU12 (15.0.4153.1)"
    CASE @majorVer
        WHEN 17 THEN 'SQL Server 2025'
        WHEN 16 THEN 'SQL Server 2022'
        WHEN 15 THEN 'SQL Server 2019'
        WHEN 14 THEN 'SQL Server 2017'
        WHEN 13 THEN 'SQL Server 2016'
        WHEN 12 THEN 'SQL Server 2014'
        WHEN 11 THEN 'SQL Server 2012'
        ELSE          'SQL Server'
    END
    + ' '
    + ISNULL(CAST(SERVERPROPERTY('ProductUpdateLevel') AS varchar(20)),
             CAST(SERVERPROPERTY('ProductLevel') AS varchar(20)))
    + ' (' + @productVersion + ')'                                             AS patch_summary;
