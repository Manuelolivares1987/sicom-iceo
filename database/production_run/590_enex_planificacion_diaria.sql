-- ============================================================================
-- SICOM-ICEO | 590 — ENEX: planificación diaria (Gantt) con mirada hacia adelante
-- ============================================================================
-- Pedido de Manuel (2026-10-14): planificar /dashboard/enex como la planilla
-- "Planificacion_Diaria_Ago-Oct_2026" (instalación × día, códigos CMP/C/MP/CP)
-- y ver % de avance real vs planificado vs proyectado.
--
-- El mantenedor NO cambia: /m/enex sigue leyendo enex_programaciones por mes y
-- fecha_programada. La Gantt escribe exactamente esas filas.
--
--   1. Trigger: el período (año/mes) sigue a la fecha programada. Antes
--      rpc_enex_reprogramar movía la fecha y dejaba el mes viejo: mover el
--      29-sep al 02-oct dejaba el servicio en septiembre y el teléfono, que
--      consulta por mes, lo mostraba en el mes equivocado.
--   2. rpc_enex_mover_programacion: arrastrar/mover un día en la Gantt.
--   3. rpc_enex_programar_lote: programa varias de una vez (importar la
--      planilla, programar mant.+calib. el mismo día). Idempotente: no
--      duplica la misma instalación+servicio+fecha.
-- ============================================================================

-- ── 1. Período sigue a la fecha ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_enex_prog_periodo_de_fecha()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.fecha_programada IS NOT NULL THEN
        NEW.periodo_anio := EXTRACT(YEAR  FROM NEW.fecha_programada)::int;
        NEW.periodo_mes  := EXTRACT(MONTH FROM NEW.fecha_programada)::int;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enex_prog_periodo_de_fecha ON enex_programaciones;
CREATE TRIGGER trg_enex_prog_periodo_de_fecha
    BEFORE INSERT OR UPDATE OF fecha_programada ON enex_programaciones
    FOR EACH ROW EXECUTE FUNCTION fn_enex_prog_periodo_de_fecha();

-- ── 2. Mover una programación a otro día ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_enex_mover_programacion(p_programacion_id uuid, p_fecha date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_fecha IS NULL THEN RAISE EXCEPTION 'Falta la fecha'; END IF;
    -- Lo ejecutado ya ocurrió: se mueve la ejecución, no el plan.
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = p_programacion_id) THEN
        RAISE EXCEPTION 'Este servicio ya tiene ejecución registrada: no se puede mover';
    END IF;
    UPDATE enex_programaciones SET fecha_programada = p_fecha WHERE id = p_programacion_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Programación no encontrada'; END IF;
    RETURN jsonb_build_object('success', true);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_enex_mover_programacion(uuid, date) TO authenticated;

-- ── 3. Programar en lote ────────────────────────────────────────────────────
-- p_items = [{instalacion_id, tipo_servicio, fecha, observacion}]
CREATE OR REPLACE FUNCTION public.rpc_enex_programar_lote(p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_it jsonb; v_fecha date; v_inst uuid; v_tipo text;
    v_creadas int := 0; v_omitidas int := 0;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'p_items debe ser un arreglo'; END IF;

    FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_inst  := (v_it->>'instalacion_id')::uuid;
        v_tipo  := v_it->>'tipo_servicio';
        v_fecha := (v_it->>'fecha')::date;
        IF v_tipo NOT IN ('mantencion','calibracion') OR v_fecha IS NULL OR v_inst IS NULL THEN
            RAISE EXCEPTION 'Ítem inválido: %', v_it;
        END IF;
        IF EXISTS (SELECT 1 FROM enex_programaciones
                    WHERE instalacion_id = v_inst AND tipo_servicio = v_tipo AND fecha_programada = v_fecha) THEN
            v_omitidas := v_omitidas + 1;
            CONTINUE;
        END IF;
        INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
        VALUES (v_inst, v_tipo, EXTRACT(YEAR FROM v_fecha)::int, EXTRACT(MONTH FROM v_fecha)::int, v_fecha,
                NULLIF(v_it->>'observacion',''), auth.uid());
        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'creadas', v_creadas, 'omitidas', v_omitidas);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_enex_programar_lote(jsonb) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG590 OK: ENEX planificación diaria (período sigue a la fecha, mover, lote)'; END $$;
