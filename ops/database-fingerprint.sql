SET timezone = 'UTC';
SET extra_float_digits = 3;
SELECT format(
  'SELECT %L || ''|'' || count(*) || ''|'' || md5(coalesce(string_agg(md5(to_jsonb(t)::text), '''' ORDER BY md5(to_jsonb(t)::text)), '''')) FROM %I.%I t;',
  schemaname || '.' || tablename, schemaname, tablename
)
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename
\gexec
