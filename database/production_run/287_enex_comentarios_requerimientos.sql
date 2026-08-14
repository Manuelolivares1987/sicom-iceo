-- ============================================================================
-- SICOM-ICEO | 287 — Comentarios y requerimientos al mandante en el informe ENEX
-- ============================================================================
-- El informe deja constancia de lo que se hizo, pero no de lo que HAY QUE HACER.
-- Todo lo que el técnico detecta y excede el alcance de la visita (una manguera
-- por cambiar, un repuesto que hay que comprar, una autorización que falta)
-- terminaba contado de palabra o por WhatsApp: el mandante no lo veía escrito en
-- ninguna parte y después nadie podía probar que se avisó.
--
-- Ahora cada servicio lleva sus COMENTARIOS y REQUERIMIENTOS, y salen impresos
-- en el mismo documento que ESM/ENEX firma. Al firmar, el mandante da por
-- recibido el trabajo Y por informada la necesidad.
--
-- Reglas:
--   · comentario   → informativo, no pide nada;
--   · requerimiento→ pide una acción del mandante (autorizar, comprar, coordinar);
--   · se pueden escribir mientras el informe esté PENDIENTE de la firma de ESM.
--     Una vez que ESM recibió conforme, el documento queda cerrado: cambiarlo
--     sería alterar lo que alguien ya firmó;
--   · cualquier cambio invalida el PDF guardado, que se regenera.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tabla ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS enex_requerimientos (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ejecucion_id   UUID NOT NULL REFERENCES enex_ejecuciones(id) ON DELETE CASCADE,
    tipo           TEXT NOT NULL DEFAULT 'requerimiento',   -- comentario | requerimiento
    prioridad      TEXT NOT NULL DEFAULT 'media',           -- baja | media | alta
    titulo         TEXT,
    descripcion    TEXT NOT NULL,
    -- Actividad de la pauta que lo originó (opcional): permite decir "esto sale
    -- del ítem 3.2 que quedó NO CONFORME" en vez de un texto suelto.
    pauta_item_id  UUID REFERENCES enex_pauta_items(id) ON DELETE SET NULL,
    plazo          DATE,                                    -- fecha sugerida de atención
    orden          INT NOT NULL DEFAULT 0,
    creado_por     UUID REFERENCES usuarios_perfil(id),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enex_req_tipo_check') THEN
        ALTER TABLE enex_requerimientos ADD CONSTRAINT enex_req_tipo_check
            CHECK (tipo IN ('comentario','requerimiento'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'enex_req_prioridad_check') THEN
        ALTER TABLE enex_requerimientos ADD CONSTRAINT enex_req_prioridad_check
            CHECK (prioridad IN ('baja','media','alta'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_enex_req_ejec ON enex_requerimientos(ejecucion_id);

COMMENT ON TABLE enex_requerimientos IS
    'Comentarios y requerimientos al mandante que se imprimen en el informe ENEX firmable. MIG287.';
COMMENT ON COLUMN enex_requerimientos.tipo IS
    'comentario = informativo · requerimiento = pide una acción del mandante.';

ALTER TABLE enex_requerimientos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_enex_req_sel ON enex_requerimientos;
CREATE POLICY pol_enex_req_sel ON enex_requerimientos
    FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);
-- La escritura va solo por RPC (valida permiso + informe no firmado).


-- ── 2. Vista de consulta ────────────────────────────────────────────────────
DROP VIEW IF EXISTS v_enex_requerimientos;
CREATE VIEW v_enex_requerimientos AS
SELECT r.id, r.ejecucion_id, r.tipo, r.prioridad, r.titulo, r.descripcion,
       r.pauta_item_id, r.plazo, r.orden, r.created_at, r.updated_at,
       pi.codigo      AS item_codigo,
       pi.descripcion AS item_descripcion,
       up.nombre_completo AS creado_por_nombre,
       e.fecha_ejecucion, e.ot_numero,
       e.firma_mandante_url IS NOT NULL AS informe_firmado,
       p.tipo_servicio,
       i.id AS instalacion_id, i.nombre AS instalacion, i.patente,
       f.id AS faena_id, f.nombre AS faena
  FROM enex_requerimientos r
  JOIN enex_ejecuciones    e  ON e.id = r.ejecucion_id
  JOIN enex_programaciones p  ON p.id = e.programacion_id
  JOIN enex_instalaciones  i  ON i.id = p.instalacion_id
  JOIN enex_faenas         f  ON f.id = i.faena_id
  LEFT JOIN enex_pauta_items pi ON pi.id = r.pauta_item_id
  LEFT JOIN usuarios_perfil  up ON up.id = r.creado_por;
GRANT SELECT ON v_enex_requerimientos TO authenticated;


-- ── 3. Guardar (alta y edición) ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_requerimiento_guardar(
    p_id UUID DEFAULT NULL,
    p_ejecucion_id UUID DEFAULT NULL,
    p_tipo TEXT DEFAULT 'requerimiento',
    p_prioridad TEXT DEFAULT 'media',
    p_titulo TEXT DEFAULT NULL,
    p_descripcion TEXT DEFAULT NULL,
    p_pauta_item_id UUID DEFAULT NULL,
    p_plazo DATE DEFAULT NULL,
    p_orden INT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id UUID; v_ejec UUID; v_firmado BOOLEAN; v_orden INT;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    IF NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Escribe qué se necesita'; END IF;
    IF p_tipo NOT IN ('comentario','requerimiento') THEN RAISE EXCEPTION 'Tipo inválido'; END IF;
    IF p_prioridad NOT IN ('baja','media','alta') THEN RAISE EXCEPTION 'Prioridad inválida'; END IF;

    v_ejec := COALESCE(p_ejecucion_id, (SELECT ejecucion_id FROM enex_requerimientos WHERE id = p_id));
    IF v_ejec IS NULL THEN RAISE EXCEPTION 'Falta el servicio al que pertenece'; END IF;

    SELECT firma_mandante_url IS NOT NULL INTO v_firmado
      FROM enex_ejecuciones WHERE id = v_ejec;
    IF v_firmado IS NULL THEN RAISE EXCEPTION 'Servicio no encontrado'; END IF;
    -- Un informe ya recibido conforme no se toca: lo que ESM firmó es lo que ESM
    -- vio. Si aparece algo nuevo, va en el informe del próximo servicio.
    IF v_firmado THEN
        RAISE EXCEPTION 'El informe ya fue firmado por ESM: no se le pueden agregar ni cambiar requerimientos';
    END IF;

    IF p_id IS NULL THEN
        SELECT COALESCE(MAX(orden), 0) + 1 INTO v_orden FROM enex_requerimientos WHERE ejecucion_id = v_ejec;
        INSERT INTO enex_requerimientos (
            ejecucion_id, tipo, prioridad, titulo, descripcion, pauta_item_id, plazo, orden, creado_por)
        VALUES (v_ejec, p_tipo, p_prioridad, NULLIF(TRIM(COALESCE(p_titulo,'')),''),
                TRIM(p_descripcion), p_pauta_item_id, p_plazo, COALESCE(p_orden, v_orden), auth.uid())
        RETURNING id INTO v_id;
    ELSE
        UPDATE enex_requerimientos
           SET tipo = p_tipo, prioridad = p_prioridad,
               titulo = NULLIF(TRIM(COALESCE(p_titulo,'')),''),
               descripcion = TRIM(p_descripcion),
               pauta_item_id = p_pauta_item_id, plazo = p_plazo,
               orden = COALESCE(p_orden, orden), updated_at = now()
         WHERE id = p_id
        RETURNING id INTO v_id;
        IF v_id IS NULL THEN RAISE EXCEPTION 'Requerimiento no encontrado'; END IF;
    END IF;

    -- El PDF guardado ya no dice lo mismo que el servicio: se regenera.
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v_ejec;

    RETURN jsonb_build_object('success', true, 'requerimiento_id', v_id, 'ejecucion_id', v_ejec);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_requerimiento_guardar(UUID,UUID,TEXT,TEXT,TEXT,TEXT,UUID,DATE,INT)
    TO authenticated;


-- ── 4. Eliminar ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_enex_requerimiento_eliminar(p_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_ejec UUID; v_firmado BOOLEAN;
BEGIN
    IF NOT fn_enex_puede_gestionar() THEN RAISE EXCEPTION 'Sin permiso ENEX'; END IF;
    SELECT r.ejecucion_id, e.firma_mandante_url IS NOT NULL
      INTO v_ejec, v_firmado
      FROM enex_requerimientos r JOIN enex_ejecuciones e ON e.id = r.ejecucion_id
     WHERE r.id = p_id;
    IF v_ejec IS NULL THEN RAISE EXCEPTION 'Requerimiento no encontrado'; END IF;
    IF v_firmado THEN
        RAISE EXCEPTION 'El informe ya fue firmado por ESM: no se le pueden quitar requerimientos';
    END IF;

    DELETE FROM enex_requerimientos WHERE id = p_id;
    UPDATE enex_ejecuciones SET informe_pdf_url = NULL WHERE id = v_ejec;
    RETURN jsonb_build_object('success', true);
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_requerimiento_eliminar(UUID) TO authenticated;


-- ── 5. Quien va a firmar los ve antes de firmar ─────────────────────────────
-- Misma función de MIG277 + el bloque de comentarios y requerimientos. Es el
-- punto del cambio: que ESM lea la necesidad en la misma pantalla donde firma.
CREATE OR REPLACE FUNCTION rpc_enex_firma_datos(p_token TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_ejec UUID; v_tok RECORD; v_out JSONB;
BEGIN
    SELECT * INTO v_tok FROM enex_firma_tokens WHERE token = p_token;
    IF v_tok IS NULL THEN RETURN jsonb_build_object('ok', false, 'motivo', 'no_existe'); END IF;
    IF NOT v_tok.activo THEN RETURN jsonb_build_object('ok', false, 'motivo', 'revocado'); END IF;
    IF v_tok.expira_at <= now() THEN RETURN jsonb_build_object('ok', false, 'motivo', 'vencido'); END IF;
    v_ejec := v_tok.ejecucion_id;

    SELECT jsonb_build_object(
        'ok', true,
        'tipo', v_tok.tipo,
        'ya_firmado', CASE WHEN v_tok.tipo = 'tecnico'
                           THEN e.firma_tecnico_url IS NOT NULL
                           ELSE e.firma_mandante_url IS NOT NULL END,
        'firmante', CASE WHEN v_tok.tipo = 'tecnico'
                         THEN e.tecnico_nombre ELSE e.firmante_mandante_nombre END,
        'firmado_at', CASE WHEN v_tok.tipo = 'tecnico' THEN NULL ELSE e.firmante_mandante_at END,
        'firma_tecnico_lista',  e.firma_tecnico_url IS NOT NULL,
        'firma_mandante_lista', e.firma_mandante_url IS NOT NULL,
        'tecnico_nombre',  e.tecnico_nombre,
        'mandante_nombre', e.firmante_mandante_nombre,
        'fecha', e.fecha_ejecucion,
        'ot_numero', e.ot_numero,
        'observacion', e.observacion,
        'tecnico', COALESCE(e.tecnico_nombre, e.ejecutor),
        'instalacion', i.nombre,
        'faena', f.nombre,
        'tipo_servicio', p.tipo_servicio,
        'pauta', pa.nombre,
        'evidencia_urls', e.evidencia_urls,
        'actividades', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'codigo', pi.codigo, 'descripcion', pi.descripcion, 'bloque', pi.bloque,
                       'resultado', ei.resultado, 'valor', ei.valor_medicion, 'unidad', pi.unidad,
                       'observacion', ei.observacion,
                       'fotos_antes', ei.fotos_antes, 'fotos_despues', ei.fotos_despues)
                     ORDER BY pi.bloque_orden, pi.orden)
              FROM enex_ejecucion_items ei
              JOIN enex_pauta_items pi ON pi.id = ei.pauta_item_id
             WHERE ei.ejecucion_id = e.id
               AND pi.bloque NOT LIKE '0.%'), '[]'::jsonb),
        -- [MIG287] Lo que el mandante tiene que resolver, a la vista antes de firmar.
        'requerimientos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', r.id, 'tipo', r.tipo, 'prioridad', r.prioridad,
                       'titulo', r.titulo, 'descripcion', r.descripcion, 'plazo', r.plazo,
                       'item_codigo', ri.codigo, 'item_descripcion', ri.descripcion)
                     ORDER BY CASE r.tipo WHEN 'requerimiento' THEN 0 ELSE 1 END,
                              CASE r.prioridad WHEN 'alta' THEN 0 WHEN 'media' THEN 1 ELSE 2 END,
                              r.orden)
              FROM enex_requerimientos r
              LEFT JOIN enex_pauta_items ri ON ri.id = r.pauta_item_id
             WHERE r.ejecucion_id = e.id), '[]'::jsonb),
        'datos_servicio', COALESCE((
            SELECT jsonb_object_agg(pi.codigo, ei.observacion)
              FROM enex_ejecucion_items ei
              JOIN enex_pauta_items pi ON pi.id = ei.pauta_item_id
             WHERE ei.ejecucion_id = e.id AND pi.codigo LIKE 'DS.%'
               AND ei.observacion IS NOT NULL), '{}'::jsonb)
    ) INTO v_out
      FROM enex_ejecuciones e
      JOIN enex_programaciones p ON p.id = e.programacion_id
      JOIN enex_instalaciones i ON i.id = p.instalacion_id
      JOIN enex_faenas f ON f.id = i.faena_id
      LEFT JOIN enex_pautas pa ON pa.id = e.pauta_id
     WHERE e.id = v_ejec;

    UPDATE enex_firma_tokens SET usos = usos + 1 WHERE id = v_tok.id;
    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION rpc_enex_firma_datos(TEXT) TO anon, authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
SELECT 'MIG287 OK' AS resultado,
       (SELECT count(*) FROM enex_requerimientos) AS requerimientos,
       (SELECT count(*) FROM pg_proc WHERE proname = 'rpc_enex_requerimiento_guardar') AS rpc_guardar,
       (SELECT count(*) FROM pg_proc WHERE proname = 'rpc_enex_requerimiento_eliminar') AS rpc_eliminar,
       (SELECT count(*) FROM pg_views WHERE viewname = 'v_enex_requerimientos') AS vista;
