-- ============================================================================
-- SICOM-ICEO | Migración 36 — Tendencia + Auditoría de cambios en Reporte Diario
-- ============================================================================
-- Propósito : Complementa la migración 33 con dos funciones que alimentan los
--             gráficos de tendencia (últimos N días) y la sección de
--             "cambios del día" del reporte diario de la flota.
--
--   * fn_tendencia_reporte_diario(dias)  → serie temporal extraída de los
--                                          snapshots históricos (sin recalcular).
--   * fn_cambios_estado_dia(fecha)       → lista de overrides manuales del día
--                                          con usuario, motivo y OT asociada.
-- ============================================================================


-- ============================================================================
-- 1. TENDENCIA HISTÓRICA (últimos N días)
-- ============================================================================
-- Usa exclusivamente los snapshots guardados en reportes_diarios_snapshot, así
-- no recalculamos todo el JSON. Devuelve una fila por día con las métricas que
-- alimentan los gráficos (línea de OEE/Disp/Util y barras apiladas de estados).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_tendencia_reporte_diario(
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    fecha                   DATE,
    oee_promedio            NUMERIC,
    disponibilidad_promedio NUMERIC,
    utilizacion_promedio    NUMERIC,
    calidad_promedio        NUMERIC,
    total_arrendados        INTEGER,
    total_disponibles       INTEGER,
    total_mantencion        INTEGER,
    total_taller            INTEGER,
    total_fuera_servicio    INTEGER,
    total_uso_interno       INTEGER,
    total_leasing           INTEGER,
    cambios_24h             INTEGER,
    ots_abiertas            INTEGER,
    alertas_criticas        INTEGER
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        s.fecha,
        ((s.payload -> 'oee_mes' -> 'total' ->> 'oee_promedio')::NUMERIC)             AS oee_promedio,
        ((s.payload -> 'oee_mes' -> 'total' ->> 'disponibilidad_promedio')::NUMERIC)  AS disponibilidad_promedio,
        ((s.payload -> 'oee_mes' -> 'total' ->> 'utilizacion_promedio')::NUMERIC)     AS utilizacion_promedio,
        ((s.payload -> 'oee_mes' -> 'total' ->> 'calidad_promedio')::NUMERIC)         AS calidad_promedio,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'A')::INTEGER, 0)      AS total_arrendados,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'D')::INTEGER, 0)      AS total_disponibles,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'M')::INTEGER, 0)      AS total_mantencion,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'T')::INTEGER, 0)      AS total_taller,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'F')::INTEGER, 0)      AS total_fuera_servicio,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'U')::INTEGER, 0)      AS total_uso_interno,
        COALESCE((s.payload -> 'flota' -> 'por_estado_hoy' ->> 'L')::INTEGER, 0)      AS total_leasing,
        COALESCE((s.payload -> 'flota' ->> 'cambios_24h')::INTEGER, 0)                AS cambios_24h,
        COALESCE((s.payload -> 'mantenimiento' ->> 'ots_abiertas')::INTEGER, 0)       AS ots_abiertas,
        COALESCE((s.payload -> 'alertas' ->> 'criticas_activas')::INTEGER, 0)         AS alertas_criticas
    FROM reportes_diarios_snapshot s
    WHERE s.fecha >= CURRENT_DATE - (p_dias || ' days')::INTERVAL
    ORDER BY s.fecha ASC;
$$;

COMMENT ON FUNCTION fn_tendencia_reporte_diario(INTEGER) IS
    'Serie temporal de los últimos N días extraída de los snapshots guardados. Alimenta gráficos de tendencia.';


-- ============================================================================
-- 2. CAMBIOS DE ESTADO DEL DÍA (auditoría)
-- ============================================================================
-- Lista todos los overrides manuales registrados en estado_diario_flota de la
-- fecha pedida, con patente, equipo, quién los hizo, motivo, y OT asociada.
-- Se ordena por hora descendente (lo más reciente arriba).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_cambios_estado_dia(
    p_fecha DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    fecha_hora        TIMESTAMPTZ,
    activo_id         UUID,
    patente           TEXT,
    equipo            TEXT,
    estado_codigo     CHAR(1),
    motivo            TEXT,
    usuario_id        UUID,
    usuario_nombre    TEXT,
    usuario_rol       TEXT,
    ot_relacionada_id UUID,
    ot_folio          TEXT
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        e.actualizado_at                               AS fecha_hora,
        e.activo_id,
        COALESCE(a.patente, a.codigo)::TEXT            AS patente,
        COALESCE(a.nombre, m.nombre, '—')::TEXT        AS equipo,
        e.estado_codigo,
        e.motivo_override                              AS motivo,
        e.actualizado_por                              AS usuario_id,
        COALESCE(u.nombre_completo, u.email, 'Sistema')::TEXT AS usuario_nombre,
        COALESCE(u.rol::TEXT, '—')                     AS usuario_rol,
        e.ot_relacionada_id,
        ot.folio::TEXT                                 AS ot_folio
    FROM estado_diario_flota e
    LEFT JOIN activos a          ON a.id = e.activo_id
    LEFT JOIN modelos m          ON m.id = a.modelo_id
    LEFT JOIN usuarios_perfil u  ON u.id = e.actualizado_por
    LEFT JOIN ordenes_trabajo ot ON ot.id = e.ot_relacionada_id
    WHERE e.fecha = p_fecha
      AND e.override_manual = true
    ORDER BY e.actualizado_at DESC NULLS LAST;
$$;

COMMENT ON FUNCTION fn_cambios_estado_dia(DATE) IS
    'Lista los overrides manuales del día con usuario, motivo y OT asociada. Alimenta el timeline del reporte diario.';


-- ============================================================================
-- 3. PERMISOS RLS
-- ============================================================================
-- Ambas funciones heredan RLS de las tablas base (reportes_diarios_snapshot,
-- estado_diario_flota). No es necesario crear policies nuevas — los perfiles
-- con lectura sobre esas tablas también podrán invocar las funciones.
-- ============================================================================

GRANT EXECUTE ON FUNCTION fn_tendencia_reporte_diario(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_cambios_estado_dia(DATE)           TO authenticated;


-- ============================================================================
-- 4. VERIFICACIÓN (smoke test)
-- ============================================================================

DO $$
DECLARE
    v_tendencia_count INTEGER;
    v_cambios_count   INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_tendencia_count FROM fn_tendencia_reporte_diario(30);
    SELECT COUNT(*) INTO v_cambios_count   FROM fn_cambios_estado_dia(CURRENT_DATE);

    RAISE NOTICE '── Migración 36 aplicada ──';
    RAISE NOTICE 'Snapshots últimos 30 días:  %', v_tendencia_count;
    RAISE NOTICE 'Cambios manuales hoy:       %', v_cambios_count;
END $$;
