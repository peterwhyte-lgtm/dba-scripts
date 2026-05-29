/*
Script Name : Get-MigrationChecklist
Description : Returns Migration Checklist for DBA review and troubleshooting.
Author      : Peter Whyte (https://sqldba.blog)
*/
-- Migration checklist and configuration review template.
-- Use this as a starting point before moving objects, jobs, logins, or linked servers.

SELECT 'Pre-migration checklist:' AS note;
SELECT '1. Confirm backup/restore coverage.' AS checklist_item;
SELECT '2. Confirm instance and database compatibility.' AS checklist_item;
SELECT '3. Review linked servers, jobs, and logins.' AS checklist_item;
SELECT '4. Validate security and permissions.' AS checklist_item;
SELECT '5. Test restore and application connectivity.' AS checklist_item;




