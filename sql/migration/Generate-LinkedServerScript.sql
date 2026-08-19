/*
Script Name : Generate-LinkedServerScript
Category    : migration
Purpose     : Generate sp_addlinkedserver + sp_addlinkedsrvlogin DDL for all linked servers.
              Run on SOURCE server. Execute the output on TARGET after migration.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-generate-linked-server-script/)
Requires    : VIEW ANY DEFINITION or sysadmin
*/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

/*
  DESIGN: Linked server login mappings with stored remote credentials cannot have passwords
  scripted — SQL Server does not expose them. Mappings using stored credentials are scripted
  with a placeholder (NULL password) and a clear comment. Re-enter the remote password manually
  on the target for each HIGH-risk mapping flagged by Get-LinkedServerSecurity.sql.

  Impersonation mappings (useself = 1) are scripted correctly and require no manual password entry.
  No-mapping entries (access denied for unmatched logins) are scripted correctly.
*/

DECLARE @ddl  NVARCHAR(MAX) = N'';
DECLARE @crlf NCHAR(2)      = CHAR(13) + CHAR(10);

SET @ddl = @ddl
    + N'-- ================================================================' + @crlf
    + N'-- Linked Server Migration Script' + @crlf
    + N'-- Source  : ' + @@SERVERNAME + @crlf
    + N'-- Generated: ' + CONVERT(NVARCHAR(30), GETDATE(), 120) + @crlf
    + N'-- IMPORTANT: Stored credentials (remote_login / rmtpassword) cannot' + @crlf
    + N'-- be scripted. Lines marked ENTER_PASSWORD_HERE require manual entry.' + @crlf
    + N'-- Run Get-LinkedServerSecurity.sql to identify HIGH-risk mappings.' + @crlf
    + N'-- ================================================================' + @crlf + @crlf;

-- ── One block per linked server ───────────────────────────────────────────────

DECLARE @ls_name      NVARCHAR(128);
DECLARE @ls_product   NVARCHAR(128);
DECLARE @ls_provider  NVARCHAR(128);
DECLARE @ls_datasrc   NVARCHAR(4000);
DECLARE @ls_location  NVARCHAR(4000);
DECLARE @ls_provstr   NVARCHAR(4000);
DECLARE @ls_catalog   NVARCHAR(128);
DECLARE @ls_rpc_out   bit;
DECLARE @ls_collation bit;

DECLARE ls_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT
        s.name,
        ISNULL(s.product,   N''),
        ISNULL(s.provider,  N'SQLNCLI'),
        ISNULL(s.data_source, N''),
        ISNULL(CAST(s.location AS NVARCHAR(4000)), N''),
        ISNULL(CAST(s.provider_string AS NVARCHAR(4000)), N''),
        ISNULL(s.catalog,   N''),
        s.is_rpc_out_enabled,
        s.is_collation_compatible
    FROM sys.servers s
    WHERE s.is_linked = 1
    ORDER BY s.name;

OPEN ls_cur;
FETCH NEXT FROM ls_cur INTO
    @ls_name, @ls_product, @ls_provider, @ls_datasrc,
    @ls_location, @ls_provstr, @ls_catalog, @ls_rpc_out, @ls_collation;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ddl = @ddl
        + N'-- Linked Server: ' + @ls_name + @crlf
        + N'IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE name = N''' + REPLACE(@ls_name, N'''', N'''''') + N''' AND is_linked = 1)' + @crlf
        + N'BEGIN' + @crlf
        + N'    EXEC sp_addlinkedserver' + @crlf
        + N'        @server     = N''' + REPLACE(@ls_name,     N'''', N'''''') + N''',' + @crlf
        + N'        @srvproduct = N''' + REPLACE(@ls_product,  N'''', N'''''') + N''',' + @crlf
        + N'        @provider   = N''' + REPLACE(@ls_provider, N'''', N'''''') + N''',' + @crlf
        + N'        @datasrc    = N''' + REPLACE(@ls_datasrc,  N'''', N'''''') + N'''' + @crlf
        + CASE WHEN @ls_location <> N''
               THEN N'       ,@location  = N''' + REPLACE(@ls_location, N'''', N'''''') + N'''' + @crlf
               ELSE N'' END
        + CASE WHEN @ls_provstr <> N''
               THEN N'       ,@provstr   = N''' + REPLACE(@ls_provstr,  N'''', N'''''') + N'''' + @crlf
               ELSE N'' END
        + CASE WHEN @ls_catalog <> N''
               THEN N'       ,@catalog   = N''' + REPLACE(@ls_catalog,  N'''', N'''''') + N'''' + @crlf
               ELSE N'' END
        + N';' + @crlf + @crlf;

    -- Options
    IF @ls_rpc_out = 1
        SET @ddl = @ddl
            + N'    EXEC sp_serveroption @server = N''' + REPLACE(@ls_name, N'''', N'''''') + N''', @optname = N''rpc out'', @optvalue = N''true'';' + @crlf;

    IF @ls_collation = 1
        SET @ddl = @ddl
            + N'    EXEC sp_serveroption @server = N''' + REPLACE(@ls_name, N'''', N'''''') + N''', @optname = N''collation compatible'', @optvalue = N''true'';' + @crlf;

    -- Login mappings for this linked server
    DECLARE @ll_local   NVARCHAR(128);
    DECLARE @ll_remote  NVARCHAR(128);
    DECLARE @ll_useself bit;

    DECLARE ll_cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            ISNULL(sp.name, N''),
            ISNULL(ll.remote_name, N''),
            ll.uses_self_credential
        FROM sys.linked_logins ll
        INNER JOIN sys.servers s2 ON ll.server_id = s2.server_id
        LEFT JOIN sys.server_principals sp ON ll.local_principal_id = sp.principal_id
        WHERE s2.name = @ls_name
        ORDER BY sp.name;

    OPEN ll_cur;
    FETCH NEXT FROM ll_cur INTO @ll_local, @ll_remote, @ll_useself;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @ddl = @ddl + @crlf
            + CASE
                WHEN @ll_useself = 1 THEN
                    N'    -- Impersonation mapping (self credentials)' + @crlf +
                    N'    EXEC sp_addlinkedsrvlogin' + @crlf +
                    N'        @rmtsrvname  = N''' + REPLACE(@ls_name,  N'''', N'''''') + N''',' + @crlf +
                    N'        @useself     = N''True''' + @crlf +
                    CASE WHEN @ll_local <> N''
                         THEN N'       ,@locallogin = N''' + REPLACE(@ll_local, N'''', N'''''') + N'''' + @crlf
                         ELSE N'' END +
                    N'    ;' + @crlf
                WHEN @ll_remote <> N'' AND @ll_local = N'' THEN
                    N'    -- Catch-all mapping - ENTER_PASSWORD_HERE (stored credential, cannot be scripted)' + @crlf +
                    N'    EXEC sp_addlinkedsrvlogin' + @crlf +
                    N'        @rmtsrvname  = N''' + REPLACE(@ls_name,   N'''', N'''''') + N''',' + @crlf +
                    N'        @useself     = N''False'',' + @crlf +
                    N'        @locallogin  = NULL,' + @crlf +
                    N'        @rmtuser     = N''' + REPLACE(@ll_remote, N'''', N'''''') + N''',' + @crlf +
                    N'        @rmtpassword = N''ENTER_PASSWORD_HERE'';' + @crlf
                WHEN @ll_remote <> N'' THEN
                    N'    -- Explicit mapping - ENTER_PASSWORD_HERE (stored credential, cannot be scripted)' + @crlf +
                    N'    EXEC sp_addlinkedsrvlogin' + @crlf +
                    N'        @rmtsrvname  = N''' + REPLACE(@ls_name,   N'''', N'''''') + N''',' + @crlf +
                    N'        @useself     = N''False'',' + @crlf +
                    N'        @locallogin  = N''' + REPLACE(@ll_local,  N'''', N'''''') + N''',' + @crlf +
                    N'        @rmtuser     = N''' + REPLACE(@ll_remote, N'''', N'''''') + N''',' + @crlf +
                    N'        @rmtpassword = N''ENTER_PASSWORD_HERE'';' + @crlf
                ELSE
                    N'    -- No mapping (access denied for unmatched logins)' + @crlf +
                    N'    EXEC sp_addlinkedsrvlogin' + @crlf +
                    N'        @rmtsrvname  = N''' + REPLACE(@ls_name,  N'''', N'''''') + N''',' + @crlf +
                    N'        @useself     = N''False'',' + @crlf +
                    N'        @locallogin  = NULL,' + @crlf +
                    N'        @rmtuser     = NULL,' + @crlf +
                    N'        @rmtpassword = NULL;' + @crlf
              END;

        FETCH NEXT FROM ll_cur INTO @ll_local, @ll_remote, @ll_useself;
    END

    CLOSE ll_cur;
    DEALLOCATE ll_cur;

    SET @ddl = @ddl + N'END' + @crlf + N'GO' + @crlf + @crlf;

    FETCH NEXT FROM ls_cur INTO
        @ls_name, @ls_product, @ls_provider, @ls_datasrc,
        @ls_location, @ls_provstr, @ls_catalog, @ls_rpc_out, @ls_collation;
END

CLOSE ls_cur;
DEALLOCATE ls_cur;

IF @ddl = N''
    SET @ddl = N'-- No linked servers found on ' + @@SERVERNAME + CHAR(13) + CHAR(10);

SELECT @ddl AS ddl;
