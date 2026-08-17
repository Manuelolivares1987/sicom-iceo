-- ============================================================================
-- SICOM-ICEO | 299 — Renovación de exámenes con archivo + alertas escaladas
-- ============================================================================
-- Tres cosas sobre el control documental de personal (MIG298):
--
--   1. Renovar un examen SUBIENDO el respaldo, con historial de versiones.
--   2. Alerta desde 60 días, subiendo la frecuencia a medida que se acerca.
--   3. Cola de correo para que el aviso llegue solo.
--
-- ── EL ARCHIVO VA A UN BUCKET PRIVADO ──────────────────────────────────────
-- Un examen ocupacional es un dato de SALUD de una persona identificada. El
-- bucket `documentos` que usa el resto del sistema es PÚBLICO: cualquiera con
-- la URL abre el archivo, sin login. Poner ahí un examen de alcohol y drogas
-- sería exponer datos sensibles de los trabajadores.
-- Se crea `examenes-personal`, privado, y se lee con URL firmada temporal
-- (mismo patrón que `informes-tecnicos`).
--
-- ── POR QUÉ EL HISTORIAL NO SE PISA ────────────────────────────────────────
-- Al renovar, el examen anterior NO se borra: pasa a `prevencion_examen_historial`.
-- Ante una fiscalización la pregunta no es solo "¿está vigente hoy?" sino
-- "¿estuvo vigente en la fecha del incidente?". Sin historial esa pregunta no
-- se puede responder.
--
-- ── ESCALAMIENTO ───────────────────────────────────────────────────────────
-- Avisar todos los días desde 60 días antes entrena a la gente a ignorar el
-- correo. Avisar una sola vez hace que se pase por alto. La cadencia sube a
-- medida que el vencimiento se acerca:
--
--     60 a 31 días  →  1 vez por semana   (los lunes)
--     30 a 15 días  →  cada 3 días
--     14 a  8 días  →  día por medio
--      7 a  1 días  →  todos los días
--     vencido        →  todos los días, y no para hasta que se renueve
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================


-- ############################################################################
-- 1. BUCKET PRIVADO PARA LOS RESPALDOS
-- ############################################################################

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('examenes-personal', 'examenes-personal', false, 10485760)
ON CONFLICT (id) DO UPDATE SET public = false;   -- nunca público, ni por error

-- Solo quien puede ver/editar el control documental toca estos archivos.
DROP POLICY IF EXISTS exam_personal_storage_select ON storage.objects;
CREATE POLICY exam_personal_storage_select ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'examenes-personal' AND fn_prevencion_personal_puede_ver());

DROP POLICY IF EXISTS exam_personal_storage_insert ON storage.objects;
CREATE POLICY exam_personal_storage_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'examenes-personal' AND fn_prevencion_personal_puede_editar());

DROP POLICY IF EXISTS exam_personal_storage_update ON storage.objects;
CREATE POLICY exam_personal_storage_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (bucket_id = 'examenes-personal' AND fn_prevencion_personal_puede_editar());


-- ############################################################################
-- 2. HISTORIAL DE VERSIONES
-- ############################################################################

CREATE TABLE IF NOT EXISTS prevencion_examen_historial (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    examen_id      UUID        NOT NULL REFERENCES prevencion_examenes(id) ON DELETE CASCADE,
    personal_id    UUID        NOT NULL REFERENCES prevencion_personal(id) ON DELETE CASCADE,
    tipo_codigo    VARCHAR(40) NOT NULL,

    -- Estado del examen ANTES de la renovación.
    laboratorio        VARCHAR(160),
    fecha_vencimiento  DATE,
    observacion        TEXT,
    archivo_path       TEXT,

    reemplazado_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reemplazado_por    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    motivo             TEXT
);

COMMENT ON TABLE prevencion_examen_historial IS
    'Versiones anteriores de cada examen. Permite responder "¿estaba vigente el día del incidente?". MIG299.';

CREATE INDEX IF NOT EXISTS idx_prev_hist_examen
    ON prevencion_examen_historial (examen_id, reemplazado_at DESC);

ALTER TABLE prevencion_examen_historial ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_hist_select ON prevencion_examen_historial;
CREATE POLICY prev_hist_select ON prevencion_examen_historial
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

GRANT SELECT ON prevencion_examen_historial TO authenticated;


-- Path del archivo (el bucket es privado, así que se guarda el path, no la URL:
-- las URLs firmadas caducan y guardar una vencida es guardar basura).
ALTER TABLE prevencion_examenes
    ADD COLUMN IF NOT EXISTS archivo_path   TEXT,
    ADD COLUMN IF NOT EXISTS archivo_nombre TEXT,
    ADD COLUMN IF NOT EXISTS fecha_emision_real DATE,
    ADD COLUMN IF NOT EXISTS renovado_at    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS renovado_por   UUID REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON COLUMN prevencion_examenes.archivo_path IS
    'Path en el bucket privado examenes-personal. Se sirve con URL firmada. MIG299.';


-- ############################################################################
-- 3. REGISTRO DE AVISOS YA ENVIADOS
-- ############################################################################
-- Va antes del RPC de renovar porque renovar limpia esta tabla (reinicia el
-- ciclo de avisos del examen).

CREATE TABLE IF NOT EXISTS prevencion_alertas_enviadas (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    examen_id    UUID        NOT NULL REFERENCES prevencion_examenes(id) ON DELETE CASCADE,
    enviada_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    dias_restantes INTEGER,
    nivel        VARCHAR(20),
    destinatarios TEXT
);

COMMENT ON TABLE prevencion_alertas_enviadas IS
    'Registro de avisos ya enviados por examen: evita repetir el mismo día y sostiene el escalamiento. MIG299.';

CREATE INDEX IF NOT EXISTS idx_prev_alertas_examen
    ON prevencion_alertas_enviadas (examen_id, enviada_at DESC);

ALTER TABLE prevencion_alertas_enviadas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_alertas_select ON prevencion_alertas_enviadas;
CREATE POLICY prev_alertas_select ON prevencion_alertas_enviadas
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

GRANT SELECT ON prevencion_alertas_enviadas TO authenticated;


-- ############################################################################
-- 4. RENOVAR UN EXAMEN
-- ############################################################################
-- Un solo RPC: archiva la versión anterior y deja la nueva vigente. El
-- frontend sube el archivo al bucket y pasa el path; la base no ve el binario.

DROP FUNCTION IF EXISTS fn_prevencion_renovar_examen(UUID, DATE, DATE, TEXT, TEXT, TEXT, TEXT);
CREATE FUNCTION fn_prevencion_renovar_examen(
    p_examen_id        UUID,
    p_fecha_vencimiento DATE,
    p_fecha_emision    DATE DEFAULT NULL,
    p_laboratorio      TEXT DEFAULT NULL,
    p_archivo_path     TEXT DEFAULT NULL,
    p_archivo_nombre   TEXT DEFAULT NULL,
    p_observacion      TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_prev prevencion_examenes%ROWTYPE;
    v_new  prevencion_examenes%ROWTYPE;
BEGIN
    IF NOT fn_prevencion_personal_puede_editar() THEN
        RAISE EXCEPTION 'No autorizado para renovar exámenes.' USING ERRCODE = '42501';
    END IF;
    IF p_fecha_vencimiento IS NULL THEN
        RAISE EXCEPTION 'La fecha de vencimiento del nuevo examen es obligatoria.'
            USING ERRCODE = '23514';
    END IF;
    -- Un examen que ya nace vencido no es una renovación: es un error de tipeo,
    -- y dejarlo pasar apagaría la alerta sin que nadie renueve nada.
    IF p_fecha_vencimiento <= CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de vencimiento (%) no puede ser hoy ni pasada.', p_fecha_vencimiento
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_prev FROM prevencion_examenes WHERE id = p_examen_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El examen no existe.' USING ERRCODE = 'P0002';
    END IF;

    -- Se archiva la versión anterior solo si tenía contenido.
    IF v_prev.fecha_vencimiento IS NOT NULL OR v_prev.archivo_path IS NOT NULL THEN
        INSERT INTO prevencion_examen_historial (
            examen_id, personal_id, tipo_codigo, laboratorio,
            fecha_vencimiento, observacion, archivo_path, reemplazado_por, motivo)
        VALUES (v_prev.id, v_prev.personal_id, v_prev.tipo_codigo, v_prev.laboratorio,
                v_prev.fecha_vencimiento, v_prev.observacion, v_prev.archivo_path,
                auth.uid(), 'Renovación');
    END IF;

    UPDATE prevencion_examenes SET
        fecha_vencimiento  = p_fecha_vencimiento,
        fecha_emision_real = COALESCE(p_fecha_emision, fecha_emision_real),
        laboratorio        = COALESCE(NULLIF(trim(p_laboratorio), ''), laboratorio),
        archivo_path       = COALESCE(p_archivo_path, archivo_path),
        archivo_nombre     = COALESCE(p_archivo_nombre, archivo_nombre),
        observacion        = NULLIF(trim(COALESCE(p_observacion, '')), ''),
        -- Renovar limpia el bloqueo del mandante: si el examen nuevo también
        -- viniera de un laboratorio no aceptado, se vuelve a marcar a mano.
        observacion_bloqueante = false,
        aplica             = true,
        renovado_at        = NOW(),
        renovado_por       = auth.uid()
     WHERE id = p_examen_id
    RETURNING * INTO v_new;

    -- La renovación reinicia el ciclo de avisos.
    DELETE FROM prevencion_alertas_enviadas WHERE examen_id = p_examen_id;

    RETURN to_jsonb(v_new);
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_renovar_examen(UUID, DATE, DATE, TEXT, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_renovar_examen IS
    'Renueva un examen archivando la versión anterior y reiniciando sus alertas. MIG299.';


-- ############################################################################
-- 5. ALERTAS ESCALADAS
-- ############################################################################




-- ── Nivel de urgencia y cadencia ───────────────────────────────────────────
-- Una sola función define el escalamiento, para que pantalla y correo no
-- puedan discrepar sobre qué es "crítico".
CREATE OR REPLACE FUNCTION fn_prevencion_nivel_alerta(p_dias INTEGER)
RETURNS TABLE (nivel TEXT, cada_dias INTEGER)
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
               WHEN p_dias IS NULL   THEN 'sin_dato'
               WHEN p_dias <  0      THEN 'vencido'
               WHEN p_dias <= 7      THEN 'critico'
               WHEN p_dias <= 14     THEN 'urgente'
               WHEN p_dias <= 30     THEN 'alto'
               WHEN p_dias <= 60     THEN 'medio'
               ELSE 'ninguno'
           END,
           CASE
               WHEN p_dias IS NULL   THEN 7    -- sin dato: recordatorio semanal
               WHEN p_dias <  0      THEN 1    -- vencido: todos los días
               WHEN p_dias <= 7      THEN 1
               WHEN p_dias <= 14     THEN 2
               WHEN p_dias <= 30     THEN 3
               WHEN p_dias <= 60     THEN 7
               ELSE NULL                        -- fuera de ventana: no se avisa
           END;
$$;

COMMENT ON FUNCTION fn_prevencion_nivel_alerta(INTEGER) IS
    'Nivel de urgencia y cada cuántos días avisar. Ventana: 60 días. MIG299.';


-- ── Qué toca avisar hoy ────────────────────────────────────────────────────
-- Devuelve solo los exámenes cuyo último aviso ya cumplió su cadencia. El cron
-- puede correr todos los días sin que nadie reciba correo de más.
DROP FUNCTION IF EXISTS fn_prevencion_alertas_pendientes();
CREATE FUNCTION fn_prevencion_alertas_pendientes()
RETURNS TABLE (
    examen_id       UUID,
    personal_id     UUID,
    rut             TEXT,
    persona         TEXT,
    empresa         TEXT,
    faena_codigo    TEXT,
    tipo_nombre     TEXT,
    laboratorio     TEXT,
    fecha_vencimiento DATE,
    dias_restantes  INTEGER,
    nivel           TEXT,
    cada_dias       INTEGER,
    ultima_alerta   TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT e.id,
           p.id,
           p.rut::TEXT,
           (p.nombres || ' ' || COALESCE(p.apellidos, ''))::TEXT,
           p.empresa::TEXT,
           p.faena_codigo::TEXT,
           t.nombre::TEXT,
           e.laboratorio::TEXT,
           e.fecha_vencimiento,
           (e.fecha_vencimiento - CURRENT_DATE)::INTEGER,
           n.nivel,
           n.cada_dias,
           ult.enviada_at
      FROM prevencion_examenes e
      JOIN prevencion_personal p     ON p.id = e.personal_id AND p.activo
      JOIN prevencion_examen_tipos t ON t.codigo = e.tipo_codigo
      CROSS JOIN LATERAL fn_prevencion_nivel_alerta(
                     (e.fecha_vencimiento - CURRENT_DATE)::INTEGER) n
      LEFT JOIN LATERAL (
          SELECT a.enviada_at FROM prevencion_alertas_enviadas a
           WHERE a.examen_id = e.id ORDER BY a.enviada_at DESC LIMIT 1
      ) ult ON true
     WHERE e.aplica                       -- las exenciones no generan alerta
       AND n.cada_dias IS NOT NULL        -- fuera de la ventana de 60 días
       AND (ult.enviada_at IS NULL
            OR ult.enviada_at < NOW() - (n.cada_dias || ' days')::INTERVAL)
     ORDER BY (e.fecha_vencimiento - CURRENT_DATE) NULLS FIRST, p.apellidos;
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_alertas_pendientes() TO authenticated, service_role;

COMMENT ON FUNCTION fn_prevencion_alertas_pendientes() IS
    'Exámenes que toca avisar hoy según el escalamiento. Idempotente por día. MIG299.';


-- Marca los avisos como enviados. Lo llama la API después de que el correo
-- salió: si el envío falla, no se marca y se reintenta al día siguiente.
DROP FUNCTION IF EXISTS fn_prevencion_marcar_alertas(UUID[], TEXT);
CREATE FUNCTION fn_prevencion_marcar_alertas(p_ids UUID[], p_destinatarios TEXT DEFAULT NULL)
RETURNS INTEGER
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
    WITH ins AS (
        INSERT INTO prevencion_alertas_enviadas (examen_id, dias_restantes, nivel, destinatarios)
        SELECT e.id,
               (e.fecha_vencimiento - CURRENT_DATE)::INTEGER,
               n.nivel,
               p_destinatarios
          FROM prevencion_examenes e
          CROSS JOIN LATERAL fn_prevencion_nivel_alerta(
                         (e.fecha_vencimiento - CURRENT_DATE)::INTEGER) n
         WHERE e.id = ANY(p_ids)
        RETURNING 1)
    SELECT count(*)::INTEGER FROM ins;
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_marcar_alertas(UUID[], TEXT) TO service_role;

COMMENT ON FUNCTION fn_prevencion_marcar_alertas(UUID[], TEXT) IS
    'Registra los avisos efectivamente enviados. Solo service_role (lo llama el cron). MIG299.';


-- ############################################################################
-- 6. LA VISTA EXPONE EL RESPALDO
-- ############################################################################
-- v_prevencion_examenes_estado se creó en MIG298, antes de que existieran las
-- columnas de archivo. Se agregan AL FINAL (CREATE OR REPLACE VIEW solo admite
-- columnas nuevas al final, no reordenar las existentes).

CREATE OR REPLACE VIEW v_prevencion_examenes_estado AS
SELECT e.id,
       e.personal_id,
       p.rut, p.nombres, p.apellidos, p.empresa, p.nro_contrato,
       p.faena_codigo, p.activo AS persona_activa,
       e.tipo_codigo, t.nombre AS tipo_nombre, t.categoria, t.orden,
       e.laboratorio, e.fecha_vencimiento, e.aplica, e.motivo_no_aplica,
       e.observacion, e.observacion_bloqueante, e.archivo_url,
       (e.fecha_vencimiento - CURRENT_DATE) AS dias_restantes,
       CASE
           WHEN NOT e.aplica                          THEN 'no_aplica'
           WHEN e.observacion_bloqueante              THEN 'observado'
           WHEN e.fecha_vencimiento IS NULL           THEN 'sin_dato'
           WHEN e.fecha_vencimiento <  CURRENT_DATE   THEN 'vencido'
           WHEN e.fecha_vencimiento <= CURRENT_DATE + 30 THEN 'por_vencer_30'
           WHEN e.fecha_vencimiento <= CURRENT_DATE + 60 THEN 'por_vencer_60'
           ELSE 'vigente'
       END AS estado,
       -- ── nuevas en MIG299 ──
       e.archivo_path,
       e.archivo_nombre,
       e.renovado_at,
       e.fecha_emision_real,
       (SELECT count(*) FROM prevencion_examen_historial h WHERE h.examen_id = e.id)::INTEGER
           AS versiones_anteriores,
       (SELECT n.nivel FROM fn_prevencion_nivel_alerta(
                (e.fecha_vencimiento - CURRENT_DATE)::INTEGER) n) AS nivel_alerta
  FROM prevencion_examenes e
  JOIN prevencion_personal p    ON p.id = e.personal_id
  JOIN prevencion_examen_tipos t ON t.codigo = e.tipo_codigo;
