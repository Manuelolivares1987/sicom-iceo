-- ============================================================================
-- SICOM-ICEO | 591 — ENEX: pauta trimestral por LUGAR (Lomas Bayas Lubricantes)
-- ============================================================================
-- Manuel entregó "Pauta_Lomas_Trimestral_V02.xlsx" (2026-10-14): el avance de
-- Lomas no se mide por servicio sino por ACTIVIDAD × LUGAR. Cada Truck Shop
-- tiene 33 actividades trimestrales repartidas en 4 lugares:
--   · Housekeeping de instalaciones (1.1–1.4)
--   · TK de refrigerante y aceite residual (SM) (3.8, 3.9, 4.4–4.7)
--   · Sala de microfiltrado (2.4–2.9, 3.2, 3.3, 3.6, 3.7, 4.4–4.7)
--   · Lubricanteras / racks (5.1–5.4, 5.6–5.9, 3.2)
-- Un mismo código vive en dos lugares (4.4 en TK y en microfiltrado; 3.2 en
-- microfiltrado y en racks): la actividad es (lugar, código), no el código.
-- % avance real = ejecutadas ÷ 33 por Truck Shop; proyectado = + planificadas.
--
-- El mantenedor NO cambia de pantalla: planificar una actividad con fecha la
-- escribe como tarea del plan semanal publicado (enex_plan_tareas), que es lo
-- que /m/enex ya muestra en «Plan de hoy».
--
--   1. 5.9 «Inspección manguera carrete» entra a la pauta (trimestral).
--   2. enex_pauta_lugares / enex_pauta_lugar_items: la plantilla 33 + 33.
--   3. enex_trimestre_actividades: estado de cada actividad en el trimestre
--      (pendiente / planificada / ejecutada / reprogramada / no_aplica).
--   4. rpc_enex_trimestre_actividad_set: marcar/planificar (y llevarlo al
--      plan del mantenedor).
--   5. rpc_enex_trimestre_sincronizar: lo registrado en los informes de
--      terreno marca la actividad como ejecutada (nunca la baja).
--   6. Seed del 3°T 2026 (jul-sep) tal como está en la planilla.
-- ============================================================================

-- ── 1. Actividad 5.9 ────────────────────────────────────────────────────────
INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion, periodicidad, tipo_campo, requiere_foto, obligatorio, activo, critico)
SELECT p.id, '5. Mantención Lubricanteras', 5, 9, '5.9', 'Inspección manguera carrete', 'trimestral', 'ok_nook', false, true, true, false
  FROM enex_pautas p
 WHERE p.codigo = 'PAUTA-LUB'
   AND NOT EXISTS (SELECT 1 FROM enex_pauta_items i WHERE i.pauta_id = p.id AND i.codigo = '5.9' AND i.periodicidad = 'trimestral');

-- ── 2. Plantilla de lugares ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_pauta_lugares (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id        UUID NOT NULL REFERENCES enex_faenas(id) ON DELETE CASCADE,
    area            TEXT NOT NULL,                 -- "Truck Shop Lomas 1"
    nombre          TEXT NOT NULL,                 -- "Sala de microfiltrado"
    observacion     TEXT,
    -- Puntos donde se ejecuta en terreno (el servicio que abre el mantenedor).
    instalacion_ids UUID[] NOT NULL DEFAULT '{}',
    orden           INT NOT NULL DEFAULT 0,
    activo          BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (faena_id, area, nombre)
);

CREATE TABLE IF NOT EXISTS enex_pauta_lugar_items (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lugar_id      UUID NOT NULL REFERENCES enex_pauta_lugares(id) ON DELETE CASCADE,
    pauta_item_id UUID NOT NULL REFERENCES enex_pauta_items(id),
    orden         INT NOT NULL DEFAULT 0,
    observacion   TEXT,
    activo        BOOLEAN NOT NULL DEFAULT true,
    UNIQUE (lugar_id, pauta_item_id)
);

-- ── 3. Estado por trimestre ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_trimestre_actividades (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lugar_item_id    UUID NOT NULL REFERENCES enex_pauta_lugar_items(id) ON DELETE CASCADE,
    trimestre_inicio DATE NOT NULL,                -- primer día del trimestre
    estado           TEXT NOT NULL DEFAULT 'pendiente'
                     CHECK (estado IN ('pendiente','planificada','ejecutada','reprogramada','no_aplica')),
    fecha_plan       DATE,
    fecha_ejecucion  DATE,
    ejecucion_id     UUID REFERENCES enex_ejecuciones(id) ON DELETE SET NULL,
    comentario       TEXT,
    origen           TEXT NOT NULL DEFAULT 'manual' CHECK (origen IN ('manual','informe','planilla')),
    plan_tarea_ids   UUID[] NOT NULL DEFAULT '{}', -- tareas que ve el mantenedor
    updated_by       UUID,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (lugar_item_id, trimestre_inicio)
);
CREATE INDEX IF NOT EXISTS ix_enex_trim_act_trim ON enex_trimestre_actividades (trimestre_inicio);

ALTER TABLE enex_pauta_lugares         ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_pauta_lugar_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_trimestre_actividades ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_lugares_sel ON enex_pauta_lugares;
CREATE POLICY pol_enex_lugares_sel ON enex_pauta_lugares FOR SELECT USING (fn_user_rol() IS NOT NULL);
DROP POLICY IF EXISTS pol_enex_lugares_wr ON enex_pauta_lugares;
CREATE POLICY pol_enex_lugares_wr ON enex_pauta_lugares FOR ALL USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());
DROP POLICY IF EXISTS pol_enex_lugar_items_sel ON enex_pauta_lugar_items;
CREATE POLICY pol_enex_lugar_items_sel ON enex_pauta_lugar_items FOR SELECT USING (fn_user_rol() IS NOT NULL);
DROP POLICY IF EXISTS pol_enex_lugar_items_wr ON enex_pauta_lugar_items;
CREATE POLICY pol_enex_lugar_items_wr ON enex_pauta_lugar_items FOR ALL USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());
DROP POLICY IF EXISTS pol_enex_trim_act_sel ON enex_trimestre_actividades;
CREATE POLICY pol_enex_trim_act_sel ON enex_trimestre_actividades FOR SELECT USING (fn_user_rol() IS NOT NULL);
-- Escritura solo por RPC (mantiene el plan del mantenedor en sincronía).

-- Plantilla aplanada (lugar + actividad) para la pantalla.
CREATE OR REPLACE VIEW v_enex_pauta_lugar_items AS
SELECT li.id AS lugar_item_id, l.id AS lugar_id, l.faena_id, l.area, l.nombre AS lugar, l.observacion AS lugar_observacion,
       l.instalacion_ids, l.orden AS lugar_orden, li.orden, li.observacion,
       it.id AS pauta_item_id, it.codigo, it.descripcion, it.bloque, it.periodicidad
  FROM enex_pauta_lugar_items li
  JOIN enex_pauta_lugares l ON l.id = li.lugar_id
  JOIN enex_pauta_items it  ON it.id = li.pauta_item_id
 WHERE l.activo AND li.activo;
GRANT SELECT ON v_enex_pauta_lugar_items TO authenticated;

-- ── 4. Marcar / planificar ──────────────────────────────────────────────────
-- Planificar (o reprogramar) con fecha deja la actividad en el «Plan de hoy»
-- del mantenedor: tarea en el plan semanal publicado de esa semana, en cada
-- punto del lugar, y el servicio del mes del punto (como al publicar un plan).
CREATE OR REPLACE FUNCTION public.rpc_enex_trimestre_actividad_set(
    p_lugar_item_ids uuid[], p_trimestre_inicio date, p_estado text,
    p_fecha date DEFAULT NULL, p_comentario text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_li uuid; v_act enex_trimestre_actividades%ROWTYPE; v_l RECORD;
    v_plan uuid; v_lunes date; v_inst uuid; v_tareas uuid[]; v_tid uuid; v_prog uuid;
    v_n int := 0; v_plan_borrador boolean := false;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF p_estado NOT IN ('pendiente','planificada','ejecutada','reprogramada','no_aplica') THEN
        RAISE EXCEPTION 'Estado inválido: %', p_estado; END IF;
    IF p_estado IN ('planificada','reprogramada') AND p_fecha IS NULL THEN
        RAISE EXCEPTION 'Para planificar falta la fecha'; END IF;

    FOREACH v_li IN ARRAY p_lugar_item_ids LOOP
        SELECT * INTO v_l FROM v_enex_pauta_lugar_items WHERE lugar_item_id = v_li;
        IF NOT FOUND THEN RAISE EXCEPTION 'Actividad no encontrada'; END IF;

        INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio)
        VALUES (v_li, p_trimestre_inicio)
        ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
        SELECT * INTO v_act FROM enex_trimestre_actividades
         WHERE lugar_item_id = v_li AND trimestre_inicio = p_trimestre_inicio FOR UPDATE;

        -- Lo planificado antes y aún no hecho sale del plan del mantenedor.
        DELETE FROM enex_plan_tareas WHERE id = ANY(v_act.plan_tarea_ids) AND estado = 'pendiente';
        v_tareas := '{}';

        IF p_estado IN ('planificada','reprogramada') THEN
            v_lunes := date_trunc('week', p_fecha)::date;
            SELECT id INTO v_plan FROM enex_planes WHERE faena_id = v_l.faena_id AND semana_inicio = v_lunes;
            IF v_plan IS NULL THEN
                INSERT INTO enex_planes (faena_id, semana_inicio, semana_fin, nombre, estado, observacion, creado_por)
                VALUES (v_l.faena_id, v_lunes, v_lunes + 6, 'Semana ' || to_char(v_lunes, 'DD-MM-YYYY'),
                        'publicado', 'Creado desde la pauta trimestral', auth.uid())
                RETURNING id INTO v_plan;
            ELSIF (SELECT estado FROM enex_planes WHERE id = v_plan) = 'borrador' THEN
                v_plan_borrador := true;
            END IF;
            FOREACH v_inst IN ARRAY v_l.instalacion_ids LOOP
                INSERT INTO enex_plan_tareas (plan_id, fecha, area, instalacion_id, pauta_item_id, codigo_item, alcance, comentario, estado, orden)
                VALUES (v_plan, p_fecha, v_l.area, v_inst, v_l.pauta_item_id, v_l.codigo, v_l.lugar,
                        NULLIF(concat_ws(' · ', v_l.observacion, p_comentario), ''), 'pendiente',
                        v_l.lugar_orden * 100 + v_l.orden)
                RETURNING id INTO v_tid;
                v_tareas := v_tareas || v_tid;
                -- El servicio del mes del punto, para que el mantenedor pueda abrirlo.
                SELECT id INTO v_prog FROM enex_programaciones
                 WHERE instalacion_id = v_inst AND tipo_servicio = 'mantencion'
                   AND periodo_anio = EXTRACT(YEAR FROM p_fecha)::int AND periodo_mes = EXTRACT(MONTH FROM p_fecha)::int
                 LIMIT 1;
                IF v_prog IS NULL THEN
                    INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
                    VALUES (v_inst, 'mantencion', EXTRACT(YEAR FROM p_fecha)::int, EXTRACT(MONTH FROM p_fecha)::int,
                            p_fecha, 'Creada desde la pauta trimestral', auth.uid());
                END IF;
            END LOOP;
        ELSIF p_estado = 'ejecutada' THEN
            UPDATE enex_plan_tareas SET estado = 'hecha' WHERE id = ANY(v_act.plan_tarea_ids);
            v_tareas := (SELECT coalesce(array_agg(id), '{}') FROM enex_plan_tareas WHERE id = ANY(v_act.plan_tarea_ids));
        END IF;

        UPDATE enex_trimestre_actividades SET
            estado          = p_estado,
            fecha_plan      = CASE WHEN p_estado IN ('planificada','reprogramada') THEN p_fecha
                                   WHEN p_estado = 'pendiente' THEN NULL ELSE fecha_plan END,
            fecha_ejecucion = CASE WHEN p_estado = 'ejecutada' THEN coalesce(p_fecha, fecha_ejecucion, CURRENT_DATE)
                                   WHEN p_estado IN ('pendiente','planificada','reprogramada') THEN NULL ELSE fecha_ejecucion END,
            ejecucion_id    = CASE WHEN p_estado = 'ejecutada' THEN ejecucion_id ELSE NULL END,
            comentario      = coalesce(p_comentario, comentario),
            origen          = 'manual',
            plan_tarea_ids  = v_tareas,
            updated_by      = auth.uid(),
            updated_at      = now()
         WHERE id = v_act.id;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'actualizadas', v_n, 'plan_en_borrador', v_plan_borrador);
END $function$;
GRANT EXECUTE ON FUNCTION public.rpc_enex_trimestre_actividad_set(uuid[], date, text, date, text) TO authenticated;

-- ── 5. Lo que dicen los informes ───────────────────────────────────────────
-- Una actividad registrada en terreno (OK / NO OK / medición) dentro del
-- trimestre marca como ejecutada la actividad del lugar: primero el lugar
-- que tiene ese punto; si el código está en dos lugares del mismo punto (4.4
-- en TK y en microfiltrado), el primero aún no ejecutado. Nunca baja un
-- estado (lo marcado a mano manda).
CREATE OR REPLACE FUNCTION public.rpc_enex_trimestre_sincronizar(p_faena_id uuid, p_trimestre_inicio date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r RECORD; v_li uuid; v_n int := 0; v_fin date := (p_trimestre_inicio + interval '3 months')::date;
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sin sesión'; END IF;
    FOR r IN
        SELECT e.id AS ejecucion_id, e.fecha_ejecucion, p.instalacion_id, i.area, it.codigo
          FROM enex_ejecuciones e
          JOIN enex_programaciones p ON p.id = e.programacion_id
          JOIN enex_instalaciones i  ON i.id = p.instalacion_id
          JOIN enex_ejecucion_items x ON x.ejecucion_id = e.id
          JOIN enex_pauta_items it   ON it.id = x.pauta_item_id
         WHERE i.faena_id = p_faena_id
           AND e.estado IN ('ejecutada','cumplida')
           AND e.fecha_ejecucion >= p_trimestre_inicio AND e.fecha_ejecucion < v_fin
           AND it.periodicidad = 'trimestral'
           AND (x.valor_medicion IS NOT NULL OR (x.resultado IS NOT NULL AND x.resultado <> 'na'))
         ORDER BY e.fecha_ejecucion
    LOOP
        SELECT v.lugar_item_id INTO v_li
          FROM v_enex_pauta_lugar_items v
          LEFT JOIN enex_trimestre_actividades a ON a.lugar_item_id = v.lugar_item_id AND a.trimestre_inicio = p_trimestre_inicio
         WHERE v.faena_id = p_faena_id AND v.area = r.area AND v.codigo = r.codigo AND v.periodicidad = 'trimestral'
           AND coalesce(a.estado, 'pendiente') NOT IN ('ejecutada','no_aplica')
         ORDER BY (r.instalacion_id = ANY(v.instalacion_ids)) DESC, v.lugar_orden, v.orden
         LIMIT 1;
        CONTINUE WHEN v_li IS NULL;

        INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_ejecucion, ejecucion_id, origen, updated_at)
        VALUES (v_li, p_trimestre_inicio, 'ejecutada', r.fecha_ejecucion, r.ejecucion_id, 'informe', now())
        ON CONFLICT (lugar_item_id, trimestre_inicio) DO UPDATE
           SET estado = 'ejecutada', fecha_ejecucion = EXCLUDED.fecha_ejecucion,
               ejecucion_id = EXCLUDED.ejecucion_id, origen = 'informe', updated_at = now();
        UPDATE enex_plan_tareas SET estado = 'hecha', ejecucion_id = r.ejecucion_id
         WHERE id IN (SELECT unnest(plan_tarea_ids) FROM enex_trimestre_actividades
                       WHERE lugar_item_id = v_li AND trimestre_inicio = p_trimestre_inicio);
        v_n := v_n + 1;
    END LOOP;
    RETURN jsonb_build_object('success', true, 'marcadas', v_n);
END $function$;
GRANT EXECUTE ON FUNCTION public.rpc_enex_trimestre_sincronizar(uuid, date) TO authenticated;

-- ── 6. Seed Lomas Bayas Lubricantes (planilla V02) ──────────────────────────
DO $$
DECLARE v_f uuid; v_pauta uuid; v_l uuid; v_li uuid;
BEGIN
  SELECT id INTO v_f FROM enex_faenas WHERE codigo = 'LB_LUB';  -- OJO: dos faenas Lomas, filtrar por código
  SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB';
  IF v_f IS NULL OR v_pauta IS NULL THEN RAISE EXCEPTION 'Falta faena LB_LUB o PAUTA-LUB'; END IF;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 1', 'Housekeeping de instalaciones', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS1-MF') ORDER BY codigo), 1)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.1' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.1 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-11', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-11', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-11', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-11', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 1', 'TK de refrigerante y aceite residual (SM)', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS1-MF') ORDER BY codigo), 2)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 1', 'Sala de microfiltrado', 'No operativa', ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS1-MF') ORDER BY codigo), 3)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, '1 bomba' FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, 'Válvulas mecánicas' FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'no_aplica', '2026-08-20', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 7, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 8, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 9, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 10, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-17', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 11, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 12, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 13, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 14, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'reprogramada', '2026-09-21', NULL, '20/08 sin eléctrico: reprogramada', 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 1', 'Lubricanteras (Rack 1 y 2)', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS1-R1','LB-TS1-R2') ORDER BY codigo), 4)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.1' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.1 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 7, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 8, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-12', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 9, 'No están las condiciones' FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-22', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 2', 'Housekeeping de instalaciones', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS2-MF') ORDER BY codigo), 1)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.1' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.1 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-10', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-10', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-10', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '1.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 1.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-10', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 2', 'TK de refrigerante y aceite residual (SM)', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS2-MF') ORDER BY codigo), 2)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 2', 'Sala de microfiltrado', 'Operativa', ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS2-MF') ORDER BY codigo), 3)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-05', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-05', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-05', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-05', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '2.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 2.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 7, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 8, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 9, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 10, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-07', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 11, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 12, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.5' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.5 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 13, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 14, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '4.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 4.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'planificada', '2026-09-23', NULL, NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugares (faena_id, area, nombre, observacion, instalacion_ids, orden) VALUES (v_f, 'Truck Shop Lomas 2', 'Lubricanteras (Rack 1, 2 y 3)', NULL, ARRAY(SELECT id FROM enex_instalaciones WHERE faena_id = v_f AND codigo IN ('LB-TS2-R1','LB-TS2-R2','LB-TS2-R3') ORDER BY codigo), 4)
    ON CONFLICT (faena_id, area, nombre) DO UPDATE SET instalacion_ids = EXCLUDED.instalacion_ids, observacion = EXCLUDED.observacion, orden = EXCLUDED.orden RETURNING id INTO v_l;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 1, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.1' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.1 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 2, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.2 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 3, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.3' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.3 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 4, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.4' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.4 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 5, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.6' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.6 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 6, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.7' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.7 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 7, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.8' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.8 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 8, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '5.9' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 5.9 no está en PAUTA-LUB'; END IF;
  INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio, estado, fecha_plan, fecha_ejecucion, comentario, origen)
    VALUES (v_li, '2026-07-01', 'ejecutada', NULL, '2026-08-20', NULL, 'planilla') ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;
  v_li := NULL;
  INSERT INTO enex_pauta_lugar_items (lugar_id, pauta_item_id, orden, observacion)
    SELECT v_l, id, 9, NULL FROM enex_pauta_items WHERE pauta_id = v_pauta AND codigo = '3.2' AND periodicidad = 'trimestral' AND activo
    ON CONFLICT (lugar_id, pauta_item_id) DO UPDATE SET orden = EXCLUDED.orden, observacion = EXCLUDED.observacion RETURNING id INTO v_li;
  IF v_li IS NULL THEN RAISE EXCEPTION 'Actividad 3.2 no está en PAUTA-LUB'; END IF;
  v_li := NULL;
END $$;

-- Lo registrado en los informes de terreno se suma al abrir la pantalla
-- (rpc_enex_trimestre_sincronizar corre al cargar la pauta trimestral).
DO $$ BEGIN RAISE NOTICE 'MIG591 OK: pauta trimestral por lugar (Lomas Bayas Lubricantes, 33 + 33 actividades)'; END $$;
