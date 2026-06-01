-- ============================================================================
-- SICOM-ICEO | 106 — Cierre diario de flota (propuesta geocerca + confirmacion)
-- ============================================================================
-- Implementa el flujo de "tablero de cierre diario":
--   1. fn_propuesta_cierre_diario(fecha): arma, por equipo de flota, el
--      estado del dia ANTERIOR (semilla) + un SUGERIDO calculado por geocerca
--      (fn_estado_por_geocerca), con fallback al dia anterior si no hay senal.
--   2. rpc_confirmar_cierre_diario(fecha, items): la persona revisa/edita y al
--      dar OK esto ESCRIBE estado_diario_flota (congelado, override_manual) y
--      PROPAGA a activos el estado_comercial + contrato, para que comercial y
--      el resto del sistema queden consistentes.
--
-- Universo: misma flota que el analisis de fiabilidad (camiones, camionetas,
-- lubrimovil, equipo_menor). Excluye surtidores/bombas/estanques.
-- ============================================================================

-- ============================================================================
-- 1. PROPUESTA DEL DIA (lectura, no escribe)
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_propuesta_cierre_diario(
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    activo_id          UUID,
    patente            VARCHAR,
    codigo             VARCHAR,
    equipamiento       VARCHAR,
    cliente_actual     VARCHAR,
    contrato_id        UUID,
    contrato_label     TEXT,
    estado_previo      CHAR(1),
    estado_sugerido    CHAR(1),
    geocerca_nombre    VARCHAR,
    gps_ts             TIMESTAMPTZ,
    gps_lat            NUMERIC,
    gps_lng            NUMERIC,
    ya_confirmado      BOOLEAN,
    estado_dia_actual  CHAR(1)
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.patente,
        a.codigo,
        a.nombre AS equipamiento,
        a.cliente_actual,
        a.contrato_id,
        (c.codigo || COALESCE(' · ' || c.cliente, ''))::text AS contrato_label,
        prev.estado_codigo AS estado_previo,
        COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::char(1) AS estado_sugerido,
        geo.nombre AS geocerca_nombre,
        g.ts_gps,
        g.latitud,
        g.longitud,
        (hoy.activo_id IS NOT NULL AND hoy.override_manual) AS ya_confirmado,
        hoy.estado_codigo AS estado_dia_actual
    FROM activos a
    LEFT JOIN contratos c ON c.id = a.contrato_id
    LEFT JOIN gps_estado_actual g ON g.activo_id = a.id
    LEFT JOIN LATERAL (
        SELECT e.estado_codigo
          FROM estado_diario_flota e
         WHERE e.activo_id = a.id AND e.fecha < p_fecha
         ORDER BY e.fecha DESC
         LIMIT 1
    ) prev ON true
    LEFT JOIN LATERAL (
        SELECT e.activo_id, e.estado_codigo, e.override_manual
          FROM estado_diario_flota e
         WHERE e.activo_id = a.id AND e.fecha = p_fecha
    ) hoy ON true
    LEFT JOIN LATERAL (
        SELECT gg.nombre
          FROM gps_geocercas gg
         WHERE gg.activo
           AND g.latitud IS NOT NULL
           AND fn_punto_en_geocerca(g.latitud, g.longitud, gg.id)
         ORDER BY gg.radio_m ASC
         LIMIT 1
    ) geo ON true
    WHERE a.estado != 'dado_baja'
      AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    ORDER BY a.patente NULLS LAST, a.codigo;
END $$;

COMMENT ON FUNCTION fn_propuesta_cierre_diario(DATE) IS
    'Propuesta de cierre diario por equipo: estado del dia anterior (semilla) + '
    'sugerido por geocerca (fn_estado_por_geocerca, fallback al previo) + '
    'ubicacion/geocerca actual y contrato. No escribe.';


-- ============================================================================
-- 2. CONFIRMACION DEL DIA (escribe + propaga)
-- ============================================================================
-- p_items: arreglo JSON [{activo_id, estado_codigo, contrato_id?}, ...]
--   estado_codigo : codigo elegido por la persona (A,C,D,H,R,M,T,F,V,U,L)
--   contrato_id   : contrato a asignar (o null para soltarlo)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_confirmar_cierre_diario(
    p_fecha DATE,
    p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_item      JSONB;
    v_activo    UUID;
    v_estado    CHAR(1);
    v_contrato  UUID;
    v_cliente   VARCHAR;
    v_estado_com estado_comercial_enum;
    v_n         INTEGER := 0;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_activo   := (v_item->>'activo_id')::uuid;
        v_estado   := upper(v_item->>'estado_codigo')::char(1);
        v_contrato := NULLIF(v_item->>'contrato_id', '')::uuid;

        IF v_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L') THEN
            RAISE EXCEPTION 'Estado invalido % para activo %', v_estado, v_activo;
        END IF;

        -- Cliente: del contrato si viene; si no, el actual del activo
        v_cliente := NULL;
        IF v_contrato IS NOT NULL THEN
            SELECT cliente INTO v_cliente FROM contratos WHERE id = v_contrato;
        END IF;
        IF v_cliente IS NULL THEN
            SELECT cliente_actual INTO v_cliente FROM activos WHERE id = v_activo;
        END IF;

        -- Upsert del estado del dia (congelado como cierre)
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo, cliente,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at, registrado_por, observacion
        ) VALUES (
            v_activo, p_fecha, v_contrato, v_estado, v_cliente,
            true, 'Cierre diario de flota', false,
            v_user, now(), v_user, 'Cierre diario confirmado'
        )
        ON CONFLICT (activo_id, fecha) DO UPDATE SET
            estado_codigo   = EXCLUDED.estado_codigo,
            contrato_id     = EXCLUDED.contrato_id,
            cliente         = EXCLUDED.cliente,
            override_manual = true,
            motivo_override = 'Cierre diario de flota',
            calculado_auto  = false,
            actualizado_por = EXCLUDED.actualizado_por,
            actualizado_at  = now(),
            updated_at      = now();

        -- Reverse-map a estado_comercial (solo codigos comerciales;
        -- M/T/F/H no cambian el comercial: un equipo arrendado en taller
        -- sigue comercialmente arrendado).
        v_estado_com := (CASE v_estado
            WHEN 'A' THEN 'arrendado'
            WHEN 'C' THEN 'arrendado'
            WHEN 'D' THEN 'disponible'
            WHEN 'U' THEN 'uso_interno'
            WHEN 'L' THEN 'leasing'
            WHEN 'R' THEN 'en_recepcion'
            WHEN 'V' THEN 'en_venta'
            ELSE NULL
        END)::estado_comercial_enum;

        -- Propagar a activos: contrato siempre; comercial + cliente solo si mapea
        UPDATE activos SET
            contrato_id      = v_contrato,
            estado_comercial = COALESCE(v_estado_com, estado_comercial),
            cliente_actual   = CASE WHEN v_estado_com IS NOT NULL THEN v_cliente
                                    ELSE cliente_actual END,
            updated_at       = now()
        WHERE id = v_activo;

        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'confirmados', v_n);
END $$;

COMMENT ON FUNCTION rpc_confirmar_cierre_diario(DATE, JSONB) IS
    'Confirma el cierre diario: escribe estado_diario_flota (override_manual) por '
    'cada equipo y propaga estado_comercial + contrato a activos.';

GRANT EXECUTE ON FUNCTION fn_propuesta_cierre_diario(DATE)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_confirmar_cierre_diario(DATE, JSONB) TO anon, authenticated;


-- ============================================================================
-- 3. SMOKE TEST
-- ============================================================================
DO $$
DECLARE v_rows INTEGER;
BEGIN
    SELECT count(*) INTO v_rows FROM fn_propuesta_cierre_diario(CURRENT_DATE);
    RAISE NOTICE '== Cierre diario ==';
    RAISE NOTICE 'fn_propuesta_cierre_diario(hoy) devolvio % equipos', v_rows;
    IF v_rows = 0 THEN
        RAISE EXCEPTION 'Propuesta vacia: revisar universo de flota.';
    END IF;
END $$;
