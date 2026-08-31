-- ============================================================================
-- MIG450 · Finalizar la OT también para el reloj
-- ============================================================================
--
-- MIG449 dejó `fn_taller_cerrar_ejecuciones_abiertas` y nadie la llamaba. Sin
-- eso la OT quedaba ejecutada y su ejecución corriendo para siempre: no hay
-- fecha de término, y la fecha de término es de donde salen los días que
-- deciden el tramo del bono.
--
-- Se reemplaza el cierre de terreno agregando esa llamada. Todo lo demás
-- —firma del técnico, trabajo registrado, medidores, marca de quién cerró—
-- queda igual que en MIG445.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_finalizar_mecanico(
    p_ot_id UUID,
    p_firma_tecnico_url TEXT,
    p_con_observaciones BOOLEAN DEFAULT FALSE,
    p_observaciones TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_inst RECORD; v_falta TEXT[] := ARRAY[]::TEXT[];
    v_trabajo JSONB;
    v_res JSONB;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF p_firma_tecnico_url IS NULL OR length(trim(p_firma_tecnico_url)) = 0 THEN
        RAISE EXCEPTION 'La firma del técnico es obligatoria para finalizar'; END IF;

    -- [MIG445] Sin trabajo registrado no hay OT que cerrar.
    v_trabajo := fn_taller_ot_tiene_trabajo(p_ot_id);
    IF NOT (v_trabajo->>'tiene')::BOOLEAN THEN
        RAISE EXCEPTION 'Esta OT no tiene trabajo registrado: no hay ningún ítem respondido ni tiempo de ejecución. Marca el checklist o usa el cronómetro antes de finalizar.';
    END IF;

    -- [MIG397] Con cuánto uso volvió el equipo se anota antes de cerrar.
    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;

    IF v_inst.id IS NOT NULL THEN
        IF v_inst.horometro IS NULL THEN
            v_falta := array_append(v_falta, 'el horómetro'::TEXT);
        END IF;
        IF v_inst.kilometraje IS NULL AND fn_activo_exige_kilometraje(v_inst.activo_id) THEN
            v_falta := array_append(v_falta, 'el kilometraje'::TEXT);
        END IF;
        IF array_length(v_falta, 1) > 0 THEN
            RAISE EXCEPTION 'Falta anotar % del equipo. Está arriba de la lista de tareas, en «Medidores del equipo».',
                array_to_string(v_falta, ' y ');
        END IF;
    END IF;

    UPDATE ordenes_trabajo SET firma_tecnico_url = p_firma_tecnico_url, updated_at = NOW() WHERE id = p_ot_id;

    -- [MIG450] El reloj se cierra con la OT. Antes la OT quedaba ejecutada y la
    -- ejecución seguía corriendo: sin fecha de término no hay días que medir, y
    -- los días son la mitad del bono.
    PERFORM fn_taller_cerrar_ejecuciones_abiertas(p_ot_id, p_observaciones);

    v_res := rpc_transicion_ot(
        p_ot_id,
        (CASE WHEN p_con_observaciones THEN 'ejecutada_con_observaciones' ELSE 'ejecutada_ok' END)::estado_ot_enum,
        v_user, NULL, NULL, p_observaciones, NULL);

    PERFORM fn_taller_marcar_cierre(p_ot_id, 'terreno');
    RETURN v_res;
END;
$$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_ok BOOLEAN;
BEGIN
    SELECT pg_get_functiondef(p.oid) ILIKE '%fn_taller_cerrar_ejecuciones_abiertas%'
      INTO v_ok
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname='rpc_taller_finalizar_mecanico';
    IF NOT COALESCE(v_ok, FALSE) THEN
        RAISE EXCEPTION 'FALLO: finalizar no cierra el reloj';
    END IF;
    RAISE NOTICE 'finalizar cierra la OT y su ejecución';
END
$mig$;

COMMIT;
