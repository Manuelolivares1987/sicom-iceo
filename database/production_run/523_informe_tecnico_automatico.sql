-- ============================================================================
-- MIG523 · El informe técnico de intervención se hace solo
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
-- «Quiero hacer el informe técnico de intervención y no pasa nada —
-- necesito que se haga AUTOMÁTICO ese informe.»
--
-- El sistema ya sabe todo lo que el informe pide: qué ítems se trabajaron y
-- cómo quedaron (checklist V03), los medidores del equipo y el estado con
-- que salió la OT. Obligar a alguien a re-escribirlo era el motivo de que
-- los informes viajaran vacíos (MIG520 los rebotaba, y con razón).
--
-- QUÉ SE HACE
--  1. fn_informe_autocompletar(informe): llena el resumen del trabajo (ítems
--     visibles del V03 con su resultado — o el checklist de la OT si no hay
--     V03) y el estado de salida. SOLO llena campos vacíos: lo que escribió
--     una persona no se pisa.
--  2. Trigger al pasar la OT a ejecutada_ok / ejecutada_con_observaciones:
--     si no hay informe vigente lo CREA (folio real, trabajos precargados),
--     lo autocompleta y lo deja en pendiente_revision — al aprobador le
--     llega listo para aprobar. Nunca bloquea el cierre: si algo falla,
--     queda un WARNING y la OT cierra igual.
--  3. El informe atascado de hoy (IT-202608-00005, observado y vacío) se
--     autocompleta y se reenvía a revisión: a Manuel solo le queda Aprobar.
-- ============================================================================

BEGIN;

-- ── 1 · Autocompletar desde lo que el sistema ya sabe ───────────────────────
CREATE OR REPLACE FUNCTION public.fn_informe_autocompletar(p_informe_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_inf     public.informes_intervencion;
    v_ot      RECORD;
    v_resumen TEXT := '';
    v_salida  TEXT;
    v_linea   RECORD;
    v_n       INT := 0;
    v_cambio  BOOLEAN := FALSE;
BEGIN
    SELECT * INTO v_inf FROM public.informes_intervencion WHERE id = p_informe_id;
    IF NOT FOUND THEN RETURN FALSE; END IF;

    SELECT ot.folio, ot.estado::text AS estado, a.horas_uso_actual, a.kilometraje_actual,
           COALESCE(a.patente, a.codigo) AS patente
      INTO v_ot
      FROM public.ordenes_trabajo ot LEFT JOIN activos a ON a.id = ot.activo_id
     WHERE ot.id = v_inf.ot_id;

    -- Resumen: los ítems visibles del V03 con su resultado.
    IF COALESCE(v_inf.trabajo_realizado_resumen, '') = '' THEN
        FOR v_linea IN
            SELECT descripcion, resultado::text AS res, observacion
              FROM v_taller_ot_checklist_v3
             WHERE ot_id = v_inf.ot_id AND excluido = false
               AND resultado IS NOT NULL AND resultado::text <> 'pendiente'
             ORDER BY bloque_orden, orden
        LOOP
            v_n := v_n + 1;
            v_resumen := v_resumen || '— ' || v_linea.descripcion || ': '
                || CASE v_linea.res WHEN 'ok' THEN 'ejecutado OK'
                                    WHEN 'no_ok' THEN 'NO OK (queda como No Conformidad)'
                                    ELSE v_linea.res END
                || COALESCE('. ' || NULLIF(trim(v_linea.observacion), ''), '')
                || E'\n';
        END LOOP;

        -- Sin V03: el checklist de la OT.
        IF v_n = 0 THEN
            FOR v_linea IN
                SELECT descripcion, resultado::text AS res, observacion
                  FROM checklist_ot
                 WHERE ot_id = v_inf.ot_id AND resultado IS NOT NULL
                 ORDER BY orden
            LOOP
                v_n := v_n + 1;
                v_resumen := v_resumen || '— ' || v_linea.descripcion || ': ' || v_linea.res
                    || COALESCE('. ' || NULLIF(trim(v_linea.observacion), ''), '') || E'\n';
            END LOOP;
        END IF;

        IF v_n > 0 THEN
            v_resumen := 'Trabajos ejecutados según checklist de la OT ' || COALESCE(v_ot.folio,'')
                || ' (equipo ' || COALESCE(v_ot.patente,'—') || '):' || E'\n' || v_resumen
                || CASE WHEN v_ot.horas_uso_actual IS NOT NULL OR v_ot.kilometraje_actual IS NOT NULL
                        THEN 'Medidores al cierre: '
                          || COALESCE(round(v_ot.horas_uso_actual)::text || ' h', '')
                          || CASE WHEN v_ot.horas_uso_actual IS NOT NULL AND v_ot.kilometraje_actual IS NOT NULL THEN ' · ' ELSE '' END
                          || COALESCE(round(v_ot.kilometraje_actual)::text || ' km', '')
                        ELSE '' END;
            UPDATE public.informes_intervencion
               SET trabajo_realizado_resumen = v_resumen, updated_at = NOW()
             WHERE id = p_informe_id;
            v_cambio := TRUE;
        END IF;
    END IF;

    -- Estado de salida: según cómo salió la OT.
    IF COALESCE(v_inf.estado_salida, '') = '' THEN
        v_salida := CASE v_ot.estado
            WHEN 'ejecutada_ok' THEN 'Operativo — el equipo sale disponible.'
            WHEN 'ejecutada_con_observaciones' THEN 'Operativo con observaciones — ver detalle de trabajos.'
            WHEN 'cerrada' THEN 'Operativo — el equipo sale disponible.'
            ELSE NULL END;
        IF v_salida IS NOT NULL THEN
            UPDATE public.informes_intervencion
               SET estado_salida = v_salida, updated_at = NOW()
             WHERE id = p_informe_id;
            v_cambio := TRUE;
        END IF;
    END IF;

    RETURN v_cambio;
END; $fn$;

COMMENT ON FUNCTION public.fn_informe_autocompletar(UUID) IS
'Llena el resumen del trabajo y el estado de salida del informe técnico con lo que el sistema ya sabe (checklist V03, medidores, estado de la OT). Solo campos vacíos: lo escrito por una persona no se pisa. MIG523.';

-- ── 2 · Al ejecutarse la OT, el informe nace solo y llega listo ─────────────
CREATE OR REPLACE FUNCTION public.fn_ot_informe_automatico()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
    v_id UUID; v_ci UUID;
BEGIN
    -- Nada de esto puede bloquear el cierre de una OT.
    BEGIN
        SELECT id INTO v_id FROM public.informes_intervencion
         WHERE ot_id = NEW.id AND es_version_vigente
           AND estado IN ('borrador','pendiente_revision','observado','aprobado')
         LIMIT 1;

        IF v_id IS NULL THEN
            SELECT id INTO v_ci FROM public.checklist_v2_instance
             WHERE ot_id = NEW.id ORDER BY created_at DESC LIMIT 1;

            INSERT INTO public.informes_intervencion(
                folio, ot_id, activo_id, checklist_instance_id, version, es_version_vigente,
                estado, tipo_intervencion, fecha_ingreso, fecha_inicio, fecha_termino,
                ejecutor_principal_id, elaborado_por)
            VALUES (
                public.fn_next_folio_informe_intervencion(), NEW.id, NEW.activo_id, v_ci, 1, true,
                'borrador', NEW.tipo::text, NEW.created_at, NEW.fecha_inicio, NEW.fecha_termino,
                NEW.responsable_id, COALESCE(auth.uid(), NEW.created_by))
            RETURNING id INTO v_id;

            -- Los trabajos precargados, igual que el RPC de crear (MIG191).
            INSERT INTO public.informe_intervencion_trabajos(informe_id, checklist_item_id, sistema, componente, trabajo_planificado, estado, observacion)
            SELECT v_id, co.id, co.seccion, NULL, co.descripcion, 'pendiente', co.observacion
              FROM public.checklist_ot co WHERE co.ot_id = NEW.id;
            INSERT INTO public.informe_intervencion_trabajos(informe_id, nc_id, sistema, sintoma, diagnostico, estado, observacion)
            SELECT v_id, nc.id, nc.tipo::text, nc.descripcion, nc.accion_correctiva, 'pendiente', nc.descripcion
              FROM public.no_conformidades nc WHERE nc.ot_id = NEW.id;
        END IF;

        PERFORM public.fn_informe_autocompletar(v_id);

        -- Si quedó completo y todavía es editable, viaja a revisión solo.
        UPDATE public.informes_intervencion
           SET estado = 'pendiente_revision', updated_at = NOW()
         WHERE id = v_id AND estado IN ('borrador','observado')
           AND COALESCE(trabajo_realizado_resumen,'') <> ''
           AND COALESCE(estado_salida,'') <> '';
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'MIG523: no se pudo generar el informe automático de la OT % (%)', NEW.folio, SQLERRM;
    END;
    RETURN NEW;
END; $fn$;

DROP TRIGGER IF EXISTS trg_ot_informe_automatico ON ordenes_trabajo;
CREATE TRIGGER trg_ot_informe_automatico
AFTER UPDATE OF estado ON ordenes_trabajo
FOR EACH ROW
WHEN (NEW.estado IN ('ejecutada_ok','ejecutada_con_observaciones')
      AND OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION public.fn_ot_informe_automatico();

-- ── 3 · El informe atascado de hoy queda listo para aprobar ─────────────────
DO $mig$
DECLARE v_inf UUID := '42dddc1d-2f56-4120-a947-3a02ce40ee6a'; v_ok BOOLEAN;
        v_admin UUID; v_est TEXT;
BEGIN
    v_ok := fn_informe_autocompletar(v_inf);
    RAISE NOTICE 'IT-202608-00005 autocompletado: %', v_ok;

    UPDATE informes_intervencion
       SET estado = 'pendiente_revision', updated_at = NOW()
     WHERE id = v_inf AND estado IN ('borrador','observado')
       AND COALESCE(trabajo_realizado_resumen,'') <> '' AND COALESCE(estado_salida,'') <> '';

    SELECT estado INTO v_est FROM informes_intervencion WHERE id = v_inf;
    IF v_est <> 'pendiente_revision' THEN
        RAISE EXCEPTION 'FALLO: el informe quedó en «%» y no en revisión', v_est;
    END IF;

    -- Aprobar debe pasar ahora (con rollback: el clic lo da Manuel).
    SELECT id INTO v_admin FROM usuarios_perfil WHERE rol='administrador' AND activo LIMIT 1;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, TRUE);
    BEGIN
        -- El RPC devuelve VOID: se ejecuta con PERFORM y el marcador revierte.
        PERFORM rpc_aprobar_informe_intervencion(v_inf);
        RAISE EXCEPTION 'ROLLBACK_MARKER aprobado';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'ROLLBACK_MARKER%' THEN
            RAISE NOTICE 'prueba OK: aprobar PASA (revertido)';
        ELSE
            RAISE EXCEPTION 'FALLO: aprobar sigue rebotando: %', SQLERRM;
        END IF;
    END;

    RAISE NOTICE 'MIG523 OK · el informe técnico se hace solo y llega listo para aprobar';
END
$mig$;

COMMIT;
