-- ############################################################################
-- MIG633 · Equipo fuera del cálculo de fiabilidad, por período
-- ----------------------------------------------------------------------------
-- QUÉ PASABA (Manuel 2026-10-21): seis camiones nuevos (CC-20-04 a CC-20-09:
-- WBFZ-22, WBGD-20, WBGD-30, WCWR-35, WCWR-25, WCWR-33) entraron al sistema el
-- 16-oct y se marcan 'D' disponible cada día mientras se equipan. 'D' cuenta
-- como día arriba: inflan la fiabilidad con camiones que todavía no operan.
--
-- LA REGLA: un equipo puede quedar FUERA DEL CÁLCULO entre dos fechas
-- (desde → hasta; abierto mientras siga fuera). Esos días no cuentan ni arriba
-- ni abajo: salen del numerador y del denominador, como 'S' (MIG306). Lo demás
-- del sistema no cambia: el estado diario (la 'D', el GPS, la OT) queda igual,
-- y el equipo sigue en mapa, taller, costos y documentos.
--
-- POR QUÉ POR PERÍODO Y NO UNA CASILLA SÍ/NO: con un booleano, al volver a
-- incluir el camión todos sus días anteriores vuelven al cálculo y la
-- fiabilidad de un mes ya informado cambia hacia atrás. Con fechas, el alta
-- vale desde ese día y lo informado no se mueve.
--
-- CÓMO: una vista `v_estado_diario_fiabilidad` = estado_diario_flota menos los
-- días fuera de cálculo. Las funciones que calculan fiabilidad o
-- disponibilidad leen la vista en vez de la tabla. Las que escriben el estado
-- diario o lo usan para operación (GPS, cierre, comercial) no se tocan.
-- Se parchea la definición VIVA de cada función (pg_get_functiondef).
-- ############################################################################

-- ── 1. Períodos fuera de cálculo ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activo_fiabilidad_exclusion (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id    UUID NOT NULL REFERENCES activos (id) ON DELETE CASCADE,
    desde        DATE NOT NULL,
    hasta        DATE,                              -- NULL = sigue fuera
    motivo       TEXT NOT NULL CHECK (length(btrim(motivo)) >= 5),
    creado_por   UUID,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cerrado_por  UUID,
    cerrado_at   TIMESTAMPTZ,
    CHECK (hasta IS NULL OR hasta >= desde)
);
-- Un solo período abierto por equipo.
CREATE UNIQUE INDEX IF NOT EXISTS uq_fiab_exclusion_abierta
    ON activo_fiabilidad_exclusion (activo_id) WHERE hasta IS NULL;
CREATE INDEX IF NOT EXISTS idx_fiab_exclusion_activo ON activo_fiabilidad_exclusion (activo_id, desde);

ALTER TABLE activo_fiabilidad_exclusion ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_fiab_exclusion_select ON activo_fiabilidad_exclusion;
CREATE POLICY pol_fiab_exclusion_select ON activo_fiabilidad_exclusion
    FOR SELECT TO authenticated USING (true);
REVOKE ALL ON activo_fiabilidad_exclusion FROM anon;
GRANT SELECT ON activo_fiabilidad_exclusion TO authenticated;   -- se escribe solo por RPC

-- ── 2. El estado diario que cuenta para fiabilidad ──────────────────────────
CREATE OR REPLACE VIEW v_estado_diario_fiabilidad WITH (security_invoker = true) AS
SELECT e.*
  FROM estado_diario_flota e
 WHERE NOT EXISTS (
        SELECT 1 FROM activo_fiabilidad_exclusion x
         WHERE x.activo_id = e.activo_id
           AND e.fecha >= x.desde
           AND (x.hasta IS NULL OR e.fecha <= x.hasta));
COMMENT ON VIEW v_estado_diario_fiabilidad IS
    'MIG633: estado_diario_flota sin los días en que el equipo está fuera del cálculo de fiabilidad (activo_fiabilidad_exclusion). Úsese para TODO cálculo de fiabilidad/disponibilidad.';
REVOKE ALL ON v_estado_diario_fiabilidad FROM anon;
GRANT SELECT ON v_estado_diario_fiabilidad TO authenticated;

-- ── 3. Sacar y dar de alta (desde Sugerencias GPS) ──────────────────────────
-- Sacar: abre un período desde p_desde (por defecto, el primer día del equipo
-- en el estado diario). Si se saca desde una fecha anterior a un alta, no se
-- pisa: cada período queda registrado.
CREATE OR REPLACE FUNCTION public.rpc_fiabilidad_excluir(p_activo_id uuid, p_motivo text, p_desde date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_desde DATE;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para sacar equipos del cálculo de fiabilidad.' USING ERRCODE = '42501';
    END IF;
    IF length(btrim(coalesce(p_motivo, ''))) < 5 THEN
        RAISE EXCEPTION 'Escribe el motivo (mínimo 5 caracteres), por ejemplo «en equipamiento».' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (SELECT 1 FROM activo_fiabilidad_exclusion WHERE activo_id = p_activo_id AND hasta IS NULL) THEN
        RAISE EXCEPTION 'El equipo ya está fuera del cálculo.' USING ERRCODE = 'P0001';
    END IF;

    v_desde := coalesce(p_desde,
                        (SELECT min(fecha) FROM estado_diario_flota WHERE activo_id = p_activo_id),
                        (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    -- No se superpone con un período ya cerrado.
    IF EXISTS (SELECT 1 FROM activo_fiabilidad_exclusion
                WHERE activo_id = p_activo_id AND hasta >= v_desde) THEN
        RAISE EXCEPTION 'Ese equipo ya estuvo fuera del cálculo hasta una fecha posterior al %; elige otra fecha.',
            to_char(v_desde, 'DD-MM-YYYY') USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO activo_fiabilidad_exclusion (activo_id, desde, motivo, creado_por)
    VALUES (p_activo_id, v_desde, btrim(p_motivo), auth.uid());
    RETURN jsonb_build_object('desde', v_desde);
END $function$;

-- Dar de alta: cierra el período abierto el día anterior a p_desde (por
-- defecto, hoy). Si el alta es el mismo día en que empezó (o antes), el
-- período no tuvo días: se borra.
CREATE OR REPLACE FUNCTION public.rpc_fiabilidad_incluir(p_activo_id uuid, p_desde date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_alta DATE := coalesce(p_desde, (NOW() AT TIME ZONE 'America/Santiago')::DATE);
    v_x    activo_fiabilidad_exclusion;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para dar de alta equipos en el cálculo de fiabilidad.' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_x FROM activo_fiabilidad_exclusion WHERE activo_id = p_activo_id AND hasta IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El equipo ya cuenta para fiabilidad.' USING ERRCODE = 'P0001';
    END IF;

    IF v_alta <= v_x.desde THEN
        DELETE FROM activo_fiabilidad_exclusion WHERE id = v_x.id;
        RETURN jsonb_build_object('alta', v_alta, 'periodo_borrado', true);
    END IF;
    UPDATE activo_fiabilidad_exclusion
       SET hasta = v_alta - 1, cerrado_por = auth.uid(), cerrado_at = NOW()
     WHERE id = v_x.id;
    RETURN jsonb_build_object('alta', v_alta, 'fuera_hasta', v_alta - 1);
END $function$;

REVOKE ALL ON FUNCTION rpc_fiabilidad_excluir(uuid, text, date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_fiabilidad_incluir(uuid, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_fiabilidad_excluir(uuid, text, date) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_fiabilidad_incluir(uuid, date) TO authenticated;

-- Para el informe: quién está fuera del cálculo dentro de un rango.
CREATE OR REPLACE FUNCTION public.fn_fiabilidad_excluidos(p_ini date, p_fin date)
 RETURNS TABLE(activo_id uuid, patente text, codigo text, desde date, hasta date, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    SELECT x.activo_id, a.patente::TEXT, a.codigo::TEXT, x.desde, x.hasta, x.motivo
      FROM activo_fiabilidad_exclusion x
      JOIN activos a ON a.id = x.activo_id
     WHERE x.desde <= p_fin AND (x.hasta IS NULL OR x.hasta >= p_ini)
     ORDER BY a.patente;
$function$;
REVOKE ALL ON FUNCTION fn_fiabilidad_excluidos(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_fiabilidad_excluidos(date, date) TO authenticated;

-- ── 4. Las funciones de fiabilidad y disponibilidad leen la vista ───────────
-- 4a. Completas: todas sus lecturas del estado diario son para el indicador
--     (ninguna escribe; verificado antes de aplicar).
DO $$
DECLARE
    f    TEXT;
    v_def TEXT;
    v_new TEXT;
BEGIN
    FOREACH f IN ARRAY ARRAY[
        'calcular_oee_activo', 'fn_calcular_fiabilidad_activo', 'fn_calcular_fiabilidad_flota',
        'fn_calcular_oee_fiabilidad_activo', 'fn_panel_disponibilidad', 'fn_panel_equipos_detenidos']
    LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = f;
        IF v_def IS NULL THEN RAISE EXCEPTION 'MIG633: no existe %', f; END IF;
        IF v_def ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?estado_diario_flota' THEN
            RAISE EXCEPTION 'MIG633: % escribe en estado_diario_flota; no se parchea', f;
        END IF;
        v_new := regexp_replace(v_def, '\mestado_diario_flota\M', 'v_estado_diario_fiabilidad', 'g');
        IF v_new = v_def THEN RAISE EXCEPTION 'MIG633: % no lee estado_diario_flota', f; END IF;
        EXECUTE v_new;
    END LOOP;
END $$;

-- 4b. Parciales: solo la parte que calcula el indicador.
DO $$
DECLARE
    v_def TEXT;
    a     TEXT;
    b     TEXT;
BEGIN
    -- Informe de fiabilidad (link público): la matriz de días. Los días de
    -- arriendo por contrato siguen leyendo la tabla (son historia comercial).
    v_def := replace(pg_get_functiondef('public.fn_reporte_fiabilidad_publico'::regproc), chr(13), '');
    a := E'FROM estado_diario_flota e\n      JOIN activos a ON a.id = e.activo_id\n      WHERE e.fecha BETWEEN p_ini AND p_fin';
    IF position(a IN v_def) = 0 THEN RAISE EXCEPTION 'MIG633: fn_reporte_fiabilidad_publico sin la matriz esperada'; END IF;
    EXECUTE replace(v_def, a, replace(a, 'FROM estado_diario_flota e', 'FROM v_estado_diario_fiabilidad e'));

    -- Reporte de flota (link): la disponibilidad del mes.
    v_def := replace(pg_get_functiondef('public.fn_reporte_flota_publico'::regproc), chr(13), '');
    a := E'FROM estado_diario_flota e JOIN veh v ON v.id = e.activo_id\n   WHERE e.fecha >= date_trunc(''month'', (SELECT f FROM ult))';
    IF position(a IN v_def) = 0 THEN RAISE EXCEPTION 'MIG633: fn_reporte_flota_publico sin el bloque mes esperado'; END IF;
    EXECUTE replace(v_def, a, replace(a, 'FROM estado_diario_flota e', 'FROM v_estado_diario_fiabilidad e'));

    -- Disponibilidad del taller (bono): la base del indicador. El conteo de
    -- días cargados (completitud del dato) sigue sobre la tabla.
    v_def := replace(pg_get_functiondef('public.fn_taller_disponibilidad_periodo'::regproc), chr(13), '');
    a := E'SELECT * FROM estado_diario_flota\n         WHERE fecha BETWEEN p_desde AND p_hasta\n           AND estado_codigo <> ''S''';
    IF position(a IN v_def) = 0 THEN RAISE EXCEPTION 'MIG633: fn_taller_disponibilidad_periodo sin la base esperada'; END IF;
    EXECUTE replace(v_def, a, replace(a, 'FROM estado_diario_flota', 'FROM v_estado_diario_fiabilidad'));
END $$;

-- 4c. Resumen diario: los conteos siguen siendo la flota completa; los
--     porcentajes (disponibilidad mecánica, tasa de arriendo) excluyen los
--     días fuera de cálculo.
CREATE OR REPLACE VIEW v_resumen_diario_flota AS
SELECT edf.fecha,
    edf.operacion,
    count(*) AS total_equipos,
    count(*) FILTER (WHERE edf.estado_codigo = 'A'::bpchar) AS arrendados,
    count(*) FILTER (WHERE edf.estado_codigo = 'D'::bpchar) AS disponibles,
    count(*) FILTER (WHERE edf.estado_codigo = 'U'::bpchar) AS uso_interno,
    count(*) FILTER (WHERE edf.estado_codigo = 'L'::bpchar) AS leasing,
    count(*) FILTER (WHERE edf.estado_codigo = 'M'::bpchar) AS en_mantencion,
    count(*) FILTER (WHERE edf.estado_codigo = 'T'::bpchar) AS en_terreno,
    count(*) FILTER (WHERE edf.estado_codigo = 'F'::bpchar) AS fuera_servicio,
    count(*) FILTER (WHERE edf.estado_codigo = 'H'::bpchar) AS en_habilitacion,
    count(*) FILTER (WHERE edf.estado_codigo = 'R'::bpchar) AS en_recepcion,
    count(*) FILTER (WHERE edf.estado_codigo = 'V'::bpchar) AS en_venta,
    round(count(*) FILTER (WHERE edf.estado_codigo <> ALL (ARRAY['M'::bpchar, 'T'::bpchar, 'F'::bpchar, 'H'::bpchar, 'S'::bpchar]) AND NOT x.fuera)::numeric
          / NULLIF(count(*) FILTER (WHERE edf.estado_codigo <> 'S'::bpchar AND NOT x.fuera), 0)::numeric * 100::numeric, 1) AS disponibilidad_mecanica_pct,
    round(count(*) FILTER (WHERE edf.estado_codigo = 'A'::bpchar AND NOT x.fuera)::numeric
          / NULLIF(count(*) FILTER (WHERE edf.estado_codigo <> ALL (ARRAY['M'::bpchar, 'T'::bpchar, 'F'::bpchar, 'H'::bpchar, 'V'::bpchar, 'S'::bpchar]) AND NOT x.fuera), 0)::numeric * 100::numeric, 1) AS tasa_arriendo_pct,
    count(*) FILTER (WHERE edf.estado_codigo = 'S'::bpchar) AS siniestrados
   FROM estado_diario_flota edf
   CROSS JOIN LATERAL (SELECT EXISTS (
            SELECT 1 FROM activo_fiabilidad_exclusion fx
             WHERE fx.activo_id = edf.activo_id AND edf.fecha >= fx.desde
               AND (fx.hasta IS NULL OR edf.fecha <= fx.hasta)) AS fuera) x
  GROUP BY edf.fecha, edf.operacion;

-- ── 5. Los seis camiones nuevos, fuera desde su primer día ──────────────────
INSERT INTO activo_fiabilidad_exclusion (activo_id, desde, motivo)
SELECT a.id, (SELECT min(e.fecha) FROM estado_diario_flota e WHERE e.activo_id = a.id),
       'Camión nuevo en equipamiento (pedido por Manuel Olivares, 21-10-2026)'
  FROM activos a
 WHERE a.codigo IN ('CC-20-04', 'CC-20-05', 'CC-20-06', 'CC-20-07', 'CC-20-08', 'CC-20-09')
   AND EXISTS (SELECT 1 FROM estado_diario_flota e WHERE e.activo_id = a.id)
   AND NOT EXISTS (SELECT 1 FROM activo_fiabilidad_exclusion x WHERE x.activo_id = a.id AND x.hasta IS NULL);

DO $$
BEGIN
    IF (SELECT count(*) FROM activo_fiabilidad_exclusion WHERE hasta IS NULL) < 6 THEN
        RAISE EXCEPTION 'MIG633: se esperaban 6 camiones fuera del cálculo';
    END IF;
END $$;
