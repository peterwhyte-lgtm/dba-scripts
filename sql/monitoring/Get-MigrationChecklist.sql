/*
Script Name : Get-MigrationChecklist
Category    : configuration-and-environment
Purpose     : Pre-migration validation checklist for backups, compatibility, jobs, and permissions.
Author      : Peter Whyte (https://sqldba.blog)
Safe        : Read-only
Impact      : Low
Requires    : VIEW ANY DATABASE
*/
SET NOCOUNT ON;
-- SAFE:ReadOnly
-- IMPACT:Low

SELECT 'Pre-migration checklist:' AS note;
SELECT '1. Confirm backup/restore coverage.' AS checklist_item;
SELECT '2. Confirm instance and database compatibility.' AS checklist_item;
SELECT '3. Review linked servers, jobs, and logins.' AS checklist_item;
SELECT '4. Validate security and permissions.' AS checklist_item;
SELECT '5. Test restore and application connectivity.' AS checklist_item;




