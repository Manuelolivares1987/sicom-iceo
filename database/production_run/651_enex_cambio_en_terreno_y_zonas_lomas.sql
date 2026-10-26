-- 651 — ENEX: cambio de programa en terreno, camión «por asignar» y zonas de
-- Lomas Lubricantes (2026-10-26).
--
-- Lo que pasó: el 26-10 la cuadrilla llegó a Lomas Combustibles con la EESS
-- programada y ESM pidió calibrar camiones. El teléfono solo mostraba lo
-- programado: no había cómo dejar constancia ni registrar los camiones. Y la
-- patente no se sabe al planificar: la operación entrega el camión que tiene
-- disponible en el momento. Vale para TODAS las faenas de combustible.
--
--   1. Camión «por asignar» (es_comodin) por faena de combustible con camiones.
--      Centinela ya usaba uno de hecho («CAMIONES», 22 programaciones sin
--      patente): se formaliza. Se planifica «N camiones» contra él y la
--      patente la pone el supervisor en terreno.
--   2. rpc_enex_terreno_camion: el supervisor anota la patente. La programación
--      pasa al camión real; si la patente no está en el maestro de la faena, se
--      crea (creada_en_terreno, para avisarle al planificador). Si la
--      programación no existe (cambio de programa: calibración que no estaba
--      planificada), la crea con el id que generó el teléfono —idempotente,
--      porque viaja desde la cola sin señal—.
--   3. rpc_enex_por_reprogramar: «no se hizo, pedido de ESM». Queda marcada con
--      el motivo hasta que el planificador le pone fecha nueva (mover o
--      reprogramar limpia la marca). Sigue contando como programada: el KPI no
--      se maquilla.
--   4. Lomas Lubricantes en 3 zonas por Truck Shop, como la planilla «Pauta
--      Lomas Bayas Lubricantes»: Instalaciones exteriores (housekeeping + TK +
--      eléctrica) · Sala de microfiltrado · Racks. Antes eran 4 (housekeeping y
--      TK separados); se unen moviendo las actividades, sin tocar lo del 3°T.

-- ── 1. Camión por asignar ────────────────────────────────────────────────────
ALTER TABLE enex_instalaciones ADD COLUMN IF NOT EXISTS es_comodin BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE enex_instalaciones ADD COLUMN IF NOT EXISTS creada_en_terreno BOOLEAN NOT NULL DEFAULT false;

UPDATE enex_instalaciones i SET es_comodin = true, nombre = 'Camión por asignar'
  FROM enex_faenas f
 WHERE f.id = i.faena_id AND f.codigo = 'CENTINELA' AND i.tipo = 'camion' AND i.patente IS NULL AND i.nombre = 'CAMIONES';

INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, activo, orden, es_comodin)
SELECT f.id, 'CAM-POR-ASIGNAR', 'Camión por asignar', 'camion', 'combustible', true, 999, true
  FROM enex_faenas f
 WHERE f.activo AND 'combustible' = ANY(f.lineas)
   AND EXISTS (SELECT 1 FROM enex_instalaciones c WHERE c.faena_id = f.id AND c.tipo = 'camion' AND c.activo)
   AND NOT EXISTS (SELECT 1 FROM enex_instalaciones c WHERE c.faena_id = f.id AND c.es_comodin);

CREATE UNIQUE INDEX IF NOT EXISTS ux_enex_inst_comodin ON enex_instalaciones (faena_id) WHERE es_comodin;

-- ── 2. Marcas en la programación ─────────────────────────────────────────────
ALTER TABLE enex_programaciones ADD COLUMN IF NOT EXISTS origen TEXT NOT NULL DEFAULT 'plan';
DO $$ BEGIN
    ALTER TABLE enex_programaciones ADD CONSTRAINT enex_programaciones_origen_chk CHECK (origen IN ('plan','terreno'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
ALTER TABLE enex_programaciones ADD COLUMN IF NOT EXISTS por_reprogramar_at TIMESTAMPTZ;
ALTER TABLE enex_programaciones ADD COLUMN IF NOT EXISTS por_reprogramar_motivo TEXT;
ALTER TABLE enex_programaciones ADD COLUMN IF NOT EXISTS por_reprogramar_por UUID;

-- Ponerle fecha nueva (mover o reprogramar) resuelve el «por reprogramar».
CREATE OR REPLACE FUNCTION fn_enex_prog_limpia_por_reprogramar()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.fecha_programada IS DISTINCT FROM OLD.fecha_programada THEN
        NEW.por_reprogramar_at := NULL;
        NEW.por_reprogramar_motivo := NULL;
        NEW.por_reprogramar_por := NULL;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_enex_prog_limpia_por_reprogramar ON enex_programaciones;
CREATE TRIGGER trg_enex_prog_limpia_por_reprogramar
    BEFORE UPDATE OF fecha_programada ON enex_programaciones
    FOR EACH ROW EXECUTE FUNCTION fn_enex_prog_limpia_por_reprogramar();

-- Patente comparable: sin espacios, guiones ni puntos, en mayúscula.
CREATE OR REPLACE FUNCTION fn_enex_patente_norm(p TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT NULLIF(regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g'), '');
$$;

-- ── 3. Patente en terreno (y calibración no planificada) ──────────────────────
CREATE OR REPLACE FUNCTION public.rpc_enex_terreno_camion(
    p_programacion_id uuid, p_patente text,
    p_faena_id uuid DEFAULT NULL, p_fecha date DEFAULT NULL, p_motivo text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_pat text := fn_enex_patente_norm(p_patente);
    v_prog enex_programaciones%ROWTYPE; v_inst enex_instalaciones%ROWTYPE;
    v_faena uuid; v_comodin uuid; v_cam uuid; v_creada boolean := false;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF v_pat IS NULL OR length(v_pat) NOT BETWEEN 4 AND 8 THEN
        RAISE EXCEPTION 'Patente inválida: %', coalesce(p_patente, '(vacía)'); END IF;

    SELECT * INTO v_prog FROM enex_programaciones WHERE id = p_programacion_id FOR UPDATE;
    IF FOUND THEN
        SELECT * INTO v_inst FROM enex_instalaciones WHERE id = v_prog.instalacion_id;
        IF v_inst.tipo <> 'camion' THEN RAISE EXCEPTION 'Este servicio no es de un camión'; END IF;
        v_faena := v_inst.faena_id;
        IF EXISTS (SELECT 1 FROM enex_ejecuciones e WHERE e.programacion_id = p_programacion_id AND e.firma_mandante_url IS NOT NULL)
           AND fn_enex_patente_norm(v_inst.patente) IS DISTINCT FROM v_pat THEN
            RAISE EXCEPTION 'El servicio ya tiene la firma del mandante: la patente no se puede cambiar';
        END IF;
    ELSE
        -- Cambio de programa en terreno: calibración que no estaba planificada.
        IF p_faena_id IS NULL OR p_fecha IS NULL THEN RAISE EXCEPTION 'Falta la faena o la fecha'; END IF;
        v_faena := p_faena_id;
        SELECT id INTO v_comodin FROM enex_instalaciones WHERE faena_id = v_faena AND es_comodin;
        IF v_comodin IS NULL THEN
            INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, activo, orden, es_comodin)
            VALUES (v_faena, 'CAM-POR-ASIGNAR', 'Camión por asignar', 'camion', 'combustible', true, 999, true)
            RETURNING id INTO v_comodin;
        END IF;
        INSERT INTO enex_programaciones (id, instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por, origen)
        VALUES (p_programacion_id, v_comodin, 'calibracion', EXTRACT(YEAR FROM p_fecha)::int, EXTRACT(MONTH FROM p_fecha)::int,
                p_fecha, coalesce(NULLIF(btrim(p_motivo), ''), 'Calibración en terreno (cambio de programa)'), auth.uid(), 'terreno');
    END IF;

    SELECT id INTO v_cam FROM enex_instalaciones
     WHERE faena_id = v_faena AND tipo = 'camion' AND NOT es_comodin AND fn_enex_patente_norm(patente) = v_pat
     ORDER BY activo DESC LIMIT 1;
    IF v_cam IS NULL THEN
        INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, patente, activo, orden, creada_en_terreno)
        VALUES (v_faena, v_pat, 'Aljibe ' || v_pat, 'camion', 'combustible', v_pat, true, 500, true)
        RETURNING id INTO v_cam;
        v_creada := true;
    ELSE
        UPDATE enex_instalaciones SET activo = true WHERE id = v_cam AND NOT activo;
    END IF;

    UPDATE enex_programaciones SET instalacion_id = v_cam WHERE id = p_programacion_id;
    RETURN jsonb_build_object('success', true, 'programacion_id', p_programacion_id, 'instalacion_id', v_cam,
                              'patente', v_pat, 'camion_nuevo', v_creada);
END $function$;
REVOKE ALL ON FUNCTION public.rpc_enex_terreno_camion(uuid, text, uuid, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_terreno_camion(uuid, text, uuid, date, text) TO authenticated;

-- ── 4. «No se hizo: pedido de ESM» ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_enex_por_reprogramar(
    p_programacion_id uuid, p_motivo text, p_deshacer boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF NOT coalesce(p_deshacer, false) AND NULLIF(btrim(p_motivo), '') IS NULL THEN
        RAISE EXCEPTION 'Falta el motivo'; END IF;
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = p_programacion_id) AND NOT coalesce(p_deshacer, false) THEN
        RAISE EXCEPTION 'Este servicio ya tiene trabajo registrado: no se puede dejar por reprogramar';
    END IF;
    UPDATE enex_programaciones SET
        por_reprogramar_at     = CASE WHEN p_deshacer THEN NULL ELSE coalesce(por_reprogramar_at, now()) END,
        por_reprogramar_motivo = CASE WHEN p_deshacer THEN NULL ELSE btrim(p_motivo) END,
        por_reprogramar_por    = CASE WHEN p_deshacer THEN NULL ELSE auth.uid() END
     WHERE id = p_programacion_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Programación no encontrada'; END IF;
    RETURN jsonb_build_object('success', true);
END $function$;
REVOKE ALL ON FUNCTION public.rpc_enex_por_reprogramar(uuid, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_por_reprogramar(uuid, text, boolean) TO authenticated;

-- ── 5. Vistas: las marcas nuevas al final (CREATE OR REPLACE no admite otro orden)
CREATE OR REPLACE VIEW v_enex_terreno_pendientes AS
 SELECT pr.id AS programacion_id,
    pr.periodo_anio,
    pr.periodo_mes,
    pr.tipo_servicio,
    pr.fecha_programada,
    i.id AS instalacion_id,
    i.nombre AS instalacion,
    i.tipo AS instalacion_tipo,
    i.patente,
    i.linea,
    f.id AS faena_id,
    f.codigo AS faena_codigo,
    f.nombre AS faena,
    fn_enex_pauta_de_programacion(pr.id) AS pauta_id,
    ( SELECT p.nombre FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_nombre,
    ( SELECT p.es_borrador FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_borrador,
    ( SELECT count(*) AS count FROM enex_pauta_items it
       WHERE it.pauta_id = fn_enex_pauta_de_programacion(pr.id) AND it.activo) AS pauta_items,
    e.id AS ejecucion_id,
    e.estado,
    e.firma_mandante_url,
    e.firma_mandante_url IS NOT NULL AS cumplida,
    (EXISTS ( SELECT 1
           FROM enex_ejecuciones e2
             JOIN enex_programaciones p2 ON p2.id = e2.programacion_id
          WHERE p2.instalacion_id = pr.instalacion_id AND p2.tipo_servicio = pr.tipo_servicio AND p2.id <> pr.id
            AND (e2.estado = ANY (ARRAY['ejecutada'::text, 'cumplida'::text])) AND e2.fecha_ejecucion IS NOT NULL
            AND fn_enex_trimestre_key(e2.fecha_ejecucion) = fn_enex_trimestre_key(COALESCE(pr.fecha_programada, make_date(pr.periodo_anio, pr.periodo_mes, 15)))
            AND NOT i.es_comodin)) AS es_recobro,
    i.es_comodin,
    pr.origen,
    pr.por_reprogramar_at,
    pr.por_reprogramar_motivo
   FROM enex_programaciones pr
     JOIN enex_instalaciones i ON i.id = pr.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = pr.id;

CREATE OR REPLACE VIEW v_enex_panel_mensual AS
 SELECT p.id AS programacion_id,
    p.periodo_anio,
    p.periodo_mes,
    p.tipo_servicio,
    p.fecha_programada,
    p.observacion AS prog_observacion,
    i.id AS instalacion_id,
    i.nombre AS instalacion,
    i.tipo AS instalacion_tipo,
    i.codigo AS instalacion_codigo,
    i.linea,
    i.patente,
    f.id AS faena_id,
    f.codigo AS faena_codigo,
    f.nombre AS faena,
    e.id AS ejecucion_id,
    e.estado,
    e.fecha_ejecucion,
    e.ot_numero,
    e.ejecutor,
    e.observacion AS ejec_observacion,
    e.evidencia_urls,
    e.firma_mandante_url,
    e.firmante_mandante_nombre,
    e.firmante_mandante_at,
    e.firma_mandante_url IS NOT NULL AS cumplida,
    e.informe_pdf_url,
    e.firma_tecnico_url IS NOT NULL AS firma_tecnico_lista,
    e.tecnico_nombre,
    i.es_comodin,
    i.creada_en_terreno,
    p.origen,
    p.por_reprogramar_at,
    p.por_reprogramar_motivo
   FROM enex_programaciones p
     JOIN enex_instalaciones i ON i.id = p.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id;

-- ── 5b. Programar «N camiones por asignar» ───────────────────────────────────
-- Igual que MIG590, más `cantidad` para el camión por asignar: es el TOTAL que
-- se quiere ese día (crea solo lo que falta), así reimportar la planilla
-- («CP2») no duplica. Para el resto sigue sin duplicar instalación+servicio+día.
CREATE OR REPLACE FUNCTION public.rpc_enex_programar_lote(p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_it jsonb; v_fecha date; v_inst uuid; v_tipo text; v_cant int; v_ya int;
    v_creadas int := 0; v_omitidas int := 0;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF jsonb_typeof(p_items) <> 'array' THEN RAISE EXCEPTION 'p_items debe ser un arreglo'; END IF;

    FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_inst  := (v_it->>'instalacion_id')::uuid;
        v_tipo  := v_it->>'tipo_servicio';
        v_fecha := (v_it->>'fecha')::date;
        IF v_tipo NOT IN ('mantencion','calibracion') OR v_fecha IS NULL OR v_inst IS NULL THEN
            RAISE EXCEPTION 'Ítem inválido: %', v_it;
        END IF;
        v_cant := CASE WHEN (SELECT es_comodin FROM enex_instalaciones WHERE id = v_inst)
                       THEN greatest(coalesce((v_it->>'cantidad')::int, 1), 1) ELSE 1 END;
        SELECT count(*) INTO v_ya FROM enex_programaciones
         WHERE instalacion_id = v_inst AND tipo_servicio = v_tipo AND fecha_programada = v_fecha;
        IF v_ya >= v_cant THEN
            v_omitidas := v_omitidas + 1;
            CONTINUE;
        END IF;
        FOR i IN 1 .. (v_cant - v_ya) LOOP
            INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por)
            VALUES (v_inst, v_tipo, EXTRACT(YEAR FROM v_fecha)::int, EXTRACT(MONTH FROM v_fecha)::int, v_fecha,
                    NULLIF(v_it->>'observacion',''), auth.uid());
            v_creadas := v_creadas + 1;
        END LOOP;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'creadas', v_creadas, 'omitidas', v_omitidas);
END $function$;
GRANT EXECUTE ON FUNCTION public.rpc_enex_programar_lote(jsonb) TO authenticated;

-- ── 6. Lomas Lubricantes: 3 zonas por Truck Shop ──────────────────────────────
DO $$
DECLARE r RECORD; v_hk uuid; v_tk uuid;
BEGIN
    FOR r IN SELECT DISTINCT l.area, l.faena_id FROM enex_pauta_lugares l
               JOIN enex_faenas f ON f.id = l.faena_id WHERE f.codigo = 'LB_LUB' LOOP
        SELECT id INTO v_hk FROM enex_pauta_lugares
         WHERE faena_id = r.faena_id AND area = r.area AND nombre = 'Housekeeping de instalaciones';
        SELECT id INTO v_tk FROM enex_pauta_lugares
         WHERE faena_id = r.faena_id AND area = r.area AND nombre = 'TK de refrigerante y aceite residual (SM)';
        IF v_hk IS NULL OR v_tk IS NULL THEN CONTINUE; END IF;  -- ya aplicada
        UPDATE enex_pauta_lugar_items SET lugar_id = v_hk, orden = orden + 10 WHERE lugar_id = v_tk;
        UPDATE enex_pauta_lugares SET activo = false, nombre = nombre || ' (unida a Instalaciones exteriores)' WHERE id = v_tk;
        UPDATE enex_pauta_lugares SET nombre = 'Instalaciones exteriores', orden = 1 WHERE id = v_hk;
        UPDATE enex_pauta_lugares SET orden = 2 WHERE faena_id = r.faena_id AND area = r.area AND nombre = 'Sala de microfiltrado';
        UPDATE enex_pauta_lugares SET orden = 3 WHERE faena_id = r.faena_id AND area = r.area AND nombre LIKE 'Lubricanteras%';
    END LOOP;
END $$;

-- ── 7. Servicio creado en terreno (cualquier instalación) ─────────────────────
-- En Lomas: iba al rack y ESM pide la sala de microfiltrado. Si el punto no
-- tiene servicio del mes, el teléfono lo crea con su propio id (idempotente:
-- viaja desde la cola sin señal).
CREATE OR REPLACE FUNCTION public.rpc_enex_terreno_servicio(
    p_programacion_id uuid, p_instalacion_id uuid, p_tipo_servicio text, p_fecha date, p_motivo text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF EXISTS (SELECT 1 FROM enex_programaciones WHERE id = p_programacion_id) THEN
        RETURN jsonb_build_object('success', true, 'ya_existia', true);
    END IF;
    IF p_tipo_servicio NOT IN ('mantencion','calibracion') OR p_fecha IS NULL THEN
        RAISE EXCEPTION 'Servicio inválido'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_instalaciones WHERE id = p_instalacion_id) THEN
        RAISE EXCEPTION 'Instalación no encontrada'; END IF;
    INSERT INTO enex_programaciones (id, instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada, observacion, creado_por, origen)
    VALUES (p_programacion_id, p_instalacion_id, p_tipo_servicio, EXTRACT(YEAR FROM p_fecha)::int, EXTRACT(MONTH FROM p_fecha)::int,
            p_fecha, coalesce(NULLIF(btrim(p_motivo), ''), 'Creado en terreno (cambio de programa)'), auth.uid(), 'terreno');
    RETURN jsonb_build_object('success', true, 'ya_existia', false);
END $function$;
REVOKE ALL ON FUNCTION public.rpc_enex_terreno_servicio(uuid, uuid, text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_terreno_servicio(uuid, uuid, text, date, text) TO authenticated;

-- Pauta de cada punto (la que usaría un servicio nuevo), para que el teléfono
-- pueda abrir sin señal un servicio que no estaba planificado.
CREATE OR REPLACE VIEW v_enex_terreno_instalaciones AS
SELECT i.id AS instalacion_id, i.nombre AS instalacion, i.tipo AS instalacion_tipo, i.patente, i.linea, i.area,
       i.es_comodin, f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
       coalesce(i.pauta_mantencion_id, (SELECT p.id FROM enex_pautas p
          WHERE p.activo AND p.tipo_servicio = 'mantencion' AND i.tipo = ANY(p.aplica_tipos)
          ORDER BY p.es_borrador ASC, p.version DESC LIMIT 1)) AS pauta_mantencion_id,
       coalesce(i.pauta_calibracion_id, (SELECT p.id FROM enex_pautas p
          WHERE p.activo AND p.tipo_servicio = 'calibracion' AND i.tipo = ANY(p.aplica_tipos)
          ORDER BY p.es_borrador ASC, p.version DESC LIMIT 1)) AS pauta_calibracion_id
  FROM enex_instalaciones i
  JOIN enex_faenas f ON f.id = i.faena_id
 WHERE i.activo AND f.activo;
GRANT SELECT ON v_enex_terreno_instalaciones TO authenticated;

-- ── 8. Lomas: zona no hecha / otra zona en terreno ───────────────────────────
ALTER TABLE enex_trimestre_actividades ADD COLUMN IF NOT EXISTS por_reprogramar_at TIMESTAMPTZ;
ALTER TABLE enex_trimestre_actividades ADD COLUMN IF NOT EXISTS por_reprogramar_motivo TEXT;

-- Planificarla de nuevo o ejecutarla resuelve el «por reprogramar».
CREATE OR REPLACE FUNCTION fn_enex_trim_act_limpia_por_reprogramar()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado = 'ejecutada' OR (NEW.fecha_plan IS NOT NULL AND NEW.fecha_plan IS DISTINCT FROM OLD.fecha_plan) THEN
        NEW.por_reprogramar_at := NULL;
        NEW.por_reprogramar_motivo := NULL;
    END IF;
    RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_enex_trim_act_limpia_por_reprogramar ON enex_trimestre_actividades;
CREATE TRIGGER trg_enex_trim_act_limpia_por_reprogramar
    BEFORE UPDATE ON enex_trimestre_actividades
    FOR EACH ROW EXECUTE FUNCTION fn_enex_trim_act_limpia_por_reprogramar();

-- p_hacer = false: la zona planificada para p_fecha no se hizo (vuelve a
--   pendiente con el motivo; sus tareas del plan quedan «no realizada»).
-- p_hacer = true: la zona se hace hoy aunque no estaba planificada (queda
--   planificada para p_fecha; el informe la marca ejecutada al sincronizar).
CREATE OR REPLACE FUNCTION public.rpc_enex_zona_terreno(
    p_lugar_id uuid, p_fecha date, p_hacer boolean, p_motivo text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_trim date := date_trunc('quarter', p_fecha)::date; v_n int := 0;
BEGIN
    IF NOT fn_enex_puede_ejecutar() THEN RAISE EXCEPTION 'Sin permiso para ejecutar en terreno'; END IF;
    IF p_fecha IS NULL THEN RAISE EXCEPTION 'Falta la fecha'; END IF;
    IF NOT EXISTS (SELECT 1 FROM enex_pauta_lugares WHERE id = p_lugar_id) THEN RAISE EXCEPTION 'Zona no encontrada'; END IF;

    INSERT INTO enex_trimestre_actividades (lugar_item_id, trimestre_inicio)
    SELECT li.id, v_trim FROM enex_pauta_lugar_items li WHERE li.lugar_id = p_lugar_id AND li.activo
    ON CONFLICT (lugar_item_id, trimestre_inicio) DO NOTHING;

    IF p_hacer THEN
        UPDATE enex_trimestre_actividades a SET estado = 'planificada', fecha_plan = p_fecha,
               comentario = coalesce(NULLIF(btrim(p_motivo), ''), a.comentario), updated_by = auth.uid(), updated_at = now()
          FROM enex_pauta_lugar_items li
         WHERE li.id = a.lugar_item_id AND li.lugar_id = p_lugar_id AND li.activo
           AND a.trimestre_inicio = v_trim AND a.estado NOT IN ('ejecutada','no_aplica');
        GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSE
        IF NULLIF(btrim(p_motivo), '') IS NULL THEN RAISE EXCEPTION 'Falta el motivo'; END IF;
        UPDATE enex_plan_tareas SET estado = 'no_realizada', updated_at = now()
         WHERE estado = 'pendiente' AND id IN (
            SELECT unnest(a.plan_tarea_ids) FROM enex_trimestre_actividades a
              JOIN enex_pauta_lugar_items li ON li.id = a.lugar_item_id
             WHERE li.lugar_id = p_lugar_id AND a.trimestre_inicio = v_trim AND a.fecha_plan = p_fecha);
        UPDATE enex_trimestre_actividades a SET estado = 'pendiente', fecha_plan = NULL,
               por_reprogramar_at = now(), por_reprogramar_motivo = btrim(p_motivo),
               updated_by = auth.uid(), updated_at = now()
          FROM enex_pauta_lugar_items li
         WHERE li.id = a.lugar_item_id AND li.lugar_id = p_lugar_id
           AND a.trimestre_inicio = v_trim AND a.fecha_plan = p_fecha AND a.estado IN ('planificada','reprogramada');
        GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
    RETURN jsonb_build_object('success', true, 'actividades', v_n);
END $function$;
REVOKE ALL ON FUNCTION public.rpc_enex_zona_terreno(uuid, date, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_enex_zona_terreno(uuid, date, boolean, text) TO authenticated;

-- El informe marca la zona que se planificó para ese día. Antes, un código que
-- está en dos zonas del mismo punto (4.4-4.7 en exteriores y en la sala) caía
-- siempre en la primera, aunque se hubiera hecho la sala.
DO $$
DECLARE v_def text := pg_get_functiondef('public.rpc_enex_trimestre_sincronizar(uuid, date)'::regprocedure);
        v_old text := '(coalesce(a.estado, ''pendiente'') <> ''ejecutada'') DESC,';
BEGIN
    IF position('(a.fecha_plan = r.fecha_ejecucion) DESC NULLS LAST' IN v_def) > 0 THEN RETURN; END IF;
    IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'MIG651: no se encontró el ORDER BY de rpc_enex_trimestre_sincronizar'; END IF;
    EXECUTE replace(v_def, v_old, v_old || ' (a.fecha_plan = r.fecha_ejecucion) DESC NULLS LAST,');
END $$;

SELECT json_build_object(
  'comodines', (SELECT json_agg(json_build_object('faena', f.codigo, 'nombre', i.nombre,
                  'progs', (SELECT count(*) FROM enex_programaciones p WHERE p.instalacion_id = i.id)))
                  FROM enex_instalaciones i JOIN enex_faenas f ON f.id = i.faena_id WHERE i.es_comodin),
  'zonas_lomas', (SELECT json_agg(json_build_object('area', area, 'zona', lugar, 'actividades', n) ORDER BY area, lugar_orden)
                    FROM (SELECT area, lugar, lugar_orden, count(*) n FROM v_enex_pauta_lugar_items v
                            JOIN enex_faenas f ON f.id = v.faena_id WHERE f.codigo = 'LB_LUB'
                           GROUP BY 1, 2, 3) z)
) AS resultado;
