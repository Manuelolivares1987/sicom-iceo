-- ============================================================================
-- SICOM-ICEO | 225 — Plan semanal de Calidad
-- ============================================================================
-- El encargado de calidad programa sus tareas de la semana (auditorías,
-- chequeos cruzados, inspecciones, documentación, otras) en un plan semanal
-- propio, con modal tipo "Programar tarea" del plan del taller.
--   - Tabla calidad_plan_tareas: una fila = una tarea en un día.
--   - Lectura: cualquier usuario autenticado. Escritura: solo vía RPCs
--     (auditor_calidad, administrador, jefe_mantenimiento, supervisor,
--      subgerente_operaciones).
-- ============================================================================

CREATE TABLE IF NOT EXISTS calidad_plan_tareas (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fecha            DATE NOT NULL,
    titulo           TEXT NOT NULL,
    descripcion      TEXT,
    tipo             TEXT NOT NULL DEFAULT 'otro'
                     CHECK (tipo IN ('auditoria','chequeo_cruzado','inspeccion','documentacion','otro')),
    equipo_texto     TEXT,                          -- patente / equipo / lugar (texto libre)
    responsable      TEXT,                          -- encargado de calidad a cargo
    horas_estimadas  NUMERIC(5,1),
    estado           TEXT NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','en_curso','hecha','cancelada')),
    hecha_at         TIMESTAMPTZ,
    created_by       UUID REFERENCES usuarios_perfil(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_calidad_plan_fecha ON calidad_plan_tareas(fecha);

ALTER TABLE calidad_plan_tareas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_calidad_plan_select ON calidad_plan_tareas;
CREATE POLICY pol_calidad_plan_select ON calidad_plan_tareas FOR SELECT TO authenticated USING (true);
-- Sin policy de INSERT/UPDATE/DELETE: solo las RPCs (SECURITY DEFINER) escriben.

-- ── Helper de autorización ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_calidad_plan_autorizado()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_rol TEXT := fn_user_rol();
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador','jefe_mantenimiento','supervisor','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para planificar calidad', v_rol;
    END IF;
END $$;

-- ── RPC: programar tarea ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_calidad_agregar_tarea(
    p_fecha date,
    p_titulo text,
    p_tipo text DEFAULT 'otro',
    p_descripcion text DEFAULT NULL,
    p_equipo_texto text DEFAULT NULL,
    p_responsable text DEFAULT NULL,
    p_horas numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_id UUID;
BEGIN
    PERFORM fn_calidad_plan_autorizado();
    IF COALESCE(TRIM(p_titulo), '') = '' THEN RAISE EXCEPTION 'El título es obligatorio'; END IF;

    INSERT INTO calidad_plan_tareas (fecha, titulo, descripcion, tipo, equipo_texto, responsable, horas_estimadas, created_by)
    VALUES (p_fecha, TRIM(p_titulo), NULLIF(TRIM(COALESCE(p_descripcion,'')),''), COALESCE(p_tipo,'otro'),
            NULLIF(TRIM(COALESCE(p_equipo_texto,'')),''), NULLIF(TRIM(COALESCE(p_responsable,'')),''), p_horas, auth.uid())
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id);
END $$;

-- ── RPC: actualizar (estado y/o mover de día) ────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_calidad_actualizar_tarea(
    p_id uuid,
    p_estado text DEFAULT NULL,
    p_fecha date DEFAULT NULL,
    p_titulo text DEFAULT NULL,
    p_descripcion text DEFAULT NULL,
    p_responsable text DEFAULT NULL,
    p_horas numeric DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    PERFORM fn_calidad_plan_autorizado();

    UPDATE calidad_plan_tareas SET
        estado      = COALESCE(p_estado, estado),
        fecha       = COALESCE(p_fecha, fecha),
        titulo      = COALESCE(NULLIF(TRIM(COALESCE(p_titulo,'')),''), titulo),
        descripcion = COALESCE(p_descripcion, descripcion),
        responsable = COALESCE(p_responsable, responsable),
        horas_estimadas = COALESCE(p_horas, horas_estimadas),
        hecha_at    = CASE WHEN p_estado = 'hecha' THEN NOW()
                           WHEN p_estado IS NOT NULL THEN NULL
                           ELSE hecha_at END,
        updated_at  = NOW()
     WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tarea no encontrada'; END IF;

    RETURN jsonb_build_object('success', true);
END $$;

-- ── RPC: eliminar ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_calidad_eliminar_tarea(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    PERFORM fn_calidad_plan_autorizado();
    DELETE FROM calidad_plan_tareas WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tarea no encontrada'; END IF;
    RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION rpc_calidad_agregar_tarea(date, text, text, text, text, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_calidad_actualizar_tarea(uuid, text, date, text, text, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_calidad_eliminar_tarea(uuid) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG225 OK: plan semanal de calidad (tabla + 3 RPCs)'; END $$;
