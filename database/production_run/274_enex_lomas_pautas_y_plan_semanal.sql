-- ============================================================================
-- SICOM-ICEO | 274 — Lomas Bayas Lubricantes: pauta del contrato al día,
--                     puntos ordenados y PLAN SEMANAL de trabajo
-- ============================================================================
-- Pedido de Manuel (2026-08-11, el plan de esta semana ya está en ejecución):
--
--   1. PUNTOS. Lomas tenía 9 registros con duplicados y nombres inconsistentes
--      ("Truck shop 2", "TruckShop2/ Rack 2", "Truck Shop Lomas 1  - Rack 2").
--      La realidad del levantamiento: Lomas 1 = 2 racks, Lomas 2 = 3 racks, y
--      una sala de microfiltrado en cada uno → 7 puntos. Se normalizan nombres,
--      se agrupan por ÁREA (el truck shop) y se desactivan los duplicados.
--
--   2. PAUTA. El contrato lista 6 códigos una sola vez "a requerimiento", pero
--      en terreno son dos actividades distintas: inspeccionar (trimestral) y
--      cambiar/eliminar (a requerimiento). La pauta operativa aprobada por
--      Manuel las desdobla: 27 trimestrales + 18 por requerimiento + 1 anual.
--      4.2 y 4.3 (voltaje/amperaje) salen de la pauta vigente — quedan
--      inactivas, no borradas, por si el mandante las reclama.
--
--   3. PLAN SEMANAL. El trabajo NO se hace "toda la pauta de una vez": se
--      reparte por día y por área ("lunes 10, Lomas 2, ítems 1.1 a 1.4"), y a
--      veces por rack. Eso no existía en el sistema. Se agrega el plan como
--      capa de organización: no reemplaza la programación trimestral (que es
--      la que mide el KPI del contrato), le dice al técnico qué toca hoy.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_ejecuciones') THEN
        RAISE EXCEPTION 'STOP — falta MIG206/208'; END IF;
END $$;


-- ── 1. Área de la instalación ───────────────────────────────────────────────
-- El plan semanal razona por área ("LOMAS 1"), no por punto: el aseo del pretil
-- es del truck shop entero, la inspección de carretes es de un rack concreto.
ALTER TABLE enex_instalaciones
    ADD COLUMN IF NOT EXISTS area TEXT;

COMMENT ON COLUMN enex_instalaciones.area IS
    'Agrupador operativo del punto (ej. "Truck Shop Lomas 1"). Lo usa el plan semanal. MIG274.';


-- ── 2. Puntos de Lomas Bayas: nombres únicos, área y orden ──────────────────
DO $$
DECLARE
    v_faena UUID;
    v_ts1   TEXT := 'Truck Shop Lomas 1';
    v_ts2   TEXT := 'Truck Shop Lomas 2';
    v_id    UUID;
    r       TEXT[];
    -- nombre_final , codigo , area , orden , nombres_previos (separados por §)
    puntos CONSTANT TEXT[][] := ARRAY[
        ARRAY['Truck Shop Lomas 1 - Rack 1',        'LB-TS1-R1', 'Truck Shop Lomas 1', '1',
              'Truck Shop Lomas 1 - RACK 1'],
        ARRAY['Truck Shop Lomas 1 - Rack 2',        'LB-TS1-R2', 'Truck Shop Lomas 1', '2',
              'Truck Shop Lomas 1 - Rack 2'],
        ARRAY['Truck Shop Lomas 1 - Microfiltrado', 'LB-TS1-MF', 'Truck Shop Lomas 1', '3',
              'Truck Shop Lomas 1 - Microfiltrado'],
        ARRAY['Truck Shop Lomas 2 - Rack 1',        'LB-TS2-R1', 'Truck Shop Lomas 2', '4',
              'Truck Shop Lomas 2 - Rack 1'],
        ARRAY['Truck Shop Lomas 2 - Rack 2',        'LB-TS2-R2', 'Truck Shop Lomas 2', '5',
              'TruckShop2/ Rack 2'],
        ARRAY['Truck Shop Lomas 2 - Rack 3',        'LB-TS2-R3', 'Truck Shop Lomas 2', '6',
              'Truck shop 2 / Rack 3'],
        ARRAY['Truck Shop Lomas 2 - Microfiltrado', 'LB-TS2-MF', 'Truck Shop Lomas 2', '7',
              'Truck Shop Lomas 2 -  Microfiltrado']
    ];
BEGIN
    SELECT id INTO v_faena FROM enex_faenas WHERE nombre ILIKE '%lomas%' LIMIT 1;
    IF v_faena IS NULL THEN RAISE NOTICE 'MIG274: no existe la faena Lomas — se omite'; RETURN; END IF;

    FOREACH r SLICE 1 IN ARRAY puntos LOOP
        -- Busca por el nombre anterior (tolerando espacios de más) o por el final
        SELECT id INTO v_id FROM enex_instalaciones
        WHERE faena_id = v_faena
          AND (regexp_replace(lower(nombre), '\s+', ' ', 'g') = regexp_replace(lower(r[5]), '\s+', ' ', 'g')
            OR regexp_replace(lower(nombre), '\s+', ' ', 'g') = regexp_replace(lower(r[1]), '\s+', ' ', 'g'))
        ORDER BY (SELECT count(*) FROM enex_programaciones p WHERE p.instalacion_id = enex_instalaciones.id) DESC
        LIMIT 1;

        IF v_id IS NULL THEN
            INSERT INTO enex_instalaciones (faena_id, nombre, codigo, area, tipo, linea, frecuencia_meses, orden, activo)
            VALUES (v_faena, r[1], r[2], r[3], 'truck_shop', 'lubricante', 3, r[4]::int, TRUE);
            RAISE NOTICE 'MIG274: punto creado %', r[1];
        ELSE
            UPDATE enex_instalaciones
               SET nombre = r[1], codigo = r[2], area = r[3], orden = r[4]::int,
                   tipo = 'truck_shop', linea = 'lubricante', activo = TRUE
             WHERE id = v_id;
        END IF;
    END LOOP;

    -- Lo que quede fuera de los 7 puntos oficiales se desactiva (no se borra:
    -- puede tener programaciones colgando y el histórico debe seguir legible).
    UPDATE enex_instalaciones
       SET activo = FALSE
     WHERE faena_id = v_faena
       AND (codigo IS NULL OR codigo <> ALL (ARRAY['LB-TS1-R1','LB-TS1-R2','LB-TS1-MF',
                                                   'LB-TS2-R1','LB-TS2-R2','LB-TS2-R3','LB-TS2-MF']))
       AND activo;
END $$;


-- ── 3. Pauta de lubricantes al día (PAUTA-LUB) ──────────────────────────────
-- Los 6 códigos que el contrato dejaba solo "a requerimiento" se desdoblan:
-- la INSPECCIÓN es trimestral y el CAMBIO/ELIMINACIÓN queda a requerimiento.
DO $$
DECLARE
    v_pauta UUID;
    v_id    UUID;
    r       TEXT[];
    -- codigo , descripcion , periodicidad , bloque , bloque_orden , orden , tipo_campo
    items CONSTANT TEXT[][] := ARRAY[
        -- 2. Sala de microfiltrado — inspecciones trimestrales que faltaban
        ARRAY['2.8', 'Inspección de electroválvulas',      'trimestral',    '2. Sala de microfiltrado',  '2', '8',  'ok_nook'],
        ARRAY['2.9', 'Inspección de fugas',                'trimestral',    '2. Sala de microfiltrado',  '2', '9',  'ok_nook'],
        -- 5. Lubricanteras
        ARRAY['5.2', 'Inspección de fugas',                'trimestral',    '5. Mantención Lubricanteras','5', '2',  'ok_nook'],
        ARRAY['5.6', 'Inspección estado Test Point',       'trimestral',    '5. Mantención Lubricanteras','5', '6',  'ok_nook'],
        ARRAY['5.7', 'Inspección estado de carretes',      'trimestral',    '5. Mantención Lubricanteras','5', '7',  'ok_nook'],
        ARRAY['5.8', 'Inspección estado de pistolas',      'trimestral',    '5. Mantención Lubricanteras','5', '8',  'ok_nook'],
        -- ... y sus pares por requerimiento (renombrados para no confundirse)
        ARRAY['2.8', 'Cambio de electroválvulas',          'requerimiento', '2. Sala de microfiltrado',  '2', '18', 'ok_nook'],
        ARRAY['2.9', 'Eliminación de fugas',               'requerimiento', '2. Sala de microfiltrado',  '2', '19', 'ok_nook'],
        ARRAY['5.2', 'Eliminación de fugas',               'requerimiento', '5. Mantención Lubricanteras','5', '12', 'ok_nook'],
        ARRAY['5.5', 'Limpieza de lubricanteras',          'requerimiento', '5. Mantención Lubricanteras','5', '15', 'ok_nook'],
        ARRAY['5.6', 'Cambio de Test Point',               'requerimiento', '5. Mantención Lubricanteras','5', '16', 'ok_nook'],
        ARRAY['5.7', 'Cambio de carretes',                 'requerimiento', '5. Mantención Lubricanteras','5', '17', 'ok_nook'],
        ARRAY['5.8', 'Cambio de pistolas',                 'requerimiento', '5. Mantención Lubricanteras','5', '18', 'ok_nook']
    ];
BEGIN
    SELECT id INTO v_pauta FROM enex_pautas WHERE codigo = 'PAUTA-LUB' AND activo LIMIT 1;
    IF v_pauta IS NULL THEN RAISE NOTICE 'MIG274: no existe PAUTA-LUB — se omite'; RETURN; END IF;

    FOREACH r SLICE 1 IN ARRAY items LOOP
        -- Cada (código, periodicidad) es una actividad distinta.
        SELECT id INTO v_id FROM enex_pauta_items
         WHERE pauta_id = v_pauta AND codigo = r[1] AND periodicidad = r[3] LIMIT 1;

        IF v_id IS NULL THEN
            INSERT INTO enex_pauta_items (pauta_id, bloque, bloque_orden, orden, codigo, descripcion,
                                          periodicidad, tipo_campo, obligatorio, activo)
            VALUES (v_pauta, r[4], r[5]::int, r[6]::int, r[1], r[2], r[3], r[7], TRUE, TRUE);
        ELSE
            UPDATE enex_pauta_items
               SET descripcion = r[2], bloque = r[4], bloque_orden = r[5]::int, orden = r[6]::int,
                   tipo_campo = r[7], activo = TRUE
             WHERE id = v_id;
        END IF;
    END LOOP;

    -- 4.2 y 4.3 no están en la pauta operativa vigente. Se desactivan; el
    -- histórico que ya las tenga marcadas se conserva intacto.
    UPDATE enex_pauta_items SET activo = FALSE
     WHERE pauta_id = v_pauta AND codigo IN ('4.2', '4.3') AND activo;

    -- 2.7 es recobrable por contrato (**): que quede dicho en la propia pauta.
    UPDATE enex_pauta_items
       SET descripcion = 'Mantención calefactores (costo recobrable)'
     WHERE pauta_id = v_pauta AND codigo = '2.7' AND descripcion NOT ILIKE '%recobrable%';
END $$;


-- ── 4. Plan semanal de trabajo ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_planes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_id      UUID NOT NULL REFERENCES enex_faenas(id) ON DELETE CASCADE,
    semana_inicio DATE NOT NULL,                       -- lunes de la semana
    semana_fin    DATE NOT NULL,
    nombre        TEXT,
    estado        TEXT NOT NULL DEFAULT 'borrador'
                  CHECK (estado IN ('borrador','publicado','cerrado')),
    observacion   TEXT,
    creado_por    UUID REFERENCES usuarios_perfil(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Una sola versión viva del plan por faena y semana: reimportar el Excel
-- corrige el plan, no crea uno paralelo que nadie sabe cuál es.
CREATE UNIQUE INDEX IF NOT EXISTS ux_enex_planes_faena_semana
    ON enex_planes (faena_id, semana_inicio);

CREATE TABLE IF NOT EXISTS enex_plan_tareas (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id        UUID NOT NULL REFERENCES enex_planes(id) ON DELETE CASCADE,
    fecha          DATE NOT NULL,
    area           TEXT,                               -- "Truck Shop Lomas 1"
    instalacion_id UUID REFERENCES enex_instalaciones(id) ON DELETE SET NULL,
    pauta_item_id  UUID REFERENCES enex_pauta_items(id) ON DELETE SET NULL,
    codigo_item    TEXT,                               -- lo que decía el Excel ("1.1")
    alcance        TEXT,                               -- "Rack 1 / Rack 2"
    comentario     TEXT,
    estado         TEXT NOT NULL DEFAULT 'pendiente'
                   CHECK (estado IN ('pendiente','en_proceso','hecha','no_realizada')),
    ejecucion_id   UUID REFERENCES enex_ejecuciones(id) ON DELETE SET NULL,
    orden          INT NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_enex_plan_tareas_plan  ON enex_plan_tareas (plan_id);
CREATE INDEX IF NOT EXISTS ix_enex_plan_tareas_fecha ON enex_plan_tareas (fecha);
CREATE INDEX IF NOT EXISTS ix_enex_plan_tareas_inst  ON enex_plan_tareas (instalacion_id);

COMMENT ON TABLE enex_planes IS
    'Plan semanal de trabajo ENEX por faena. Organiza qué se hace cada día; el KPI del contrato lo sigue midiendo enex_programaciones. MIG274.';
COMMENT ON TABLE enex_plan_tareas IS
    'Una actividad de la pauta asignada a un día y a un área/punto. MIG274.';

-- updated_at
CREATE OR REPLACE FUNCTION fn_enex_plan_touch() RETURNS TRIGGER
LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS tg_enex_planes_touch ON enex_planes;
CREATE TRIGGER tg_enex_planes_touch BEFORE UPDATE ON enex_planes
    FOR EACH ROW EXECUTE FUNCTION fn_enex_plan_touch();
DROP TRIGGER IF EXISTS tg_enex_plan_tareas_touch ON enex_plan_tareas;
CREATE TRIGGER tg_enex_plan_tareas_touch BEFORE UPDATE ON enex_plan_tareas
    FOR EACH ROW EXECUTE FUNCTION fn_enex_plan_touch();


-- ── 5. RLS: lo ve todo usuario con rol; lo edita quien gestiona ENEX ────────
ALTER TABLE enex_planes      ENABLE ROW LEVEL SECURITY;
ALTER TABLE enex_plan_tareas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_enex_planes_sel ON enex_planes;
CREATE POLICY pol_enex_planes_sel ON enex_planes FOR SELECT USING (fn_user_rol() IS NOT NULL);
DROP POLICY IF EXISTS pol_enex_planes_wr ON enex_planes;
CREATE POLICY pol_enex_planes_wr ON enex_planes FOR ALL
    USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());

DROP POLICY IF EXISTS pol_enex_plan_tareas_sel ON enex_plan_tareas;
CREATE POLICY pol_enex_plan_tareas_sel ON enex_plan_tareas FOR SELECT USING (fn_user_rol() IS NOT NULL);
DROP POLICY IF EXISTS pol_enex_plan_tareas_wr ON enex_plan_tareas;
CREATE POLICY pol_enex_plan_tareas_wr ON enex_plan_tareas FOR ALL
    USING (fn_enex_puede_gestionar()) WITH CHECK (fn_enex_puede_gestionar());

GRANT SELECT ON enex_planes, enex_plan_tareas TO authenticated;


-- ── 6. Vista del plan (con todo resuelto para la pantalla y el teléfono) ────
CREATE OR REPLACE VIEW v_enex_plan_tareas AS
SELECT t.id,
       t.plan_id,
       pl.faena_id,
       f.nombre        AS faena,
       pl.semana_inicio,
       pl.semana_fin,
       pl.estado       AS plan_estado,
       t.fecha,
       t.area,
       t.instalacion_id,
       i.nombre        AS instalacion,
       i.codigo        AS instalacion_codigo,
       t.pauta_item_id,
       COALESCE(t.codigo_item, it.codigo)  AS codigo_item,
       it.descripcion  AS actividad,
       it.bloque,
       it.bloque_orden,
       it.periodicidad,
       it.tipo_campo,
       t.alcance,
       t.comentario,
       t.estado,
       t.ejecucion_id,
       t.orden
  FROM enex_plan_tareas t
  JOIN enex_planes pl        ON pl.id = t.plan_id
  JOIN enex_faenas f         ON f.id = pl.faena_id
  LEFT JOIN enex_instalaciones i ON i.id = t.instalacion_id
  LEFT JOIN enex_pauta_items it  ON it.id = t.pauta_item_id;

GRANT SELECT ON v_enex_plan_tareas TO authenticated;


-- ── 7. RPCs ─────────────────────────────────────────────────────────────────

-- Crea o reusa el plan de una semana. La semana se ancla al lunes.
CREATE OR REPLACE FUNCTION rpc_enex_plan_guardar(
    p_faena_id UUID,
    p_semana   DATE,                       -- cualquier día de la semana
    p_nombre   TEXT DEFAULT NULL,
    p_observacion TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_lunes DATE := p_semana - ((EXTRACT(ISODOW FROM p_semana)::int - 1));
    v_id    UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;

    INSERT INTO enex_planes (faena_id, semana_inicio, semana_fin, nombre, observacion, creado_por)
    VALUES (p_faena_id, v_lunes, v_lunes + 6, p_nombre, p_observacion, auth.uid())
    ON CONFLICT (faena_id, semana_inicio) DO UPDATE
        SET nombre      = COALESCE(EXCLUDED.nombre, enex_planes.nombre),
            observacion = COALESCE(EXCLUDED.observacion, enex_planes.observacion)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'plan_id', v_id,
                              'semana_inicio', v_lunes, 'semana_fin', v_lunes + 6);
END $$;

-- Carga masiva de tareas (lo que sale del Excel del planificador).
-- p_tareas: [{fecha, area, instalacion_id, codigo_item, alcance, comentario}]
-- p_reemplazar = true borra las tareas pendientes del plan antes de cargar: al
-- reimportar el Excel corregido no quedan las viejas mezcladas. Nunca borra
-- tareas ya trabajadas.
CREATE OR REPLACE FUNCTION rpc_enex_plan_importar(
    p_plan_id    UUID,
    p_tareas     JSONB,
    p_reemplazar BOOLEAN DEFAULT TRUE
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_faena   UUID;
    v_pauta   UUID;
    t         JSONB;
    v_item    UUID;
    v_inst    UUID;
    v_n       INT := 0;
    v_sin     INT := 0;
    v_orden   INT := 0;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;

    SELECT faena_id INTO v_faena FROM enex_planes WHERE id = p_plan_id;
    IF v_faena IS NULL THEN RAISE EXCEPTION 'Plan no encontrado'; END IF;

    IF p_reemplazar THEN
        DELETE FROM enex_plan_tareas
         WHERE plan_id = p_plan_id AND estado = 'pendiente' AND ejecucion_id IS NULL;
    END IF;

    FOR t IN SELECT * FROM jsonb_array_elements(p_tareas) LOOP
        v_orden := v_orden + 1;
        v_inst := NULLIF(t->>'instalacion_id', '')::UUID;

        -- Pauta de la instalación, o la de lubricantes de la faena si la tarea
        -- es de área (sin punto asignado todavía).
        SELECT COALESCE(i.pauta_mantencion_id,
                        (SELECT p.id FROM enex_pautas p
                          WHERE p.activo AND p.tipo_servicio = 'mantencion'
                            AND p.linea = i.linea AND i.tipo = ANY(p.aplica_tipos)
                          ORDER BY p.version DESC LIMIT 1))
          INTO v_pauta
          FROM enex_instalaciones i WHERE i.id = v_inst;

        IF v_pauta IS NULL THEN
            SELECT id INTO v_pauta FROM enex_pautas
             WHERE activo AND codigo = 'PAUTA-LUB' ORDER BY version DESC LIMIT 1;
        END IF;

        -- El Excel trae el código ("1.1"). El plan semanal es del servicio
        -- trimestral, así que ante un código repetido gana el trimestral.
        v_item := NULL;
        IF NULLIF(t->>'codigo_item', '') IS NOT NULL AND v_pauta IS NOT NULL THEN
            SELECT id INTO v_item FROM enex_pauta_items
             WHERE pauta_id = v_pauta AND activo
               AND lower(codigo) = lower(trim(t->>'codigo_item'))
             ORDER BY (periodicidad = 'trimestral') DESC, orden
             LIMIT 1;
        END IF;
        IF v_item IS NULL THEN v_sin := v_sin + 1; END IF;

        INSERT INTO enex_plan_tareas (plan_id, fecha, area, instalacion_id, pauta_item_id,
                                      codigo_item, alcance, comentario, orden)
        VALUES (p_plan_id, (t->>'fecha')::DATE, NULLIF(t->>'area',''), v_inst, v_item,
                NULLIF(t->>'codigo_item',''), NULLIF(t->>'alcance',''), NULLIF(t->>'comentario',''),
                v_orden);
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'tareas', v_n, 'sin_actividad', v_sin);
END $$;

-- Alta/edición puntual de una tarea desde la pantalla.
CREATE OR REPLACE FUNCTION rpc_enex_plan_tarea_guardar(
    p_id             UUID,
    p_plan_id        UUID,
    p_fecha          DATE,
    p_area           TEXT DEFAULT NULL,
    p_instalacion_id UUID DEFAULT NULL,
    p_pauta_item_id  UUID DEFAULT NULL,
    p_alcance        TEXT DEFAULT NULL,
    p_comentario     TEXT DEFAULT NULL,
    p_estado         TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;

    IF p_id IS NULL THEN
        INSERT INTO enex_plan_tareas (plan_id, fecha, area, instalacion_id, pauta_item_id,
                                      codigo_item, alcance, comentario,
                                      estado, orden)
        VALUES (p_plan_id, p_fecha, p_area, p_instalacion_id, p_pauta_item_id,
                (SELECT codigo FROM enex_pauta_items WHERE id = p_pauta_item_id),
                p_alcance, p_comentario, COALESCE(p_estado, 'pendiente'),
                COALESCE((SELECT max(orden) + 1 FROM enex_plan_tareas WHERE plan_id = p_plan_id), 1))
        RETURNING id INTO v_id;
    ELSE
        UPDATE enex_plan_tareas
           SET fecha = p_fecha, area = p_area, instalacion_id = p_instalacion_id,
               pauta_item_id = COALESCE(p_pauta_item_id, pauta_item_id),
               codigo_item = COALESCE((SELECT codigo FROM enex_pauta_items WHERE id = p_pauta_item_id), codigo_item),
               alcance = p_alcance, comentario = p_comentario,
               estado = COALESCE(p_estado, estado)
         WHERE id = p_id
        RETURNING id INTO v_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'tarea_id', v_id);
END $$;

CREATE OR REPLACE FUNCTION rpc_enex_plan_tarea_eliminar(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;
    DELETE FROM enex_plan_tareas WHERE id = p_id AND ejecucion_id IS NULL;
    RETURN jsonb_build_object('success', true);
END $$;

-- Publicar / cerrar el plan. Publicar es lo que lo hace visible en terreno.
CREATE OR REPLACE FUNCTION rpc_enex_plan_estado(p_plan_id UUID, p_estado TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permisos para planificar ENEX'; END IF;
    IF p_estado NOT IN ('borrador','publicado','cerrado') THEN RAISE EXCEPTION 'Estado inválido'; END IF;
    UPDATE enex_planes SET estado = p_estado WHERE id = p_plan_id;
    RETURN jsonb_build_object('success', true, 'estado', p_estado);
END $$;

-- El técnico marca su avance desde el teléfono (no requiere ser planificador).
CREATE OR REPLACE FUNCTION rpc_enex_plan_tarea_avance(
    p_id UUID, p_estado TEXT, p_ejecucion_id UUID DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sesión requerida'; END IF;
    IF p_estado NOT IN ('pendiente','en_proceso','hecha','no_realizada') THEN
        RAISE EXCEPTION 'Estado inválido'; END IF;
    UPDATE enex_plan_tareas
       SET estado = p_estado,
           ejecucion_id = COALESCE(p_ejecucion_id, ejecucion_id)
     WHERE id = p_id;
    RETURN jsonb_build_object('success', true);
END $$;

GRANT EXECUTE ON FUNCTION rpc_enex_plan_guardar(UUID, DATE, TEXT, TEXT)                     TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_plan_importar(UUID, JSONB, BOOLEAN)                      TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_plan_tarea_guardar(UUID, UUID, DATE, TEXT, UUID, UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_plan_tarea_eliminar(UUID)                                TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_plan_estado(UUID, TEXT)                                  TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_plan_tarea_avance(UUID, TEXT, UUID)                      TO authenticated;


-- ── 8. Validación ───────────────────────────────────────────────────────────
DO $$
DECLARE v_pts INT; v_tri INT; v_req INT;
BEGIN
    SELECT count(*) INTO v_pts FROM enex_instalaciones i
      JOIN enex_faenas f ON f.id = i.faena_id
     WHERE f.nombre ILIKE '%lomas%' AND i.activo;
    SELECT count(*) INTO v_tri FROM enex_pauta_items it
      JOIN enex_pautas p ON p.id = it.pauta_id
     WHERE p.codigo = 'PAUTA-LUB' AND it.activo AND it.periodicidad = 'trimestral'
       AND it.codigo ~ '^[0-9]';
    SELECT count(*) INTO v_req FROM enex_pauta_items it
      JOIN enex_pautas p ON p.id = it.pauta_id
     WHERE p.codigo = 'PAUTA-LUB' AND it.activo AND it.periodicidad = 'requerimiento';
    RAISE NOTICE 'MIG274 · puntos Lomas activos=% · pauta trimestral=% · requerimiento=%', v_pts, v_tri, v_req;
END $$;

SELECT 'MIG274 OK' AS resultado,
       (SELECT count(*) FROM enex_instalaciones i JOIN enex_faenas f ON f.id=i.faena_id
         WHERE f.nombre ILIKE '%lomas%' AND i.activo) AS puntos_lomas,
       (SELECT count(*) FROM enex_pauta_items it JOIN enex_pautas p ON p.id=it.pauta_id
         WHERE p.codigo='PAUTA-LUB' AND it.activo) AS items_pauta;
