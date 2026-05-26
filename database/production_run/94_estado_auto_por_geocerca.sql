-- ============================================================================
-- 94_estado_auto_por_geocerca.sql
-- ----------------------------------------------------------------------------
-- 1. Agrega estado 'C' (En contrato) al CHECK de estado_diario_flota (Francke, CMP).
-- 2. fn_estado_por_geocerca(activo): deriva el estado del equipo desde su
--    posición GPS / geocerca actual:
--      - en faena de cliente  -> 'C' si opera bajo contrato, si no 'A'
--      - en base/taller        -> 'T' (correctivo abierto) o 'M' (mantención)
--      - fuera de toda geocerca-> 'T'/'M' si hay OT abierta, si no 'R' (tránsito)
--      - sin GPS o señal vieja -> NULL (no auto)
-- 3. fn_aplicar_estado_geocerca(fecha): aplica el estado derivado a esa fecha,
--    HÍBRIDO: respeta override_manual=true (no lo pisa).
-- ADITIVO.
-- ============================================================================

-- 1. Permitir 'C'
ALTER TABLE estado_diario_flota DROP CONSTRAINT IF EXISTS chk_estado_codigo;
ALTER TABLE estado_diario_flota ADD CONSTRAINT chk_estado_codigo
  CHECK (estado_codigo IN ('A','C','D','H','R','M','T','F','V','U','L'));

-- 2. Estado derivado de geocerca
CREATE OR REPLACE FUNCTION fn_estado_por_geocerca(p_activo_id uuid)
RETURNS char(1)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_lat numeric; v_lng numeric; v_ts timestamptz;
  v_contrato uuid; v_tipo text; v_geo_id uuid;
  v_ot_corr boolean; v_ot_prev boolean; v_es_contrato boolean;
BEGIN
  SELECT latitud, longitud, ts_gps INTO v_lat, v_lng, v_ts
    FROM gps_estado_actual WHERE activo_id = p_activo_id;
  IF v_lat IS NULL THEN RETURN NULL; END IF;
  IF v_ts IS NOT NULL AND v_ts < now() - interval '48 hours' THEN RETURN NULL; END IF;

  SELECT contrato_id INTO v_contrato FROM activos WHERE id = p_activo_id;

  -- ¿En qué geocerca está? prioriza la de su contrato, luego faena, luego radio menor
  SELECT g.id, g.tipo::text INTO v_geo_id, v_tipo
  FROM gps_geocercas g
  WHERE g.activo AND fn_punto_en_geocerca(v_lat, v_lng, g.id)
  ORDER BY (g.contrato_id IS NOT DISTINCT FROM v_contrato) DESC,
           (g.tipo = 'faena_cliente') DESC, g.radio_m ASC
  LIMIT 1;

  SELECT
    EXISTS(SELECT 1 FROM ordenes_trabajo o WHERE o.activo_id = p_activo_id
            AND o.tipo = 'correctivo'
            AND o.estado IN ('creada','asignada','en_ejecucion','pausada')),
    EXISTS(SELECT 1 FROM ordenes_trabajo o WHERE o.activo_id = p_activo_id
            AND o.tipo IN ('preventivo','inspeccion')
            AND o.estado IN ('creada','asignada','en_ejecucion','pausada'))
  INTO v_ot_corr, v_ot_prev;

  IF v_geo_id IS NULL THEN
    IF v_ot_corr THEN RETURN 'T'; ELSIF v_ot_prev THEN RETURN 'M'; ELSE RETURN 'R'; END IF;
  END IF;

  IF v_tipo IN ('base_pillado','taller_externo','bodega') THEN
    -- En base/taller: T si correctivo abierto, M si preventivo abierto,
    -- si no hay OT -> Disponible (parqueado en base, listo para arriendo).
    IF v_ot_corr THEN RETURN 'T'; ELSIF v_ot_prev THEN RETURN 'M'; ELSE RETURN 'D'; END IF;
  END IF;

  -- faena_cliente
  SELECT EXISTS(SELECT 1 FROM estado_diario_flota e
                WHERE e.activo_id = p_activo_id AND e.estado_codigo = 'C')
    INTO v_es_contrato;
  RETURN CASE WHEN v_es_contrato THEN 'C' ELSE 'A' END;
END $$;

-- 3. Aplicar a una fecha (respeta override_manual)
CREATE OR REPLACE FUNCTION fn_aplicar_estado_geocerca(p_fecha date DEFAULT current_date)
RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE v_n integer := 0;
BEGIN
  WITH calc AS (
    SELECT a.id AS activo_id, fn_estado_por_geocerca(a.id) AS est
    FROM activos a WHERE a.estado <> 'dado_baja'
  )
  INSERT INTO estado_diario_flota (activo_id, fecha, estado_codigo, calculado_auto, override_manual, motivo_override)
  SELECT activo_id, p_fecha, est, true, false, 'Auto geocerca'
  FROM calc WHERE est IS NOT NULL
  ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo, calculado_auto = true, updated_at = now()
    WHERE estado_diario_flota.override_manual = false;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- 4. Cron diario: aplica el estado por geocerca a las 09:20 UTC (~06:20 Chile),
--    después del cálculo base (09:00) y antes del snapshot del reporte (09:30).
--    Híbrido: respeta override_manual. El snapshot de las 09:30 lo recoge.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'estado-auto-geocerca') THEN
    PERFORM cron.unschedule('estado-auto-geocerca');
  END IF;
END $$;
SELECT cron.schedule('estado-auto-geocerca', '20 9 * * *',
  $$ SELECT fn_aplicar_estado_geocerca(current_date); $$);
