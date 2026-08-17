-- ============================================================================
-- SICOM-ICEO | 303 — Envío manual del reporte documental + resumen del rol
-- ============================================================================
-- Dos cosas:
--
--   1. Que prevención pueda ENVIAR el reporte cuando quiera, sin esperar al
--      cron. El aviso automático solo manda lo que toca por cadencia; para
--      responderle al mandante o llevar algo a una reunión hace falta mandar
--      la foto completa del momento.
--
--   2. Un resumen del estado de prevención para su dashboard, que hoy cae al
--      genérico y le muestra OT, ICEO e inventario —nada de su trabajo—.
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================


-- ############################################################################
-- 1. REPORTE COMPLETO PARA ENVIAR
-- ############################################################################
-- Diferencia con fn_prevencion_alertas_pendientes: esa devuelve solo lo que
-- toca avisar HOY según el escalamiento (y por eso puede venir vacía si ya se
-- avisó). Esta devuelve TODO lo que no está conforme en este momento, que es
-- lo que se manda cuando alguien pide "el estado documental".

DROP FUNCTION IF EXISTS fn_prevencion_reporte_envio(TEXT, BOOLEAN);
CREATE FUNCTION fn_prevencion_reporte_envio(
    p_faena TEXT DEFAULT NULL,
    p_incluir_vigentes BOOLEAN DEFAULT false
)
RETURNS TABLE (
    examen_id       UUID,
    rut             TEXT,
    persona         TEXT,
    empresa         TEXT,
    faena_codigo    TEXT,
    tipo_nombre     TEXT,
    laboratorio     TEXT,
    fecha_vencimiento DATE,
    dias_restantes  INTEGER,
    estado          TEXT,
    nivel           TEXT,
    observacion     TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT v.id,
           v.rut::TEXT,
           (v.nombres || ' ' || COALESCE(v.apellidos, ''))::TEXT,
           v.empresa::TEXT,
           v.faena_codigo::TEXT,
           v.tipo_nombre::TEXT,
           v.laboratorio::TEXT,
           v.fecha_vencimiento,
           v.dias_restantes::INTEGER,
           v.estado::TEXT,
           COALESCE(v.nivel_alerta, 'ninguno')::TEXT,
           v.observacion::TEXT
      FROM v_prevencion_examenes_estado v
     WHERE v.persona_activa
       AND (p_faena IS NULL OR v.faena_codigo = p_faena)
       -- Las exenciones nunca van al reporte: no son brecha.
       AND v.estado <> 'no_aplica'
       AND (p_incluir_vigentes
            OR v.estado IN ('vencido','sin_dato','observado','por_vencer_30','por_vencer_60'))
     ORDER BY CASE v.estado
                  WHEN 'vencido'       THEN 1
                  WHEN 'sin_dato'      THEN 2
                  WHEN 'observado'     THEN 3
                  WHEN 'por_vencer_30' THEN 4
                  WHEN 'por_vencer_60' THEN 5
                  ELSE 6 END,
              v.dias_restantes NULLS FIRST,
              v.apellidos, v.nombres;
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_reporte_envio(TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_reporte_envio(TEXT, BOOLEAN) IS
    'Estado documental completo para enviar por correo a pedido. MIG303.';


-- Versión para el servidor: valida el secreto en vez de la sesión, porque la
-- API corre sin usuario cuando arma el correo.
DROP FUNCTION IF EXISTS fn_prevencion_reporte_envio_cron(TEXT, TEXT, BOOLEAN);
CREATE FUNCTION fn_prevencion_reporte_envio_cron(
    p_secreto TEXT, p_faena TEXT DEFAULT NULL, p_incluir_vigentes BOOLEAN DEFAULT false
)
RETURNS TABLE (
    examen_id       UUID,
    rut             TEXT,
    persona         TEXT,
    empresa         TEXT,
    faena_codigo    TEXT,
    tipo_nombre     TEXT,
    laboratorio     TEXT,
    fecha_vencimiento DATE,
    dias_restantes  INTEGER,
    estado          TEXT,
    nivel           TEXT,
    observacion     TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY SELECT * FROM fn_prevencion_reporte_envio(p_faena, p_incluir_vigentes);
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_reporte_envio_cron(TEXT, TEXT, BOOLEAN) TO anon, authenticated;


-- ############################################################################
-- 2. BITÁCORA DE ENVÍOS MANUALES
-- ############################################################################
-- Quién mandó qué y a quién. Ante una discusión con el mandante ("nunca me
-- avisaron") esto es la prueba, y sin registro no existe.

CREATE TABLE IF NOT EXISTS prevencion_envios_manuales (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    faena_codigo  VARCHAR(60),
    destinatarios TEXT        NOT NULL,
    asunto        TEXT,
    total_items   INTEGER,
    vencidos      INTEGER,
    mensaje       TEXT,
    enviado_por   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    enviado_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE prevencion_envios_manuales IS
    'Registro de reportes documentales enviados a pedido. Evidencia de que se avisó. MIG303.';

CREATE INDEX IF NOT EXISTS idx_prev_envios_fecha
    ON prevencion_envios_manuales (enviado_at DESC);

ALTER TABLE prevencion_envios_manuales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_envios_select ON prevencion_envios_manuales;
CREATE POLICY prev_envios_select ON prevencion_envios_manuales
    FOR SELECT TO authenticated USING (fn_prevencion_personal_puede_ver());

GRANT SELECT ON prevencion_envios_manuales TO authenticated;


DROP FUNCTION IF EXISTS fn_prevencion_registrar_envio(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, UUID);
CREATE FUNCTION fn_prevencion_registrar_envio(
    p_secreto TEXT, p_faena TEXT, p_destinatarios TEXT, p_asunto TEXT,
    p_total INTEGER, p_vencidos INTEGER, p_mensaje TEXT DEFAULT NULL,
    p_enviado_por UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    INSERT INTO prevencion_envios_manuales (
        faena_codigo, destinatarios, asunto, total_items, vencidos, mensaje, enviado_por)
    VALUES (p_faena, p_destinatarios, p_asunto, p_total, p_vencidos, p_mensaje, p_enviado_por)
    RETURNING id INTO v_id;
    RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_registrar_envio(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, UUID) TO anon, authenticated;


-- ############################################################################
-- 3. RESUMEN PARA EL DASHBOARD DE PREVENCIÓN
-- ############################################################################
-- Lo que prevención necesita ver al entrar, en una sola llamada: su documental
-- de personal, sus equipos con papeles vencidos, sus recorridos pendientes y
-- los hallazgos abiertos.

DROP FUNCTION IF EXISTS fn_prevencion_dashboard();
CREATE FUNCTION fn_prevencion_dashboard()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out JSONB; v_uid UUID := auth.uid(); v_rol TEXT;
BEGIN
    IF NOT fn_prevencion_personal_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado.' USING ERRCODE = '42501';
    END IF;
    v_rol := fn_user_rol();

    SELECT jsonb_build_object(
        'generado_at', NOW(),

        -- ── Documental de personal ──
        'personal', (
            SELECT jsonb_build_object(
                'personas',     count(*),
                'no_conformes', count(*) FILTER (WHERE estado_general = 'no_conforme'),
                'observados',   count(*) FILTER (WHERE estado_general = 'observado'),
                'por_vencer',   count(*) FILTER (WHERE estado_general = 'por_vencer'),
                'conformes',    count(*) FILTER (WHERE estado_general = 'conforme'),
                'exam_vencidos',COALESCE(SUM(vencidos), 0),
                'exam_sin_dato',COALESCE(SUM(sin_dato), 0))
              FROM v_prevencion_personal_estado WHERE activo),

        -- Los 5 casos más urgentes, para actuar sin buscar.
        'personal_urgente', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'persona', persona, 'rut', rut, 'tipo', tipo_nombre,
                       'vence', fecha_vencimiento, 'dias', dias_restantes,
                       'estado', estado) ORDER BY dias_restantes NULLS FIRST)
              FROM (SELECT * FROM fn_prevencion_reporte_envio(NULL, false) LIMIT 5) s), '[]'::JSONB),

        -- ── Documental de equipos ──
        'equipos', (
            SELECT jsonb_build_object(
                'con_vencidos', count(DISTINCT activo_id) FILTER (WHERE vencidas > 0),
                'docs_vencidos', COALESCE(SUM(vencidas), 0),
                'por_vencer_30', COALESCE(SUM(por_vencer), 0))
              FROM (
                SELECT c.activo_id,
                       count(*) FILTER (WHERE c.fecha_vencimiento < CURRENT_DATE) vencidas,
                       count(*) FILTER (WHERE c.fecha_vencimiento >= CURRENT_DATE
                                          AND c.fecha_vencimiento <= CURRENT_DATE + 30) por_vencer
                  FROM v_certificacion_actual c
                 GROUP BY c.activo_id) t),

        -- ── Recorridos Gemba propios ──
        'recorridos', (
            SELECT jsonb_build_object(
                'mis_pendientes', (
                    SELECT count(*) FROM gemba_plantillas p
                     WHERE p.activo AND v_rol = ANY(p.roles)
                       AND NOT EXISTS (
                           SELECT 1 FROM gemba_recorridos r
                            WHERE r.plantilla_id = p.id
                              AND r.responsable_id = v_uid
                              AND r.fecha >= CURRENT_DATE
                                  - CASE p.cadencia WHEN 'diaria' THEN 1 WHEN 'semanal' THEN 7
                                                    WHEN 'quincenal' THEN 14 ELSE 30 END)),
                'del_mes', (
                    SELECT count(*) FROM gemba_recorridos
                     WHERE fecha >= date_trunc('month', CURRENT_DATE)),
                'hallazgos_abiertos', (
                    SELECT count(*) FROM gemba_hallazgos
                     WHERE COALESCE(estado, '') NOT IN ('cerrado','anulado')))),

        -- ── Último envío del reporte ──
        'ultimo_envio', (
            SELECT jsonb_build_object('at', enviado_at, 'faena', faena_codigo,
                                      'destinatarios', destinatarios)
              FROM prevencion_envios_manuales ORDER BY enviado_at DESC LIMIT 1)
    ) INTO v_out;

    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_dashboard() TO authenticated;

COMMENT ON FUNCTION fn_prevencion_dashboard() IS
    'Resumen del estado de prevención para su dashboard. MIG303.';
