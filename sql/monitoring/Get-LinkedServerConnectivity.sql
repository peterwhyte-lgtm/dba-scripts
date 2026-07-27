/*
Script Name : Get-LinkedServerConnectivity
Category    : monitoring
Purpose     : Inventories all linked servers and tests each one for connectivity using sp_testlinkedserver.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-linked-servers/)
Requires    : sysadmin or ALTER ANY LINKED SERVER
*/
-- Blog: https://sqldba.blog/dba-scripts-get-linked-servers/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/* Note: sys.linked_servers was removed in SQL Server 2025 — use sys.servers WHERE is_linked = 1 */

IF OBJECT_ID('tempdb..#LSResults') IS NOT NULL DROP TABLE #LSResults;
CREATE TABLE #LSResults (
    linked_server_name      NVARCHAR(128) NOT NULL,
    product                 NVARCHAR(128),
    provider                NVARCHAR(128),
    data_source             NVARCHAR(4000),
    is_rpc_out_enabled      BIT,
    is_remote_login_enabled BIT,
    modify_date             DATETIME,
    connectivity            VARCHAR(15)   NOT NULL DEFAULT 'UNTESTED',
    error_detail            NVARCHAR(2000)
);

INSERT INTO #LSResults (linked_server_name, product, provider, data_source,
                        is_rpc_out_enabled, is_remote_login_enabled, modify_date)
SELECT
    name,
    product,
    provider,
    data_source,
    is_rpc_out_enabled,
    is_remote_login_enabled,
    modify_date
FROM sys.servers
WHERE is_linked = 1;

/* ── Test connectivity for each linked server ────────────────────────────── */
DECLARE @ls  NVARCHAR(128);
DECLARE @err NVARCHAR(2000);

DECLARE ls_cur CURSOR FAST_FORWARD FOR
    SELECT linked_server_name FROM #LSResults ORDER BY linked_server_name;

OPEN ls_cur; FETCH NEXT FROM ls_cur INTO @ls;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        EXEC sp_testlinkedserver @ls;
        UPDATE #LSResults SET connectivity = 'REACHABLE' WHERE linked_server_name = @ls;
    END TRY
    BEGIN CATCH
        SET @err = LEFT(ERROR_MESSAGE(), 2000);
        UPDATE #LSResults
        SET connectivity = 'UNREACHABLE', error_detail = @err
        WHERE linked_server_name = @ls;
    END CATCH;
    FETCH NEXT FROM ls_cur INTO @ls;
END;
CLOSE ls_cur; DEALLOCATE ls_cur;

SELECT
    linked_server_name,
    product,
    provider,
    data_source,
    connectivity,
    is_rpc_out_enabled,
    is_remote_login_enabled,
    modify_date,
    error_detail
FROM #LSResults
ORDER BY CASE connectivity WHEN 'UNREACHABLE' THEN 1 WHEN 'REACHABLE' THEN 2 ELSE 3 END,
         linked_server_name;

DROP TABLE #LSResults;
