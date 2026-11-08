-- 673 — «Observación» en el checklist: el ítem funciona pero hay que mirarlo (Manuel 08-11-2026,
-- benchmark MaintainX: Pass / Flag / Fail).
--
-- Hasta hoy el mecánico tenía OK / NO OK / N.A. Lo que «está bien pero hay que cambiarlo en la
-- próxima» quedaba como OK (se perdía) o como NO OK (bloqueaba el certificado por algo que no
-- impide trabajar). Ahora:
--   * checklist_v2_instance_item.observado: marca sobre un ítem OK. NO cambia `resultado`, así
--     que los conteos de calidad, fiabilidad e informes que leen ok/no_ok siguen igual.
--   * Marcarla abre sola una NC DIFERIBLE (severidad baja) en la recepción con OT, igual que el
--     NO OK abre la suya. Desmarcarla la retira si nadie la tocó todavía.
--   * La NC diferible NO bloquea el certificado; queda en la bandeja para la próxima OS.
--   * Si el ítem pasa a NO OK, la NC diferible sube a normal (severidad media, bloquea), y si
--     vuelve de NO OK a «OK con observación», baja a diferible en vez de borrarse.

ALTER TABLE checklist_v2_instance_item ADD COLUMN IF NOT EXISTS observado BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN checklist_v2_instance_item.observado IS
    '[MIG673] OK con observación: funciona pero hay que atenderlo en la próxima OS. Abre una NC diferible.';

ALTER TABLE no_conformidades ADD COLUMN IF NOT EXISTS diferible BOOLEAN NOT NULL DEFAULT false;
COMMENT ON COLUMN no_conformidades.diferible IS
    '[MIG673] Nació de una observación: no bloquea el certificado; se resuelve en la próxima OS.';

-- ── La observación abre / retira su NC diferible ────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_trg_observado_a_nc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inst RECORD;
    v_desc TEXT;
BEGIN
    IF NEW.observado IS NOT DISTINCT FROM OLD.observado THEN RETURN NEW; END IF;

    SELECT i.ot_id, i.activo_id, i.momento_uso INTO v_inst
      FROM checklist_v2_instance i WHERE i.id = NEW.instance_id;
    IF v_inst.ot_id IS NULL OR v_inst.momento_uso <> 'recepcion_devolucion' THEN
        RETURN NEW;
    END IF;

    IF NEW.observado THEN
        -- Si ya hay NC para el ítem (p.ej. venía de un NO OK), no se duplica.
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = NEW.id) THEN
            RETURN NEW;
        END IF;
        v_desc := COALESCE(
            (SELECT ti.descripcion FROM checklist_template_v2_item ti WHERE ti.id = NEW.template_item_id),
            NULLIF(TRIM(NEW.descripcion_custom), ''),
            'Ítem de inspección');
        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen,
            checklist_item_ref, estado_planificacion, registrada_por, created_by, diferible
        ) VALUES (
            v_inst.activo_id, v_inst.ot_id, 'otra',
            'Observación: ' || v_desc || COALESCE(' — ' || NULLIF(TRIM(NEW.observacion), ''), ''),
            CURRENT_DATE, 'baja', 'inspeccion_ot',
            NEW.id, 'registrada', auth.uid(), auth.uid(), true
        );
    ELSIF NEW.resultado IS DISTINCT FROM 'no_ok' THEN
        -- Se quitó la marca: se retira la NC diferible si todavía no tiene vida propia.
        DELETE FROM no_conformidades n
         WHERE n.checklist_item_ref = NEW.id AND n.diferible
           AND n.estado_planificacion = 'registrada' AND n.plan_ot_id IS NULL AND NOT n.resuelto
           AND NOT EXISTS (SELECT 1 FROM nc_materiales m WHERE m.no_conformidad_id = n.id)
           AND NOT EXISTS (SELECT 1 FROM taller_os_nc x WHERE x.no_conformidad_id = n.id);
    END IF;
    RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_observado_a_nc ON checklist_v2_instance_item;
CREATE TRIGGER trg_observado_a_nc AFTER UPDATE OF observado ON checklist_v2_instance_item
    FOR EACH ROW EXECUTE FUNCTION fn_trg_observado_a_nc();

-- ── NO OK sobre un ítem observado: la NC diferible sube a normal ────────────
-- (trg_nc_al_marcar_no_ok corre antes que trg_observado_a_nc por orden alfabético, y el
-- DELETE de arriba exige diferible = true: una NC ya subida nunca se borra.)
CREATE OR REPLACE FUNCTION public.fn_trg_nc_al_marcar_no_ok()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_inst   RECORD;
    v_desc   TEXT;
    v_nc     UUID;
BEGIN
    SELECT i.id, i.ot_id, i.activo_id, i.momento_uso
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.id = NEW.instance_id;

    IF v_inst.ot_id IS NULL OR v_inst.momento_uso <> 'recepcion_devolucion' THEN
        RETURN NEW;
    END IF;

    -- ── Se marcó NO OK: nace la no conformidad ──────────────────────────────
    IF NEW.resultado = 'no_ok' AND OLD.resultado IS DISTINCT FROM 'no_ok' THEN
        IF EXISTS (SELECT 1 FROM no_conformidades WHERE checklist_item_ref = NEW.id) THEN
            -- [MIG673] Venía como observación: ahora es una falla de verdad.
            UPDATE no_conformidades
               SET diferible = false, severidad = 'media',
                   descripcion = regexp_replace(descripcion, '^Observación: ', ''),
                   updated_at = NOW()
             WHERE checklist_item_ref = NEW.id AND diferible;
            RETURN NEW;
        END IF;
        -- [MIG537] Las tareas a medida no tienen plantilla: su nombre vive en
        -- descripcion_custom. Antes la NC nacía sin nombre.
        v_desc := COALESCE(
            (SELECT ti.descripcion FROM checklist_template_v2_item ti WHERE ti.id = NEW.template_item_id),
            NULLIF(TRIM(NEW.descripcion_custom), ''),
            'Ítem de inspección');

        INSERT INTO no_conformidades (
            activo_id, ot_id, tipo, descripcion, fecha_evento, severidad, origen,
            checklist_item_ref, estado_planificacion, registrada_por, created_by
        ) VALUES (
            v_inst.activo_id, v_inst.ot_id, 'otra',
            v_desc || COALESCE(' — ' || NULLIF(TRIM(NEW.observacion), ''), ''),
            CURRENT_DATE, 'media', 'inspeccion_ot',
            NEW.id, 'registrada', auth.uid(), auth.uid()
        );
        RETURN NEW;
    END IF;

    -- ── Se corrigió: la NC se retira, salvo que ya tenga vida propia ────────
    IF OLD.resultado = 'no_ok' AND NEW.resultado IS DISTINCT FROM 'no_ok' THEN
        SELECT id INTO v_nc FROM no_conformidades WHERE checklist_item_ref = NEW.id;
        IF v_nc IS NULL THEN RETURN NEW; END IF;

        IF EXISTS (SELECT 1 FROM no_conformidades n
                    WHERE n.id = v_nc
                      AND (n.estado_planificacion IS DISTINCT FROM 'registrada'
                           OR n.plan_ot_id IS NOT NULL
                           OR n.resuelto
                           OR EXISTS (SELECT 1 FROM nc_materiales m WHERE m.no_conformidad_id = n.id))) THEN
            RETURN NEW;
        END IF;

        -- [MIG673] De NO OK a «OK con observación»: la NC baja a diferible, no se borra.
        IF NEW.observado THEN
            UPDATE no_conformidades
               SET diferible = true, severidad = 'baja',
                   descripcion = 'Observación: ' || regexp_replace(descripcion, '^Observación: ', ''),
                   updated_at = NOW()
             WHERE id = v_nc;
            RETURN NEW;
        END IF;

        DELETE FROM no_conformidades WHERE id = v_nc;
    END IF;

    RETURN NEW;
END $function$;

-- ── Vistas: exponen la marca (columnas nuevas al final) ─────────────────────
CREATE OR REPLACE VIEW v_taller_ot_checklist_v3 AS
 WITH inst AS (
         SELECT DISTINCT ON (checklist_v2_instance.ot_id) checklist_v2_instance.id,
            checklist_v2_instance.ot_id,
            checklist_v2_instance.activo_id,
            checklist_v2_instance.estado,
            checklist_v2_instance.arrastre_de_instance_id,
            checklist_v2_instance.momento_uso
           FROM checklist_v2_instance
          WHERE checklist_v2_instance.ot_id IS NOT NULL
          ORDER BY checklist_v2_instance.ot_id, checklist_v2_instance.fecha_inicio DESC
        )
 SELECT ii.id AS instance_item_id,
    inst.id AS instance_id,
    inst.ot_id,
    inst.estado AS instance_estado,
    COALESCE(ti.bloque::text, 'Tareas adicionales'::text) AS bloque,
    COALESCE(ti.bloque_orden, 999) AS bloque_orden,
    COALESCE(ti.orden, 9999) AS orden,
    ti.codigo,
    COALESCE(ii.descripcion_custom, ti.descripcion::character varying) AS descripcion,
    COALESCE(ii.tiempo_min_override, ti.tiempo_min::numeric) AS tiempo_min,
    ii.tiempo_min_override IS NOT NULL AS tiempo_editado,
    COALESCE(ti.requiere_foto, false) AS requiere_foto,
    COALESCE(ti.obligatorio, false) AS obligatorio,
    COALESCE(ti.critico, false) AS critico,
    ti.categoria_calidad,
    ii.resultado,
    ii.observacion,
    ii.foto_url,
    ii.excluido,
    ii.template_item_id IS NULL AS es_custom,
    ii.mediciones,
    ii.foto_urls,
    inst.arrastre_de_instance_id IS NOT NULL AS instance_arrastre,
    po.folio AS arrastre_ot_folio,
    COALESCE(pi.fecha_cierre, pi.fecha_inicio) AS arrastre_fecha,
    ii.arrastre_de_item_id IS NOT NULL AS arrastre,
    pii.observacion AS arrastre_observacion,
    pii.foto_url AS arrastre_foto_url,
    COALESCE(ti.tipo_respuesta, ii.tipo_respuesta_custom, 'ok_no_ok'::text) AS tipo_respuesta,
    ii.valor_numerico,
    ii.observado,
    inst.momento_uso::text AS momento_uso
   FROM inst
     JOIN checklist_v2_instance_item ii ON ii.instance_id = inst.id
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     LEFT JOIN checklist_v2_instance pi ON pi.id = inst.arrastre_de_instance_id
     LEFT JOIN ordenes_trabajo po ON po.id = pi.ot_id
     LEFT JOIN checklist_v2_instance_item pii ON pii.id = ii.arrastre_de_item_id;

CREATE OR REPLACE VIEW v_nc_recepcion AS
 SELECT nc.id,
    nc.activo_id,
    a.patente,
    a.codigo,
    a.nombre AS equipo,
    nc.descripcion,
    nc.severidad,
    nc.origen,
    nc.estado_planificacion,
    nc.grupo_trabajo,
    nc.horas_estimadas,
    nc.tiempo_estimado_dias,
    nc.informe_recepcion_id,
    nc.plan_ot_id,
    nc.resuelto,
    nc.created_at,
    ( SELECT count(*) AS count
           FROM nc_materiales m
          WHERE m.no_conformidad_id = nc.id) AS n_materiales,
    nc.ot_id,
    nc.foto_url,
    nc.checklist_item_ref,
    ( SELECT count(*) AS count
           FROM ot_recursos_solicitados r
          WHERE r.instance_item_id = nc.checklist_item_ref) AS n_recursos_operador,
    ii.observacion AS observacion_item,
    ot.folio AS ot_folio,
    up.nombre_completo AS registrada_por_nombre,
    COALESCE(nc.recobro_override, ii.cobrable_override, ti.default_cobrable,
        CASE
            WHEN h.atribuible_cliente IS TRUE THEN 'cliente'::default_cobrable_enum
            WHEN h.atribuible_cliente IS FALSE THEN 'empresa'::default_cobrable_enum
            ELSE NULL::default_cobrable_enum
        END) AS recobro,
        CASE
            WHEN nc.recobro_override IS NOT NULL THEN 'jefe'::text
            WHEN ii.cobrable_override IS NOT NULL THEN 'terreno'::text
            WHEN ti.default_cobrable IS NOT NULL THEN 'pauta'::text
            WHEN h.atribuible_cliente IS NOT NULL THEN 'informe'::text
            ELSE 'sin_definir'::text
        END AS recobro_fuente,
    nc.recobro_nota,
    ( SELECT count(*) AS count
           FROM evidencias_ot e
          WHERE e.tipo::text = 'nota'::text AND (e.ot_id = nc.ot_id OR e.ot_id = nc.plan_ot_id)) AS n_notas_operador,
    nc.recobro_informe_id,
    ir.folio AS recobro_informe_folio,
    ir.estado::text AS recobro_informe_estado,
    COALESCE(( SELECT sum(m.cantidad * COALESCE(p.costo_unitario_actual, 0::numeric)) AS sum
           FROM nc_materiales m
             LEFT JOIN productos p ON p.id = m.producto_id
          WHERE m.no_conformidad_id = nc.id), 0::numeric) AS costo_materiales_estimado,
    nc.nota_evidencia_id,
    nc.archivado_at,
    nc.archivado_motivo,
    ( SELECT x.os_id
           FROM taller_os_nc x
             JOIN taller_os o ON o.id = x.os_id AND o.estado <> 'anulada'::text
          WHERE x.no_conformidad_id = nc.id
         LIMIT 1) AS os_id,
    ( SELECT o.folio
           FROM taller_os_nc x
             JOIN taller_os o ON o.id = x.os_id AND o.estado <> 'anulada'::text
          WHERE x.no_conformidad_id = nc.id
         LIMIT 1) AS os_folio,
    nc.diferible
   FROM no_conformidades nc
     JOIN activos a ON a.id = nc.activo_id
     LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
     LEFT JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     LEFT JOIN informe_recepcion_hallazgos h ON h.id = nc.hallazgo_id
     LEFT JOIN ordenes_trabajo ot ON ot.id = COALESCE(nc.plan_ot_id, nc.ot_id)
     LEFT JOIN usuarios_perfil up ON up.id = nc.registrada_por
     LEFT JOIN informes_recepcion ir ON ir.id = nc.recobro_informe_id
  WHERE nc.origen::text = ANY (ARRAY['recepcion_checklist'::text, 'recepcion_adhoc'::text, 'inspeccion_ot'::text, 'ejecucion_ot'::text, 'manual'::text, 'checklist_cliente'::text, 'auditoria_calidad'::text]);

-- ── El certificado no lo bloquea una observación ────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_emitir_certificado_activo(p_activo_id uuid, p_tipo_codigo text, p_datos jsonb, p_operador_nombre text, p_firma_operador_url text, p_firma_jefe_url text, p_operador_tecnico_id uuid DEFAULT NULL::uuid, p_fecha_emision date DEFAULT NULL::date, p_ciudad text DEFAULT NULL::text, p_ot_id uuid DEFAULT NULL::uuid, p_vence_el date DEFAULT NULL::date, p_horometro_emision numeric DEFAULT NULL::numeric, p_vigencia_horas numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_jefe TEXT; v_nc INT; v_numero INT; v_id UUID; v_fecha DATE;
    v_horo NUMERIC; v_lista TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Rol % no autorizado para emitir certificados', v_rol;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificado_tipos WHERE codigo = p_tipo_codigo AND activo) THEN
        RAISE EXCEPTION 'Tipo de certificado "%" no existe', p_tipo_codigo;
    END IF;
    IF COALESCE(TRIM(p_operador_nombre),'') = '' THEN
        RAISE EXCEPTION 'Indica el operador que realizó el trabajo';
    END IF;
    IF COALESCE(TRIM(p_firma_operador_url),'') = '' OR COALESCE(TRIM(p_firma_jefe_url),'') = '' THEN
        RAISE EXCEPTION 'El certificado requiere la firma del operador Y la del jefe de taller';
    END IF;

    -- GATE [MIG671/673]: bloquean las NC abiertas que están en la bandeja (no archivadas),
    -- y el mensaje dice CUÁLES, no solo cuántas.
    SELECT COUNT(*),
           string_agg(left(descripcion, 60), ' · ' ORDER BY created_at) FILTER (WHERE rn <= 3)
      INTO v_nc, v_lista
      FROM (SELECT descripcion, created_at, row_number() OVER (ORDER BY created_at) rn
              FROM no_conformidades
             WHERE activo_id = p_activo_id AND COALESCE(resuelto, false) = false
               AND archivado_at IS NULL
               AND NOT diferible) s;   -- [MIG673] la observación no bloquea
    IF v_nc > 0 THEN
        RAISE EXCEPTION 'El equipo tiene % No Conformidad(es) abiertas: % — ciérralas en la bandeja de NC antes de emitir.',
            v_nc, v_lista || CASE WHEN v_nc > 3 THEN ' (y ' || (v_nc - 3) || ' más)' ELSE '' END;
    END IF;

    v_fecha := COALESCE(p_fecha_emision, CURRENT_DATE);
    IF p_vence_el IS NOT NULL AND p_vence_el < v_fecha THEN
        RAISE EXCEPTION 'El vencimiento no puede ser anterior a la emisión.';
    END IF;

    -- [MIG514] Vigencia por horas: el horómetro de emisión es obligatorio
    -- (si no viene, se toma el del maestro — y si tampoco está, se exige).
    IF p_vigencia_horas IS NOT NULL THEN
        IF p_vigencia_horas <= 0 THEN
            RAISE EXCEPTION 'La vigencia en horas tiene que ser mayor que cero.';
        END IF;
        v_horo := COALESCE(p_horometro_emision,
                           (SELECT a.horas_uso_actual FROM activos a WHERE a.id = p_activo_id));
        IF v_horo IS NULL THEN
            RAISE EXCEPTION 'Anota el horómetro del equipo: la vigencia por horas se cuenta desde ahí.';
        END IF;
    END IF;

    SELECT nombre_completo INTO v_jefe FROM usuarios_perfil WHERE id = v_user;

    PERFORM pg_advisory_xact_lock(hashtext('cert_activo_' || p_activo_id::text));
    SELECT COALESCE(max(numero), 0) + 1 INTO v_numero
      FROM activo_certificados WHERE activo_id = p_activo_id;

    INSERT INTO activo_certificados (
        activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
        operador_tecnico_id, operador_nombre, firma_operador_url,
        jefe_nombre, firma_jefe_url, ot_id, vence_el,
        horometro_emision, vigencia_horas, created_by)
    VALUES (
        p_activo_id, p_tipo_codigo, v_numero, v_fecha,
        COALESCE(NULLIF(TRIM(p_ciudad),''), 'Coquimbo'), COALESCE(p_datos, '{}'::jsonb),
        p_operador_tecnico_id, TRIM(p_operador_nombre), p_firma_operador_url,
        COALESCE(v_jefe, '—'), p_firma_jefe_url, p_ot_id, p_vence_el,
        v_horo, p_vigencia_horas, v_user)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'id', v_id, 'certificado_id', v_id, 'numero', v_numero,
        'horometro_vence', CASE WHEN p_vigencia_horas IS NOT NULL THEN v_horo + p_vigencia_horas END);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_emitir_certificado_activo(uuid,text,jsonb,text,text,text,uuid,date,text,uuid,date,numeric,numeric) TO authenticated;


NOTIFY pgrst, 'reload schema';
