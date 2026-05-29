/*
Script Name : Get-DeadlockSummary
Description : Returns Deadlock Summary for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Summarize recent deadlock events from the system_health extended event session.
-- Useful for performance troubleshooting when deadlocks are suspected.

SELECT
    XEvent.query('(event/data/value[@name="xml_report"]/value)[1]') AS deadlock_xml
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
WHERE object_name = 'xml_deadlock_report';




