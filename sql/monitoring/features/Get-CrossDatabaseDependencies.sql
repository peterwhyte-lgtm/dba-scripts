/*
Script Name : Get-CrossDatabaseDependencies
Category    : monitoring
Purpose     : Objects in the current database that reference other databases via 3-part names or linked servers — critical to find before a migration, rename, or decommission.
              Note: only captures statically-resolvable references. Dynamic SQL built at runtime will not appear here.
Author      : Peter Whyte (https://sqldba.blog/dba-scripts-get-collation-conflicts-and-cross-database-dependencies/)
Requires    : VIEW DEFINITION
*/
-- SAFE:ReadOnly
-- IMPACT:Low
-- SCOPE:CurrentDatabase
SET NOCOUNT ON;

/* ── Static cross-database references from sys.sql_expression_dependencies ─ */
SELECT
    'Object Reference' AS reference_type,
    DB_NAME() AS source_database,
    OBJECT_SCHEMA_NAME(d.referencing_id) AS source_schema,
    OBJECT_NAME(d.referencing_id) AS source_object,
    o.type_desc AS source_object_type,
    COALESCE(d.referenced_server_name + '.', '')
    + COALESCE(d.referenced_database_name + '.', '')
    + COALESCE(d.referenced_schema_name + '.', '')
    + COALESCE(d.referenced_entity_name, '?') AS referenced_target,
    d.referenced_server_name,
    d.referenced_database_name,
    d.referenced_schema_name,
    d.referenced_entity_name
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
WHERE ( d.referenced_database_name IS NOT NULL
       AND d.referenced_database_name <> DB_NAME()
      )
   OR d.referenced_server_name IS NOT NULL

UNION ALL

/* ── Synonyms pointing to other databases or servers ────────────────────── */
SELECT
    'Synonym' AS reference_type,
    DB_NAME() AS source_database,
    SCHEMA_NAME(syn.schema_id) AS source_schema,
    syn.name AS source_object,
    'SYNONYM' AS source_object_type,
    syn.base_object_name AS referenced_target,
    /* Parse server from 4-part name (server.db.schema.obj) */
    CASE WHEN syn.base_object_name LIKE '[[]%].%.[%].%'
         THEN PARSENAME(REPLACE(syn.base_object_name, '].[', '.'), 4)
         ELSE NULL END AS referenced_server_name,
    /* Parse database: 4-part = part 3, 3-part = part 3 */
    CASE WHEN LEN(syn.base_object_name) - LEN(REPLACE(syn.base_object_name, '.', '')) >= 2
         THEN PARSENAME(REPLACE(REPLACE(syn.base_object_name,'[',''),']',''), 3)
         ELSE NULL END AS referenced_database_name,
    NULL AS referenced_schema_name,
    NULL AS referenced_entity_name
FROM sys.synonyms syn
WHERE syn.base_object_name LIKE '%.%.%' /* at least a 3-part name */

ORDER BY reference_type, source_object, referenced_target;
