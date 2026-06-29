-- ============================================================================
-- 173_taller_control_de_cambios.sql
-- ----------------------------------------------------------------------------
-- CONTROL DE CAMBIOS del plan semanal de taller.
--
-- Problema: hoy mover una jornada de un dia a otro (rpc_taller_mover_jornada),
-- cambiar el responsable o la cuadrilla es un UPDATE plano sin registro: no se
-- sabe quien lo cambio, ni cuando, ni por que. Manuel pide que, una vez
-- CONFIRMADO el plan, todo cambio del "dia a dia" exija un MOTIVO y quede
-- trazado, y que el personal asignado sea coherente/visible.
--
-- Que hace:
--   1. Tabla taller_plan_jornada_eventos (bitacora de cambios por jornada).
--   2. fn_taller_plan_confirmado(plan_semanal_id) -> el plan ya no es borrador.
--   3. fn_taller_log_jornada_evento(...) helper interno (SECURITY DEFINER).
--   4. rpc_taller_mover_jornada: + p_motivo. Exige motivo si el plan esta
--      confirmado. Registra dia anterior -> nuevo. Marca reprogramada_desde_id.
--   5. rpc_taller_editar_jornada / rpc_taller_asignar_responsable: registran
--      cambios de responsable/cuadrilla/horas; exigen motivo si cambia el
--      personal y el plan esta confirmado.
--   6. v_taller_jornada_eventos (timeline legible con nombres).
--
-- ADITIVA. Re-ejecutable (DROP+CREATE de funciones con firma nueva).
-- ============================================================================

-- ── 1. Bitacora de cambios de jornada ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_plan_jornada_eventos (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_ot_id           UUID NOT NULL REFERENCES taller_plan_semanal_ots(id) ON DELETE CASCADE,
    ot_id                UUID REFERENCES ordenes_trabajo(id) ON DELETE SET NULL,
    plan_semanal_id      UUID REFERENCES taller_planes_semanales(id) ON DELETE CASCADE,
    tipo                 VARCHAR(30) NOT NULL,
    dia_anterior         DATE,
    dia_nuevo            DATE,
    responsable_anterior UUID REFERENCES usuarios_perfil(id),
    responsable_nuevo    UUID REFERENCES usuarios_perfil(id),
    cuadrilla_anterior   VARCHAR(80),
    cuadrilla_nueva      VARCHAR(80),
    campo                VARCHAR(40),
    valor_anterior       TEXT,
    valor_nuevo          TEXT,
    motivo               TEXT,
    plan_confirmado      BOOLEAN NOT NULL DEFAULT FALSE,
    created_by           UUID REFERENCES auth.users(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_tpje_tipo CHECK (tipo IN (
        'reprogramacion','cambio_responsable','cambio_cuadrilla',
        'cambio_horas','cambio_avance','creacion','eliminacion','otro'))
);
CREATE INDEX IF NOT EXISTS idx_tpje_plan_ot ON taller_plan_jornada_eventos (plan_ot_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tpje_ot      ON taller_plan_jornada_eventos (ot_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_tpje_plansem ON taller_plan_jornada_eventos (plan_semanal_id, created_at DESC);

ALTER TABLE taller_plan_jornada_eventos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_tpje_select ON taller_plan_jornada_eventos;
CREATE POLICY pol_tpje_select ON taller_plan_jornada_eventos
    FOR SELECT TO authenticated USING (true);
-- Escritura solo via funciones SECURITY DEFINER (no policy de write).


-- ── 2. El plan ya esta confirmado? (no es borrador) ─────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_plan_confirmado(p_plan_semanal_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (SELECT estado <> 'borrador' FROM taller_planes_semanales WHERE id = p_plan_semanal_id),
        FALSE);
$$;


-- ── 3. Helper interno para registrar un evento ──────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_log_jornada_evento(
    p_plan_ot_id           UUID,
    p_tipo                 VARCHAR,
    p_motivo               TEXT    DEFAULT NULL,
    p_dia_anterior         DATE    DEFAULT NULL,
    p_dia_nuevo            DATE    DEFAULT NULL,
    p_responsable_anterior UUID    DEFAULT NULL,
    p_responsable_nuevo    UUID    DEFAULT NULL,
    p_cuadrilla_anterior   VARCHAR DEFAULT NULL,
    p_cuadrilla_nueva      VARCHAR DEFAULT NULL,
    p_campo                VARCHAR DEFAULT NULL,
    p_valor_anterior       TEXT    DEFAULT NULL,
    p_valor_nuevo          TEXT    DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ot UUID; v_plan UUID; v_conf BOOLEAN; v_id UUID;
BEGIN
    SELECT ot_id, plan_semanal_id INTO v_ot, v_plan
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    v_conf := fn_taller_plan_confirmado(v_plan);
    INSERT INTO taller_plan_jornada_eventos(
        plan_ot_id, ot_id, plan_semanal_id, tipo, motivo,
        dia_anterior, dia_nuevo, responsable_anterior, responsable_nuevo,
        cuadrilla_anterior, cuadrilla_nueva, campo, valor_anterior, valor_nuevo,
        plan_confirmado, created_by
    ) VALUES (
        p_plan_ot_id, v_ot, v_plan, p_tipo, NULLIF(TRIM(p_motivo), ''),
        p_dia_anterior, p_dia_nuevo, p_responsable_anterior, p_responsable_nuevo,
        p_cuadrilla_anterior, p_cuadrilla_nueva, p_campo, p_valor_anterior, p_valor_nuevo,
        v_conf, auth.uid()
    ) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;


-- ── 4. rpc_taller_mover_jornada (+ motivo, + bitacora) ──────────────────────
DROP FUNCTION IF EXISTS rpc_taller_mover_jornada(UUID, DATE, UUID);
CREATE OR REPLACE FUNCTION rpc_taller_mover_jornada(
    p_plan_ot_id     UUID,
    p_fecha_destino  DATE,
    p_responsable_id UUID DEFAULT NULL,
    p_motivo         TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_plan_id UUID; v_dia_destino UUID; v_estado VARCHAR; v_rol TEXT;
    v_dia_actual_id UUID; v_fecha_actual DATE; v_resp_actual UUID;
    v_confirmado BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT t.plan_semanal_id, t.estado_plan, t.plan_dia_id, t.responsable_id, d.fecha
      INTO v_plan_id, v_estado, v_dia_actual_id, v_resp_actual, v_fecha_actual
      FROM taller_plan_semanal_ots t
      JOIN taller_plan_semanal_dias d ON d.id = t.plan_dia_id
     WHERE t.id = p_plan_ot_id;
    IF v_plan_id IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;
    IF v_estado IN ('en_ejecucion','finalizada') THEN
        RAISE EXCEPTION 'No se puede mover jornada en estado %', v_estado;
    END IF;

    v_confirmado := fn_taller_plan_confirmado(v_plan_id);
    -- Si el plan ya esta confirmado, exigir motivo del cambio (control de cambios).
    IF v_confirmado AND COALESCE(TRIM(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO: el plan esta confirmado; indica por que se reprograma la jornada.';
    END IF;

    SELECT id INTO v_dia_destino FROM taller_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_id AND fecha = p_fecha_destino;
    IF v_dia_destino IS NULL THEN
        RAISE EXCEPTION 'Fecha % no pertenece al plan', p_fecha_destino;
    END IF;

    -- Sin cambio real de dia y sin cambio de responsable -> nada que registrar.
    IF v_dia_destino = v_dia_actual_id AND p_responsable_id IS NULL THEN
        RETURN jsonb_build_object('success', true, 'sin_cambios', true);
    END IF;

    UPDATE taller_plan_semanal_ots
       SET plan_dia_id    = v_dia_destino,
           responsable_id = COALESCE(p_responsable_id, responsable_id),
           reprogramada_desde_id = COALESCE(reprogramada_desde_id, p_plan_ot_id),
           estado_plan = CASE
             WHEN COALESCE(p_responsable_id, responsable_id) IS NOT NULL
              AND estado_plan = 'planificada' THEN 'asignada'
             ELSE estado_plan
           END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;

    IF v_fecha_actual <> p_fecha_destino THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'reprogramacion', p_motivo,
            p_dia_anterior := v_fecha_actual, p_dia_nuevo := p_fecha_destino);
    END IF;
    IF p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_actual THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_responsable_anterior := v_resp_actual, p_responsable_nuevo := p_responsable_id);
    END IF;

    RETURN jsonb_build_object('success', true, 'reprogramada', v_fecha_actual <> p_fecha_destino);
END;
$$;


-- ── 5. rpc_taller_editar_jornada (+ motivo, + bitacora de personal/horas) ───
DROP FUNCTION IF EXISTS rpc_taller_editar_jornada(UUID,UUID,VARCHAR,NUMERIC,NUMERIC,TEXT,BOOLEAN);
CREATE OR REPLACE FUNCTION rpc_taller_editar_jornada(
    p_plan_ot_id          UUID,
    p_responsable_id      UUID    DEFAULT NULL,
    p_cuadrilla           VARCHAR DEFAULT NULL,
    p_horas_planificadas  NUMERIC DEFAULT NULL,
    p_avance_objetivo     NUMERIC DEFAULT NULL,
    p_observaciones       TEXT    DEFAULT NULL,
    p_sync_responsable_ot BOOLEAN DEFAULT TRUE,
    p_motivo              TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_ot   UUID; v_plan UUID; v_conf BOOLEAN;
    v_resp_old UUID; v_cuad_old VARCHAR; v_horas_old NUMERIC;
    v_cambia_personal BOOLEAN;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para editar la jornada (rol: %)', v_rol;
    END IF;

    SELECT ot_id, plan_semanal_id, responsable_id, cuadrilla, horas_planificadas
      INTO v_ot, v_plan, v_resp_old, v_cuad_old, v_horas_old
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_ot IS NULL THEN RAISE EXCEPTION 'Jornada no existe'; END IF;

    v_conf := fn_taller_plan_confirmado(v_plan);
    v_cambia_personal :=
        (p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old)
     OR (p_cuadrilla     IS NOT NULL AND p_cuadrilla     IS DISTINCT FROM v_cuad_old);

    -- Si el plan esta confirmado y cambia el personal, exigir motivo.
    IF v_conf AND v_cambia_personal AND COALESCE(TRIM(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO: el plan esta confirmado; indica por que cambia el personal asignado.';
    END IF;

    UPDATE taller_plan_semanal_ots
       SET responsable_id     = COALESCE(p_responsable_id, responsable_id),
           cuadrilla          = COALESCE(p_cuadrilla, cuadrilla),
           horas_planificadas = COALESCE(p_horas_planificadas, horas_planificadas),
           avance_objetivo_pct= COALESCE(p_avance_objetivo, avance_objetivo_pct),
           observaciones      = COALESCE(p_observaciones, observaciones),
           estado_plan        = CASE WHEN estado_plan = 'planificada'
                                       AND COALESCE(p_responsable_id, responsable_id) IS NOT NULL
                                     THEN 'asignada' ELSE estado_plan END,
           updated_at         = NOW()
     WHERE id = p_plan_ot_id;

    IF p_sync_responsable_ot AND p_responsable_id IS NOT NULL THEN
        UPDATE ordenes_trabajo SET responsable_id = p_responsable_id, updated_at = NOW()
         WHERE id = v_ot;
    END IF;

    -- Bitacora
    IF p_responsable_id IS NOT NULL AND p_responsable_id IS DISTINCT FROM v_resp_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_responsable_anterior := v_resp_old, p_responsable_nuevo := p_responsable_id);
    END IF;
    IF p_cuadrilla IS NOT NULL AND p_cuadrilla IS DISTINCT FROM v_cuad_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_cuadrilla', p_motivo,
            p_cuadrilla_anterior := v_cuad_old, p_cuadrilla_nueva := p_cuadrilla);
    END IF;
    IF p_horas_planificadas IS NOT NULL AND p_horas_planificadas IS DISTINCT FROM v_horas_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_horas', p_motivo,
            p_campo := 'horas_planificadas',
            p_valor_anterior := v_horas_old::TEXT, p_valor_nuevo := p_horas_planificadas::TEXT);
    END IF;

    RETURN jsonb_build_object('success', true, 'plan_ot_id', p_plan_ot_id, 'ot_id', v_ot);
END;
$$;


-- ── 6. rpc_taller_asignar_responsable (+ motivo, + bitacora) ────────────────
DROP FUNCTION IF EXISTS rpc_taller_asignar_responsable(UUID, UUID, VARCHAR);
CREATE OR REPLACE FUNCTION rpc_taller_asignar_responsable(
    p_plan_ot_id     UUID,
    p_responsable_id UUID,
    p_cuadrilla      VARCHAR DEFAULT NULL,
    p_motivo         TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rol TEXT; v_plan UUID; v_conf BOOLEAN;
    v_resp_old UUID; v_cuad_old VARCHAR; v_cambia BOOLEAN;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado', v_rol;
    END IF;

    SELECT plan_semanal_id, responsable_id, cuadrilla
      INTO v_plan, v_resp_old, v_cuad_old
      FROM taller_plan_semanal_ots WHERE id = p_plan_ot_id;
    IF v_plan IS NULL THEN RAISE EXCEPTION 'Jornada % no existe', p_plan_ot_id; END IF;

    v_conf := fn_taller_plan_confirmado(v_plan);
    v_cambia := (p_responsable_id IS DISTINCT FROM v_resp_old)
             OR (p_cuadrilla IS NOT NULL AND p_cuadrilla IS DISTINCT FROM v_cuad_old);
    IF v_conf AND v_cambia AND COALESCE(TRIM(p_motivo), '') = '' THEN
        RAISE EXCEPTION 'MOTIVO_REQUERIDO: el plan esta confirmado; indica por que cambia el personal asignado.';
    END IF;

    UPDATE taller_plan_semanal_ots
       SET responsable_id = p_responsable_id,
           cuadrilla = COALESCE(p_cuadrilla, cuadrilla),
           estado_plan = CASE WHEN estado_plan = 'planificada' THEN 'asignada' ELSE estado_plan END,
           updated_at = NOW()
     WHERE id = p_plan_ot_id;

    IF p_responsable_id IS DISTINCT FROM v_resp_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_responsable', p_motivo,
            p_responsable_anterior := v_resp_old, p_responsable_nuevo := p_responsable_id);
    END IF;
    IF p_cuadrilla IS NOT NULL AND p_cuadrilla IS DISTINCT FROM v_cuad_old THEN
        PERFORM fn_taller_log_jornada_evento(
            p_plan_ot_id, 'cambio_cuadrilla', p_motivo,
            p_cuadrilla_anterior := v_cuad_old, p_cuadrilla_nueva := p_cuadrilla);
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$;


-- ── 7. Vista timeline legible ───────────────────────────────────────────────
CREATE OR REPLACE VIEW v_taller_jornada_eventos AS
SELECT
    e.id,
    e.plan_ot_id,
    e.ot_id,
    ot.folio                          AS ot_folio,
    e.plan_semanal_id,
    e.tipo,
    e.dia_anterior,
    e.dia_nuevo,
    e.responsable_anterior,
    ra.nombre_completo                AS responsable_anterior_nombre,
    e.responsable_nuevo,
    rn.nombre_completo                AS responsable_nuevo_nombre,
    e.cuadrilla_anterior,
    e.cuadrilla_nueva,
    e.campo,
    e.valor_anterior,
    e.valor_nuevo,
    e.motivo,
    e.plan_confirmado,
    e.created_by,
    up.nombre_completo                AS autor_nombre,
    e.created_at
FROM taller_plan_jornada_eventos e
LEFT JOIN ordenes_trabajo ot   ON ot.id = e.ot_id
LEFT JOIN usuarios_perfil ra   ON ra.id = e.responsable_anterior
LEFT JOIN usuarios_perfil rn   ON rn.id = e.responsable_nuevo
LEFT JOIN usuarios_perfil up   ON up.id = e.created_by;

GRANT SELECT ON v_taller_jornada_eventos TO authenticated;


-- ── GRANTs (nuevas firmas) ──────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION fn_taller_plan_confirmado(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_mover_jornada(UUID, DATE, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_editar_jornada(UUID,UUID,VARCHAR,NUMERIC,NUMERIC,TEXT,BOOLEAN,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_asignar_responsable(UUID, UUID, VARCHAR, TEXT) TO authenticated;


-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_name='taller_plan_jornada_eventos') THEN
        RAISE EXCEPTION 'STOP - no se creo taller_plan_jornada_eventos';
    END IF;
    RAISE NOTICE '== MIG173 OK == control de cambios de taller instalado';
END $$;

NOTIFY pgrst, 'reload schema';
