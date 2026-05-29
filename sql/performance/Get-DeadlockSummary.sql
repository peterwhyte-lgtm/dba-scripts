/*
Script Name : Get-DeadlockSummary
Category    : performance-troubleshooting
Purpose     : Extract recent deadlock events from the system_health extended event session.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW SERVER STATE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT
    XEvent.query('(event/data/value[@name="xml_report"]/value)[1]') AS deadlock_xml
FROM sys.fn_xe_file_target_read_file('system_health*.xel', NULL, NULL, NULL)
WHERE object_name = 'xml_deadlock_report';




