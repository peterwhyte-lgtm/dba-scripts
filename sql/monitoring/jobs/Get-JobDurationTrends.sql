/*
Script Name : Get-JobDurationTrends
Category    : monitoring
Purpose     : SQL Agent job duration over the last 30 days — flags jobs that are running significantly longer than their average.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-job-schedules-and-duration-trends/)
Requires    : msdb access (SQLAgentReaderRole or sysadmin)
*/
-- Blog: https://sqldba.blog/dba-scripts-get-job-schedules-and-duration-trends/
-- SAFE:ReadOnly
-- IMPACT:Low
SET NOCOUNT ON;

WITH history AS (
    SELECT
        j.job_id,
        j.name                              AS job_name,
        j.enabled,
        j.category_id,
        /* Convert HHMMSS integer to total seconds */
        (h.run_duration / 10000) * 3600
        + ((h.run_duration / 100) % 100) * 60
        + (h.run_duration % 100)            AS duration_sec,
        CONVERT(DATETIME,
            STUFF(STUFF(CAST(h.run_date AS CHAR(8)),7,0,'-'),5,0,'-') + ' ' +
            STUFF(STUFF(RIGHT('000000' + CAST(h.run_time AS VARCHAR(6)),6),5,0,':'),3,0,':')
        )                                   AS run_completed_at,
        ROW_NUMBER() OVER (
            PARTITION BY j.job_id
            ORDER BY h.run_date DESC, h.run_time DESC
        )                                   AS rn
    FROM msdb.dbo.sysjobhistory  h
    JOIN msdb.dbo.sysjobs        j ON j.job_id = h.job_id
    WHERE h.step_id    = 0
      AND h.run_status = 1   /* successful completions only */
      AND h.run_date  >= CAST(CONVERT(CHAR(8), DATEADD(DAY, -30, GETDATE()), 112) AS INT)
),
agg AS (
    SELECT
        job_id, job_name, enabled,
        COUNT(*)                                                        AS runs_last_30d,
        MAX(CASE WHEN rn = 1 THEN duration_sec  END)                   AS last_run_sec,
        MAX(CASE WHEN rn = 1 THEN run_completed_at END)                AS last_run_at,
        CAST(AVG(CAST(duration_sec AS FLOAT)) AS DECIMAL(10,1))        AS avg_sec_30d,
        MAX(duration_sec)                                              AS max_sec_30d,
        MIN(duration_sec)                                              AS min_sec_30d
    FROM history
    GROUP BY job_id, job_name, enabled
    HAVING COUNT(*) >= 2
)
SELECT
    job_name,
    enabled,
    runs_last_30d,
    CONVERT(VARCHAR(8), DATEADD(SECOND, last_run_sec,          0), 108) AS last_run_duration,
    CONVERT(VARCHAR(8), DATEADD(SECOND, CAST(avg_sec_30d AS INT), 0), 108) AS avg_duration_30d,
    CONVERT(VARCHAR(8), DATEADD(SECOND, max_sec_30d,           0), 108) AS max_duration_30d,
    CAST(
        CASE WHEN avg_sec_30d > 0
             THEN (CAST(last_run_sec AS FLOAT) - avg_sec_30d) / avg_sec_30d * 100
             ELSE 0
        END AS DECIMAL(6,1))                                            AS pct_vs_avg,
    CASE
        WHEN avg_sec_30d > 0
             AND last_run_sec > avg_sec_30d * 2
             AND (last_run_sec - avg_sec_30d) > 30  THEN 'SPIKE'
        WHEN avg_sec_30d > 0
             AND last_run_sec > avg_sec_30d * 1.25
             AND (last_run_sec - avg_sec_30d) > 10  THEN 'GROWING'
        ELSE 'OK'
    END                                                                 AS trend_status,
    /* Raw seconds for charting */
    last_run_sec,
    CAST(avg_sec_30d AS INT)                                           AS avg_sec_30d,
    max_sec_30d,
    CONVERT(VARCHAR(16), last_run_at, 120)                              AS last_run_at
FROM agg
ORDER BY pct_vs_avg DESC, job_name;
