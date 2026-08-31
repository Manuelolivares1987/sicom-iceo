-- ============================================================================
-- MIG451 · La cuadrilla se guarda por persona, no por string
-- ============================================================================
--
-- MIG446 creó `taller_ot_cuadrilla` y la sembró desde el texto que había, pero
-- la pantalla que asigna mecánicos siguió escribiendo sólo el campo de texto:
-- juntaba los nombres con coma y los metía en `taller_plan_semanal_ots.cuadrilla`.
-- O sea, la tabla nueva quedaba desactualizada desde el primer cambio.
--
-- Este RPC es el único camino para tocar la cuadrilla desde el tablero. Escribe
-- las dos cosas —la tabla por persona, que es la que paga, y el texto, que es lo
-- que el resto de las pantallas todavía muestra— para que no puedan discrepar.
--
-- El congelado no se repite acá: el trigger de MIG446 ya impide tocar la
-- cuadrilla de una OT ejecutada, y deja cada alta y cada baja en bitácora.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_set_cuadrilla(
    p_plan_ot_id  UUID,
    p_tecnico_ids UUID[],
    p_motivo      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT;
    v_texto  TEXT;
    v_n      INT;
    v_max    INT := 2;   -- mismo tope que MAX_MECANICOS en la app
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','jefe_operaciones','planificador') THEN
        RAISE EXCEPTION 'Tu perfil no puede asignar mecánicos.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id) THEN
        RAISE EXCEPTION 'La jornada no existe.';
    END IF;

    v_n := COALESCE(array_length(p_tecnico_ids, 1), 0);
    IF v_n > v_max THEN
        RAISE EXCEPTION 'Como máximo % mecánicos por jornada.', v_max;
    END IF;

    IF v_n > 0 AND EXISTS (
        SELECT 1 FROM unnest(p_tecnico_ids) AS x(id)
         WHERE NOT EXISTS (SELECT 1 FROM taller_tecnicos t
                            WHERE t.id = x.id AND COALESCE(t.activo, TRUE))
    ) THEN
        RAISE EXCEPTION 'Alguno de los técnicos no existe o está inactivo.';
    END IF;

    -- Fuera los que ya no están. El trigger de MIG446 bloquea si la OT ya se
    -- ejecutó, y anota la baja en la bitácora.
    DELETE FROM taller_ot_cuadrilla c
     WHERE c.plan_ot_id = p_plan_ot_id
       AND (v_n = 0 OR NOT (c.tecnico_id = ANY(p_tecnico_ids)));

    -- Y dentro los nuevos. El primero de la lista queda como titular.
    IF v_n > 0 THEN
        INSERT INTO taller_ot_cuadrilla (plan_ot_id, tecnico_id, rol, declarada_por, origen)
        SELECT p_plan_ot_id,
               x.id,
               CASE WHEN x.orden = 1 THEN 'titular' ELSE 'apoyo' END,
               v_user,
               'manual'
          FROM unnest(p_tecnico_ids) WITH ORDINALITY AS x(id, orden)
        ON CONFLICT (plan_ot_id, tecnico_id) DO NOTHING;
    END IF;

    -- El texto se deriva de la tabla, nunca al revés.
    SELECT string_agg(t.nombre, ', ' ORDER BY c.rol DESC, t.nombre)
      INTO v_texto
      FROM taller_ot_cuadrilla c
      JOIN taller_tecnicos t ON t.id = c.tecnico_id
     WHERE c.plan_ot_id = p_plan_ot_id;

    UPDATE taller_plan_semanal_ots
       SET cuadrilla = v_texto,
           observaciones = CASE
               WHEN COALESCE(length(trim(p_motivo)), 0) > 0
               THEN trim(COALESCE(observaciones, '') || E'\n[Cambio de cuadrilla] ' || trim(p_motivo))
               ELSE observaciones END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;

    RETURN jsonb_build_object('success', true, 'cuadrilla', v_texto, 'personas', v_n);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_set_cuadrilla(UUID, UUID[], TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_set_cuadrilla(UUID, UUID[], TEXT) TO authenticated;

-- ── La cuadrilla de una jornada, para que la pantalla la pueda mostrar ──────
CREATE OR REPLACE FUNCTION rpc_taller_cuadrilla_jornada(p_plan_ot_id UUID)
RETURNS TABLE (tecnico_id UUID, nombre TEXT, rol TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT c.tecnico_id, t.nombre::TEXT, c.rol
      FROM taller_ot_cuadrilla c
      JOIN taller_tecnicos t ON t.id = c.tecnico_id
     WHERE c.plan_ot_id = p_plan_ot_id
     ORDER BY c.rol DESC, t.nombre;
$$;

REVOKE ALL ON FUNCTION rpc_taller_cuadrilla_jornada(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_cuadrilla_jornada(UUID) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
-- Sin tocar datos: una prueba que escriba tendría que revertirse con una
-- excepción, y eso revertiría también la creación de las funciones. La prueba
-- con datos va aparte.
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public'
       AND p.proname IN ('rpc_taller_set_cuadrilla','rpc_taller_cuadrilla_jornada');
    IF v_n <> 2 THEN RAISE EXCEPTION 'FALLO: faltan funciones de cuadrilla (%)', v_n; END IF;

    SELECT count(*) INTO v_n FROM taller_ot_cuadrilla;
    RAISE NOTICE 'cuadrilla estructurada: % personas-jornada', v_n;
    RAISE NOTICE 'el tablero ya tiene por dónde escribirla';
END
$mig$;

COMMIT;
