-- ============================================================================
-- 03_bitacora_ejecucion.sql  —  Tabla de log y función helper.
-- ----------------------------------------------------------------------------
-- Crea la tabla `operacion_migraciones_log` para registrar cada paso ejecutado.
-- IDEMPOTENTE.
-- ============================================================================


CREATE TABLE IF NOT EXISTS operacion_migraciones_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    codigo_paso     VARCHAR(50) NOT NULL,
    descripcion     TEXT,
    ejecutado_por   TEXT,
    fecha_inicio    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_fin       TIMESTAMPTZ,
    resultado       VARCHAR(20) NOT NULL DEFAULT 'pendiente'
        CHECK (resultado IN ('pendiente','ok','error','revertido','warning')),
    detalle         TEXT,
    checksum_manual VARCHAR(120)
);

CREATE INDEX IF NOT EXISTS idx_oml_codigo  ON operacion_migraciones_log (codigo_paso);
CREATE INDEX IF NOT EXISTS idx_oml_fecha   ON operacion_migraciones_log (fecha_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_oml_result  ON operacion_migraciones_log (resultado);

COMMENT ON TABLE operacion_migraciones_log IS
    'Bitacora de ejecucion de migraciones productivas. NO eliminar registros.';


-- ── Función helper para registrar pasos ──────────────────────────────

CREATE OR REPLACE FUNCTION fn_log_operacion_migracion(
    p_codigo        VARCHAR,
    p_descripcion   TEXT,
    p_resultado     VARCHAR DEFAULT 'ok',
    p_detalle       TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID := gen_random_uuid();
BEGIN
    INSERT INTO operacion_migraciones_log (
        id, codigo_paso, descripcion, ejecutado_por,
        fecha_inicio, fecha_fin, resultado, detalle
    ) VALUES (
        v_id, p_codigo, p_descripcion, current_user,
        NOW(), NOW(), p_resultado, p_detalle
    );
    RETURN v_id;
END;
$$;

COMMENT ON FUNCTION fn_log_operacion_migracion IS
    'Helper para registrar paso de migracion en bitacora.';


-- ── Verificar tabla ──────────────────────────────────────────────────

SELECT 'TABLA_LOG' AS check_name,
       (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema='public' AND table_name='operacion_migraciones_log') AS existe,
       (SELECT COUNT(*) FROM pg_proc WHERE proname='fn_log_operacion_migracion') AS funcion_helper;


-- ── Registrar inicio de ejecucion productiva ─────────────────────────

SELECT fn_log_operacion_migracion(
    'PROD_INICIO',
    'Inicio de ejecucion productiva mig 55/56/57. Backup confirmado, prechecks OK.',
    'ok',
    'database=' || current_database() || ', usuario=' || current_user || ', hora=' || NOW()::TEXT
);


-- ── Vista actual de log ──────────────────────────────────────────────

SELECT codigo_paso, descripcion, resultado, fecha_inicio, ejecutado_por
FROM operacion_migraciones_log
ORDER BY fecha_inicio DESC
LIMIT 10;


-- ============================================================================
-- INTERPRETACION
-- ============================================================================
-- - existe = 1 → tabla creada.
-- - funcion_helper = 1 → función disponible.
-- - Debería aparecer la fila PROD_INICIO en la última query.
-- ============================================================================
