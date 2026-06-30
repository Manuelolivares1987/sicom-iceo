-- ============================================================================
-- SICOM-ICEO | 182 — Plan Taller: tareas sin equipo de flota + categoría + zona
-- ============================================================================
-- Pedido Manuel (2026-06-30): programar en el Plan Taller tareas que NO siempre
-- son sobre un equipo de la flota:
--   - asistencia en terreno
--   - trabajo a equipo externo (fuera de flota)
--   - trabajos de soldadura
--   - trabajos a equipos de la flota (calibración, mantención preventiva, etc.)
-- Decisiones: tarea sin equipo permitida (descripción libre, sin checklist V03);
-- categoría de trabajo; filtro por operación (Coquimbo/Calama) en el mismo plan.
--
-- Cambios:
--   1. Enum categoria_tarea_taller.
--   2. taller_plan_semanal_ots: ot_id NULLABLE + columnas categoria, titulo,
--      descripcion, equipo_externo, operacion, tecnico_id (→ taller_tecnicos).
--   3. RPC rpc_taller_agregar_tarea_libre (tarea sin OT).
--   4. Vista v_taller_plan_semanal_ots_full: LEFT JOIN a OT + columnas nuevas
--      (categoria, titulo, descripcion, equipo_externo, operacion, tecnico_*,
--      es_tarea_libre). Mantiene TODAS las columnas previas.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Enum de categorías ────────────────────────────────────────────────────
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='categoria_tarea_taller') THEN
        CREATE TYPE categoria_tarea_taller AS ENUM (
            'preventiva',        -- mantención preventiva a equipo de flota
            'calibracion',       -- calibración a equipo de flota
            'equipo_flota',      -- otros trabajos a equipos de la flota
            'asistencia_terreno',-- asistencia en terreno
            'equipo_externo',    -- trabajo a equipo externo (fuera de flota)
            'soldadura'          -- trabajos de soldadura
        );
    END IF;
END $$;

-- ── 2. Columnas en taller_plan_semanal_ots ───────────────────────────────────
ALTER TABLE taller_plan_semanal_ots ALTER COLUMN ot_id DROP NOT NULL;
ALTER TABLE taller_plan_semanal_ots
    ADD COLUMN IF NOT EXISTS categoria       categoria_tarea_taller,
    ADD COLUMN IF NOT EXISTS titulo          VARCHAR(200),
    ADD COLUMN IF NOT EXISTS descripcion     TEXT,
    ADD COLUMN IF NOT EXISTS equipo_externo  VARCHAR(200),
    ADD COLUMN IF NOT EXISTS operacion       VARCHAR(40),
    ADD COLUMN IF NOT EXISTS tecnico_id      UUID REFERENCES taller_tecnicos(id);

-- una fila del plan es una OT de flota O una tarea libre (con título)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='chk_planot_ot_o_tarea') THEN
        ALTER TABLE taller_plan_semanal_ots
            ADD CONSTRAINT chk_planot_ot_o_tarea
            CHECK (ot_id IS NOT NULL OR titulo IS NOT NULL) NOT VALID;
    END IF;
END $$;

COMMENT ON COLUMN taller_plan_semanal_ots.categoria IS 'Categoría de trabajo (MIG182).';
COMMENT ON COLUMN taller_plan_semanal_ots.titulo IS 'Título de la tarea libre (sin OT de flota). MIG182.';
COMMENT ON COLUMN taller_plan_semanal_ots.equipo_externo IS 'Equipo/cliente/lugar para tareas fuera de flota. MIG182.';
COMMENT ON COLUMN taller_plan_semanal_ots.operacion IS 'Operación/zona de la tarea libre (Coquimbo/Calama). En OT de flota se deriva del activo. MIG182.';

CREATE INDEX IF NOT EXISTS idx_taller_planot_tecnico ON taller_plan_semanal_ots (tecnico_id) WHERE tecnico_id IS NOT NULL;

-- ── 3. RPC: agregar tarea libre (sin equipo de flota) ────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_agregar_tarea_libre(
    p_plan_semanal_id UUID,
    p_fecha           DATE,
    p_categoria       categoria_tarea_taller,
    p_titulo          TEXT,
    p_descripcion     TEXT    DEFAULT NULL,
    p_equipo_externo  TEXT    DEFAULT NULL,
    p_operacion       TEXT    DEFAULT NULL,
    p_tecnico_id      UUID    DEFAULT NULL,
    p_cuadrilla       VARCHAR DEFAULT NULL,
    p_horas           NUMERIC DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_rol     TEXT := fn_user_rol();
    v_dia_id  UUID;
    v_id      UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para programar tareas (rol: %)', v_rol; END IF;
    IF NULLIF(btrim(p_titulo),'') IS NULL THEN RAISE EXCEPTION 'El título de la tarea es obligatorio'; END IF;

    SELECT id INTO v_dia_id FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = p_plan_semanal_id AND fecha = p_fecha;
    IF v_dia_id IS NULL THEN
        RAISE EXCEPTION 'No existe el día % en el plan %', p_fecha, p_plan_semanal_id;
    END IF;

    INSERT INTO taller_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id,
        categoria, titulo, descripcion, equipo_externo, operacion,
        tecnico_id, cuadrilla, horas_planificadas, estado_plan
    ) VALUES (
        p_plan_semanal_id, v_dia_id, NULL,
        p_categoria, btrim(p_titulo), NULLIF(btrim(p_descripcion),''),
        NULLIF(btrim(p_equipo_externo),''), NULLIF(btrim(p_operacion),''),
        p_tecnico_id, p_cuadrilla, p_horas, 'planificada'
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_agregar_tarea_libre(UUID,DATE,categoria_tarea_taller,TEXT,TEXT,TEXT,TEXT,UUID,VARCHAR,NUMERIC) TO authenticated;

-- quitar una tarea libre (o jornada) del plan
CREATE OR REPLACE FUNCTION rpc_taller_eliminar_tarea(p_plan_ot_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rol TEXT := fn_user_rol(); v_id UUID;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso (rol: %)', v_rol; END IF;
    DELETE FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id RETURNING id INTO v_id;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Tarea no existe'; END IF;
    RETURN jsonb_build_object('success', true, 'plan_ot_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_taller_eliminar_tarea(UUID) TO authenticated;


-- ── 4. Vista: LEFT JOIN a OT + columnas nuevas ───────────────────────────────
DROP VIEW IF EXISTS v_taller_plan_semanal_ots_full CASCADE;
CREATE VIEW v_taller_plan_semanal_ots_full AS
SELECT
    t.id AS plan_ot_id, t.plan_semanal_id, t.plan_dia_id,
    d.fecha AS dia_fecha, d.nombre_dia AS dia_nombre, d.orden AS dia_orden,
    ps.fecha_inicio_semana, ps.fecha_fin_semana, ps.estado AS plan_estado,
    t.ot_id, ot.folio AS ot_folio, ot.tipo AS ot_tipo, ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad, ot.fecha_programada AS ot_fecha_programada,
    ot.plan_mantenimiento_id, pm.nombre AS pm_nombre, pm.proxima_ejecucion_fecha AS pm_proxima_fecha,
    ot.activo_id, a.codigo AS activo_codigo, a.nombre AS activo_nombre,
    a.patente AS activo_patente, a.tipo AS activo_tipo,
    ot.faena_id, f.nombre AS faena_nombre,
    ot.contrato_id, c.codigo AS contrato_codigo, c.cliente AS contrato_cliente,
    COALESCE(t.responsable_id, ot.responsable_id)        AS responsable_id,
    COALESCE(up.nombre_completo, up_ot.nombre_completo)  AS responsable,
    t.cuadrilla, t.horas_planificadas, t.avance_objetivo_pct,
    t.secuencia_jornada, t.estado_plan AS jornada_estado, t.observaciones,
    -- NUEVO (MIG182): categoría, tarea libre, técnico, operación
    t.categoria,
    (t.ot_id IS NULL)                                    AS es_tarea_libre,
    COALESCE(t.titulo, ot.folio)                         AS titulo,
    t.descripcion                                        AS tarea_descripcion,
    t.equipo_externo,
    COALESCE(t.operacion, a.operacion)                   AS operacion,
    t.tecnico_id, tt.nombre AS tecnico_nombre, tt.especialidad AS tecnico_especialidad,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false)                          AS checklist_total,
    (SELECT COUNT(*) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false
         AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente')            AS checklist_completados,
    (SELECT COALESCE(SUM(v.tiempo_min),0) FROM v_taller_ot_checklist_v3 v
       WHERE v.ot_id = t.ot_id AND v.excluido = false)                          AS tiempo_estimado_total_min,
    (SELECT id FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada') LIMIT 1) AS ejecucion_activa_id,
    (SELECT estado FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado IN ('en_ejecucion','pausada') LIMIT 1) AS ejecucion_activa_estado,
    (SELECT avance_final FROM taller_ot_ejecuciones e
       WHERE e.ot_id = t.ot_id AND e.estado = 'finalizada'
       ORDER BY finished_at DESC LIMIT 1)                                       AS ultima_ejecucion_avance,
    t.created_at, t.updated_at
FROM taller_plan_semanal_ots t
JOIN taller_plan_semanal_dias d  ON d.id = t.plan_dia_id
JOIN taller_planes_semanales ps   ON ps.id = t.plan_semanal_id
LEFT JOIN ordenes_trabajo ot      ON ot.id = t.ot_id
LEFT JOIN planes_mantenimiento pm ON pm.id = ot.plan_mantenimiento_id
LEFT JOIN activos a               ON a.id = ot.activo_id
LEFT JOIN faenas f                ON f.id = ot.faena_id
LEFT JOIN contratos c             ON c.id = ot.contrato_id
LEFT JOIN usuarios_perfil up      ON up.id = t.responsable_id
LEFT JOIN usuarios_perfil up_ot   ON up_ot.id = ot.responsable_id
LEFT JOIN taller_tecnicos tt      ON tt.id = t.tecnico_id;

COMMENT ON VIEW v_taller_plan_semanal_ots_full IS
    'Jornadas del plan (OT de flota o tarea libre) con categoría, técnico, operación y checklist V03. MIG182 (extiende MIG157).';
GRANT SELECT ON v_taller_plan_semanal_ots_full TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'enum_ok', EXISTS(SELECT 1 FROM pg_type WHERE typname='categoria_tarea_taller'),
    'ot_id_nullable', (SELECT is_nullable FROM information_schema.columns
        WHERE table_name='taller_plan_semanal_ots' AND column_name='ot_id'),
    'cols_nuevas', (SELECT array_agg(column_name ORDER BY column_name)
        FROM information_schema.columns WHERE table_name='taller_plan_semanal_ots'
          AND column_name IN ('categoria','titulo','descripcion','equipo_externo','operacion','tecnico_id')),
    'rpcs', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc
        WHERE proname IN ('rpc_taller_agregar_tarea_libre','rpc_taller_eliminar_tarea')),
    'vista_ok', EXISTS(SELECT 1 FROM information_schema.views WHERE table_name='v_taller_plan_semanal_ots_full')
) AS resultado;

NOTIFY pgrst, 'reload schema';
