-- ============================================================================
-- 81_mantenimiento_one_shot_sembrar_planes.sql
-- ----------------------------------------------------------------------------
-- One-shot: cierra el gap actual de 54 activos descubiertos llamando a
-- fn_auto_crear_planes_activo() para cada activo vivo con modelo.
--
-- Idempotente: si un activo ya tiene todos sus planes, no hace nada.
--
-- Resultado esperado: cobertura sube de ~21% a ~100% (todos los activos
-- con modelo y pautas disponibles tienen sus planes asignados).
-- ============================================================================

DO $$
DECLARE
    v_a   RECORD;
    v_tot_activos INT := 0;
    v_tot_creados INT := 0;
    v_creados_act INT;
BEGIN
    FOR v_a IN
        SELECT id, codigo FROM activos
         WHERE estado != 'dado_baja'
           AND modelo_id IS NOT NULL
         ORDER BY codigo
    LOOP
        v_creados_act := fn_auto_crear_planes_activo(v_a.id);
        v_tot_activos := v_tot_activos + 1;
        v_tot_creados := v_tot_creados + v_creados_act;
        IF v_creados_act > 0 THEN
            RAISE NOTICE '  + activo % => % planes creados', v_a.codigo, v_creados_act;
        END IF;
    END LOOP;

    RAISE NOTICE '== MIG81 OK ==';
    RAISE NOTICE '   activos revisados: %', v_tot_activos;
    RAISE NOTICE '   planes creados:    %', v_tot_creados;
END $$;

-- Mostrar resultado final
SELECT * FROM v_mantenimiento_cobertura_resumen;

NOTIFY pgrst, 'reload schema';
