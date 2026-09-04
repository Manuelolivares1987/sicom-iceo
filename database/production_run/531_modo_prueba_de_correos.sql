-- ============================================================================
-- MIG531 · Modo PRUEBA de los correos: se activan de verdad, sin tocar nada
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Quiero ver si es que activa correo, todo, pero que no afecte al sistema,
-- ni estadística ni nada.»
--
-- Las funciones de correo ganan p_incluir_pruebas (default false):
--   · false (los crons reales): SOLO equipos reales — el laboratorio nunca
--     aparece en el correo de los destinatarios de verdad (regla MIG530).
--   · true (modo prueba): SOLO el equipo es_prueba — la ruta en modo prueba
--     manda ese correo únicamente a Manuel con asunto [PRUEBA].
-- Y se siembra una RT «por vencer» en PRUEBA-01 para que el correo de
-- revisión técnica tenga qué mostrar (el checklist del cliente ya está
-- pendiente por sí solo: el equipo nunca lo ha hecho).
-- ============================================================================

BEGIN;

-- ── 1 · fn_rt_por_vencer_cron con modo prueba ───────────────────────────────
DROP FUNCTION IF EXISTS fn_rt_por_vencer_cron(TEXT);
CREATE FUNCTION fn_rt_por_vencer_cron(p_secreto TEXT, p_incluir_pruebas BOOLEAN DEFAULT false)
RETURNS TABLE (
    activo_id         UUID,
    patente           TEXT,
    codigo            TEXT,
    nombre            TEXT,
    cliente           TEXT,
    zona              TEXT,
    faena             TEXT,
    fecha_vencimiento DATE,
    dias_restantes    INT,
    estado            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    SELECT a.id,
           a.patente::TEXT, a.codigo::TEXT, a.nombre::TEXT,
           a.cliente_actual::TEXT,
           COALESCE(NULLIF(TRIM(a.operacion::TEXT), ''), 'Sin zona') AS zona,
           COALESCE(f.nombre::TEXT, NULLIF(a.ubicacion_actual::TEXT, '')) AS faena,
           c.fecha_vencimiento,
           c.dias_restantes::INT,
           c.estado_real::TEXT
      FROM v_certificacion_actual c
      JOIN activos a ON a.id = c.activo_id AND a.fecha_baja IS NULL
      LEFT JOIN faenas f ON f.id = a.faena_id
     WHERE c.tipo::TEXT = 'revision_tecnica'
       AND c.estado_real IN ('vencido', 'por_vencer')
       -- [MIG531] Modo prueba: SOLO el laboratorio. Modo real: NUNCA el laboratorio.
       AND (CASE WHEN p_incluir_pruebas THEN COALESCE(a.es_prueba, false)
                 ELSE NOT COALESCE(a.es_prueba, false) END)
     ORDER BY 6, (c.estado_real = 'vencido') DESC, c.dias_restantes NULLS FIRST, a.patente;
END;
$$;

REVOKE ALL ON FUNCTION fn_rt_por_vencer_cron(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_rt_por_vencer_cron(TEXT, BOOLEAN) TO anon, authenticated;

-- ── 2 · fn_checklist_cliente_pendientes_cron con modo prueba ────────────────
DROP FUNCTION IF EXISTS fn_checklist_cliente_pendientes_cron(TEXT);
CREATE FUNCTION fn_checklist_cliente_pendientes_cron(p_secreto TEXT, p_incluir_pruebas BOOLEAN DEFAULT false)
RETURNS TABLE (
    activo_id         UUID,
    patente           TEXT,
    codigo            TEXT,
    nombre            TEXT,
    cliente           TEXT,
    estado_comercial  TEXT,
    ultima_fecha      DATE,
    dias_desde_ultimo INT,
    estado            TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT fn_sistema_secreto_valido('cron_alertas', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido';
    END IF;
    RETURN QUERY
    SELECT v.activo_id,
           v.patente::TEXT, v.codigo::TEXT, v.nombre::TEXT, v.cliente::TEXT,
           v.estado_comercial::TEXT,
           v.ultima_fecha, v.dias_desde_ultimo::INT,
           v.estado_cumplimiento::TEXT
      FROM v_checklist_cliente_cumplimiento v
     WHERE v.estado_cumplimiento <> 'al_dia'
       -- [MIG531] Modo prueba: SOLO el laboratorio. Modo real: NUNCA el laboratorio.
       AND (CASE WHEN p_incluir_pruebas
                 THEN EXISTS (SELECT 1 FROM activos ax WHERE ax.id = v.activo_id AND ax.es_prueba)
                 ELSE NOT EXISTS (SELECT 1 FROM activos ax WHERE ax.id = v.activo_id AND ax.es_prueba) END)
     ORDER BY (v.estado_cumplimiento = 'sin_check') DESC,
              v.dias_desde_ultimo DESC NULLS FIRST,
              v.cliente NULLS LAST, v.patente;
END;
$$;

REVOKE ALL ON FUNCTION fn_checklist_cliente_pendientes_cron(TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_checklist_cliente_pendientes_cron(TEXT, BOOLEAN) TO anon, authenticated;

-- ── 3 · Una RT «por vencer» de laboratorio, para que el correo tenga qué decir
DO $mig$
DECLARE v_activo UUID;
BEGIN
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    IF v_activo IS NULL THEN RAISE EXCEPTION 'FALLO: no existe TEST-01'; END IF;
    IF NOT EXISTS (SELECT 1 FROM certificaciones
                    WHERE activo_id = v_activo AND tipo::TEXT = 'revision_tecnica'
                      AND anulado_at IS NULL) THEN
        INSERT INTO certificaciones (activo_id, tipo, fecha_emision, fecha_vencimiento,
                                     numero_certificado, entidad_certificadora, bloqueante,
                                     fecha_origen, notas)
        VALUES (v_activo, 'revision_tecnica', CURRENT_DATE - 353, CURRENT_DATE + 12,
                'RT-PRUEBA', 'PLANTA DE PRUEBA', false,
                'manual', 'RT de laboratorio (MIG531): existe para probar el correo de revisión técnica.');
        RAISE NOTICE 'RT de prueba sembrada: vence en 12 días';
    END IF;
END $mig$;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_cmd TEXT; v_sec TEXT; v_real INT; v_prueba INT;
BEGIN
    SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'revision-tecnica-por-vencer';
    v_sec := substring(v_cmd FROM 'x-cron-secret'', ''([^'']+)');
    IF v_sec IS NULL THEN RAISE EXCEPTION 'FALLO: no está el cron de RT'; END IF;

    SELECT count(*) FILTER (WHERE codigo = 'TEST-01') INTO v_real FROM fn_rt_por_vencer_cron(v_sec);
    SELECT count(*) INTO v_prueba FROM fn_rt_por_vencer_cron(v_sec, true);
    RAISE NOTICE 'RT: modo real trae TEST-01 % veces (debe ser 0) · modo prueba trae % fila(s) (debe ser 1)', v_real, v_prueba;
    IF v_real <> 0 OR v_prueba <> 1 THEN RAISE EXCEPTION 'FALLO: el modo prueba de RT no separa bien'; END IF;

    SELECT count(*) FILTER (WHERE codigo = 'TEST-01') INTO v_real FROM fn_checklist_cliente_pendientes_cron(v_sec);
    SELECT count(*) INTO v_prueba FROM fn_checklist_cliente_pendientes_cron(v_sec, true);
    RAISE NOTICE 'Checklist: modo real trae TEST-01 % veces (debe ser 0) · modo prueba % fila(s) (debe ser 1)', v_real, v_prueba;
    IF v_real <> 0 OR v_prueba <> 1 THEN RAISE EXCEPTION 'FALLO: el modo prueba de checklist no separa bien'; END IF;

    RAISE NOTICE 'MIG531 OK · correos con modo prueba: lo real jamás ve el laboratorio, y viceversa';
END
$mig$;

COMMIT;
