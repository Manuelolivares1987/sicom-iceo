-- ============================================================================
-- SICOM-ICEO | 234 — ENEX Centinela: camiones (patentes), plan trimestral,
--                     recobros y registro de reprogramación para el mandante
-- ============================================================================
-- Pedido de Manuel (2026-07-21, presentación en pocas horas):
--   1. Ingresar los 21 camiones ALJIBE de Centinela (patentes) al catálogo,
--      con su ubicación (Calama/Faena) y última calibración conocida.
--   2. Cargar "las partes donde se hace mantenimiento" = programar el plan
--      trimestral de Centinela (instalaciones + camiones) para que aparezcan
--      en terreno y alimenten el KPI. Idempotente: no toca lo ya programado.
--   3. RECOBROS: si se vuelve a atender/calibrar el MISMO punto/patente dentro
--      del mismo trimestre (según el plan trimestral), la 2ª ejecución en
--      adelante es un RECOBRO (se factura adicional a ENEX). Se detecta por
--      trimestre CONTRACTUAL (anclado en febrero: May-Jun-Jul = un trimestre,
--      como en el plan "SEGUNDO TRIMESTRE" de Centinela; proyecto inició
--      2025-02-01).
--   4. REPROGRAMACIÓN: registro formal (formato ESM/PILLADO) que se entrega a
--      ENEX cuando una actividad programada se mueve de fecha.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_ejecuciones') THEN
        RAISE EXCEPTION 'STOP — falta MIG206/208'; END IF;
END $$;

-- ── 1. Columnas nuevas en instalaciones (ubicación + última calibración) ─────
ALTER TABLE enex_instalaciones
    ADD COLUMN IF NOT EXISTS ubicacion          TEXT,   -- Calama / Faena (camiones)
    ADD COLUMN IF NOT EXISTS ultima_calibracion DATE;   -- referencia de la última calibración conocida

COMMENT ON COLUMN enex_instalaciones.ubicacion IS 'Ubicación operativa del equipo (ej. camiones: Calama / Faena). MIG234.';
COMMENT ON COLUMN enex_instalaciones.ultima_calibracion IS 'Última calibración conocida (referencia de carga). MIG234.';


-- ── 2. Trimestre CONTRACTUAL (anclado en febrero) ────────────────────────────
-- El plan trimestral de Centinela agrupa May-Jun-Jul como "segundo trimestre"
-- (inicio de proyecto 2025-02-01). Trimestres: Feb-Abr, May-Jul, Ago-Oct,
-- Nov-Ene. La clave entera agrupa de forma estable (Enero pertenece al
-- trimestre Nov-Ene del año-ancla anterior).
CREATE OR REPLACE FUNCTION fn_enex_trimestre_key(p_fecha DATE)
RETURNS INT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_fecha IS NULL THEN NULL
        ELSE ( -- año-ancla: Enero cuenta para el año anterior
                 (EXTRACT(YEAR FROM p_fecha)::int - CASE WHEN EXTRACT(MONTH FROM p_fecha)::int = 1 THEN 1 ELSE 0 END) * 10
               + ( ((EXTRACT(MONTH FROM p_fecha)::int - 2 + 12) % 12) / 3 )  -- 0=Feb-Abr … 3=Nov-Ene
             )
    END;
$$;

CREATE OR REPLACE FUNCTION fn_enex_trimestre_label(p_fecha DATE)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_fecha IS NULL THEN NULL ELSE
        'T' || ((((EXTRACT(MONTH FROM p_fecha)::int - 2 + 12) % 12) / 3) + 1)::text
        || ' ' || (EXTRACT(YEAR FROM p_fecha)::int - CASE WHEN EXTRACT(MONTH FROM p_fecha)::int = 1 THEN 1 ELSE 0 END)::text
    END;
$$;
GRANT EXECUTE ON FUNCTION fn_enex_trimestre_key(DATE)   TO authenticated;
GRANT EXECUTE ON FUNCTION fn_enex_trimestre_label(DATE) TO authenticated;


-- ── 3. Seed 21 camiones ALJIBE de Centinela (patentes de la imagen) ──────────
DO $$
DECLARE
    v_cen UUID;
    v_ord INT;
    r TEXT[];
    cam CONSTANT TEXT[][] := ARRAY[
        -- patente , ubicacion , ultima_calibracion (o '')
        ['VFZK21','Calama',''],       ['SKPL79','Calama',''],       ['TBGJ68','Calama',''],
        ['TBGJ71','Faena',''],        ['SXCF77','Faena',''],        ['VFZK22','Calama',''],
        ['RKSV49','Faena',''],        ['SKPL80','Faena','2026-04-14'],
        ['TBGJ72','Faena','2026-04-14'], ['SXGH41','Faena','2026-02-05'],
        ['SKPJ31','Faena','2025-12-31'], ['TBGJ73','Faena',''],     ['RKSV46','Faena',''],
        ['TBGJ70','Faena',''],        ['TBGJ67','Faena',''],        ['SKPJ32','Faena',''],
        ['SKPL78','Faena',''],        ['TBGJ69','Faena',''],        ['SXGH43','Faena','2026-01-08'],
        ['SXCF76','Faena',''],        ['SXGG83','Faena','']
    ];
BEGIN
    SELECT id INTO v_cen FROM enex_faenas WHERE codigo='CENTINELA';
    IF v_cen IS NULL THEN RAISE EXCEPTION 'Falta faena CENTINELA'; END IF;
    SELECT COALESCE(MAX(orden),0) INTO v_ord FROM enex_instalaciones WHERE faena_id=v_cen;

    FOREACH r SLICE 1 IN ARRAY cam LOOP
        IF NOT EXISTS (SELECT 1 FROM enex_instalaciones
                        WHERE faena_id=v_cen AND UPPER(patente)=UPPER(r[1])) THEN
            v_ord := v_ord + 1;
            INSERT INTO enex_instalaciones
                (faena_id, codigo, nombre, tipo, linea, patente, ubicacion,
                 ultima_calibracion, frecuencia_meses, frecuencia_calibracion, orden)
            VALUES
                (v_cen, r[1], 'Aljibe ' || r[1], 'camion', 'combustible', r[1], r[2],
                 NULLIF(r[3],'')::DATE, 3, 'Trimestral · NCh 1436:2001', v_ord);
        ELSE
            -- si ya existe, completa ubicación / última calibración si faltan
            UPDATE enex_instalaciones
               SET ubicacion = COALESCE(ubicacion, r[2]),
                   ultima_calibracion = COALESCE(ultima_calibracion, NULLIF(r[3],'')::DATE)
             WHERE faena_id=v_cen AND UPPER(patente)=UPPER(r[1]);
        END IF;
    END LOOP;
END $$;


-- ── 4. Cargar el plan trimestral de Centinela (programaciones del período) ───
-- "las partes donde se hace mantenimiento": deja programado el trimestre activo
-- de cada instalación/camión de Centinela. Idempotente por (instalación,
-- servicio, período). Reglas de servicio por tipo:
--   eess/petrolera/semimovil → mantención + calibración
--   truck_shop               → mantención (lubricantes)
--   camion                   → calibración
-- El período de carga es el mes vigente del plan (julio 2026); las fechas por
-- día salen de la programación semanal que ya gestiona Manuel en el panel.
DO $$
DECLARE
    v_cen  UUID;
    v_anio INT := 2026;
    v_mes  INT := 7;
    i RECORD;
    v_uid UUID;
BEGIN
    SELECT id INTO v_cen FROM enex_faenas WHERE codigo='CENTINELA';
    SELECT id INTO v_uid FROM usuarios_perfil ORDER BY created_at LIMIT 1;

    FOR i IN SELECT id, tipo FROM enex_instalaciones WHERE faena_id=v_cen AND activo LOOP
        -- Mantención (todos menos camión)
        IF i.tipo IN ('eess','petrolera','semimovil','truck_shop') THEN
            IF NOT EXISTS (SELECT 1 FROM enex_programaciones
                            WHERE instalacion_id=i.id AND tipo_servicio='mantencion'
                              AND periodo_anio=v_anio AND periodo_mes=v_mes) THEN
                INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, observacion, creado_por)
                VALUES (i.id, 'mantencion', v_anio, v_mes, 'Plan trimestral Centinela (carga MIG234)', v_uid);
            END IF;
        END IF;
        -- Calibración (todos menos truck_shop)
        IF i.tipo IN ('eess','petrolera','semimovil','camion') THEN
            IF NOT EXISTS (SELECT 1 FROM enex_programaciones
                            WHERE instalacion_id=i.id AND tipo_servicio='calibracion'
                              AND periodo_anio=v_anio AND periodo_mes=v_mes) THEN
                INSERT INTO enex_programaciones (instalacion_id, tipo_servicio, periodo_anio, periodo_mes, observacion, creado_por)
                VALUES (i.id, 'calibracion', v_anio, v_mes, 'Plan trimestral Centinela (carga MIG234)', v_uid);
            END IF;
        END IF;
    END LOOP;
END $$;


-- ── 5. RECOBROS ──────────────────────────────────────────────────────────────
-- 2ª+ ejecución del mismo (instalación, tipo_servicio) dentro del mismo
-- trimestre contractual = recobro (facturable adicional a ENEX).
DROP VIEW IF EXISTS v_enex_recobros;
CREATE VIEW v_enex_recobros AS
WITH ej AS (
    SELECT e.id AS ejecucion_id, e.fecha_ejecucion, e.estado, e.ot_numero, e.ejecutor,
           e.created_at,
           p.id AS programacion_id, p.tipo_servicio,
           i.id AS instalacion_id, i.nombre AS instalacion, i.tipo AS instalacion_tipo,
           i.patente, i.linea,
           f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
           fn_enex_trimestre_key(e.fecha_ejecucion)   AS trimestre_key,
           fn_enex_trimestre_label(e.fecha_ejecucion) AS trimestre,
           ROW_NUMBER() OVER (
               PARTITION BY p.instalacion_id, p.tipo_servicio, fn_enex_trimestre_key(e.fecha_ejecucion)
               ORDER BY e.fecha_ejecucion, e.created_at) AS secuencia
    FROM enex_ejecuciones e
    JOIN enex_programaciones p ON p.id = e.programacion_id
    JOIN enex_instalaciones i  ON i.id = p.instalacion_id
    JOIN enex_faenas f         ON f.id = i.faena_id
    WHERE e.estado IN ('ejecutada','cumplida') AND e.fecha_ejecucion IS NOT NULL
)
SELECT *, (secuencia > 1) AS es_recobro FROM ej;
GRANT SELECT ON v_enex_recobros TO authenticated;

-- Chequeo puntual (para avisar en terreno / panel antes de ejecutar)
CREATE OR REPLACE FUNCTION rpc_enex_recobro_check(
    p_instalacion_id UUID, p_tipo_servicio TEXT, p_fecha DATE DEFAULT NULL, p_excluir_prog UUID DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
    SELECT jsonb_build_object(
        'previas', COUNT(*),
        'es_recobro', COUNT(*) > 0,
        'trimestre', fn_enex_trimestre_label(COALESCE(p_fecha, CURRENT_DATE)))
    FROM enex_ejecuciones e
    JOIN enex_programaciones p ON p.id = e.programacion_id
    WHERE p.instalacion_id = p_instalacion_id
      AND p.tipo_servicio  = p_tipo_servicio
      AND e.estado IN ('ejecutada','cumplida') AND e.fecha_ejecucion IS NOT NULL
      AND fn_enex_trimestre_key(e.fecha_ejecucion) = fn_enex_trimestre_key(COALESCE(p_fecha, CURRENT_DATE))
      AND (p_excluir_prog IS NULL OR p.id <> p_excluir_prog);
$$;
GRANT EXECUTE ON FUNCTION rpc_enex_recobro_check(UUID,TEXT,DATE,UUID) TO authenticated;

-- Vista de terreno: añadir es_recobro (¿el punto+servicio ya tiene ejecución en
-- el trimestre de esta programación?). Se recrea con la misma forma + 1 columna.
DROP VIEW IF EXISTS v_enex_terreno_pendientes;
CREATE VIEW v_enex_terreno_pendientes AS
SELECT pr.id AS programacion_id, pr.periodo_anio, pr.periodo_mes, pr.tipo_servicio, pr.fecha_programada,
       i.id AS instalacion_id, i.nombre AS instalacion, i.tipo AS instalacion_tipo, i.patente, i.linea,
       f.id AS faena_id, f.codigo AS faena_codigo, f.nombre AS faena,
       fn_enex_pauta_de_programacion(pr.id) AS pauta_id,
       (SELECT p.nombre FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_nombre,
       (SELECT p.es_borrador FROM enex_pautas p WHERE p.id = fn_enex_pauta_de_programacion(pr.id)) AS pauta_borrador,
       (SELECT COUNT(*) FROM enex_pauta_items it WHERE it.pauta_id = fn_enex_pauta_de_programacion(pr.id) AND it.activo) AS pauta_items,
       e.id AS ejecucion_id, e.estado, e.firma_mandante_url,
       (e.firma_mandante_url IS NOT NULL) AS cumplida,
       -- RECOBRO: ya existe otra ejecución del mismo punto+servicio en el mismo trimestre
       (EXISTS (
           SELECT 1 FROM enex_ejecuciones e2
           JOIN enex_programaciones p2 ON p2.id = e2.programacion_id
           WHERE p2.instalacion_id = pr.instalacion_id
             AND p2.tipo_servicio  = pr.tipo_servicio
             AND p2.id <> pr.id
             AND e2.estado IN ('ejecutada','cumplida') AND e2.fecha_ejecucion IS NOT NULL
             AND fn_enex_trimestre_key(e2.fecha_ejecucion)
                 = fn_enex_trimestre_key(COALESCE(pr.fecha_programada, make_date(pr.periodo_anio, pr.periodo_mes, 15)))
       )) AS es_recobro
FROM enex_programaciones pr
JOIN enex_instalaciones i ON i.id = pr.instalacion_id
JOIN enex_faenas f        ON f.id = i.faena_id
LEFT JOIN enex_ejecuciones e ON e.programacion_id = pr.id;
GRANT SELECT ON v_enex_terreno_pendientes TO authenticated;


-- ── 6. REPROGRAMACIÓN (registro formal para ENEX) ────────────────────────────
CREATE TABLE IF NOT EXISTS enex_reprogramaciones (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    programacion_id UUID REFERENCES enex_programaciones(id) ON DELETE SET NULL,
    faena_id       UUID REFERENCES enex_faenas(id),
    instalacion_id UUID REFERENCES enex_instalaciones(id),
    -- Datos capturados (denormalizados para el registro / PDF)
    faena          TEXT,
    instalacion    TEXT,
    patente        TEXT,
    tipo_activo    TEXT,                    -- eds / petrolera / semimovil / camion
    actividad      TEXT,                    -- mantencion / calibracion
    hora_ingreso   TEXT,
    supervisor_esm TEXT,
    tecnicos_pillado TEXT,
    -- Programación original
    fecha_original DATE,
    hora_original  TEXT,
    semana         TEXT,
    trimestre      TEXT,
    -- Motivo
    responsable    TEXT,                    -- mandante / operaciones_esm / pillado / cliente / otro
    causa          TEXT,                    -- equipo_no_disponible / prioridad_operacional / emergencia / falta_autorizacion / otro
    descripcion    TEXT,
    -- Nueva programación (a dónde se movió)
    nueva_fecha    DATE,
    nueva_hora     TEXT,
    -- Firmas / entrega
    firma_tecnico_url  TEXT,
    firma_esm_url      TEXT,
    firma_mandante_url TEXT,
    pdf_url        TEXT,                     -- registro entregado a ENEX
    creado_por     UUID REFERENCES usuarios_perfil(id),
    created_at     TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_enex_reprog_prog  ON enex_reprogramaciones(programacion_id);
CREATE INDEX IF NOT EXISTS idx_enex_reprog_fecha ON enex_reprogramaciones(created_at);
COMMENT ON TABLE enex_reprogramaciones IS 'Registro de reprogramación de actividades (formato ESM/PILLADO) entregable a ENEX. MIG234.';

ALTER TABLE enex_reprogramaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_reprog_sel ON enex_reprogramaciones;
CREATE POLICY pol_enex_reprog_sel ON enex_reprogramaciones FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);

-- Registrar reprogramación. Opcionalmente mueve la fecha de la programación.
CREATE OR REPLACE FUNCTION rpc_enex_reprogramar(
    p_programacion_id UUID,
    p_hora_ingreso TEXT DEFAULT NULL, p_supervisor_esm TEXT DEFAULT NULL, p_tecnicos_pillado TEXT DEFAULT NULL,
    p_responsable TEXT DEFAULT NULL, p_causa TEXT DEFAULT NULL, p_descripcion TEXT DEFAULT NULL,
    p_semana TEXT DEFAULT NULL, p_nueva_fecha DATE DEFAULT NULL, p_nueva_hora TEXT DEFAULT NULL,
    p_firma_tecnico_url TEXT DEFAULT NULL, p_firma_esm_url TEXT DEFAULT NULL, p_firma_mandante_url TEXT DEFAULT NULL,
    p_mover_fecha BOOLEAN DEFAULT true
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID; v_p RECORD;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    SELECT pr.id, pr.tipo_servicio, pr.fecha_programada, pr.periodo_anio, pr.periodo_mes,
           i.id AS instalacion_id, i.nombre AS instalacion, i.tipo, i.patente,
           f.id AS faena_id, f.nombre AS faena
      INTO v_p
      FROM enex_programaciones pr
      JOIN enex_instalaciones i ON i.id = pr.instalacion_id
      JOIN enex_faenas f        ON f.id = i.faena_id
     WHERE pr.id = p_programacion_id;
    IF v_p.id IS NULL THEN RAISE EXCEPTION 'Programación no existe'; END IF;
    IF NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN RAISE EXCEPTION 'Descripción del motivo obligatoria'; END IF;

    INSERT INTO enex_reprogramaciones (
        programacion_id, faena_id, instalacion_id, faena, instalacion, patente,
        tipo_activo, actividad, hora_ingreso, supervisor_esm, tecnicos_pillado,
        fecha_original, semana, trimestre, responsable, causa, descripcion,
        nueva_fecha, nueva_hora, firma_tecnico_url, firma_esm_url, firma_mandante_url, creado_por)
    VALUES (
        p_programacion_id, v_p.faena_id, v_p.instalacion_id, v_p.faena, v_p.instalacion, v_p.patente,
        CASE v_p.tipo WHEN 'eess' THEN 'eds' WHEN 'petrolera' THEN 'petrolera'
                      WHEN 'semimovil' THEN 'semimovil' WHEN 'camion' THEN 'camion' ELSE v_p.tipo END,
        v_p.tipo_servicio, p_hora_ingreso, p_supervisor_esm, p_tecnicos_pillado,
        v_p.fecha_programada, p_semana, fn_enex_trimestre_label(COALESCE(v_p.fecha_programada, make_date(v_p.periodo_anio, v_p.periodo_mes, 15))),
        p_responsable, p_causa, p_descripcion,
        p_nueva_fecha, p_nueva_hora, p_firma_tecnico_url, p_firma_esm_url, p_firma_mandante_url, auth.uid())
    RETURNING id INTO v_id;

    -- Mueve la fecha de la programación (misma programación, nueva fecha) si aplica.
    IF p_mover_fecha AND p_nueva_fecha IS NOT NULL THEN
        UPDATE enex_programaciones
           SET fecha_programada = p_nueva_fecha,
               observacion = COALESCE(observacion,'') ||
                   CASE WHEN COALESCE(observacion,'')='' THEN '' ELSE ' · ' END ||
                   'Reprogramada a ' || to_char(p_nueva_fecha,'DD-MM-YYYY')
         WHERE id = p_programacion_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'reprogramacion_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_reprogramar(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,DATE,TEXT,TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;

-- Guardar la URL del PDF generado (registro entregado a ENEX)
CREATE OR REPLACE FUNCTION rpc_enex_reprogramacion_set_pdf(p_id UUID, p_url TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    UPDATE enex_reprogramaciones SET pdf_url = p_url WHERE id = p_id;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_reprogramacion_set_pdf(UUID,TEXT) TO authenticated;

-- Vista de reprogramaciones (para la página de historial)
DROP VIEW IF EXISTS v_enex_reprogramaciones;
CREATE VIEW v_enex_reprogramaciones AS
SELECT r.*, up.nombre_completo AS creado_por_nombre
FROM enex_reprogramaciones r
LEFT JOIN usuarios_perfil up ON up.id = r.creado_por;
GRANT SELECT ON v_enex_reprogramaciones TO authenticated;


-- ── VALIDACIÓN ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'camiones_centinela', (SELECT COUNT(*) FROM enex_instalaciones i JOIN enex_faenas f ON f.id=i.faena_id
                            WHERE f.codigo='CENTINELA' AND i.tipo='camion'),
    'prog_centinela_jul', (SELECT COUNT(*) FROM enex_programaciones pr JOIN enex_instalaciones i ON i.id=pr.instalacion_id
                            JOIN enex_faenas f ON f.id=i.faena_id
                            WHERE f.codigo='CENTINELA' AND pr.periodo_anio=2026 AND pr.periodo_mes=7),
    'vistas', (SELECT array_agg(table_name ORDER BY table_name) FROM information_schema.views
                WHERE table_name IN ('v_enex_recobros','v_enex_reprogramaciones','v_enex_terreno_pendientes')),
    'reprog_tabla', (SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='enex_reprogramaciones')),
    'trim_may_jun_jul_igual', (SELECT fn_enex_trimestre_key('2026-05-10') = fn_enex_trimestre_key('2026-07-20')
                                   AND fn_enex_trimestre_key('2026-07-20') <> fn_enex_trimestre_key('2026-08-05')),
    'trim_label_jul', (SELECT fn_enex_trimestre_label('2026-07-20')),
    'rpcs', (SELECT array_agg(proname ORDER BY proname) FROM pg_proc WHERE proname IN
                ('rpc_enex_reprogramar','rpc_enex_recobro_check','rpc_enex_reprogramacion_set_pdf'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
