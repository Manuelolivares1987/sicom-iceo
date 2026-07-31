-- ============================================================================
-- SICOM-ICEO | 263 — Evidencia obligatoria en la auditoría e Informe de Salida
--                    a Arriendo
-- ----------------------------------------------------------------------------
-- Manuel: «El informe debe tener evidencia, de cada cosa, y esa evidencia debe
-- generar un informe de salida para arriendo del camión».
--
-- La auditoría de calidad (Gate 2) ya era la que libera el equipo a operativo y
-- deja la verificación ready-to-rent vigente. Lo que faltaba era que dejara un
-- DOCUMENTO: el informe que acompaña al camión cuando sale a arriendo, con la
-- foto de cada cosa revisada.
--
-- Qué exige ahora para aprobar (evidencia de verdad, no declarativa):
--   · foto en todo ítem marcado NO OK — el hallazgo se prueba con la foto
--   · foto en los 16 ítems del V03 que la piden (requiere_foto), salvo que se
--     marquen N/A por no corresponder al equipo
--   · la firma del auditor ya era obligatoria de hecho; ahora se valida
-- No se exige foto en los 188: sería impracticable y nadie la miraría. Se exige
-- donde prueba algo — el hallazgo y los puntos que el checklist marca como
-- críticos de registro.
--
-- Y genera:
--   · folio del informe (INF-SAL-AAAAMM-NNNN) al aprobar
--   · fn_informe_salida_arriendo(auditoria) -> todo el informe en un JSON:
--     equipo, auditor, resultado, vigencia, resumen, los ítems por bloque con
--     su foto, los hallazgos, los pendientes diferidos y los documentos del
--     equipo con su vencimiento.
--
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_resolver_auditoria_calidad') THEN
        RAISE EXCEPTION 'STOP — falta fn_resolver_auditoria_calidad (MIG125).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_name='auditoria_calidad_items' AND column_name='requiere_foto') THEN
        RAISE EXCEPTION 'STOP — falta auditoria_calidad_items.requiere_foto (MIG260).';
    END IF;
END $$;


-- ── 1. Folio del informe ────────────────────────────────────────────────────
ALTER TABLE public.auditorias_calidad
    ADD COLUMN IF NOT EXISTS folio VARCHAR(30);

CREATE UNIQUE INDEX IF NOT EXISTS uq_auditorias_calidad_folio
    ON public.auditorias_calidad (folio) WHERE folio IS NOT NULL;

COMMENT ON COLUMN public.auditorias_calidad.folio IS
    'Folio del Informe de Salida a Arriendo (INF-SAL-AAAAMM-NNNN), al aprobar. MIG263.';


-- ── 2. ¿Está completa la evidencia? ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_auditoria_evidencia_faltante(p_auditoria_id UUID)
RETURNS TABLE (item_id UUID, descripcion TEXT, motivo TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT i.id, i.descripcion,
           CASE WHEN i.resultado = 'no_ok' THEN 'hallazgo NO OK sin foto'
                ELSE 'el checklist exige foto en este punto' END
      FROM auditoria_calidad_items i
     WHERE i.auditoria_id = p_auditoria_id
       AND COALESCE(length(trim(i.foto_url)), 0) = 0
       AND (
             i.resultado = 'no_ok'
          OR (i.requiere_foto = true AND i.resultado = 'ok')
           )
     ORDER BY i.orden;
$function$;

COMMENT ON FUNCTION public.fn_auditoria_evidencia_faltante(UUID) IS
    'Ítems que no pueden quedar sin foto: los NO OK y los que el checklist marca requiere_foto. MIG263.';

REVOKE ALL ON FUNCTION public.fn_auditoria_evidencia_faltante(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_auditoria_evidencia_faltante(UUID) TO authenticated;


-- ── 3. Resolver: sin evidencia no se aprueba, y se emite el folio ───────────
CREATE OR REPLACE FUNCTION public.fn_resolver_auditoria_calidad(
    p_auditoria_id uuid,
    p_resultado character varying,
    p_items jsonb DEFAULT '[]'::jsonb,
    p_motivo_rechazo text DEFAULT NULL::text,
    p_observaciones text DEFAULT NULL::text,
    p_firma_url text DEFAULT NULL::text,
    p_evidencias jsonb DEFAULT '[]'::jsonb,
    p_dias_vigencia integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_aud  RECORD;
    v_item JSONB;
    v_ok INT; v_no_ok INT; v_na INT; v_tot INT;
    v_crit_fail INT;
    v_tec_ok BOOLEAN; v_doc_ok BOOLEAN;
    v_pend_crit INT;
    v_verif_id UUID;
    v_nc_id UUID;
    v_vig TIMESTAMPTZ;
    v_falta INT;
    v_falta_txt TEXT;
    v_folio TEXT;
    v_firma TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF v_rol NOT IN ('auditor_calidad','administrador') THEN
        RAISE EXCEPTION 'Solo el rol auditor_calidad puede resolver la auditoria. Rol: %', v_rol;
    END IF;
    IF p_resultado NOT IN ('aprobado','aprobado_con_observaciones','rechazado') THEN
        RAISE EXCEPTION 'Resultado invalido: %', p_resultado;
    END IF;

    SELECT * INTO v_aud FROM auditorias_calidad WHERE id = p_auditoria_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Auditoria % no existe', p_auditoria_id; END IF;
    IF v_aud.resultado <> 'pendiente' THEN
        RAISE EXCEPTION 'La auditoria ya fue resuelta (estado %).', v_aud.resultado;
    END IF;
    IF COALESCE(v_aud.anulada, false) THEN
        RAISE EXCEPTION 'La auditoria esta anulada.';
    END IF;

    -- SoD: el auditor no puede haber ejecutado trabajo en este equipo.
    IF EXISTS (
        SELECT 1 FROM taller_ot_ejecuciones e
        JOIN ordenes_trabajo o ON o.id = e.ot_id
        WHERE o.activo_id = v_aud.activo_id AND e.ejecutor_id = v_user
    ) THEN
        RAISE EXCEPTION 'SEGREGACION DE FUNCIONES: el auditor no puede haber ejecutado '
            'trabajo en este equipo. La auditoria debe ser independiente.';
    END IF;

    -- Actualizar items recibidos.
    FOR v_item IN SELECT * FROM jsonb_array_elements(COALESCE(p_items,'[]'::JSONB)) LOOP
        UPDATE auditoria_calidad_items SET
            resultado = COALESCE(v_item->>'resultado', resultado),
            observacion = COALESCE(v_item->>'observacion', observacion),
            foto_url = COALESCE(v_item->>'foto_url', foto_url),
            completado_at = NOW(), completado_por = v_user
        WHERE id = (v_item->>'id')::UUID AND auditoria_id = p_auditoria_id;
    END LOOP;

    SELECT COUNT(*) FILTER (WHERE resultado='ok'),
           COUNT(*) FILTER (WHERE resultado='no_ok'),
           COUNT(*) FILTER (WHERE resultado='na'),
           COUNT(*),
           COUNT(*) FILTER (WHERE resultado='no_ok' AND critico),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='tecnica'),
           bool_and(resultado IN ('ok','na')) FILTER (WHERE categoria='documentacion')
      INTO v_ok, v_no_ok, v_na, v_tot, v_crit_fail, v_tec_ok, v_doc_ok
      FROM auditoria_calidad_items WHERE auditoria_id = p_auditoria_id;

    -- [MIG263] La evidencia se exige SIEMPRE, se apruebe o se rechace: el
    -- informe de salida se sostiene en las fotos, y un rechazo sin foto del
    -- hallazgo no le sirve a nadie.
    SELECT count(*), string_agg('• ' || descripcion || ' (' || motivo || ')', E'\n')
      INTO v_falta, v_falta_txt
      FROM (SELECT * FROM fn_auditoria_evidencia_faltante(p_auditoria_id) LIMIT 12) f;
    IF v_falta > 0 THEN
        RAISE EXCEPTION 'Falta la foto de % punto(s). El informe de salida se emite con la evidencia:%s%',
            (SELECT count(*) FROM fn_auditoria_evidencia_faltante(p_auditoria_id)),
            E'\n', v_falta_txt;
    END IF;

    IF p_resultado IN ('aprobado','aprobado_con_observaciones') THEN
        IF COALESCE(v_crit_fail,0) > 0 THEN
            RAISE EXCEPTION 'No se puede aprobar: % item(es) CRITICO(s) en no_ok.', v_crit_fail;
        END IF;
        SELECT COUNT(*) INTO v_pend_crit FROM items_diferidos
        WHERE activo_id = v_aud.activo_id AND estado='pendiente' AND diferible=false;
        IF v_pend_crit > 0 THEN
            RAISE EXCEPTION 'No se puede liberar: % pendiente(s) critico(s)/seguridad sin '
                'resolver (no diferibles).', v_pend_crit;
        END IF;

        -- [MIG263] El informe lleva firma. Sin firma no hay documento de salida.
        v_firma := COALESCE(p_firma_url, v_aud.firma_auditor_url);
        IF COALESCE(length(trim(v_firma)),0) = 0 THEN
            RAISE EXCEPTION 'Falta la firma del auditor de calidad: es la que respalda el informe de salida.';
        END IF;

        v_vig := NOW() + (COALESCE(p_dias_vigencia,3) || ' days')::INTERVAL;

        -- [MIG263] Folio del informe de salida a arriendo.
        SELECT 'INF-SAL-' || to_char(NOW(),'YYYYMM') || '-' ||
               lpad((COALESCE(count(*),0) + 1)::text, 4, '0')
          INTO v_folio
          FROM auditorias_calidad
         WHERE folio LIKE 'INF-SAL-' || to_char(NOW(),'YYYYMM') || '-%';

        INSERT INTO verificaciones_disponibilidad (
            activo_id, ot_id, resultado, fecha_verificacion, vigente_hasta,
            dias_vigencia, aprobado_por, aprobado_en, firma_aprobador_url,
            items_total, items_ok, items_no_ok, items_na, puntaje_total
        ) VALUES (
            v_aud.activo_id, v_aud.ot_id, 'aprobado', NOW(), v_vig,
            COALESCE(p_dias_vigencia,3), v_user, NOW(), v_firma,
            v_tot, v_ok, v_no_ok, v_na,
            CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END
        ) RETURNING id INTO v_verif_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = p_resultado::resultado_verificacion_enum,
            calidad_tecnica_ok = COALESCE(v_tec_ok,true),
            documentacion_ok = COALESCE(v_doc_ok,true),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), vigente_hasta = v_vig, dias_vigencia = COALESCE(p_dias_vigencia,3),
            verificacion_id = v_verif_id, observaciones = p_observaciones,
            firma_auditor_url = v_firma, evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            folio = v_folio, updated_at = NOW()
        WHERE id = p_auditoria_id;

        UPDATE activos SET estado = 'operativo',
            ultima_verificacion_id = v_verif_id, verificacion_vigente_hasta = v_vig,
            updated_at = NOW()
        WHERE id = v_aud.activo_id;

    ELSE  -- rechazado
        INSERT INTO no_conformidades (activo_id, ot_id, tipo, descripcion, fecha_evento,
                                      severidad, created_by)
        VALUES (v_aud.activo_id, v_aud.ot_id, 'otra',
                'Auditoria de calidad RECHAZADA (Gate 2). ' || COALESCE(p_motivo_rechazo,''),
                CURRENT_DATE, 'alta', v_user)
        RETURNING id INTO v_nc_id;

        UPDATE auditorias_calidad SET
            auditor_id = v_user, resultado = 'rechazado',
            calidad_tecnica_ok = COALESCE(v_tec_ok,false),
            documentacion_ok = COALESCE(v_doc_ok,false),
            items_ok=v_ok, items_no_ok=v_no_ok, items_na=v_na, items_total=v_tot,
            puntaje = CASE WHEN v_tot>0 THEN ROUND(100.0*v_ok/v_tot) ELSE NULL END,
            fecha_auditoria = NOW(), motivo_rechazo = p_motivo_rechazo,
            observaciones = p_observaciones, firma_auditor_url = COALESCE(p_firma_url, firma_auditor_url),
            evidencias_fotos = COALESCE(p_evidencias,evidencias_fotos),
            no_conformidad_id = v_nc_id, updated_at = NOW()
        WHERE id = p_auditoria_id;
    END IF;

    RETURN jsonb_build_object('auditoria_id', p_auditoria_id, 'resultado', p_resultado,
        'verificacion_id', v_verif_id, 'no_conformidad_id', v_nc_id,
        'vigente_hasta', v_vig, 'items_ok', v_ok, 'items_no_ok', v_no_ok,
        'folio', v_folio);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_resolver_auditoria_calidad(uuid, character varying, jsonb, text, text, text, jsonb, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolver_auditoria_calidad(uuid, character varying, jsonb, text, text, text, jsonb, integer) TO authenticated;


-- ── 4. El informe completo, en un JSON ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_informe_salida_arriendo(p_auditoria_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_out JSONB;
BEGIN
    SELECT jsonb_build_object(
        'auditoria_id', ac.id,
        'folio',        ac.folio,
        'resultado',    ac.resultado,
        'fecha',        COALESCE(ac.fecha_auditoria, ac.created_at),
        'vigente_hasta', ac.vigente_hasta,
        'dias_vigencia', ac.dias_vigencia,
        'observaciones', ac.observaciones,
        'motivo_rechazo', ac.motivo_rechazo,
        'puntaje',      ac.puntaje,
        'calidad_tecnica_ok', ac.calidad_tecnica_ok,
        'documentacion_ok',   ac.documentacion_ok,
        'auditor', jsonb_build_object(
            'nombre', ua.nombre_completo,
            'firma_url', ac.firma_auditor_url),
        'equipo', jsonb_build_object(
            'id', a.id, 'patente', a.patente, 'codigo', a.codigo, 'nombre', a.nombre,
            'tipo', a.tipo, 'tipo_equipamiento', a.tipo_equipamiento,
            'marca', ma.nombre, 'modelo', mo.nombre, 'anio', a.anio_fabricacion,
            'kilometraje', a.kilometraje_actual, 'horas_uso', a.horas_uso_actual,
            'cliente', c.cliente, 'contrato', c.codigo, 'faena', f.nombre),
        'resumen', jsonb_build_object(
            'total', ac.items_total, 'ok', ac.items_ok,
            'no_ok', ac.items_no_ok, 'na', ac.items_na),
        'bloques', COALESCE((
            SELECT jsonb_agg(b ORDER BY b->>'orden')
              FROM (
                SELECT jsonb_build_object(
                        'bloque', COALESCE(i.bloque,'Sin bloque'),
                        'orden',  lpad(COALESCE(i.bloque_orden,99)::text,3,'0'),
                        'categoria', i.categoria,
                        'items', jsonb_agg(jsonb_build_object(
                            'descripcion', i.descripcion,
                            'resultado',   i.resultado,
                            'observacion', i.observacion,
                            'foto_url',    i.foto_url,
                            'critico',     i.critico,
                            'aplica_tipo', i.aplica_tipo) ORDER BY i.orden)) AS b
                  FROM auditoria_calidad_items i
                 WHERE i.auditoria_id = ac.id
                 GROUP BY COALESCE(i.bloque,'Sin bloque'), i.bloque_orden, i.categoria
              ) x), '[]'::jsonb),
        'hallazgos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                    'descripcion', i.descripcion, 'observacion', i.observacion,
                    'foto_url', i.foto_url, 'critico', i.critico,
                    'bloque', i.bloque) ORDER BY i.critico DESC, i.orden)
              FROM auditoria_calidad_items i
             WHERE i.auditoria_id = ac.id AND i.resultado = 'no_ok'), '[]'::jsonb),
        'pendientes', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                    'descripcion', d.descripcion, 'sistema', d.sistema,
                    'severidad', d.severidad, 'diferible', d.diferible,
                    'plazo', d.plazo_fecha_limite, 'estado', d.estado)
                   ORDER BY d.plazo_fecha_limite NULLS LAST)
              FROM items_diferidos d
             WHERE d.activo_id = ac.activo_id AND d.estado = 'pendiente'), '[]'::jsonb),
        'documentos', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                    'tipo', ce.tipo, 'numero', ce.numero_certificado,
                    'entidad', ce.entidad_certificadora,
                    'vence', ce.fecha_vencimiento, 'estado', ce.estado,
                    'bloqueante', ce.bloqueante)
                   ORDER BY ce.fecha_vencimiento NULLS LAST)
              FROM certificaciones ce
             WHERE ce.activo_id = ac.activo_id), '[]'::jsonb)
    )
    INTO v_out
    FROM auditorias_calidad ac
    JOIN activos a            ON a.id = ac.activo_id
    LEFT JOIN modelos mo      ON mo.id = a.modelo_id
    LEFT JOIN marcas ma       ON ma.id = mo.marca_id
    LEFT JOIN contratos c     ON c.id = a.contrato_id
    LEFT JOIN faenas f        ON f.id = a.faena_id
    LEFT JOIN usuarios_perfil ua ON ua.id = COALESCE(ac.auditor_id, ac.iniciada_por)
    WHERE ac.id = p_auditoria_id;

    IF v_out IS NULL THEN RAISE EXCEPTION 'La auditoría no existe.'; END IF;
    RETURN v_out;
END;
$function$;

COMMENT ON FUNCTION public.fn_informe_salida_arriendo(UUID) IS
    'Informe de Salida a Arriendo: equipo, auditor, resultado, ítems por bloque con su foto, hallazgos, pendientes y documentos. MIG263.';

REVOKE ALL ON FUNCTION public.fn_informe_salida_arriendo(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_informe_salida_arriendo(UUID) TO authenticated;


-- ── 5. Los informes emitidos, para encontrarlos después ─────────────────────
CREATE OR REPLACE VIEW public.v_informes_salida_arriendo AS
SELECT ac.id            AS auditoria_id,
       ac.folio,
       ac.activo_id,
       a.patente,
       a.codigo,
       ac.resultado,
       ac.fecha_auditoria,
       ac.vigente_hasta,
       (ac.vigente_hasta > NOW())        AS vigente,
       ac.puntaje,
       ac.items_total, ac.items_ok, ac.items_no_ok, ac.items_na,
       (SELECT count(*) FROM auditoria_calidad_items i
         WHERE i.auditoria_id = ac.id AND COALESCE(length(trim(i.foto_url)),0) > 0)::int AS fotos,
       ua.nombre_completo AS auditor
  FROM auditorias_calidad ac
  JOIN activos a ON a.id = ac.activo_id
  LEFT JOIN usuarios_perfil ua ON ua.id = ac.auditor_id
 WHERE ac.folio IS NOT NULL
 ORDER BY ac.fecha_auditoria DESC;

COMMENT ON VIEW public.v_informes_salida_arriendo IS
    'Informes de salida a arriendo emitidos (auditorías aprobadas con folio). MIG263.';

GRANT SELECT ON public.v_informes_salida_arriendo TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_activo UUID; v_r JSONB; v_id UUID; v_falta INT;
    v_inf JSONB; v_err TEXT; v_item UUID;
BEGIN
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='auditor_calidad' AND activo LIMIT 1;
    IF v_user IS NULL THEN
        SELECT id INTO v_user FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    END IF;
    IF v_user IS NULL THEN RAISE NOTICE 'MIG263: sin auditor para el smoke'; RETURN; END IF;

    -- Un equipo sin OT ejecutadas por este usuario, para no chocar con la SoD.
    SELECT a.id INTO v_activo FROM activos a
     WHERE a.fecha_baja IS NULL
       AND NOT EXISTS (SELECT 1 FROM taller_ot_ejecuciones e
                        JOIN ordenes_trabajo o ON o.id=e.ot_id
                       WHERE o.activo_id=a.id AND e.ejecutor_id=v_user)
     LIMIT 1;

    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);

    v_r  := fn_iniciar_auditoria_calidad(v_activo, NULL);
    v_id := (v_r->>'auditoria_id')::uuid;

    -- Todo OK menos un hallazgo, y sin ninguna foto.
    UPDATE auditoria_calidad_items SET resultado='ok' WHERE auditoria_id=v_id;
    -- El hallazgo del smoke va sobre un ítem NO crítico: uno crítico en no_ok
    -- bloquea la aprobación por otra vía y no probaríamos la evidencia.
    SELECT id INTO v_item FROM auditoria_calidad_items
     WHERE auditoria_id=v_id AND critico = false ORDER BY orden LIMIT 1;
    UPDATE auditoria_calidad_items SET resultado='no_ok', observacion='Smoke MIG263' WHERE id=v_item;

    SELECT count(*) INTO v_falta FROM fn_auditoria_evidencia_faltante(v_id);
    IF v_falta = 0 THEN RAISE EXCEPTION 'FALLO — no detectó la falta de fotos'; END IF;

    -- Aprobar sin fotos tiene que rebotar.
    BEGIN
        PERFORM fn_resolver_auditoria_calidad(v_id, 'aprobado', '[]'::jsonb, NULL, NULL,
                                              'https://x/firma.png', '[]'::jsonb, 3);
        RAISE EXCEPTION 'FALLO — aprobó sin la evidencia fotográfica';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
        IF SQLERRM NOT LIKE '%foto%' THEN RAISE EXCEPTION 'FALLO — rebotó por otra razón: %', SQLERRM; END IF;
    END;

    -- Con las fotos puestas, aprueba y emite folio.
    UPDATE auditoria_calidad_items
       SET foto_url = 'https://ejemplo/evidencia.jpg'
     WHERE auditoria_id = v_id AND (resultado='no_ok' OR requiere_foto);

    -- Sin firma tampoco.
    BEGIN
        PERFORM fn_resolver_auditoria_calidad(v_id, 'aprobado', '[]'::jsonb, NULL, NULL,
                                              NULL, '[]'::jsonb, 3);
        RAISE EXCEPTION 'FALLO — aprobó sin firma del auditor';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FALLO%' THEN RAISE; END IF;
        IF SQLERRM NOT LIKE '%firma%' THEN RAISE EXCEPTION 'FALLO — rebotó por otra razón: %', SQLERRM; END IF;
    END;

    v_r := fn_resolver_auditoria_calidad(v_id, 'aprobado_con_observaciones', '[]'::jsonb,
              NULL, 'Smoke MIG263', 'https://ejemplo/firma.png', '[]'::jsonb, 5);
    IF (v_r->>'folio') IS NULL THEN RAISE EXCEPTION 'FALLO — no se emitió el folio del informe'; END IF;

    v_inf := fn_informe_salida_arriendo(v_id);
    IF jsonb_array_length(v_inf->'bloques') < 10 THEN
        RAISE EXCEPTION 'FALLO — el informe salió con % bloques', jsonb_array_length(v_inf->'bloques');
    END IF;
    IF jsonb_array_length(v_inf->'hallazgos') <> 1 THEN
        RAISE EXCEPTION 'FALLO — el informe no trae el hallazgo';
    END IF;
    IF (v_inf->'hallazgos'->0->>'foto_url') IS NULL THEN
        RAISE EXCEPTION 'FALLO — el hallazgo del informe va sin foto';
    END IF;

    RAISE NOTICE 'MIG263 OK — folio %, % bloques, % hallazgo(s) con foto, equipo %',
        v_r->>'folio', jsonb_array_length(v_inf->'bloques'),
        jsonb_array_length(v_inf->'hallazgos'), v_inf->'equipo'->>'patente';

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
