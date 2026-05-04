-- ============================================================================
-- 14B2A_hotfix_control_calidad_groupby.sql
-- ----------------------------------------------------------------------------
-- HOTFIX para 14B2: error 42803 "subquery uses ungrouped column r.operador_nombre".
--
-- Causa raiz:
--   La vista v_qr_checklist_kpi_operador agrupa por
--     LOWER(COALESCE(r.operador_nombre,'(sin nombre)')),
--     COALESCE(r.operador_nombre, '(sin nombre)')
--   pero las subconsultas correlacionadas para alertas_calidad_30d /
--   alertas_calidad_confirmadas referencian r.operador_nombre RAW. PostgreSQL
--   no infiere dependencia funcional y aborta el CREATE VIEW.
--
-- Fix:
--   Refactor a CTE base: la agrupacion ocurre en el CTE, y las subconsultas
--   correlacionadas se mueven al SELECT externo donde b.operador_norm es una
--   columna regular (no agrupada).
--
-- IDEMPOTENTE: solo CREATE OR REPLACE VIEW. No toca tablas/datos.
-- NO TOCA: 14, 14B, mig 55/56/57.
-- NO ELIMINA: alertas OPERADOR_REINCIDENTE ni score calidad (estan en otras
--             funciones, no en esta vista).
-- FALLA LIMPIO si 14B no aplicado.
--
-- USO:
--   Si 14B2 fallo en la vista pero el resto se aplico, ejecutar SOLO este
--   hotfix. Si todo el 14B2 hizo rollback (ver verificacion al final),
--   re-ejecutar 14B2 (ya corregido en la fuente) — luego este hotfix es
--   redundante pero seguro.
-- ============================================================================


-- ── 0. Precheck dependencias (14B base) ─────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='qr_checklist_templates') THEN
        RAISE EXCEPTION 'STOP — 14B no aplicado. Ejecutar primero 14B_qr_checklist_offline_mantencion_produccion.sql.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='qr_checklist_respuestas') THEN
        RAISE EXCEPTION 'STOP — qr_checklist_respuestas no existe (14B incompleto).';
    END IF;
END $$;


-- ── 0.1 Garantizar dependencias minimas del 14B2 (idempotente) ──────
-- Si el 14B2 hizo rollback transaccional, faltan las columnas/tabla que la
-- vista referencia. Estos ALTERs son un subset minimo del 14B2, NO duplican
-- ni alteran nada que ya exista (IF NOT EXISTS / IF NOT EXISTS).

ALTER TABLE qr_checklist_respuestas
    ADD COLUMN IF NOT EXISTS duracion_segundos     INT,
    ADD COLUMN IF NOT EXISTS score_calidad         INT,
    ADD COLUMN IF NOT EXISTS clasificacion_calidad VARCHAR(20)
        CHECK (clasificacion_calidad IS NULL OR clasificacion_calidad IN ('alta','media','baja','sospechoso')),
    ADD COLUMN IF NOT EXISTS sospechoso            BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS qr_checklist_alertas_calidad (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    checklist_respuesta_id   UUID NOT NULL REFERENCES qr_checklist_respuestas(id) ON DELETE CASCADE,
    activo_id                UUID NOT NULL REFERENCES activos(id),
    operador_nombre          VARCHAR(200),
    tipo_alerta              VARCHAR(40) NOT NULL CHECK (tipo_alerta IN (
        'DURACION_MUY_BAJA','TODO_OK_REPETITIVO','SIN_EVIDENCIA_CRITICA',
        'GPS_NO_DISPONIBLE','FUERA_DE_ZONA','RESPUESTAS_MASIVAS_RAPIDAS',
        'OPERADOR_REINCIDENTE','FOTO_NO_CAPTURADA_EN_CAMARA','CHECKLIST_DUPLICADO',
        'EVIDENCIA_OBLIGATORIA_FALTANTE','SIN_FIRMA_DECLARACION','SCORE_BAJO'
    )),
    severidad                VARCHAR(10) NOT NULL CHECK (severidad IN ('baja','media','alta','critica')),
    detalle                  TEXT NOT NULL,
    estado                   VARCHAR(20) NOT NULL DEFAULT 'abierta'
                             CHECK (estado IN ('abierta','en_revision','confirmada','descartada')),
    revisada_por             UUID REFERENCES usuarios_perfil(id),
    revisada_en              TIMESTAMPTZ,
    accion_revision          TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_activo ON qr_checklist_alertas_calidad (activo_id, estado, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_resp   ON qr_checklist_alertas_calidad (checklist_respuesta_id);
CREATE INDEX IF NOT EXISTS idx_qr_alertas_cal_op     ON qr_checklist_alertas_calidad (operador_nombre, created_at DESC);

ALTER TABLE qr_checklist_alertas_calidad ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_qr_alertas_cal_select ON qr_checklist_alertas_calidad;
CREATE POLICY pol_qr_alertas_cal_select ON qr_checklist_alertas_calidad FOR SELECT TO authenticated
    USING (fn_qr_es_rol_mantencion());
DROP POLICY IF EXISTS pol_qr_alertas_cal_update ON qr_checklist_alertas_calidad;
CREATE POLICY pol_qr_alertas_cal_update ON qr_checklist_alertas_calidad FOR UPDATE TO authenticated
    USING (fn_qr_es_rol_mantencion()) WITH CHECK (fn_qr_es_rol_mantencion());


-- ── 1. Recrear la vista con CTE base + subqueries en SELECT externo ─
CREATE OR REPLACE VIEW v_qr_checklist_kpi_operador AS
WITH base AS (
    SELECT
        LOWER(COALESCE(r.operador_nombre,'(sin nombre)'))                            AS operador_norm,
        COALESCE(r.operador_nombre, '(sin nombre)')                                  AS operador_nombre,
        COUNT(*)::int                                                                AS total_checklists,
        COUNT(*) FILTER (WHERE r.semaforo = 'verde')::int                            AS total_verde,
        COUNT(*) FILTER (WHERE r.semaforo IN ('amarillo','naranja','rojo'))::int     AS total_con_hallazgo,
        ROUND(AVG(r.score_calidad)::numeric, 1)                                      AS score_promedio,
        ROUND(AVG(r.duracion_segundos)::numeric, 0)                                  AS duracion_promedio_seg,
        COUNT(*) FILTER (WHERE r.sospechoso = true)::int                             AS sospechosos,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'baja')::int                AS calidad_baja,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'media')::int               AS calidad_media,
        COUNT(*) FILTER (WHERE r.clasificacion_calidad = 'alta')::int                AS calidad_alta,
        MAX(r.sincronizado_at)                                                       AS ultimo_checklist_at
    FROM qr_checklist_respuestas r
    WHERE r.sincronizado_at >= NOW() - INTERVAL '90 days'
    GROUP BY LOWER(COALESCE(r.operador_nombre,'(sin nombre)')),
             COALESCE(r.operador_nombre, '(sin nombre)')
)
SELECT
    b.operador_norm,
    b.operador_nombre,
    b.total_checklists,
    b.total_verde,
    b.total_con_hallazgo,
    b.score_promedio,
    b.duracion_promedio_seg,
    b.sospechosos,
    b.calidad_baja,
    b.calidad_media,
    b.calidad_alta,
    (SELECT COUNT(*)::int FROM qr_checklist_alertas_calidad ac
       WHERE LOWER(COALESCE(ac.operador_nombre,'')) = b.operador_norm
         AND ac.created_at >= NOW() - INTERVAL '30 days')                            AS alertas_calidad_30d,
    (SELECT COUNT(*)::int FROM qr_checklist_alertas_calidad ac
       WHERE LOWER(COALESCE(ac.operador_nombre,'')) = b.operador_norm
         AND ac.estado = 'confirmada')                                               AS alertas_calidad_confirmadas,
    b.ultimo_checklist_at
FROM base b;

GRANT SELECT ON v_qr_checklist_kpi_operador TO authenticated;


-- ── 2. Bitacora ──────────────────────────────────────────────────────
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables
                WHERE table_schema='public' AND table_name='operacion_migraciones_log') THEN
        INSERT INTO operacion_migraciones_log (
            codigo_paso, descripcion, ejecutado_por,
            fecha_inicio, fecha_fin, resultado, detalle
        ) VALUES (
            'PROD_MIG14B2A_HOTFIX_GROUPBY',
            'Hotfix vista v_qr_checklist_kpi_operador (refactor a CTE base por error 42803).',
            current_user, NOW(), NOW(), 'ok',
            'Subqueries correlacionadas movidas al SELECT externo del CTE; cascada y funciones intactas.'
        );
    END IF;
END $$;


-- ── 3. Verificacion final (1 fila) ──────────────────────────────────
-- Si la vista compila, llegamos a este SELECT. Si funciones calidad / RPC /
-- tabla alertas existen, el rebuild fue exitoso o ya estaba bien.

SELECT
    (to_regprocedure('public.fn_qr_calcular_score_calidad_checklist(uuid)')        IS NOT NULL
     AND to_regprocedure('public.fn_qr_evaluar_alertas_calidad(uuid)')             IS NOT NULL
     AND to_regprocedure('public.fn_qr_clasificar_calidad(integer,integer,integer)') IS NOT NULL)
        AS funciones_calidad_compilan,
    (to_regprocedure('public.rpc_guardar_checklist_publico(jsonb)') IS NOT NULL)
        AS rpc_guardar_checklist_publico_compila,
    (to_regprocedure('public.rpc_obtener_checklist_publico_por_qr(uuid)') IS NOT NULL)
        AS rpc_obtener_checklist_compila,
    EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='qr_checklist_alertas_calidad')
        AS tabla_alertas_calidad_existe,
    EXISTS (SELECT 1 FROM pg_views
             WHERE schemaname='public' AND viewname='v_qr_checklist_kpi_operador')
        AS vista_kpi_existe,
    -- Si la vista compilo (CREATE OR REPLACE no abortó), no hay error de GROUP BY.
    -- Hacemos un SELECT 1 con LIMIT para forzar el plan y verificar lectura.
    ((SELECT COUNT(*) FROM v_qr_checklist_kpi_operador) >= 0)
        AS sin_error_groupby,
    -- Si todas las columnas calidad existen en respuestas
    (
       EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name='qr_checklist_respuestas' AND column_name='duracion_segundos')
       AND EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name='qr_checklist_respuestas' AND column_name='score_calidad')
       AND EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_name='qr_checklist_respuestas' AND column_name='clasificacion_calidad')
    )                                                            AS columnas_calidad_aplicadas,
    NOW()                                                         AS chequeado_en;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- - Si TODAS las columnas BOOL devuelven TRUE → 14B2 quedo aplicado correctamente
--   (con el hotfix). Avanzar al 14C.
--
-- - Si tabla_alertas_calidad_existe = FALSE o columnas_calidad_aplicadas = FALSE:
--   → todo el 14B2 hizo rollback. Re-ejecutar el archivo COMPLETO
--     14B2_qr_checklist_control_calidad_produccion.sql (ya corregido en la fuente).
--     Luego volver a correr este hotfix (es idempotente, no falla).
--
-- - Si rpc_guardar_checklist_publico_compila = FALSE:
--   → la RPC del 14B2 no quedo en la BD. Re-ejecutar 14B2 completo.
-- ============================================================================
