-- ============================================================================
-- SICOM-ICEO | 107 — Cierre diario: fijar Uso interno + limpiar categorias
-- ============================================================================
-- 1. Los equipos de USO INTERNO (operativos de Pillado) SIEMPRE se sugieren
--    como 'U' en el cierre diario; no se les propone cambio por geocerca.
--    Definicion: estado_comercial = 'uso_interno' (los 7 reales: furgones
--    taller movil, camionetas internas, gerencia).
-- 2. Limpieza de datos: 9 equipos tenian categoria_uso='uso_interno' pero
--    estan ARRENDADOS bajo contrato real (CMP, CM Cenizas, ESM). Su estado
--    diario es 'C' (en contrato) y asi deben verse en los reportes. Se
--    corrige su categoria_uso a 'arriendo_comercial' para que la tabla
--    "KPIs por Categoria" de Fiabilidad deje de contarlos como internos.
-- ============================================================================

-- ── 1. Reclasificar los 9 mal categorizados ────────────────────────────────
UPDATE activos
   SET categoria_uso = 'arriendo_comercial', updated_at = now()
 WHERE estado != 'dado_baja'
   AND categoria_uso = 'uso_interno'
   AND estado_comercial = 'arrendado';   -- exactamente los 9 en contrato


-- ── 2. fn_propuesta_cierre_diario con pin de Uso interno ────────────────────
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
        -- Uso interno: SIEMPRE 'U' (no se sugiere cambio por geocerca).
        -- El resto: sugerido por geocerca, fallback al dia previo, luego 'D'.
        (CASE
            WHEN a.estado_comercial = 'uso_interno' THEN 'U'
            ELSE COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')
         END)::char(1) AS estado_sugerido,
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


-- ── 3. Verificacion ────────────────────────────────────────────────────────
DO $$
DECLARE
    v_internos      INTEGER;
    v_sugeridos_u   INTEGER;
    v_recategorizados INTEGER;
BEGIN
    SELECT count(*) INTO v_internos
      FROM activos
     WHERE estado != 'dado_baja' AND estado_comercial = 'uso_interno'
       AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor');

    SELECT count(*) INTO v_sugeridos_u
      FROM fn_propuesta_cierre_diario(CURRENT_DATE)
     WHERE estado_sugerido = 'U';

    SELECT count(*) INTO v_recategorizados
      FROM activos
     WHERE estado != 'dado_baja' AND categoria_uso = 'uso_interno';

    RAISE NOTICE '== Pin Uso interno ==';
    RAISE NOTICE 'Equipos estado_comercial=uso_interno: %', v_internos;
    RAISE NOTICE 'Propuesta hoy con sugerido U: % (debe ser >= %)', v_sugeridos_u, v_internos;
    RAISE NOTICE 'Quedan con categoria_uso=uso_interno: % (deben ser los 7 reales)', v_recategorizados;
END $$;
