---
title: Finding and Diagnosing SQL Server Blocking
slug: sql-server-blocking-sessions
published: 
status: draft
category: performance
tags: [blocking, locking, performance, waits]
scripts:
  - sql/performance/Get-BlockingSummary.sql
  - sql/performance/Get-BlockingSessions.sql
  - sql/performance/Get-ActiveSessions.sql
  - powershell/reporting/Get-BlockingSummary.ps1
  - powershell/reporting/Get-BlockingSessions.ps1
seo_keyphrase:    SQL Server blocking sessions
seo_title:        Finding and Diagnosing SQL Server Blocking
seo_description:  Find and diagnose SQL Server blocking with two scripts. Identify the head blocker, see the full blocking chain, and know when to kill versus investigate. (153 chars)
repo: https://github.com/peterwhyte-lgtm/dba-scripts
---

# Finding and Diagnosing SQL Server Blocking

Blocking is one of the most common causes of sudden SQL Server slowdowns. Applications start timing out, users report that everything has frozen, and the server looks busy doing nothing productive. The fix usually takes under a minute once you can see what's happening — the challenge is getting that visibility fast enough.

This post covers two complementary scripts: a summary view that shows you the shape of blocking at a glance, and a detail view that shows you the full chain so you know which session to investigate.

## The problem

SQL Server uses locking to enforce transaction isolation. When session A holds a lock on a row and session B wants to modify the same row, session B waits. That's normal. The problem is when session A forgets to commit — or is running a long-running transaction — and session B, C, D, and E all pile up behind it. A single blocked session becomes hundreds. The application calls this "the database is down."

The key insight is that in a blocking chain, you don't kill the blocked sessions — you kill or investigate the *head blocker*: the session that everyone else is waiting for. That's the one holding the lock.

## Script 1 — blocking summary

The summary gives you a quick answer: is there blocking right now, and how bad is it?

```sql
WITH blocked_counts AS (
    SELECT
        r.blocking_session_id,
        COUNT(*)                AS blocked_session_count,
        MAX(r.wait_time) / 1000 AS max_wait_sec,
        SUM(r.wait_time) / 1000 AS total_wait_sec
    FROM sys.dm_exec_requests AS r
    WHERE r.blocking_session_id <> 0
    GROUP BY r.blocking_session_id
)
SELECT
    bc.blocking_session_id                                          AS head_blocker_session_id,
    bc.blocked_session_count,
    bc.max_wait_sec,
    bc.total_wait_sec,
    s.login_name                                                    AS head_blocker_login,
    s.host_name                                                     AS head_blocker_host,
    s.program_name                                                  AS head_blocker_program,
    DB_NAME(s.database_id)                                          AS head_blocker_database,
    s.open_transaction_count,
    r.wait_type                                                     AS head_blocker_wait_type,
    CAST(ISNULL(r.wait_time, 0) / 1000.0 AS DECIMAL(10,1))        AS head_blocker_wait_sec,
    SUBSTRING(ISNULL(qt.text, ''), 1, 500)                         AS head_blocker_statement
FROM blocked_counts                  AS bc
JOIN sys.dm_exec_sessions             AS s   ON bc.blocking_session_id = s.session_id
LEFT JOIN sys.dm_exec_requests        AS r   ON bc.blocking_session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS qt
ORDER BY bc.blocked_session_count DESC, bc.max_wait_sec DESC;
```

## Script 2 — full blocking chain detail

Once you've identified there is a head blocker, the detail script shows every session in the chain with wait times and current statements.

```sql
SELECT
    s.session_id,
    DB_NAME(s.database_id)                                          AS database_name,
    s.status,
    s.login_name,
    s.host_name,
    s.program_name,
    r.blocking_session_id,
    r.wait_type,
    CAST(ISNULL(r.wait_time, 0) / 1000.0 AS DECIMAL(10,1))        AS wait_sec,
    CAST(ISNULL(r.total_elapsed_time, 0) / 1000.0 AS DECIMAL(10,1)) AS elapsed_sec,
    r.cpu_time,
    r.logical_reads,
    t.text                                                          AS current_statement
FROM sys.dm_exec_sessions    AS s
LEFT  JOIN sys.dm_exec_requests AS r  ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t
WHERE s.is_user_process = 1
  AND (r.blocking_session_id IS NOT NULL OR r.wait_type IS NOT NULL)
ORDER BY ISNULL(r.wait_time, 0) DESC;
```

## How to run them from the repo

```powershell
# Summary first — is there blocking and who is the head blocker?
.\run.ps1 Get-BlockingSummary

# Detail — full chain with statements
.\run.ps1 Get-BlockingSessions

# All active sessions if you want broader context
.\run.ps1 Get-ActiveSessions
```

## Reading the summary output

| Column | What it means |
|--------|---------------|
| `head_blocker_session_id` | The session everyone else is waiting for |
| `blocked_session_count` | How many sessions are directly or indirectly waiting on this blocker |
| `max_wait_sec` | Longest individual wait in the blocked group |
| `head_blocker_login` | Who ran the blocking session — useful for contacting the right team |
| `head_blocker_program` | Application or tool that opened the blocking connection |
| `open_transaction_count` | How many open, uncommitted transactions this session has |
| `head_blocker_wait_type` | What the head blocker itself is waiting on (NULL = actively running or sleeping) |
| `head_blocker_statement` | The last statement the blocker ran (first 500 characters) |

## What to look for

**`open_transaction_count > 0` and `head_blocker_wait_type IS NULL`** — The head blocker has an open transaction but isn't running anything. This usually means the application started a transaction, did something, and didn't commit or roll back. A bug, or the application crashed. This kind of blocking can last indefinitely. Kill the session if needed: `KILL <session_id>`.

**`head_blocker_wait_type = LCK_M_*`** — The head blocker is itself waiting on a lock held by a different session. This means you have a blocking chain: follow it up to find the true root. The detail script will show you the full chain.

**`blocked_session_count` is large and growing** — Run the summary every 30 seconds. If the count is growing, the application is accumulating blocked sessions faster than they complete. You need to resolve the root blocker.

**`head_blocker_program` shows a specific application** — Tells you which team to call. An application holding long transactions is usually a code bug: a transaction that opens, does work, and doesn't commit promptly.

## Resolving blocking

Identify the `head_blocker_session_id` from the summary. If it has `open_transaction_count > 0` and isn't executing anything, the transaction is stuck:

```sql
-- Check what database and objects are locked
SELECT * FROM sys.dm_tran_locks WHERE request_session_id = <session_id>;

-- Kill the session if appropriate
KILL <session_id>;
```

Before killing, check with the application team: is the session doing something intentional (a long ETL job, a migration)? Killing a legitimate long transaction rolls it back, which can take as long as the transaction took to get there.

For recurring blocking, the fix is usually one of:
- Adding a missing index (so the query holds locks for less time)
- Shortening transactions in the application (commit sooner)
- Reviewing isolation level (READ COMMITTED SNAPSHOT can eliminate reader/writer contention)

## Related scripts in this repo

- [`Get-WaitStatistics.sql`](../sql/performance/Get-WaitStatistics.sql) — if `LCK_M_*` waits are high in the summary, this is the broader context
- [`Get-ActiveSessions.sql`](../sql/performance/Get-ActiveSessions.sql) — all active sessions with full wait and request detail
- [`Get-DeadlockSummary.sql`](../sql/performance/Get-DeadlockSummary.sql) — if blocking is also causing deadlocks, check this

## Get the scripts

The full scripts are available in the [dba-scripts repo on GitHub](https://github.com/peterwhyte-lgtm/dba-scripts):

- [`sql/performance/Get-BlockingSummary.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-BlockingSummary.sql)
- [`sql/performance/Get-BlockingSessions.sql`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/sql/performance/Get-BlockingSessions.sql)
- [`powershell/reporting/Get-BlockingSummary.ps1`](https://github.com/peterwhyte-lgtm/dba-scripts/blob/main/powershell/reporting/Get-BlockingSummary.ps1)

---

## SEO

**Focus keyphrase:** SQL Server blocking sessions

**Meta description** (153 chars — target 150–160):  
Find and diagnose SQL Server blocking with two scripts. Identify the head blocker, see the full blocking chain, and know when to kill versus investigate.

**Post images:**

| Image file | Alt text (≤125 chars) | Title (≤60 chars) |
|------------|-----------------------|-------------------|
| `blocking-summary-output.png` | SQL Server blocking summary query output showing head blocker session with blocked session count and current statement | SQL Server blocking summary DMV output |
