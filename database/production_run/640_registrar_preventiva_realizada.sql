-- MIG640 · Registrar a mano una preventiva ya hecha (desde Horas por equipo)
-- ============================================================================
-- La base de cada pauta (ultima_ejecucion_*) solo avanzaba al cerrar una OT
-- ligada al plan (fn_ot_cerrada_avanza_plan). Cuando el taller la hace en una
-- OT correctiva o fuera del sistema, la pauta queda vencida para siempre: el
-- DJKL-18 marcaba la SM1 con −609 h teniendo el servicio hecho.
--
-- rpc_preventiva_registrar_realizada: fija fecha, horómetro y km de la pauta
-- y, como el cierre de OT (MIG513), deja al día los peldaños MENORES de la
-- misma escalera por horas — solo si su base es anterior (nunca retrocede una
-- pauta menor hecha después). Todo queda en plan_mantenimiento_registro_manual
-- con el antes, la nota y quién lo hizo.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS plan_mantenimiento_registro_manual (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id     UUID NOT NULL REFERENCES planes_mantenimiento(id) ON DELETE CASCADE,
    activo_id   UUID NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    fecha       DATE NOT NULL,
    horas       NUMERIC,
    km          NUMERIC,
    nota        TEXT NOT NULL,
    antes       JSONB NOT NULL,
    absorbidos  INT NOT NULL DEFAULT 0,
    creado_por  UUID DEFAULT auth.uid(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS ix_plan_registro_manual_activo
    ON plan_mantenimiento_registro_manual (activo_id, created_at DESC);

ALTER TABLE plan_mantenimiento_registro_manual ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS plan_registro_manual_select ON plan_mantenimiento_registro_manual;
CREATE POLICY plan_registro_manual_select ON plan_mantenimiento_registro_manual
    FOR SELECT TO authenticated USING (true);
REVOKE ALL ON plan_mantenimiento_registro_manual FROM anon;
GRANT SELECT ON plan_mantenimiento_registro_manual TO authenticated;

CREATE OR REPLACE FUNCTION public.rpc_preventiva_registrar_realizada(
    p_plan_id UUID, p_fecha DATE, p_horas NUMERIC, p_km NUMERIC, p_nota TEXT)
 RETURNS JSONB
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_plan  planes_mantenimiento;
    v_act   activos;
    v_hoy   DATE := (NOW() AT TIME ZONE 'America/Santiago')::DATE;
    v_abs   INT := 0;
    v_antes JSONB;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('mantenimiento', 'edit',
            ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para registrar mantenciones.' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_plan FROM planes_mantenimiento WHERE id = p_plan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La pauta no existe.' USING ERRCODE = 'P0001';
    END IF;
    SELECT * INTO v_act FROM activos WHERE id = v_plan.activo_id;

    IF p_fecha IS NULL OR p_fecha > v_hoy OR p_fecha < DATE '2015-01-01' THEN
        RAISE EXCEPTION 'La fecha debe ser de hoy o anterior.' USING ERRCODE = 'P0001';
    END IF;
    IF length(btrim(coalesce(p_nota, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe de dónde sale el dato (mínimo 5 caracteres), por ejemplo «OS 3410 taller Coquimbo».'
            USING ERRCODE = 'P0001';
    END IF;
    IF v_plan.frecuencia_horas IS NOT NULL AND (p_horas IS NULL OR p_horas <= 0) THEN
        RAISE EXCEPTION 'Indica el horómetro al que se hizo la mantención.' USING ERRCODE = 'P0001';
    END IF;
    IF p_horas IS NOT NULL AND coalesce(v_act.horas_uso_actual, 0) > 0
       AND p_horas > v_act.horas_uso_actual + 1 THEN
        RAISE EXCEPTION 'El horómetro (% h) es mayor que el actual del equipo (% h).',
            p_horas, round(v_act.horas_uso_actual, 1) USING ERRCODE = 'P0001';
    END IF;
    IF p_km IS NOT NULL AND coalesce(v_act.kilometraje_actual, 0) > 0
       AND p_km > v_act.kilometraje_actual + 1 THEN
        RAISE EXCEPTION 'Los km (%) son mayores que el odómetro actual del equipo (%).',
            p_km, round(v_act.kilometraje_actual) USING ERRCODE = 'P0001';
    END IF;

    v_antes := jsonb_build_object('fecha', v_plan.ultima_ejecucion_fecha,
                                  'horas', v_plan.ultima_ejecucion_horas,
                                  'km', v_plan.ultima_ejecucion_km);

    UPDATE planes_mantenimiento
       SET ultima_ejecucion_fecha = p_fecha,
           ultima_ejecucion_horas = coalesce(p_horas, ultima_ejecucion_horas),
           ultima_ejecucion_km    = coalesce(p_km, ultima_ejecucion_km),
           proxima_ejecucion_fecha = p_fecha + coalesce(frecuencia_dias, 30),
           updated_at = NOW()
     WHERE id = p_plan_id;

    -- Absorción (MIG513): el peldaño mayor incluye a los menores.
    IF v_plan.tipo_plan IN ('por_horas','mixto') AND v_plan.frecuencia_horas IS NOT NULL AND p_horas IS NOT NULL THEN
        UPDATE planes_mantenimiento p2
           SET ultima_ejecucion_fecha = p_fecha,
               ultima_ejecucion_horas = p_horas,
               ultima_ejecucion_km    = coalesce(p_km, p2.ultima_ejecucion_km),
               proxima_ejecucion_fecha = p_fecha + coalesce(p2.frecuencia_dias, 30),
               updated_at = NOW()
         WHERE p2.activo_id = v_plan.activo_id
           AND p2.id <> p_plan_id
           AND p2.activo_plan
           AND p2.tipo_plan IN ('por_horas','mixto')
           AND p2.frecuencia_horas IS NOT NULL
           AND p2.frecuencia_horas < v_plan.frecuencia_horas
           AND coalesce(p2.ultima_ejecucion_horas, 0) < p_horas;
        GET DIAGNOSTICS v_abs = ROW_COUNT;
    END IF;

    INSERT INTO plan_mantenimiento_registro_manual (plan_id, activo_id, fecha, horas, km, nota, antes, absorbidos)
    VALUES (p_plan_id, v_plan.activo_id, p_fecha, p_horas, p_km, btrim(p_nota), v_antes, v_abs);

    RETURN jsonb_build_object('plan', v_plan.nombre, 'absorbidos', v_abs);
END $function$;

REVOKE ALL ON FUNCTION rpc_preventiva_registrar_realizada(UUID, DATE, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_preventiva_registrar_realizada(UUID, DATE, NUMERIC, NUMERIC, TEXT) TO authenticated;

COMMIT;
