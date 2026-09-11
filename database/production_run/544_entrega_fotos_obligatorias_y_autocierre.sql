-- ============================================================================
-- MIG544 · Entrega en arriendo: fotos por ítem obligatorias + acta que se cierra
-- ============================================================================
-- Manuel (2026-09-10, revisando OT-202609-00019): «No pide foto obligatoria y
-- eso es clave». En esa entrega los 10 ítems con requiere_foto quedaron OK sin
-- ninguna foto — incluidos EC.10/EC.11/EC.12 que SON una foto — y el acta V02
-- quedó en_progreso para siempre (la OT ejecutada_ok, el documento nunca
-- cerrado ni firmado a nivel de instancia).
--
-- Por qué pasó: MIG539 eximió a la entrega del candado global de "1 foto de
-- evidencia" (su evidencia son las firmas), pero nadie exigía la foto POR ÍTEM
-- que el template declara. MIG539 NO se revierte: el candado global sigue
-- eximido; lo que se agrega es la exigencia fina.
--
-- Decisión Manuel (2026-09-11): exigir las 10 fotos del template + auto-cerrar
-- el acta al finalizar la OT.
--
--   1. fn_validar_entrega_fotos_firmas (BEFORE UPDATE OF estado):
--      al pasar a ejecutada_ok/ejecutada_con_observaciones una OT cuyo
--      checklist es de entrega_arriendo:
--        a) todo ítem no excluido con requiere_foto y resultado <> 'na'
--           debe tener foto_url (el escape legítimo es marcar N/A o excluir
--           el ítem en preparación, no saltarse la foto);
--        b) los ítems de firma (ED.08/ED.09) deben tener la firma capturada
--           en mediciones (la evidencia que MIG539 invoca debe existir).
--   2. fn_autocerrar_checklist_entrega (AFTER UPDATE OF estado):
--      cierra la instancia V02 (estado='cerrado', fecha_cierre, firmas y
--      RUT/nombre copiados desde los ítems ED.08/ED.09) si no quedan
--      obligatorios pendientes. El acta queda inmutable y válida para el
--      gate de 48h de ARRENDADO.
--
-- Solo aplica a OT con checklist de momento 'entrega_arriendo'; las OT de
-- taller siguen con sus reglas (candado global de evidencia + MIG472).
-- IDEMPOTENTE. Prueba E2E al final con rollback (truco MIG539).
-- ============================================================================

BEGIN;

-- ── 1. Validación BEFORE: fotos por ítem + firmas capturadas ─────────────────
CREATE OR REPLACE FUNCTION public.fn_validar_entrega_fotos_firmas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_inst        UUID;
    v_sin_foto    INTEGER;
    v_codigos     TEXT;
    v_sin_firma   INTEGER;
BEGIN
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        SELECT ci.id INTO v_inst
          FROM checklist_v2_instance ci
          JOIN checklist_template_v2 t ON t.id = ci.template_id
         WHERE ci.ot_id = NEW.id
           AND t.momento_uso = 'entrega_arriendo'
           AND ci.estado <> 'anulado'
         LIMIT 1;

        IF v_inst IS NULL THEN
            RETURN NEW;  -- no es una entrega: no aplica
        END IF;

        -- a) Fotos por ítem: requiere_foto ⇒ foto, salvo N/A o excluido.
        SELECT COUNT(*), string_agg(ti.codigo, ', ' ORDER BY ti.bloque_orden, ti.orden)
          INTO v_sin_foto, v_codigos
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst
           AND COALESCE(ii.excluido, false) = false
           AND ti.requiere_foto = true
           AND COALESCE(ii.resultado, 'pendiente') <> 'na'
           AND (ii.foto_url IS NULL OR length(trim(ii.foto_url)) = 0);

        IF v_sin_foto > 0 THEN
            RAISE EXCEPTION
              'ENTREGA V02: faltan % fotos obligatorias del checklist (%). '
              'La foto del estado al entregar es la defensa del recobro: '
              'capturela en cada item antes de finalizar la OT %.',
              v_sin_foto, v_codigos, NEW.folio;
        END IF;

        -- b) Firmas de los ítems de firma (técnico entrega / cliente acepta).
        SELECT COUNT(*) INTO v_sin_firma
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst
           AND COALESCE(ii.excluido, false) = false
           AND ti.tipo_respuesta = 'firma'
           AND COALESCE(ii.mediciones->>'firma_operador_url', '') = '';

        IF v_sin_firma > 0 THEN
            RAISE EXCEPTION
              'ENTREGA V02: faltan % firmas del acta (tecnico que entrega y/o '
              'cliente que acepta). Capturelas en el checklist antes de '
              'finalizar la OT %.', v_sin_firma, NEW.folio;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ot_entrega_fotos_firmas ON ordenes_trabajo;
CREATE TRIGGER trg_ot_entrega_fotos_firmas
    BEFORE UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_validar_entrega_fotos_firmas();


-- ── 2. AFTER: el acta V02 se cierra sola al finalizar la OT de entrega ───────
CREATE OR REPLACE FUNCTION public.fn_autocerrar_checklist_entrega()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_inst       RECORD;
    v_pendientes INTEGER;
    v_tec        JSONB;   -- ED.08: firma técnico que entrega
    v_cli        JSONB;   -- ED.09: firma representante cliente
BEGIN
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        SELECT ci.* INTO v_inst
          FROM checklist_v2_instance ci
          JOIN checklist_template_v2 t ON t.id = ci.template_id
         WHERE ci.ot_id = NEW.id
           AND t.momento_uso = 'entrega_arriendo'
           AND ci.estado = 'en_progreso'
         LIMIT 1;

        IF v_inst.id IS NULL THEN
            RETURN NEW;
        END IF;

        -- Con obligatorios pendientes (cierre con motivo, MIG472) el acta no
        -- se cierra: queda en_progreso hasta que se complete de verdad.
        SELECT COUNT(*) INTO v_pendientes
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst.id
           AND COALESCE(ii.excluido, false) = false
           AND ti.obligatorio = true
           AND COALESCE(ii.resultado, 'pendiente') = 'pendiente';
        IF v_pendientes > 0 THEN
            RETURN NEW;
        END IF;

        -- Las firmas viven en los ítems (mediciones, flujo móvil MIG538):
        -- el de orden menor es el técnico que entrega, el mayor el cliente.
        SELECT ii.mediciones INTO v_tec
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst.id AND ti.tipo_respuesta = 'firma'
         ORDER BY ti.bloque_orden, ti.orden ASC LIMIT 1;
        SELECT ii.mediciones INTO v_cli
          FROM checklist_v2_instance_item ii
          JOIN checklist_template_v2_item ti ON ti.id = ii.template_item_id
         WHERE ii.instance_id = v_inst.id AND ti.tipo_respuesta = 'firma'
         ORDER BY ti.bloque_orden, ti.orden DESC LIMIT 1;

        UPDATE checklist_v2_instance
           SET estado             = 'cerrado',
               fecha_cierre       = NOW(),
               firma_operador_url = COALESCE(firma_operador_url, v_tec->>'firma_operador_url'),
               firma_cliente_url  = COALESCE(firma_cliente_url,  v_cli->>'firma_operador_url'),
               operador_rut       = COALESCE(operador_rut,    v_tec->>'rut_operador'),
               operador_nombre    = COALESCE(operador_nombre, v_tec->>'nombre_operador'),
               cliente_rut        = COALESCE(cliente_rut,     v_cli->>'rut_operador'),
               cliente_nombre     = COALESCE(cliente_nombre,  v_cli->>'nombre_operador')
         WHERE id = v_inst.id;
    END IF;

    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ot_autocerrar_checklist_entrega ON ordenes_trabajo;
CREATE TRIGGER trg_ot_autocerrar_checklist_entrega
    AFTER UPDATE OF estado ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_autocerrar_checklist_entrega();


-- ── 3. Prueba E2E con rollback: rebota sin fotos, cierra el acta con ellas ──
DO $mig$
DECLARE
    v_admin  UUID;
    v_activo UUID;
    v_r      JSONB;
    v_ot     UUID;
    v_estado TEXT;
    v_inst   RECORD;
    v_paso1  BOOLEAN := false;
BEGIN
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol = 'administrador' AND activo LIMIT 1;
    SELECT id INTO v_activo FROM activos WHERE codigo = 'TEST-01';
    IF v_admin IS NULL OR v_activo IS NULL THEN
        RAISE EXCEPTION 'FALLO: falta admin o TEST-01 para la prueba';
    END IF;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);

    BEGIN
        v_r  := rpc_programar_entrega_arriendo(v_activo, 'normal', CURRENT_DATE, v_admin);
        v_ot := (v_r->>'id')::uuid;

        -- Checklist todo OK, con firmas en los ítems, pero SIN NINGUNA FOTO
        UPDATE checklist_v2_instance_item ii
           SET resultado = 'ok'
          FROM checklist_v2_instance i
         WHERE i.id = ii.instance_id AND i.ot_id = v_ot
           AND COALESCE(ii.excluido, false) = false;
        UPDATE checklist_v2_instance_item ii
           SET mediciones = jsonb_build_object(
                 'firma_operador_url', 'data:image/png;base64,TEST',
                 'rut_operador', '11111111-1', 'nombre_operador', 'Prueba MIG544')
          FROM checklist_v2_instance i, checklist_template_v2_item ti
         WHERE i.id = ii.instance_id AND i.ot_id = v_ot
           AND ti.id = ii.template_item_id AND ti.tipo_respuesta = 'firma';

        UPDATE ordenes_trabajo SET firma_tecnico_url = 'data:image/png;base64,TEST'
         WHERE id = v_ot;
        SELECT estado::text INTO v_estado FROM ordenes_trabajo WHERE id = v_ot;
        IF v_estado = 'creada' THEN
            PERFORM rpc_transicion_ot(v_ot, 'asignada', v_admin, NULL, NULL, NULL, v_admin);
        END IF;
        PERFORM rpc_transicion_ot(v_ot, 'en_ejecucion', v_admin);

        -- 1) SIN fotos debe rebotar con el error nuevo
        BEGIN
            PERFORM rpc_transicion_ot(v_ot, 'ejecutada_ok', v_admin);
            RAISE EXCEPTION 'FALLO_REAL: finalizó una entrega sin fotos';
        EXCEPTION WHEN OTHERS THEN
            IF SQLERRM LIKE '%fotos obligatorias del checklist%' THEN
                v_paso1 := true;
            ELSE
                RAISE EXCEPTION 'FALLO_REAL: rebotó pero con otro error: %', SQLERRM;
            END IF;
        END;

        -- 2) CON fotos debe finalizar y el acta cerrarse sola con las firmas
        UPDATE checklist_v2_instance_item ii
           SET foto_url = 'data:image/png;base64,TEST'
          FROM checklist_v2_instance i, checklist_template_v2_item ti
         WHERE i.id = ii.instance_id AND i.ot_id = v_ot
           AND ti.id = ii.template_item_id
           AND ti.requiere_foto = true AND COALESCE(ii.excluido, false) = false;

        PERFORM rpc_transicion_ot(v_ot, 'ejecutada_ok', v_admin);

        SELECT ci.estado::text AS est, ci.firma_operador_url, ci.firma_cliente_url,
               ci.operador_rut
          INTO v_inst
          FROM checklist_v2_instance ci
         WHERE ci.ot_id = v_ot LIMIT 1;
        IF v_inst.est <> 'cerrado'
           OR v_inst.firma_operador_url IS NULL
           OR v_inst.firma_cliente_url IS NULL THEN
            RAISE EXCEPTION 'FALLO_REAL: el acta no se auto-cerró con firmas (estado=%, fo=%, fc=%)',
                v_inst.est, v_inst.firma_operador_url IS NOT NULL, v_inst.firma_cliente_url IS NOT NULL;
        END IF;
        IF NOT v_paso1 THEN
            RAISE EXCEPTION 'FALLO_REAL: el candado de fotos nunca rebotó';
        END IF;

        RAISE EXCEPTION 'ROLLBACK_MARKER candado de fotos + acta auto-cerrada OK';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK (revertida): %', SQLERRM;
        ELSE
            RAISE EXCEPTION '%', SQLERRM;
        END IF;
    END;

    -- Los triggers quedaron instalados de verdad
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ot_entrega_fotos_firmas')
       OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ot_autocerrar_checklist_entrega') THEN
        RAISE EXCEPTION 'FALLO: los triggers MIG544 no quedaron instalados';
    END IF;
    RAISE NOTICE 'MIG544 OK · entrega exige fotos por item y el acta se cierra sola';
END
$mig$;

COMMIT;

NOTIFY pgrst, 'reload schema';
