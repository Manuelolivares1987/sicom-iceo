-- ============================================================================
-- SICOM-ICEO | 229 — ENEX: varias programaciones del mismo punto en el mes
-- ============================================================================
-- Pedido de Manuel: el plan (mensual/trimestral) debe permitir programar una
-- instalación VARIAS veces en el mes (ej. calibración quincenal).
--   1. Se elimina el UNIQUE (instalacion, tipo, año, mes) → N por mes.
--   2. rpc_enex_programar: cada llamada crea una programación nueva.
--   3. rpc_enex_duplicar_periodo: copia TODAS las programaciones del período
--      origen (solo para pares instalación+servicio aún vacíos en el destino,
--      para poder re-ejecutar sin duplicar).
-- Las vistas (panel/KPI/terreno) ya son por-programación: no cambian.
-- ============================================================================

ALTER TABLE enex_programaciones
  DROP CONSTRAINT IF EXISTS enex_programaciones_instalacion_id_tipo_servicio_periodo_an_key;

CREATE INDEX IF NOT EXISTS idx_enex_prog_inst_periodo
  ON enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes);

-- ── rpc_enex_programar: siempre agrega una programación nueva ───────────────
CREATE OR REPLACE FUNCTION public.rpc_enex_programar(
    p_instalacion_id uuid, p_tipo_servicio text, p_anio integer, p_mes integer,
    p_fecha date DEFAULT NULL::date, p_observacion text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_tipo_servicio NOT IN ('mantencion','calibracion') THEN
        RAISE EXCEPTION 'tipo_servicio inválido'; END IF;

    -- [MIG229] Sin upsert: un punto se puede programar varias veces en el mes.
    INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
    VALUES (p_instalacion_id, p_tipo_servicio, p_anio, p_mes, p_fecha, p_observacion, auth.uid())
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'programacion_id', v_id);
END $function$;

-- ── rpc_enex_duplicar_periodo: copia todo el set del período origen ─────────
CREATE OR REPLACE FUNCTION public.rpc_enex_duplicar_periodo(
    p_anio_origen integer, p_mes_origen integer, p_anio_dest integer, p_mes_dest integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n INT;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;

    -- Copia TODAS las programaciones del origen, pero solo para los pares
    -- (instalación, servicio) que aún no tienen ninguna en el destino
    -- (permite re-ejecutar el botón sin duplicar el plan).
    INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, creado_por)
    SELECT o.instalacion_id, o.tipo_servicio, p_anio_dest, p_mes_dest, auth.uid()
      FROM enex_programaciones o
     WHERE o.periodo_anio = p_anio_origen AND o.periodo_mes = p_mes_origen
       AND NOT EXISTS (
           SELECT 1 FROM enex_programaciones d
            WHERE d.instalacion_id = o.instalacion_id
              AND d.tipo_servicio = o.tipo_servicio
              AND d.periodo_anio = p_anio_dest AND d.periodo_mes = p_mes_dest);
    GET DIAGNOSTICS v_n = ROW_COUNT;

    RETURN jsonb_build_object('success', true, 'copiadas', v_n);
END $function$;

DO $$ BEGIN RAISE NOTICE 'MIG229 OK: ENEX permite varias programaciones por punto/mes'; END $$;
