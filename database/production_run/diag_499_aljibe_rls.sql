-- Diagnóstico (solo lectura): ¿por qué el operador de taller no ve el campo
-- «cuenta litros» en la OT de un aljibe? El hook useMedidoresOT lee
-- checklist_v2_instance con un join embebido a activos(tipo, tipo_equipamiento);
-- si RLS de activos no deja leer al rol del taller, el join vuelve NULL y la
-- pantalla cree que el equipo no exige cuenta litros.
DO $d$
DECLARE r RECORD; v_n INT;
BEGIN
    -- 1. Las policies de activos, con sus roles.
    FOR r IN
        SELECT polname, pg_get_expr(polqual, polrelid) AS qual,
               (SELECT string_agg(rolname, ',') FROM pg_roles WHERE oid = ANY(polroles)) AS roles,
               polcmd
          FROM pg_policy WHERE polrelid = 'public.activos'::regclass
    LOOP
        RAISE NOTICE 'policy activos: % · cmd=% · roles=% · qual=%',
            r.polname, r.polcmd, COALESCE(r.roles,'(public)'), COALESCE(substr(r.qual,1,140),'-');
    END LOOP;
    SELECT count(*) INTO v_n FROM pg_policy WHERE polrelid = 'public.activos'::regclass;
    IF v_n = 0 THEN RAISE NOTICE 'activos NO tiene policies (¿RLS off?)'; END IF;
    RAISE NOTICE 'RLS activado en activos: %',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.activos'::regclass);

    -- 2. El dato del equipo de la OT que miró Manuel.
    FOR r IN
        SELECT ot.folio, a.patente, a.tipo, a.tipo_equipamiento,
               i.horometro, i.kilometraje, i.cuenta_litros, i.medidores_por IS NOT NULL AS por_persona
          FROM ordenes_trabajo ot
          JOIN checklist_v2_instance i ON i.ot_id = ot.id
          JOIN activos a ON a.id = i.activo_id
         WHERE ot.folio = 'OT-202608-00013'
         ORDER BY i.created_at DESC LIMIT 1
    LOOP
        RAISE NOTICE 'OT % · % · tipo=% · equipamiento=% · hm=% km=% cl=% · por_persona=%',
            r.folio, r.patente, r.tipo, r.tipo_equipamiento,
            r.horometro, r.kilometraje, r.cuenta_litros, r.por_persona;
    END LOOP;
END $d$;
