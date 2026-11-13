-- ============================================================================
-- SICOM-ICEO | 688 — Portal del mandante: Prevención y Operaciones
-- ============================================================================
-- Pedido de Manuel (13-11-2026): un portal por faena donde el mandante vea
-- todo lo de prevención y los informes de operaciones (calibración y
-- mantención ENEX).
--
-- Decisiones:
--   · Se AMPLÍA el portal de prevención existente (MIG308/313): mismo link por
--     faena, mismo ingreso con correo autorizado y vigencia de 12 h.
--   · Pestaña Prevención: personal y documentos (ya existía), inspecciones APR
--     y desviaciones, actividades del mes con fotos, indicadores (HH, IF, IG).
--   · Pestaña Operaciones: informes de calibración y mantención ENEX con su
--     PDF, y los equipos con su historial (ya existía).
--
-- NO se toca fn_portal_prevencion_publico (arma 46 claves y se parcha con
-- cuidado, ver MIG379/383). Todo lo nuevo va en funciones aparte, con la
-- misma regla: el alcance sale de la fila del portal, nunca de la petición.
--
-- Alcance nuevo por portal:
--   faena_ids          → faenas SICOM (inspecciones, registros, indicadores)
--   enex_faena_codigos → faenas del contrato ENEX (informes de servicio)
--
-- ADITIVA.
-- ============================================================================

BEGIN;

ALTER TABLE portales_prevencion
    ADD COLUMN IF NOT EXISTS faena_ids           UUID[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS enex_faena_codigos  TEXT[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS ver_prevencion      BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS ver_operaciones     BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN portales_prevencion.faena_ids IS
    'Faenas SICOM cuyas inspecciones, actividades e indicadores ve el mandante. MIG688.';
COMMENT ON COLUMN portales_prevencion.enex_faena_codigos IS
    'Faenas del contrato ENEX cuyos informes de calibración/mantención ve el mandante. MIG688.';


-- ── Portales por faena ──────────────────────────────────────────────────────
-- Romeral: se le suma su faena SICOM (no tiene contrato ENEX).
UPDATE portales_prevencion
   SET faena_ids = ARRAY(SELECT id FROM faenas WHERE codigo = 'FAE-CMP-ROMERAL')
 WHERE faena_codigo = 'ROMERAL' AND faena_ids = '{}';

-- Calama: un portal por faena del mandante. Nacen SIN correos externos: solo
-- entran los destinatarios internos de prevención hasta que se agreguen los
-- del mandante desde el panel. El token se arma con dos UUID
-- (gen_random_bytes no está en public).
INSERT INTO portales_prevencion (token, nombre, cliente, faena_codigo, faena_ids,
                                 enex_faena_codigos, ver_archivos_personal,
                                 requiere_identificacion, emails_autorizados, observacion)
SELECT replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
       v.nombre, v.cliente, 'CALAMA',
       ARRAY(SELECT id FROM faenas WHERE codigo = ANY (v.faenas)),
       v.enex, false, true, '{}',
       'Creado por MIG688. Agregar los correos del mandante en el panel de Prevención.'
  FROM (VALUES
    ('Portal del mandante — Centinela', 'Minera Centinela · ENEX',
        ARRAY['FAE-CENTINELA'], ARRAY['CENTINELA','NCEN_DES']),
    ('Portal del mandante — Lomas Bayas', 'Minera Lomas Bayas (Glencore) · ENEX',
        ARRAY['FAE-LOMASBAYAS','FAE-LOMASBAYAS-LUB'], ARRAY['LB_COMB','LB_LUB']),
    ('Portal del mandante — Spence', 'Minera Spence (BHP) · ENEX',
        ARRAY['FAE-SPENCE'], ARRAY['SPENCE'])
  ) AS v(nombre, cliente, faenas, enex)
 WHERE NOT EXISTS (SELECT 1 FROM portales_prevencion p WHERE p.nombre = v.nombre);


-- ── Helper: portal resuelto + ingreso vigente, o error ─────────────────────
CREATE OR REPLACE FUNCTION fn_portal_mandante_validar(p_token TEXT, p_acceso_id UUID)
RETURNS portales_prevencion
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_p portales_prevencion;
BEGIN
    v_p := fn_portal_prevencion_resolver(p_token);
    IF v_p.id IS NULL THEN
        RAISE EXCEPTION 'Link no válido o revocado.' USING ERRCODE = '42501';
    END IF;
    IF NOT fn_portal_prevencion_acceso_vigente(v_p, p_acceso_id) THEN
        RAISE EXCEPTION 'Identifíquese para ver esta documentación.' USING ERRCODE = '42501';
    END IF;
    RETURN v_p;
END $$;
REVOKE ALL ON FUNCTION fn_portal_mandante_validar(TEXT, UUID) FROM PUBLIC, anon, authenticated;


-- ── Configuración: qué pestañas y qué faenas ───────────────────────────────
CREATE OR REPLACE FUNCTION fn_portal_mandante_config(p_token TEXT, p_acceso_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_p portales_prevencion;
BEGIN
    v_p := fn_portal_mandante_validar(p_token, p_acceso_id);
    RETURN jsonb_build_object(
        'ver_prevencion', v_p.ver_prevencion,
        'ver_operaciones', v_p.ver_operaciones,
        'faenas', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'nombre', f.nombre) ORDER BY f.nombre)
                              FROM faenas f WHERE f.id = ANY (v_p.faena_ids)), '[]'::jsonb),
        'faenas_enex', COALESCE((SELECT jsonb_agg(jsonb_build_object('codigo', e.codigo, 'nombre', e.nombre) ORDER BY e.orden)
                                   FROM enex_faenas e WHERE e.codigo = ANY (v_p.enex_faena_codigos)), '[]'::jsonb));
END $$;
GRANT EXECUTE ON FUNCTION fn_portal_mandante_config(TEXT, UUID) TO anon, authenticated;


-- ── Prevención del período ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_portal_mandante_prevencion(
    p_token TEXT, p_acceso_id UUID, p_anio INT, p_mes INT)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
    v_p     portales_prevencion;
    v_desde DATE := make_date(p_anio, p_mes, 1);
    v_hasta DATE := (make_date(p_anio, p_mes, 1) + INTERVAL '1 month')::date;
BEGIN
    v_p := fn_portal_mandante_validar(p_token, p_acceso_id);
    IF NOT v_p.ver_prevencion THEN
        RAISE EXCEPTION 'Este portal no incluye prevención.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'periodo', jsonb_build_object('anio', p_anio, 'mes', p_mes),

        'inspecciones', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', i.id, 'fecha', i.fecha, 'faena', f.nombre,
                       'trabajo', i.trabajo, 'instalacion', i.instalacion,
                       'area_sector', i.area_sector, 'inspector', i.inspector_nombre,
                       'estado', i.estado, 'resultado', i.resultado,
                       'pct_cumplimiento', i.pct_cumplimiento,
                       'items_cumple', i.items_cumple, 'items_no_cumple', i.items_no_cumple,
                       'personas_no_habilitadas', i.personas_no_habilitadas,
                       'desviaciones', (SELECT count(*) FROM prevencion_inspeccion_desviaciones d WHERE d.inspeccion_id = i.id),
                       'desviaciones_abiertas', (SELECT count(*) FROM prevencion_inspeccion_desviaciones d
                                                  WHERE d.inspeccion_id = i.id AND d.estado = 'abierta'))
                     ORDER BY i.fecha DESC, i.created_at DESC)
              FROM prevencion_inspecciones i JOIN faenas f ON f.id = i.faena_id
             WHERE i.faena_id = ANY (v_p.faena_ids)
               AND i.fecha >= v_desde AND i.fecha < v_hasta), '[]'::jsonb),

        -- Abiertas: todas, no solo del mes (lo pendiente no se olvida al cambiar de mes).
        'desviaciones_abiertas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', d.id, 'fecha', i.fecha, 'faena', f.nombre, 'trabajo', i.trabajo,
                       'item_codigo', d.item_codigo, 'criticidad', d.criticidad,
                       'descripcion', d.descripcion, 'accion', d.accion,
                       'responsable', d.responsable, 'fecha_compromiso', d.fecha_compromiso,
                       'vencida', d.fecha_compromiso < CURRENT_DATE)
                     ORDER BY (d.criticidad = 'alta') DESC, d.fecha_compromiso NULLS LAST)
              FROM prevencion_inspeccion_desviaciones d
              JOIN prevencion_inspecciones i ON i.id = d.inspeccion_id
              JOIN faenas f ON f.id = i.faena_id
             WHERE i.faena_id = ANY (v_p.faena_ids) AND d.estado = 'abierta'), '[]'::jsonb),

        'actividades', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'id', r.id, 'fecha', r.fecha_actividad, 'faena', f.nombre,
                       'tipo', t.nombre, 'tipo_codigo', r.tipo_codigo,
                       'titulo', r.titulo, 'descripcion', r.descripcion,
                       'area_sector', r.area_sector, 'estado', r.estado,
                       'responsable', r.supervisor_nombre,
                       'asistentes', r.asistentes, 'duracion_minutos', r.duracion_minutos,
                       'fotos', (SELECT COALESCE(jsonb_agg(e->>'path'), '[]'::jsonb)
                                   FROM jsonb_array_elements(r.evidencias) e
                                  WHERE (e->>'content_type') LIKE 'image/%'))
                     ORDER BY r.fecha_actividad DESC, r.created_at DESC)
              FROM prevencion_registros r
              JOIN prevencion_actividad_tipos t ON t.codigo = r.tipo_codigo
              JOIN faenas f ON f.id = r.faena_id
             WHERE r.faena_id = ANY (v_p.faena_ids)
               AND r.fecha_actividad >= v_desde AND r.fecha_actividad < v_hasta), '[]'::jsonb),

        'resumen_actividades', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('tipo', x.tipo, 'realizados', x.n, 'abiertos', x.ab) ORDER BY x.orden)
              FROM (SELECT t.nombre AS tipo, t.orden, count(*) n, count(*) FILTER (WHERE r.estado = 'abierto') ab
                      FROM prevencion_registros r JOIN prevencion_actividad_tipos t ON t.codigo = r.tipo_codigo
                     WHERE r.faena_id = ANY (v_p.faena_ids)
                       AND r.fecha_actividad >= v_desde AND r.fecha_actividad < v_hasta
                     GROUP BY t.nombre, t.orden) x), '[]'::jsonb),

        'indicadores', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'faena', f.nombre, 'dotacion', v.dotacion_total, 'hh', v.hh_total,
                       'accidentes_ctp', v.accidentes_ctp, 'dias_perdidos', v.dias_perdidos,
                       'incidentes_alto_potencial', v.incidentes_alto_potencial,
                       'if', v.indice_frecuencia, 'ig', v.indice_gravedad,
                       'acum_if', v.acum_indice_frecuencia, 'acum_ig', v.acum_indice_gravedad)
                     ORDER BY f.nombre)
              FROM v_prevencion_indicadores v JOIN faenas f ON f.id = v.faena_id
             WHERE v.faena_id = ANY (v_p.faena_ids) AND v.anio = p_anio AND v.mes = p_mes), '[]'::jsonb)
    );
END $$;
GRANT EXECUTE ON FUNCTION fn_portal_mandante_prevencion(TEXT, UUID, INT, INT) TO anon, authenticated;


-- ── Detalle de una inspección (para verla y bajar su PDF) ──────────────────
-- Mismas claves que lee el informe PDF interno. Sin RUT de los trabajadores.
CREATE OR REPLACE FUNCTION fn_portal_mandante_inspeccion(p_token TEXT, p_acceso_id UUID, p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE
    v_p portales_prevencion;
    v_i prevencion_inspecciones%ROWTYPE;
BEGIN
    v_p := fn_portal_mandante_validar(p_token, p_acceso_id);
    SELECT * INTO v_i FROM prevencion_inspecciones WHERE id = p_id;
    IF NOT FOUND OR NOT (v_i.faena_id = ANY (v_p.faena_ids)) OR NOT v_p.ver_prevencion THEN
        RAISE EXCEPTION 'Inspección fuera del alcance de este portal.' USING ERRCODE = '42501';
    END IF;

    RETURN (to_jsonb(v_i) - 'inspector_id' - 'cliente_uuid')
        || jsonb_build_object(
            'faena_nombre', (SELECT nombre FROM faenas WHERE id = v_i.faena_id),
            'items', COALESCE((SELECT jsonb_agg(to_jsonb(it) ORDER BY it.item_codigo)
                                 FROM prevencion_inspeccion_items it WHERE it.inspeccion_id = p_id), '[]'::jsonb),
            'personas', COALESCE((SELECT jsonb_agg((to_jsonb(pe) - 'rut') || jsonb_build_object('rut', NULL) ORDER BY pe.nombre)
                                    FROM prevencion_inspeccion_personas pe WHERE pe.inspeccion_id = p_id), '[]'::jsonb),
            'desviaciones', COALESCE((SELECT jsonb_agg(to_jsonb(d) - 'cerrada_por' ORDER BY d.created_at)
                                        FROM prevencion_inspeccion_desviaciones d WHERE d.inspeccion_id = p_id), '[]'::jsonb));
END $$;
GRANT EXECUTE ON FUNCTION fn_portal_mandante_inspeccion(TEXT, UUID, UUID) TO anon, authenticated;


-- ── Operaciones: informes de calibración y mantención ENEX ─────────────────
-- p_mes NULL = el año completo.
CREATE OR REPLACE FUNCTION fn_portal_mandante_operaciones(
    p_token TEXT, p_acceso_id UUID, p_anio INT, p_mes INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_p portales_prevencion;
BEGIN
    v_p := fn_portal_mandante_validar(p_token, p_acceso_id);
    IF NOT v_p.ver_operaciones THEN
        RAISE EXCEPTION 'Este portal no incluye operaciones.' USING ERRCODE = '42501';
    END IF;

    RETURN jsonb_build_object(
        'periodo', jsonb_build_object('anio', p_anio, 'mes', p_mes),
        'servicios', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                       'programacion_id', v.programacion_id, 'faena', v.faena,
                       'instalacion', v.instalacion, 'instalacion_tipo', v.instalacion_tipo,
                       'patente', v.patente, 'linea', v.linea,
                       'tipo_servicio', v.tipo_servicio,
                       'periodo_mes', v.periodo_mes, 'fecha_programada', v.fecha_programada,
                       'estado', COALESCE(v.estado, 'pendiente'), 'cumplida', v.cumplida,
                       'fecha_ejecucion', v.fecha_ejecucion, 'ot_numero', v.ot_numero,
                       'tecnico', v.tecnico_nombre, 'firmante_mandante', v.firmante_mandante_nombre,
                       'informe_pdf_url', v.informe_pdf_url)
                     ORDER BY v.periodo_mes DESC, v.fecha_programada DESC NULLS LAST, v.instalacion)
              FROM v_enex_panel_mensual v
             WHERE v.faena_codigo = ANY (v_p.enex_faena_codigos)
               AND v.periodo_anio = p_anio
               AND (p_mes IS NULL OR v.periodo_mes = p_mes)), '[]'::jsonb)
    );
END $$;
GRANT EXECUTE ON FUNCTION fn_portal_mandante_operaciones(TEXT, UUID, INT, INT) TO anon, authenticated;


-- ── Foto de evidencia: solo si pertenece al alcance del portal ─────────────
-- Devuelve la ruta; la firma la hace el servidor (/api/prevencion/portal-evidencia).
CREATE OR REPLACE FUNCTION fn_portal_mandante_evidencia(p_token TEXT, p_acceso_id UUID, p_path TEXT)
RETURNS TEXT
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $$
DECLARE v_p portales_prevencion;
BEGIN
    v_p := fn_portal_mandante_validar(p_token, p_acceso_id);
    IF NOT v_p.ver_prevencion THEN
        RAISE EXCEPTION 'Este portal no incluye prevención.' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM prevencion_registros r, jsonb_array_elements(r.evidencias) e
                WHERE r.faena_id = ANY (v_p.faena_ids) AND e->>'path' = p_path)
       OR EXISTS (SELECT 1 FROM prevencion_inspeccion_items it
                    JOIN prevencion_inspecciones i ON i.id = it.inspeccion_id,
                         jsonb_array_elements(it.evidencias) e
                   WHERE i.faena_id = ANY (v_p.faena_ids) AND e->>'path' = p_path) THEN
        UPDATE portal_prevencion_accesos SET ultima_vista = NOW(), vistas = vistas + 1
         WHERE id = p_acceso_id;
        RETURN p_path;
    END IF;
    RAISE EXCEPTION 'Archivo fuera del alcance de este portal.' USING ERRCODE = '42501';
END $$;
GRANT EXECUTE ON FUNCTION fn_portal_mandante_evidencia(TEXT, UUID, TEXT) TO anon, authenticated;

COMMIT;

SELECT nombre, faena_codigo, array_length(faena_ids, 1) AS faenas_sicom,
       enex_faena_codigos, coalesce(array_length(emails_autorizados, 1), 0) AS correos
  FROM portales_prevencion ORDER BY nombre;
