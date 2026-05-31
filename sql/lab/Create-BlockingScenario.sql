/*
Script Name : Create-BlockingScenario
Category    : lab
Purpose     : Controlled blocking scenario for testing Get-BlockingChains, Get-BlockingSessions,
              and blocking analysis tools.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Writes data
Impact      : Medium  *** DEV / TEST INSTANCES ONLY ***
Requires    : CREATE TABLE, INSERT, UPDATE, DROP TABLE
*/
-- SAFE:WritesData
-- IMPACT:Medium
-- LAB:DevOnly

/*
  ===================================================================
   WARNING: DO NOT PRESS F5 / EXECUTE ALL ON THIS FILE
   Running the full script hangs your SSMS connection because
   the blocker section contains WAITFOR DELAY.

   HOW TO USE:
   Open TWO SSMS query windows on the same instance.
   Highlight each step section individually and run it
   in the window indicated below.

   STEP 1  --  any window  :  SETUP section
   STEP 2  --  Window 1    :  BLOCKER section (holds lock 45 s, auto-releases)
   STEP 3  --  Window 2    :  BLOCKED section (run within 45 s of Step 2)
   STEP 4  --  any window  :  DETECT section (while 2 and 3 are active)
   STEP 5  --  any window  :  CLEANUP
  ===================================================================
*/

-- Safety: skip all runnable code when the file is executed as a whole batch.
GOTO CannotRunAsFullScript;


/* ================================================================
   STEP 1 -- SETUP  (highlight and run in either window)
   ================================================================ */

IF OBJECT_ID('dbo.lab_blocking_test', 'U') IS NOT NULL
    DROP TABLE dbo.lab_blocking_test;

CREATE TABLE dbo.lab_blocking_test (
    order_id   INT           NOT NULL CONSTRAINT PK_lab_blocking PRIMARY KEY CLUSTERED,
    customer   VARCHAR(50)   NOT NULL,
    status     VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    amount     DECIMAL(10,2) NOT NULL,
    updated_at DATETIME2     NOT NULL DEFAULT SYSDATETIME()
);

INSERT INTO dbo.lab_blocking_test (order_id, customer, status, amount) VALUES
    (1, 'Acme Corp',   'PENDING', 1250.00),
    (2, 'Beta Ltd',    'PENDING',  750.00),
    (3, 'Gamma Inc',   'PENDING', 2100.00);

SELECT * FROM dbo.lab_blocking_test ORDER BY order_id;
-- Expected: 3 rows, all PENDING.


/* ================================================================
   STEP 2 -- BLOCKER  (highlight and run in Window 1)
   Holds an exclusive lock on order_id = 1 for 45 seconds.
   Lock releases automatically -- no manual ROLLBACK needed.
   Switch to Window 2 and run Step 3 before the timer expires.
   ================================================================ */

BEGIN TRANSACTION;
    UPDATE dbo.lab_blocking_test
    SET    status     = 'PROCESSING',
           updated_at = SYSDATETIME()
    WHERE  order_id   = 1;

    WAITFOR DELAY '00:00:45';   -- lock held here; run Step 3 in Window 2 now
COMMIT TRANSACTION;

SELECT order_id, status FROM dbo.lab_blocking_test WHERE order_id = 1;
-- Shows PROCESSING after commit.


/* ================================================================
   STEP 3 -- BLOCKED  (highlight and run in Window 2)
   Run while Window 1 is still in WAITFOR.
   Will hang until Window 1 releases the lock after 45 seconds.
   ================================================================ */

UPDATE dbo.lab_blocking_test
SET    status     = 'SHIPPED',
       updated_at = SYSDATETIME()
WHERE  order_id   = 1;

SELECT order_id, status FROM dbo.lab_blocking_test WHERE order_id = 1;
-- Shows SHIPPED once unblocked.


/* ================================================================
   STEP 4 -- DETECT  (highlight and run in any window
   while Steps 2 and 3 are both active)
   ================================================================ */

SELECT
    r.session_id                                        AS blocked_session,
    r.blocking_session_id                               AS blocking_session,
    r.wait_type,
    r.wait_time / 1000                                  AS wait_seconds,
    SUBSTRING(
        t.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
              WHEN -1 THEN DATALENGTH(t.text)
              ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    )                                                   AS blocked_statement,
    s.login_name,
    s.host_name
FROM        sys.dm_exec_requests       r
JOIN        sys.dm_exec_sessions       s ON r.session_id = s.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id > 0
ORDER BY r.wait_time DESC;

-- PowerShell alternatives (run in a separate terminal):
--   .\run.ps1 Get-BlockingChains     -- recursive chain with depth and downstream waiters
--   .\run.ps1 Get-BlockingSessions   -- flat view of all blocked sessions
--   .\run.ps1 Get-ActiveSessions     -- all active sessions including open transactions


/* ================================================================
   STEP 5 -- CLEANUP  (highlight and run in any window)
   ================================================================ */

IF OBJECT_ID('dbo.lab_blocking_test', 'U') IS NOT NULL
    DROP TABLE dbo.lab_blocking_test;

SELECT OBJECT_ID('dbo.lab_blocking_test') AS should_be_null;


/* ================================================================
   END OF FILE -- do not add runnable code below this label
   ================================================================ */
CannotRunAsFullScript:
PRINT '';
PRINT '==============================================================';
PRINT '  This file cannot be executed as a full script.';
PRINT '  Highlight each STEP section individually and run it in';
PRINT '  the SSMS window indicated in the file header.';
PRINT '  Running the full file will hang your SSMS connection.';
PRINT '==============================================================';
PRINT '';