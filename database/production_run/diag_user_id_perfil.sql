SELECT jsonb_build_object(
  'rls_enabled', (SELECT relrowsecurity FROM pg_class WHERE relname='checklist_v2_instance_item'),
  'policies', (SELECT jsonb_agg(jsonb_build_object('pol', polname, 'cmd', polcmd, 'roles',
        (SELECT array_agg(rolname) FROM pg_roles WHERE oid = ANY(p.polroles))))
      FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid WHERE c.relname='checklist_v2_instance_item')
) AS r;
