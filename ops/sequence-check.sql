SELECT format(
  'DO $test$ BEGIN IF (SELECT last_value FROM %I.%I) < coalesce((SELECT max(%I) FROM %I.%I), 0) THEN RAISE EXCEPTION ''sequence behind restored table''; END IF; END $test$;',
  sn.nspname, s.relname, a.attname, tn.nspname, t.relname
)
FROM pg_class s
JOIN pg_namespace sn ON sn.oid = s.relnamespace
JOIN pg_sequence sq ON sq.seqrelid = s.oid AND sq.seqincrement > 0
JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
JOIN pg_class t ON t.oid = d.refobjid
JOIN pg_namespace tn ON tn.oid = t.relnamespace
JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
WHERE s.relkind = 'S'
\gexec
