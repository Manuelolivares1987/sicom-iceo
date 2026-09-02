-- ============================================================================
-- MIG495 · Traer el checklist a la versión vigente de su pauta
-- ============================================================================
--
-- LO QUE VIO MANUEL
-- 02-09-2026: abrió la OT-202609-00002 (Atego, servicio SM4) y seguía diciendo
-- «SM3 completo», después de que MIG494 abriera las pautas escalonadas.
--
-- POR QUÉ
-- Esa OT se creó a las 19:35 y MIG494 rehizo los checklists unos minutos
-- después. El checklist de una OT es una COPIA del template al momento de
-- crearla — tiene que serlo, porque si no, editar una pauta le cambiaría las
-- preguntas a alguien que ya está respondiendo. Así que la OT se quedó con la
-- versión vieja: 3 ítems, uno de ellos «SM3 completo».
--
-- No es un error de MIG494: es su regla de seguridad funcionando. Lo que
-- faltaba era la puerta para el caso legítimo — un checklist que nadie tocó
-- todavía puede actualizarse sin costo.
--
-- LO QUE HACE
--   1. Una función para traer el checklist de una OT a la versión vigente de su
--      pauta, SÓLO si nadie respondió nada. Con una sola respuesta puesta, no
--      se toca: el mecánico se quedaría sin lo que ya marcó.
--   2. La aplica a las que hoy están en esa situación: 2 checklists, los dos
--      sin responder.
--
-- El checklist viejo se ANULA, no se borra: queda el rastro de que hubo un
-- cambio de versión y por qué.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION rpc_taller_ot_actualizar_checklist_pauta(p_ot_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_rol      TEXT;
    v_inst     UUID;
    v_tpl_act  UUID;
    v_pauta    UUID;
    v_tocado   BOOLEAN;
    v_contrato UUID;
    v_horas    NUMERIC;
    v_km       NUMERIC;
    v_nuevo    UUID;
    v_activo   UUID;
    v_n        INT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones',
                     'jefe_mantenimiento','planificador') THEN
        RAISE EXCEPTION 'Rol % no autorizado para actualizar el checklist', v_rol;
    END IF;

    SELECT i.id, t.pauta_fabricante_id, i.activo_id
      INTO v_inst, v_pauta, v_activo
      FROM checklist_v2_instance i
      JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = p_ot_id AND i.estado = 'en_progreso'
     ORDER BY i.fecha_inicio DESC LIMIT 1;

    IF v_inst IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'motivo', 'Esta OT no tiene un checklist abierto.');
    END IF;
    IF v_pauta IS NULL THEN
        RETURN jsonb_build_object('success', FALSE,
            'motivo', 'El checklist de esta OT no viene de una pauta del fabricante.');
    END IF;

    SELECT t2.id INTO v_tpl_act FROM checklist_template_v2 t2
     WHERE t2.pauta_fabricante_id = v_pauta AND t2.activo
     ORDER BY t2.version DESC LIMIT 1;

    IF v_tpl_act IS NULL THEN
        RETURN jsonb_build_object('success', FALSE, 'motivo', 'La pauta no tiene una versión vigente.');
    END IF;
    IF v_tpl_act = (SELECT template_id FROM checklist_v2_instance WHERE id = v_inst) THEN
        RETURN jsonb_build_object('success', TRUE, 'ya_estaba', TRUE);
    END IF;

    SELECT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                    WHERE ii.instance_id = v_inst
                      AND COALESCE(ii.resultado, 'pendiente') <> 'pendiente')
      INTO v_tocado;
    IF v_tocado THEN
        RETURN jsonb_build_object('success', FALSE,
            'motivo', 'Este checklist ya tiene respuestas. Cambiarlo dejaría sin efecto lo '
                   || 'que el mecánico marcó, así que se termina con el que empezó.');
    END IF;

    SELECT contrato_id, horas_uso_actual, kilometraje_actual
      INTO v_contrato, v_horas, v_km FROM activos WHERE id = v_activo;

    UPDATE checklist_v2_instance
       SET estado = 'anulado',
           observaciones = trim(COALESCE(observaciones,'') ||
               ' [MIG495] Reemplazado por la versión vigente de la pauta.')
     WHERE id = v_inst;

    v_nuevo := fn_inicializar_checklist_v2(
        v_tpl_act, v_activo, v_contrato, NULL, v_horas, v_km, NULL, NULL);
    UPDATE checklist_v2_instance SET ot_id = p_ot_id WHERE id = v_nuevo;

    SELECT count(*) INTO v_n FROM checklist_v2_instance_item WHERE instance_id = v_nuevo;

    RETURN jsonb_build_object('success', TRUE, 'instance_id', v_nuevo, 'pasos', v_n);
END;
$$;

COMMENT ON FUNCTION rpc_taller_ot_actualizar_checklist_pauta(UUID) IS
    'Trae el checklist de una OT a la versión vigente de su pauta, sólo si nadie '
    'respondió nada. El anterior queda anulado, no borrado.';

-- ── Las que hoy quedaron atrás ──────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_n INT := 0; v_admin UUID;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    FOR r IN
        SELECT DISTINCT i.ot_id, ot.folio
          FROM checklist_v2_instance i
          JOIN checklist_template_v2 t ON t.id = i.template_id
          JOIN ordenes_trabajo ot ON ot.id = i.ot_id
         WHERE i.estado = 'en_progreso'
           AND t.pauta_fabricante_id IS NOT NULL
           AND NOT t.activo
           AND NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                            WHERE ii.instance_id = i.id
                              AND COALESCE(ii.resultado,'pendiente') <> 'pendiente')
    LOOP
        RAISE NOTICE '  %: %', r.folio, rpc_taller_ot_actualizar_checklist_pauta(r.ot_id);
        v_n := v_n + 1;
    END LOOP;
    RAISE NOTICE 'checklists traídos a la versión vigente: %', v_n;
END $mig$;

REVOKE ALL ON FUNCTION rpc_taller_ot_actualizar_checklist_pauta(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_ot_actualizar_checklist_pauta(UUID) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE v_atras INT; v_completo INT;
BEGIN
    SELECT count(*) INTO v_atras
      FROM checklist_v2_instance i
      JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.estado = 'en_progreso' AND t.pauta_fabricante_id IS NOT NULL AND NOT t.activo;

    SELECT count(*) INTO v_completo
      FROM checklist_v2_instance_item ii
      JOIN checklist_v2_instance i ON i.id = ii.instance_id
      JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
     WHERE i.estado = 'en_progreso'
       AND fn_pauta_ref_codigo(ti.descripcion) IS NOT NULL;

    RAISE NOTICE 'checklists abiertos con versión vieja: % · pasos que aún dicen «completo»: %',
                 v_atras, v_completo;
END $mig$;

COMMIT;
