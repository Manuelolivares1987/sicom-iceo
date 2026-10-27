-- ============================================================================
-- 658_enex_cambio_de_tarea_y_universo_contrato.sql
-- ----------------------------------------------------------------------------
-- 27-10-2026. Lomas Combustibles: el 26-10 tocaba EESS Valle Amanda y ESM pidió
-- calibrar camiones; hoy tocaba el Brazo de carga y otra vez camiones. No es una
-- reprogramación (misma tarea, otro día): ESM SACA una tarea y pone otra.
--
-- KPI Mantenimiento V8 (págs. 24-27 del contrato VA_24_068):
--   KPI_CPM = tareas ejecutadas ÷ tareas programadas · revisión trimestral por faena.
--   Consideración 1: «La no asistencia o no cumplimiento de alguna mantención
--   preventiva puede estar justificada bajo correo y autorizada por ADC Enex-Esm».
--
-- Decisiones de Manuel (27-10):
--   · La tarea desplazada sale del KPI SOLO con el correo del ADC adjunto.
--     Sin correo («pendiente_adc») sigue contando como atrasada.
--   · Lo que se hizo en su lugar (camiones) es tarea del contrato: suma al
--     numerador y al denominador. El recobro (2.ª vez en el trimestre) ya existe.
--   · El % de avance de cada contrato se mide contra el UNIVERSO del contrato,
--     no contra lo cargado en SICOM.
--
-- Piezas:
--   1. enex_faenas.contrato_*: universo trimestral (instalaciones de combustible
--      = mantención + calibración; truck shop = mantención; camión = calibración).
--   2. enex_cambios_tarea + enex_programaciones.cambio_tarea_id (los reemplazos).
--   3. rpc_enex_cambio_tarea / _destino / _anular.
--   4. v_enex_panel_mensual (+ columnas al final) y v_enex_kpi_mensual (descuenta
--      las justificadas). /m/enex NO cambia.
--   0. (Manuel, 27-10) El trimestre NO es igual para todos los contratos:
--      Spence, Lomas Combustibles y Lomas Lubricantes = trimestre calendario
--      (Jul-Sep cerró en septiembre; ahora Oct-Dic). Centinela (y DES, que va
--      dentro) = Feb-Abr, May-Jul, Ago-Oct, Nov-Ene. Hasta hoy todo SICOM usaba el
--      de Centinela: los recobros de Spence/Lomas cruzaban trimestres.
-- ============================================================================

-- ── 0. Trimestre por contrato ──────────────────────────────────────────────
ALTER TABLE enex_faenas
    ADD COLUMN IF NOT EXISTS trimestre_ancla SMALLINT NOT NULL DEFAULT 2 CHECK (trimestre_ancla BETWEEN 1 AND 3);
COMMENT ON COLUMN enex_faenas.trimestre_ancla IS
  'MIG658: mes en que parte el trimestre del contrato. 1 = Ene-Mar/Abr-Jun/Jul-Sep/Oct-Dic (Spence, Lomas). 2 = Feb-Abr/May-Jul/Ago-Oct/Nov-Ene (Centinela).';
UPDATE enex_faenas SET trimestre_ancla = 1 WHERE codigo IN ('SPENCE', 'LB_COMB', 'LB_LUB');
UPDATE enex_faenas SET trimestre_ancla = 2 WHERE codigo IN ('CENTINELA', 'NCEN_DES');

-- Primer día del trimestre que contiene la fecha, según el ancla del contrato.
CREATE OR REPLACE FUNCTION fn_enex_trimestre_inicio(p_fecha DATE, p_ancla INTEGER)
RETURNS DATE LANGUAGE sql IMMUTABLE AS $$
    SELECT (date_trunc('month', p_fecha)
            - make_interval(months => (EXTRACT(MONTH FROM p_fecha)::int - coalesce(p_ancla, 2) + 12) % 3))::date
$$;

CREATE OR REPLACE FUNCTION fn_enex_fin_trimestre(p_fecha DATE, p_ancla INTEGER)
RETURNS DATE LANGUAGE sql IMMUTABLE AS $$
    SELECT (fn_enex_trimestre_inicio(p_fecha, p_ancla) + INTERVAL '3 months' - INTERVAL '1 day')::date
$$;

-- Clave comparable (aaaamm del primer mes). La versión de 1 argumento (ancla febrero) se mantiene.
CREATE OR REPLACE FUNCTION fn_enex_trimestre_key(p_fecha DATE, p_ancla INTEGER)
RETURNS INTEGER LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_fecha IS NULL THEN NULL ELSE
        (EXTRACT(YEAR FROM fn_enex_trimestre_inicio(p_fecha, p_ancla))::int * 100
         + EXTRACT(MONTH FROM fn_enex_trimestre_inicio(p_fecha, p_ancla))::int) END
$$;

-- «Oct-Dic 2026», «Nov-Ene 2026»: el nombre dice los meses, sin T1..T4 ambiguos.
CREATE OR REPLACE FUNCTION fn_enex_trimestre_label(p_fecha DATE, p_ancla INTEGER)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_fecha IS NULL THEN NULL ELSE
        (ARRAY['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'])[EXTRACT(MONTH FROM fn_enex_trimestre_inicio(p_fecha, p_ancla))::int]
        || '-' ||
        (ARRAY['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'])[EXTRACT(MONTH FROM fn_enex_fin_trimestre(p_fecha, p_ancla))::int]
        || ' ' || EXTRACT(YEAR FROM fn_enex_trimestre_inicio(p_fecha, p_ancla))::text END
$$;

-- Recobros: 2.ª atención del mismo punto en el trimestre DE SU CONTRATO.
CREATE OR REPLACE VIEW v_enex_recobros AS
 WITH ej AS (
         SELECT e.id AS ejecucion_id,
            e.fecha_ejecucion,
            e.estado,
            e.ot_numero,
            e.ejecutor,
            e.created_at,
            p.id AS programacion_id,
            p.tipo_servicio,
            i.id AS instalacion_id,
            i.nombre AS instalacion,
            i.tipo AS instalacion_tipo,
            i.patente,
            i.linea,
            f.id AS faena_id,
            f.codigo AS faena_codigo,
            f.nombre AS faena,
            fn_enex_trimestre_key(e.fecha_ejecucion, f.trimestre_ancla) AS trimestre_key,
            fn_enex_trimestre_label(e.fecha_ejecucion, f.trimestre_ancla) AS trimestre,
            row_number() OVER (PARTITION BY p.instalacion_id, p.tipo_servicio, (fn_enex_trimestre_key(e.fecha_ejecucion, f.trimestre_ancla))
                               ORDER BY e.fecha_ejecucion, e.created_at) AS secuencia
           FROM enex_ejecuciones e
             JOIN enex_programaciones p ON p.id = e.programacion_id
             JOIN enex_instalaciones i ON i.id = p.instalacion_id
             JOIN enex_faenas f ON f.id = i.faena_id
          WHERE e.estado = ANY (ARRAY['ejecutada'::text, 'cumplida'::text]) AND e.fecha_ejecucion IS NOT NULL
        )
 SELECT ejecucion_id, fecha_ejecucion, estado, ot_numero, ejecutor, created_at, programacion_id, tipo_servicio,
    instalacion_id, instalacion, instalacion_tipo, patente, linea, faena_id, faena_codigo, faena,
    trimestre_key, trimestre, secuencia, (secuencia > 1) AS es_recobro
   FROM ej;

CREATE OR REPLACE FUNCTION rpc_enex_recobro_check(p_instalacion_id uuid, p_tipo_servicio text, p_fecha date DEFAULT NULL::date, p_excluir_prog uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
    WITH a AS (SELECT f.trimestre_ancla AS ancla FROM enex_instalaciones i JOIN enex_faenas f ON f.id = i.faena_id WHERE i.id = p_instalacion_id)
    SELECT jsonb_build_object(
        'previas', COUNT(e.id),
        'es_recobro', COUNT(e.id) > 0,
        'trimestre', fn_enex_trimestre_label(COALESCE(p_fecha, CURRENT_DATE), (SELECT ancla FROM a)))
    FROM enex_ejecuciones e
    JOIN enex_programaciones p ON p.id = e.programacion_id
    WHERE p.instalacion_id = p_instalacion_id
      AND p.tipo_servicio  = p_tipo_servicio
      AND e.estado IN ('ejecutada','cumplida') AND e.fecha_ejecucion IS NOT NULL
      AND fn_enex_trimestre_key(e.fecha_ejecucion, (SELECT ancla FROM a))
          = fn_enex_trimestre_key(COALESCE(p_fecha, CURRENT_DATE), (SELECT ancla FROM a))
      AND (p_excluir_prog IS NULL OR p.id <> p_excluir_prog);
$function$;

-- Teléfono: misma vista, solo cambia el trimestre con que se marca el recobro.
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
    (e.firma_mandante_url IS NOT NULL) AS cumplida,
    (EXISTS ( SELECT 1
           FROM enex_ejecuciones e2
             JOIN enex_programaciones p2 ON p2.id = e2.programacion_id
          WHERE p2.instalacion_id = pr.instalacion_id AND p2.tipo_servicio = pr.tipo_servicio AND p2.id <> pr.id
            AND e2.estado = ANY (ARRAY['ejecutada'::text, 'cumplida'::text]) AND e2.fecha_ejecucion IS NOT NULL
            AND fn_enex_trimestre_key(e2.fecha_ejecucion, f.trimestre_ancla)
                = fn_enex_trimestre_key(COALESCE(pr.fecha_programada, make_date(pr.periodo_anio, pr.periodo_mes, 15)), f.trimestre_ancla)
            AND NOT i.es_comodin)) AS es_recobro,
    i.es_comodin,
    pr.origen,
    pr.por_reprogramar_at,
    pr.por_reprogramar_motivo
   FROM enex_programaciones pr
     JOIN enex_instalaciones i ON i.id = pr.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = pr.id;

-- ── 1. Universo contractual por faena ──────────────────────────────────────
ALTER TABLE enex_faenas
    ADD COLUMN IF NOT EXISTS contrato_inst_combustible INTEGER,
    ADD COLUMN IF NOT EXISTS contrato_inst_lubricante  INTEGER,
    ADD COLUMN IF NOT EXISTS contrato_camiones         INTEGER,
    ADD COLUMN IF NOT EXISTS contrato_universo_nota    TEXT;

COMMENT ON COLUMN enex_faenas.contrato_inst_combustible IS
  'MIG658: instalaciones de combustible del contrato. Cada una = mantención + calibración por trimestre.';
COMMENT ON COLUMN enex_faenas.contrato_inst_lubricante IS
  'MIG658: instalaciones de lubricantes (truck shop) del contrato. Cada una = mantención por trimestre.';
COMMENT ON COLUMN enex_faenas.contrato_camiones IS
  'MIG658: camiones de combustible del contrato. Cada uno = calibración por trimestre.';

UPDATE enex_faenas SET contrato_inst_combustible = 11, contrato_inst_lubricante = 3, contrato_camiones = 20,
       contrato_universo_nota = 'Contrato VA_24_068 pág. 5: 11 instalaciones de combustible (incluye EESS y Semimóvil Encuentro, sector DES), 3 Truck Shop y 20 camiones (17 de 20 m³, 2 de 10 m³, 1 de 5 m³).'
 WHERE codigo = 'CENTINELA';
UPDATE enex_faenas SET contrato_inst_combustible = 4, contrato_inst_lubricante = 0, contrato_camiones = 8,
       contrato_universo_nota = 'Contrato VA_24_068 págs. 5-6: EESS S1, Petrolera P1, Instalación Enaex y TK 120 SX; 8 camiones (7 de 20 m³, 1 de 10 m³).'
 WHERE codigo = 'SPENCE';
UPDATE enex_faenas SET contrato_inst_combustible = 3, contrato_inst_lubricante = 0, contrato_camiones = 4,
       contrato_universo_nota = 'Contrato VA_24_068 pág. 6: Semimóvil Fortuna, EESS Valle Amanda y Brazo de carga Valle Amanda; 4 camiones de 20 m³.'
 WHERE codigo = 'LB_COMB';
UPDATE enex_faenas SET contrato_universo_nota = 'Sector Encuentro (anexo NCEN 11-09-2025): sus instalaciones van dentro del universo de Centinela.'
 WHERE codigo = 'NCEN_DES';
UPDATE enex_faenas SET contrato_universo_nota = 'Contrato LB-AG-GAD-SCT-2791: el avance por actividad y lugar está en «Pauta por lugar». Universo de servicios por definir.'
 WHERE codigo = 'LB_LUB';

CREATE OR REPLACE FUNCTION rpc_enex_faena_universo(
    p_faena_id UUID, p_combustible INTEGER, p_lubricante INTEGER, p_camiones INTEGER, p_nota TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso para gestionar el contrato ENEX'; END IF;
    IF least(coalesce(p_combustible, 0), coalesce(p_lubricante, 0), coalesce(p_camiones, 0)) < 0 THEN
        RAISE EXCEPTION 'El universo no puede ser negativo'; END IF;
    UPDATE enex_faenas
       SET contrato_inst_combustible = p_combustible, contrato_inst_lubricante = p_lubricante,
           contrato_camiones = p_camiones,
           contrato_universo_nota = coalesce(NULLIF(btrim(p_nota), ''), contrato_universo_nota)
     WHERE id = p_faena_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Faena no encontrada'; END IF;
    RETURN jsonb_build_object('success', true);
END $$;


-- ── 2. Cambio de tarea ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_cambios_tarea (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    programacion_id       UUID NOT NULL REFERENCES enex_programaciones(id) ON DELETE CASCADE,
    fecha                 DATE NOT NULL,           -- día en que ESM cambió la tarea
    solicitante_esm       TEXT NOT NULL,
    motivo                TEXT NOT NULL,
    evidencia_url         TEXT,                    -- WhatsApp / correo del pedido
    destino               TEXT NOT NULL CHECK (destino IN ('reprogramada', 'pendiente_adc', 'justificada_adc')),
    nueva_fecha           DATE,
    adc_nombre            TEXT,
    adc_autorizacion_url  TEXT,                    -- el correo del ADC (Consideración 1 KPI V8)
    adc_autorizado_at     TIMESTAMPTZ,
    creado_por            UUID DEFAULT auth.uid(),
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_at        TIMESTAMPTZ,
    CONSTRAINT enex_cambio_justificada_con_adc
        CHECK (destino <> 'justificada_adc' OR (adc_autorizacion_url IS NOT NULL AND NULLIF(btrim(adc_nombre), '') IS NOT NULL)),
    CONSTRAINT enex_cambio_reprogramada_con_fecha
        CHECK (destino <> 'reprogramada' OR nueva_fecha IS NOT NULL)
);
-- Un cambio vigente por tarea desplazada (si se equivoca, se anula y se registra de nuevo).
CREATE UNIQUE INDEX IF NOT EXISTS uq_enex_cambio_tarea_prog ON enex_cambios_tarea (programacion_id);

COMMENT ON TABLE enex_cambios_tarea IS
  'MIG658: ESM saca una tarea programada y pide otra. La desplazada se reprograma, o sale del KPI solo con el correo del ADC.';

ALTER TABLE enex_cambios_tarea ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_cambios_tarea_sel ON enex_cambios_tarea;
CREATE POLICY pol_enex_cambios_tarea_sel ON enex_cambios_tarea
    FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);

ALTER TABLE enex_programaciones
    ADD COLUMN IF NOT EXISTS cambio_tarea_id UUID REFERENCES enex_cambios_tarea(id) ON DELETE SET NULL;
COMMENT ON COLUMN enex_programaciones.cambio_tarea_id IS
  'MIG658: esta programación se hizo EN REEMPLAZO de la tarea que ESM desplazó.';

ALTER TABLE enex_programaciones DROP CONSTRAINT IF EXISTS enex_programaciones_origen_chk;
ALTER TABLE enex_programaciones ADD CONSTRAINT enex_programaciones_origen_chk
    CHECK (origen = ANY (ARRAY['plan', 'terreno', 'cambio_esm']));

-- Evidencias (correo del ADC, captura de WhatsApp) en documentos/enex-cambios-tarea/
DROP POLICY IF EXISTS storage_enex_cambios_insert ON storage.objects;
CREATE POLICY storage_enex_cambios_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'documentos' AND (storage.foldername(name))[1] = 'enex-cambios-tarea');


-- Aplica el destino a la tarea desplazada (común a crear y a cambiar destino).
CREATE OR REPLACE FUNCTION fn_enex_cambio_aplicar_destino(
    p_prog_id UUID, p_fecha_original DATE, p_destino TEXT, p_nueva_fecha DATE)
RETURNS VOID LANGUAGE plpgsql SET search_path TO 'public' AS $$
DECLARE v_fin DATE;
BEGIN
    IF p_destino = 'reprogramada' THEN
        IF p_nueva_fecha IS NULL THEN RAISE EXCEPTION 'Elige la nueva fecha'; END IF;
        -- El trimestre es el del contrato de esa faena.
        SELECT fn_enex_fin_trimestre(p_fecha_original, f.trimestre_ancla) INTO v_fin
          FROM enex_programaciones p JOIN enex_instalaciones i ON i.id = p.instalacion_id JOIN enex_faenas f ON f.id = i.faena_id
         WHERE p.id = p_prog_id;
        IF p_nueva_fecha > v_fin THEN
            RAISE EXCEPTION 'Fuera del trimestre: la nueva fecha debe caer a más tardar el %. Si no cabe, déjala pendiente del correo del ADC.',
                            to_char(v_fin, 'DD-MM-YYYY');
        END IF;
        -- El trigger de MIG651 limpia la marca «no se hizo» al cambiar la fecha.
        UPDATE enex_programaciones SET fecha_programada = p_nueva_fecha WHERE id = p_prog_id;
    ELSE
        -- Queda en su día original (atrasada hasta que llegue el correo, o justificada).
        UPDATE enex_programaciones
           SET por_reprogramar_at = NULL, por_reprogramar_motivo = NULL, por_reprogramar_por = NULL
         WHERE id = p_prog_id;
    END IF;
END $$;


CREATE OR REPLACE FUNCTION rpc_enex_cambio_tarea(
    p_programacion_id UUID,
    p_solicitante     TEXT,
    p_motivo          TEXT,
    p_destino         TEXT,
    p_nueva_fecha     DATE  DEFAULT NULL,
    p_evidencia_url   TEXT  DEFAULT NULL,
    p_adc_nombre      TEXT  DEFAULT NULL,
    p_adc_url         TEXT  DEFAULT NULL,
    p_reemplazos      JSONB DEFAULT '[]'::jsonb)   -- [{programacion_id} | {instalacion_id, tipo_servicio} | {patente}]
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
    v_prog   enex_programaciones%ROWTYPE;
    v_inst   enex_instalaciones%ROWTYPE;
    v_fecha  DATE;
    v_cambio UUID;
    r        JSONB;
    v_rid    UUID;
    v_iid    UUID;
    v_tipo   TEXT;
    v_pat    TEXT;
    v_obs    TEXT;
    v_n      INTEGER := 0;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso para gestionar el plan ENEX'; END IF;
    IF NULLIF(btrim(p_solicitante), '') IS NULL THEN RAISE EXCEPTION 'Indica quién de ESM pidió el cambio'; END IF;

    SELECT * INTO v_prog FROM enex_programaciones WHERE id = p_programacion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Programación no encontrada'; END IF;
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = p_programacion_id) THEN
        RAISE EXCEPTION 'Esta tarea ya tiene ejecución registrada: no se puede desplazar'; END IF;
    IF EXISTS (SELECT 1 FROM enex_cambios_tarea WHERE programacion_id = p_programacion_id) THEN
        RAISE EXCEPTION 'Esta tarea ya tiene un cambio registrado: cambia su destino o anúlalo'; END IF;
    SELECT * INTO v_inst FROM enex_instalaciones WHERE id = v_prog.instalacion_id;

    v_fecha := coalesce(v_prog.fecha_programada, make_date(v_prog.periodo_anio, v_prog.periodo_mes, 1));
    IF p_destino = 'justificada_adc' AND (p_adc_url IS NULL OR NULLIF(btrim(p_adc_nombre), '') IS NULL) THEN
        RAISE EXCEPTION 'Para justificar hace falta el correo del ADC y su nombre'; END IF;

    INSERT INTO enex_cambios_tarea (programacion_id, fecha, solicitante_esm, motivo, evidencia_url, destino,
                                    nueva_fecha, adc_nombre, adc_autorizacion_url, adc_autorizado_at)
    VALUES (p_programacion_id, v_fecha, btrim(p_solicitante),
            coalesce(NULLIF(btrim(p_motivo), ''), v_prog.por_reprogramar_motivo, 'Cambio de tarea pedido por ESM'),
            p_evidencia_url, p_destino,
            CASE WHEN p_destino = 'reprogramada' THEN p_nueva_fecha END,
            NULLIF(btrim(p_adc_nombre), ''), p_adc_url,
            CASE WHEN p_destino = 'justificada_adc' THEN now() END)
    RETURNING id INTO v_cambio;

    PERFORM fn_enex_cambio_aplicar_destino(p_programacion_id, v_fecha, p_destino, p_nueva_fecha);

    -- Lo que se hizo en su lugar, el mismo día.
    v_obs := format('En reemplazo de %s (%s), pedido por %s', v_inst.nombre,
                    CASE v_prog.tipo_servicio WHEN 'calibracion' THEN 'calibración' ELSE 'mantención' END,
                    btrim(p_solicitante));
    FOR r IN SELECT * FROM jsonb_array_elements(coalesce(p_reemplazos, '[]'::jsonb)) LOOP
        v_rid := NULLIF(r->>'programacion_id', '')::uuid;
        IF v_rid IS NOT NULL THEN
            -- Una tarea ya planificada para otro día que ESM adelantó.
            UPDATE enex_programaciones p
               SET fecha_programada = v_fecha, cambio_tarea_id = v_cambio
             WHERE p.id = v_rid AND p.id <> p_programacion_id
               AND NOT EXISTS (SELECT 1 FROM enex_ejecuciones e WHERE e.programacion_id = p.id)
               AND p.instalacion_id IN (SELECT id FROM enex_instalaciones WHERE faena_id = v_inst.faena_id);
            IF NOT FOUND THEN RAISE EXCEPTION 'La tarea a adelantar no existe, ya se ejecutó o es de otra faena'; END IF;
            v_n := v_n + 1;
            CONTINUE;
        END IF;

        v_iid  := NULLIF(r->>'instalacion_id', '')::uuid;
        v_tipo := coalesce(NULLIF(r->>'tipo_servicio', ''), 'calibracion');
        v_pat  := fn_enex_patente_norm(r->>'patente');
        IF v_iid IS NULL AND v_pat IS NOT NULL THEN
            IF length(v_pat) NOT BETWEEN 4 AND 8 THEN RAISE EXCEPTION 'Patente inválida: %', r->>'patente'; END IF;
            SELECT id INTO v_iid FROM enex_instalaciones
             WHERE faena_id = v_inst.faena_id AND tipo = 'camion' AND NOT es_comodin
               AND fn_enex_patente_norm(patente) = v_pat
             ORDER BY activo DESC LIMIT 1;
            IF v_iid IS NULL THEN
                INSERT INTO enex_instalaciones (faena_id, codigo, nombre, tipo, linea, patente, activo, orden, creada_en_terreno)
                VALUES (v_inst.faena_id, v_pat, 'Aljibe ' || v_pat, 'camion', 'combustible', v_pat, true, 500, true)
                RETURNING id INTO v_iid;
            ELSE
                UPDATE enex_instalaciones SET activo = true WHERE id = v_iid AND NOT activo;
            END IF;
            v_tipo := 'calibracion';
        END IF;
        IF v_iid IS NULL THEN RAISE EXCEPTION 'Cada reemplazo necesita instalación o patente'; END IF;
        IF v_tipo NOT IN ('mantencion', 'calibracion') THEN RAISE EXCEPTION 'Tipo de servicio inválido: %', v_tipo; END IF;
        IF NOT EXISTS (SELECT 1 FROM enex_instalaciones WHERE id = v_iid AND faena_id = v_inst.faena_id) THEN
            RAISE EXCEPTION 'El reemplazo es de otra faena'; END IF;

        -- Si ya estaba ese mismo servicio ese día (p. ej. lo creó el teléfono), se enlaza; no se duplica.
        UPDATE enex_programaciones SET cambio_tarea_id = v_cambio
         WHERE id = (SELECT id FROM enex_programaciones
                      WHERE instalacion_id = v_iid AND tipo_servicio = v_tipo AND fecha_programada = v_fecha
                        AND cambio_tarea_id IS NULL AND id <> p_programacion_id LIMIT 1);
        IF NOT FOUND THEN
            INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, fecha_programada,
                                             observacion, creado_por, origen, cambio_tarea_id)
            VALUES (v_iid, v_tipo, EXTRACT(YEAR FROM v_fecha)::int, EXTRACT(MONTH FROM v_fecha)::int, v_fecha,
                    v_obs, auth.uid(), 'cambio_esm', v_cambio);
        END IF;
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'cambio_id', v_cambio, 'reemplazos', v_n);
END $$;


-- Cambiar el destino después (llegó el correo del ADC, o sí cupo una fecha).
CREATE OR REPLACE FUNCTION rpc_enex_cambio_tarea_destino(
    p_cambio_id UUID, p_destino TEXT, p_nueva_fecha DATE DEFAULT NULL,
    p_adc_nombre TEXT DEFAULT NULL, p_adc_url TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_c enex_cambios_tarea%ROWTYPE;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso para gestionar el plan ENEX'; END IF;
    SELECT * INTO v_c FROM enex_cambios_tarea WHERE id = p_cambio_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cambio no encontrado'; END IF;
    IF EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_c.programacion_id) THEN
        RAISE EXCEPTION 'La tarea ya se ejecutó: su destino no se puede cambiar'; END IF;
    IF p_destino = 'justificada_adc' AND (coalesce(p_adc_url, v_c.adc_autorizacion_url) IS NULL
                                          OR NULLIF(btrim(coalesce(p_adc_nombre, v_c.adc_nombre)), '') IS NULL) THEN
        RAISE EXCEPTION 'Para justificar hace falta el correo del ADC y su nombre'; END IF;

    UPDATE enex_cambios_tarea
       SET destino = p_destino,
           nueva_fecha = CASE WHEN p_destino = 'reprogramada' THEN p_nueva_fecha END,
           adc_nombre = coalesce(NULLIF(btrim(p_adc_nombre), ''), adc_nombre),
           adc_autorizacion_url = coalesce(p_adc_url, adc_autorizacion_url),
           adc_autorizado_at = CASE WHEN p_destino = 'justificada_adc' THEN coalesce(adc_autorizado_at, now()) END,
           actualizado_at = now()
     WHERE id = p_cambio_id;
    PERFORM fn_enex_cambio_aplicar_destino(v_c.programacion_id, v_c.fecha, p_destino, p_nueva_fecha);
    -- Si antes se había reprogramado y ahora no, vuelve a su día original.
    IF v_c.destino = 'reprogramada' AND p_destino <> 'reprogramada' THEN
        UPDATE enex_programaciones SET fecha_programada = v_c.fecha WHERE id = v_c.programacion_id;
    END IF;
    RETURN jsonb_build_object('success', true);
END $$;


-- Anular un cambio mal registrado: la tarea vuelve a su día; los reemplazos
-- creados aquí sin ejecución se borran; los adelantados quedan en su nuevo día.
CREATE OR REPLACE FUNCTION rpc_enex_cambio_tarea_anular(p_cambio_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_c enex_cambios_tarea%ROWTYPE; v_borrados INTEGER;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso para gestionar el plan ENEX'; END IF;
    SELECT * INTO v_c FROM enex_cambios_tarea WHERE id = p_cambio_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Cambio no encontrado'; END IF;

    DELETE FROM enex_programaciones p
     WHERE p.cambio_tarea_id = p_cambio_id AND p.origen = 'cambio_esm'
       AND NOT EXISTS (SELECT 1 FROM enex_ejecuciones e WHERE e.programacion_id = p.id);
    GET DIAGNOSTICS v_borrados = ROW_COUNT;
    UPDATE enex_programaciones SET cambio_tarea_id = NULL WHERE cambio_tarea_id = p_cambio_id;
    IF NOT EXISTS (SELECT 1 FROM enex_ejecuciones WHERE programacion_id = v_c.programacion_id) THEN
        UPDATE enex_programaciones SET fecha_programada = v_c.fecha
         WHERE id = v_c.programacion_id AND fecha_programada IS DISTINCT FROM v_c.fecha;
    END IF;
    DELETE FROM enex_cambios_tarea WHERE id = p_cambio_id;
    RETURN jsonb_build_object('success', true, 'reemplazos_borrados', v_borrados);
END $$;

REVOKE ALL ON FUNCTION rpc_enex_cambio_tarea(UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_cambio_tarea_destino(UUID, TEXT, DATE, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_cambio_tarea_anular(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_enex_faena_universo(UUID, INTEGER, INTEGER, INTEGER, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_enex_cambio_aplicar_destino(UUID, DATE, TEXT, DATE) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_cambio_tarea(UUID, TEXT, TEXT, TEXT, DATE, TEXT, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_cambio_tarea_destino(UUID, TEXT, DATE, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_cambio_tarea_anular(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_enex_faena_universo(UUID, INTEGER, INTEGER, INTEGER, TEXT) TO authenticated;


-- ── 3. Vistas ──────────────────────────────────────────────────────────────
-- Panel: mismas columnas + las del cambio de tarea AL FINAL (CREATE OR REPLACE).
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
    (e.firma_mandante_url IS NOT NULL) AS cumplida,
    e.informe_pdf_url,
    (e.firma_tecnico_url IS NOT NULL) AS firma_tecnico_lista,
    e.tecnico_nombre,
    i.es_comodin,
    i.creada_en_terreno,
    p.origen,
    p.por_reprogramar_at,
    p.por_reprogramar_motivo,
    -- [MIG658] esta tarea fue desplazada por ESM
    ct.id AS cambio_tarea_id,
    ct.destino AS cambio_destino,
    ct.fecha AS cambio_fecha,
    ct.solicitante_esm AS cambio_solicitante,
    ct.motivo AS cambio_motivo,
    ct.nueva_fecha AS cambio_nueva_fecha,
    ct.adc_nombre AS cambio_adc_nombre,
    ct.adc_autorizacion_url AS cambio_adc_url,
    ct.evidencia_url AS cambio_evidencia_url,
    (ct.destino = 'justificada_adc') AS justificada,
    -- [MIG658] esta tarea se hizo en reemplazo de otra
    p.cambio_tarea_id AS reemplaza_cambio_id,
    ri.nombre AS reemplaza_instalacion,
    rp.tipo_servicio AS reemplaza_tipo_servicio,
    f.trimestre_ancla AS faena_trimestre_ancla
   FROM enex_programaciones p
     JOIN enex_instalaciones i ON i.id = p.instalacion_id
     JOIN enex_faenas f ON f.id = i.faena_id
     LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id
     LEFT JOIN enex_cambios_tarea ct ON ct.programacion_id = p.id
     LEFT JOIN enex_cambios_tarea rc ON rc.id = p.cambio_tarea_id
     LEFT JOIN enex_programaciones rp ON rp.id = rc.programacion_id
     LEFT JOIN enex_instalaciones ri ON ri.id = rp.instalacion_id;

-- KPI: lo justificado por el ADC sale del denominador (Consideración 1, KPI V8).
CREATE OR REPLACE VIEW v_enex_kpi_mensual AS
 WITH base AS (
         SELECT f.id AS faena_id,
            f.codigo AS faena_codigo,
            f.nombre AS faena,
            f.facturacion_mensual_clp,
            p.periodo_anio,
            p.periodo_mes,
            (count(*) FILTER (WHERE ct.id IS NULL OR ct.destino <> 'justificada_adc'))::integer AS programadas,
            (count(*) FILTER (WHERE e.firma_mandante_url IS NOT NULL))::integer AS cumplidas,
            (count(*) FILTER (WHERE ct.destino = 'justificada_adc'))::integer AS justificadas
           FROM enex_programaciones p
             JOIN enex_instalaciones i ON i.id = p.instalacion_id
             JOIN enex_faenas f ON f.id = i.faena_id
             LEFT JOIN enex_ejecuciones e ON e.programacion_id = p.id
             LEFT JOIN enex_cambios_tarea ct ON ct.programacion_id = p.id
          GROUP BY f.id, f.codigo, f.nombre, f.facturacion_mensual_clp, p.periodo_anio, p.periodo_mes
        )
 SELECT faena_id,
    faena_codigo,
    faena,
    facturacion_mensual_clp,
    periodo_anio,
    periodo_mes,
    programadas,
    cumplidas,
        CASE
            WHEN programadas = 0 THEN NULL::numeric
            ELSE round(cumplidas::numeric / programadas::numeric * 100::numeric, 1)
        END AS cumplimiento_pct,
        CASE
            WHEN programadas = 0 THEN 0
            WHEN cumplidas::numeric / programadas::numeric >= 0.96 THEN 0
            WHEN cumplidas::numeric / programadas::numeric >= 0.90 THEN 10
            WHEN cumplidas::numeric / programadas::numeric >= 0.80 THEN 20
            ELSE 100
        END AS tramo_multa_pct,
        CASE
            WHEN programadas = 0 THEN 0::numeric
            WHEN cumplidas::numeric / programadas::numeric >= 0.96 THEN 0::numeric
            WHEN cumplidas::numeric / programadas::numeric >= 0.90 THEN round(facturacion_mensual_clp * 0.10, 0)
            WHEN cumplidas::numeric / programadas::numeric >= 0.80 THEN round(facturacion_mensual_clp * 0.20, 0)
            ELSE round(facturacion_mensual_clp * 0.20, 0)
        END AS monto_riesgo_clp,
    programadas > 0 AND cumplidas::numeric / programadas::numeric < 0.80 AS en_revision_continuidad,
    justificadas
   FROM base b;

SELECT codigo, trimestre_ancla, fn_enex_trimestre_label(CURRENT_DATE, trimestre_ancla) AS trimestre_hoy,
       contrato_inst_combustible c, contrato_inst_lubricante l, contrato_camiones cam,
       coalesce(contrato_inst_combustible, 0) * 2 + coalesce(contrato_inst_lubricante, 0) + coalesce(contrato_camiones, 0) AS tareas_trimestre
  FROM enex_faenas ORDER BY codigo;
