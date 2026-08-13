-- ============================================================================
-- SICOM-ICEO | 286 — Lo que reporta el cliente también se puede planificar
-- ============================================================================
-- MIG285 hace que la novedad del cliente se vuelva no conformidad y llegue al
-- jefe de taller. Pero las funciones que crean la OT correctiva tienen su
-- propia lista de orígenes válidos, y 'checklist_cliente' no estaba: el jefe
-- veía el hallazgo y el botón "Planificar" no lo tomaba.
--
-- Avisar sin poder actuar es peor que no avisar.
--
-- ADITIVA, IDEMPOTENTE — solo agrega el origen a las dos listas.
-- ============================================================================

DO $$
DECLARE
    v_nombre TEXT;
    v_def    TEXT;
    v_viejo  CONSTANT TEXT := '''ejecucion_ot'',''manual''';
    v_nuevo  CONSTANT TEXT := '''ejecucion_ot'',''manual'',''checklist_cliente''';
    v_tocadas INT := 0;
BEGIN
    FOREACH v_nombre IN ARRAY ARRAY['fn_planificar_nc_equipo', 'fn_planificar_nc'] LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = v_nombre;

        IF v_def IS NULL THEN
            RAISE NOTICE 'MIG286: % no existe, se omite', v_nombre;
            CONTINUE;
        END IF;

        IF v_def LIKE '%checklist_cliente%' THEN
            RAISE NOTICE 'MIG286: % ya acepta checklist_cliente', v_nombre;
            CONTINUE;
        END IF;

        -- fn_planificar_nc trabaja sobre UNA no conformidad ya elegida y no
        -- filtra por origen: no hay nada que ampliar ahí.
        IF v_def NOT LIKE '%origen%' THEN
            RAISE NOTICE 'MIG286: % no filtra por origen, no requiere cambio', v_nombre;
            CONTINUE;
        END IF;

        IF position(v_viejo IN v_def) = 0 THEN
            RAISE EXCEPTION 'STOP — % filtra por origen con un formato inesperado', v_nombre;
        END IF;

        EXECUTE replace(v_def, v_viejo, v_nuevo);
        v_tocadas := v_tocadas + 1;
        RAISE NOTICE 'MIG286: % ahora planifica lo que reporta el cliente', v_nombre;
    END LOOP;

    RAISE NOTICE 'MIG286: % función(es) actualizada(s)', v_tocadas;
END $$;

SELECT 'MIG286 OK' AS resultado,
       (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname LIKE 'fn_planificar_nc%'
           AND pg_get_functiondef(p.oid) LIKE '%checklist_cliente%') AS funciones_ok;
