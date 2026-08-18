-- ============================================================================
-- SICOM-ICEO | 304 — El semáforo de pantalla se alinea con el escalamiento
-- ============================================================================
-- BUG. La pantalla mostraba "≤30 días" tanto para quien vence en 28 como para
-- quien vence en 4. El correo sí distinguía —`fn_prevencion_nivel_alerta` los
-- separa en critico(≤7) / urgente(≤14) / alto(≤30) / medio(≤60)— pero la vista
-- `v_prevencion_examenes_estado` tenía su propia escala, más gruesa.
--
-- Dos fuentes de verdad para lo mismo. El resultado real hoy: Pablo Astorga
-- con el psicosensotécnico Y la licencia de planta venciendo en 4 días, y
-- Felipe López con tres exámenes en 5 días, se veían en pantalla igual que
-- alguien con casi un mes por delante. Quien mira el tablero no tiene forma de
-- saber a quién llamar primero.
--
-- Se corrige derivando el estado de la MISMA función que usa el correo. Si
-- mañana se cambia la cadencia, pantalla y correo se mueven juntos.
--
-- ADITIVA (redefine vistas y una función; no toca datos).
-- ============================================================================


-- ############################################################################
-- 1. LA VISTA DERIVA SU ESTADO DEL ESCALAMIENTO
-- ############################################################################
-- Los estados nuevos son `por_vencer_7` y `por_vencer_14`. Se conservan
-- `por_vencer_30` y `por_vencer_60` con el mismo nombre para no romper lo que
-- ya los lee.

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
           WHEN NOT e.aplica                 THEN 'no_aplica'
           WHEN e.observacion_bloqueante     THEN 'observado'
           WHEN e.fecha_vencimiento IS NULL  THEN 'sin_dato'
           ELSE CASE n.nivel
                    WHEN 'vencido' THEN 'vencido'
                    WHEN 'critico' THEN 'por_vencer_7'
                    WHEN 'urgente' THEN 'por_vencer_14'
                    WHEN 'alto'    THEN 'por_vencer_30'
                    WHEN 'medio'   THEN 'por_vencer_60'
                    ELSE 'vigente'
                END
       END AS estado,
       e.archivo_path,
       e.archivo_nombre,
       e.renovado_at,
       e.fecha_emision_real,
       (SELECT count(*) FROM prevencion_examen_historial h WHERE h.examen_id = e.id)::INTEGER
           AS versiones_anteriores,
       n.nivel AS nivel_alerta
  FROM prevencion_examenes e
  JOIN prevencion_personal p     ON p.id = e.personal_id
  JOIN prevencion_examen_tipos t ON t.codigo = e.tipo_codigo
  -- La MISMA función que decide la cadencia del correo decide el color de la
  -- pantalla. Una sola fuente de verdad.
  CROSS JOIN LATERAL fn_prevencion_nivel_alerta(
                 (e.fecha_vencimiento - CURRENT_DATE)::INTEGER) n;

COMMENT ON VIEW v_prevencion_examenes_estado IS
    'Semáforo por examen, derivado de fn_prevencion_nivel_alerta para que pantalla y correo no discrepen. MIG304.';


-- ############################################################################
-- 2. EL ESTADO DE LA PERSONA GANA UN NIVEL "CRÍTICO"
-- ############################################################################
-- Antes, alguien con un examen venciendo en 4 días quedaba como 'por_vencer',
-- el mismo cajón que alguien con 28. Ahora 'critico' se separa, y va por
-- encima de 'observado': un papel que vence esta semana apremia más que uno
-- con fecha lejana que el mandante no acepta.

CREATE OR REPLACE VIEW v_prevencion_personal_estado AS
SELECT p.id AS personal_id, p.rut, p.nombres, p.apellidos, p.empresa,
       p.nro_contrato, p.faena_codigo, p.cargo, p.activo, p.observacion,
       count(*) FILTER (WHERE v.estado = 'vencido')::INTEGER       AS vencidos,
       count(*) FILTER (WHERE v.estado = 'observado')::INTEGER     AS observados,
       count(*) FILTER (WHERE v.estado = 'sin_dato')::INTEGER      AS sin_dato,
       -- por_vencer_30 pasa a significar "dentro de 30 días" en su conjunto,
       -- para que quien ya leía esta columna siga viendo lo mismo.
       count(*) FILTER (WHERE v.estado IN ('por_vencer_7','por_vencer_14','por_vencer_30'))::INTEGER
                                                                   AS por_vencer_30,
       count(*) FILTER (WHERE v.estado = 'por_vencer_60')::INTEGER AS por_vencer_60,
       count(*) FILTER (WHERE v.estado = 'vigente')::INTEGER       AS vigentes,
       count(*) FILTER (WHERE v.estado = 'no_aplica')::INTEGER     AS no_aplica,
       min(v.fecha_vencimiento) FILTER (WHERE v.aplica AND NOT v.observacion_bloqueante)
                                                                   AS proximo_vencimiento,
       CASE
           WHEN count(*) FILTER (WHERE v.estado IN ('vencido','sin_dato')) > 0 THEN 'no_conforme'
           WHEN count(*) FILTER (WHERE v.estado = 'por_vencer_7') > 0          THEN 'critico'
           WHEN count(*) FILTER (WHERE v.estado = 'observado') > 0             THEN 'observado'
           WHEN count(*) FILTER (WHERE v.estado IN ('por_vencer_14','por_vencer_30')) > 0
                                                                              THEN 'por_vencer'
           ELSE 'conforme'
       END AS estado_general,
       -- Días hasta el vencimiento más próximo que todavía cuenta. Permite
       -- ordenar "a quién llamo primero" sin recorrer los ítems.
       min(v.dias_restantes) FILTER (
           WHERE v.aplica AND NOT v.observacion_bloqueante AND v.dias_restantes >= 0
       )::INTEGER                                                  AS dias_al_proximo
  FROM prevencion_personal p
  LEFT JOIN v_prevencion_examenes_estado v ON v.personal_id = p.id
 GROUP BY p.id;

COMMENT ON VIEW v_prevencion_personal_estado IS
    'Estado por persona. `critico` = algo vence dentro de 7 días. MIG304.';


-- ############################################################################
-- 3. EL REPORTE INCLUYE LOS ESTADOS NUEVOS
-- ############################################################################
-- Sin esto, los críticos desaparecerían del correo a pedido: el filtro
-- enumeraba los estados uno por uno y `por_vencer_7` no existía cuando se
-- escribió.

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
       AND v.estado <> 'no_aplica'
       -- Por descarte y no por lista blanca: si mañana se agrega un estado
       -- nuevo, entra al reporte solo; antes había que acordarse de sumarlo.
       AND (p_incluir_vigentes OR v.estado <> 'vigente')
     ORDER BY CASE v.estado
                  WHEN 'vencido'       THEN 1
                  WHEN 'sin_dato'      THEN 2
                  WHEN 'por_vencer_7'  THEN 3
                  WHEN 'observado'     THEN 4
                  WHEN 'por_vencer_14' THEN 5
                  WHEN 'por_vencer_30' THEN 6
                  WHEN 'por_vencer_60' THEN 7
                  ELSE 8 END,
              v.dias_restantes NULLS FIRST,
              v.apellidos, v.nombres;
$$;
GRANT EXECUTE ON FUNCTION fn_prevencion_reporte_envio(TEXT, BOOLEAN) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_reporte_envio(TEXT, BOOLEAN) IS
    'Estado documental para enviar. Filtra por descarte para no perder estados nuevos. MIG304.';


-- ############################################################################
-- 4. EL TABLERO CUENTA LOS CRÍTICOS APARTE
-- ############################################################################

DROP FUNCTION IF EXISTS fn_prevencion_control_documental(TEXT);
CREATE FUNCTION fn_prevencion_control_documental(p_faena TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_out JSONB;
BEGIN
    IF NOT fn_prevencion_personal_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado para ver el control documental de personal.'
            USING ERRCODE = '42501';
    END IF;

    SELECT jsonb_build_object(
        'generado_at', NOW(),
        'faena', p_faena,
        'resumen', (
            SELECT jsonb_build_object(
                'personas',      count(*),
                'no_conformes',  count(*) FILTER (WHERE estado_general = 'no_conforme'),
                'criticos',      count(*) FILTER (WHERE estado_general = 'critico'),
                'observados',    count(*) FILTER (WHERE estado_general = 'observado'),
                'por_vencer',    count(*) FILTER (WHERE estado_general = 'por_vencer'),
                'conformes',     count(*) FILTER (WHERE estado_general = 'conforme'),
                'examenes_vencidos', COALESCE(SUM(vencidos), 0),
                'examenes_sin_dato', COALESCE(SUM(sin_dato), 0),
                'examenes_observados', COALESCE(SUM(observados), 0),
                -- Cuántos ítems vencen dentro de 7 días, que es la pregunta
                -- operativa: qué hay que resolver esta semana.
                'examenes_criticos', (
                    SELECT count(*) FROM v_prevencion_examenes_estado v2
                     WHERE v2.persona_activa AND v2.estado = 'por_vencer_7'
                       AND (p_faena IS NULL OR v2.faena_codigo = p_faena)))
              FROM v_prevencion_personal_estado
             WHERE activo AND (p_faena IS NULL OR faena_codigo = p_faena)),

        'personas', COALESCE((
            SELECT jsonb_agg(to_jsonb(x) || jsonb_build_object(
                       'examenes', (
                           SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.orden), '[]'::JSONB)
                             FROM v_prevencion_examenes_estado e
                            WHERE e.personal_id = x.personal_id))
                   ORDER BY
                       CASE x.estado_general
                           WHEN 'no_conforme' THEN 1
                           WHEN 'critico'     THEN 2
                           WHEN 'observado'   THEN 3
                           WHEN 'por_vencer'  THEN 4
                           ELSE 5 END,
                       x.dias_al_proximo NULLS LAST,
                       x.apellidos, x.nombres)
              FROM v_prevencion_personal_estado x
             WHERE x.activo AND (p_faena IS NULL OR x.faena_codigo = p_faena)), '[]'::JSONB),

        'faenas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('faena', faena_codigo, 'personas', n)
                             ORDER BY faena_codigo)
              FROM (SELECT COALESCE(faena_codigo, '(sin faena)') AS faena_codigo, count(*) n
                      FROM v_prevencion_personal_estado WHERE activo
                     GROUP BY 1) s), '[]'::JSONB)
    ) INTO v_out;

    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_control_documental(TEXT) TO authenticated;

COMMENT ON FUNCTION fn_prevencion_control_documental(TEXT) IS
    'Control documental completo, con los críticos (≤7 días) contados aparte. MIG304.';


-- ############################################################################
-- 5. EL DASHBOARD TAMBIÉN CUENTA LOS CRÍTICOS
-- ############################################################################

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

        'personal', (
            SELECT jsonb_build_object(
                'personas',     count(*),
                'no_conformes', count(*) FILTER (WHERE estado_general = 'no_conforme'),
                'criticos',     count(*) FILTER (WHERE estado_general = 'critico'),
                'observados',   count(*) FILTER (WHERE estado_general = 'observado'),
                'por_vencer',   count(*) FILTER (WHERE estado_general = 'por_vencer'),
                'conformes',    count(*) FILTER (WHERE estado_general = 'conforme'),
                'exam_vencidos',COALESCE(SUM(vencidos), 0),
                'exam_sin_dato',COALESCE(SUM(sin_dato), 0),
                'exam_criticos',(SELECT count(*) FROM v_prevencion_examenes_estado v2
                                  WHERE v2.persona_activa AND v2.estado = 'por_vencer_7'))
              FROM v_prevencion_personal_estado WHERE activo),

        'personal_urgente', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'persona', persona, 'rut', rut, 'tipo', tipo_nombre,
                       'vence', fecha_vencimiento, 'dias', dias_restantes,
                       'estado', estado) ORDER BY dias_restantes NULLS FIRST)
              FROM (SELECT * FROM fn_prevencion_reporte_envio(NULL, false) LIMIT 5) s), '[]'::JSONB),

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

        'ultimo_envio', (
            SELECT jsonb_build_object('at', enviado_at, 'faena', faena_codigo,
                                      'destinatarios', destinatarios)
              FROM prevencion_envios_manuales ORDER BY enviado_at DESC LIMIT 1)
    ) INTO v_out;

    RETURN v_out;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_dashboard() TO authenticated;

COMMENT ON FUNCTION fn_prevencion_dashboard() IS
    'Resumen de prevención, con los ítems que vencen dentro de 7 días. MIG304.';
