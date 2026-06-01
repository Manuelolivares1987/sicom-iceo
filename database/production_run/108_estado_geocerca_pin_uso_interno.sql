-- ============================================================================
-- SICOM-ICEO | 108 — fn_estado_por_geocerca respeta Uso interno (fix raiz)
-- ============================================================================
-- Bug: la bandeja de sugerencias por GPS (fn_sugerencias_estado_gps) seguia
-- pidiendo cambio de estado en los equipos de USO INTERNO, porque el sugerido
-- se calcula con fn_estado_por_geocerca, que deriva el estado puro del GPS
-- (un uso interno parado en el taller -> sugiere 'D').
--
-- Fix de raiz: fn_estado_por_geocerca devuelve SIEMPRE 'U' para equipos con
-- estado_comercial='uso_interno' (operativos propios de Pillado). Asi lo
-- respetan TODOS los consumidores: la bandeja de sugerencias Y el cierre diario.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_estado_por_geocerca(p_activo_id uuid)
 RETURNS character
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_lat numeric; v_lng numeric; v_ts timestamptz;
  v_contrato uuid; v_tipo text; v_geo_id uuid;
  v_ot_corr boolean; v_ot_prev boolean; v_es_contrato boolean;
BEGIN
  -- Uso interno: equipos operativos propios de Pillado, SIEMPRE 'U'.
  -- No se sugiere cambio por GPS/geocerca.
  IF (SELECT estado_comercial FROM activos WHERE id = p_activo_id) = 'uso_interno' THEN
    RETURN 'U';
  END IF;

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
END $function$;


-- ── Verificacion ───────────────────────────────────────────────────────────
DO $$
DECLARE
    v_internos        INTEGER;
    v_internos_u      INTEGER;
    v_piden_cambio    INTEGER;
BEGIN
    SELECT count(*) INTO v_internos
      FROM activos WHERE estado <> 'dado_baja' AND estado_comercial = 'uso_interno';

    -- De los uso interno, cuantos devuelven 'U' por geocerca
    SELECT count(*) INTO v_internos_u
      FROM activos
     WHERE estado <> 'dado_baja' AND estado_comercial = 'uso_interno'
       AND fn_estado_por_geocerca(id) = 'U';

    -- En la bandeja de sugerencias, cuantos uso interno aun "no coinciden"
    SELECT count(*) INTO v_piden_cambio
      FROM fn_sugerencias_estado_gps(CURRENT_DATE) s
      JOIN activos a ON a.id = s.activo_id
     WHERE a.estado_comercial = 'uso_interno' AND s.coincide = false;

    RAISE NOTICE '== Pin uso interno en fn_estado_por_geocerca ==';
    RAISE NOTICE 'Uso interno: % | devuelven U: % | aun piden cambio: %',
                 v_internos, v_internos_u, v_piden_cambio;
    IF v_piden_cambio > 0 THEN
        RAISE EXCEPTION 'Aun hay % uso interno pidiendo cambio.', v_piden_cambio;
    END IF;
END $$;
