-- ============================================================================
-- MIG492 · La pauta del fabricante es sólo para MPN
-- ============================================================================
--
-- LO QUE CORRIGIÓ MANUEL
-- 02-09-2026: «ojo, el checklist del fabricante sería para MPN; para el resto es
-- el genérico».
--
-- MIG490 lo dejó para cualquier OT que viniera de un plan de mantenimiento.
-- Está más abierto de lo que corresponde: una MTN es la mantención total del
-- equipo cuando vuelve de arriendo, y ahí lo que se hace es la revisión
-- completa, no los pasos de un servicio programado. La pauta del fabricante es
-- el trabajo del MPN, la preventiva pura.
--
-- CÓMO SE SABE QUE ES MPN
-- Por el concepto declarado (`ordenes_trabajo.bono_concepto`), y si todavía no
-- está declarado, por la deducción que ya existe en `fn_taller_ot_concepto`:
-- preventivo CON contrato vigente = MPN, sin contrato = MTN. Importa que valgan
-- las dos vías porque hoy NINGUNA de las 129 OT tiene el concepto declarado
-- —el campo es de MIG466 y recién ahora se está usando— y las que crea el cron
-- de preventivas tampoco lo van a traer.
--
-- EL ORDEN EN QUE PASAN LAS COSAS
-- Al programar desde el tablero, la OT se crea primero y el concepto se declara
-- un segundo después. Así que el checklist se decide dos veces: al nacer la OT
-- con lo que se sepa en ese momento, y otra vez cuando el planificador declara
-- el tipo de tarea. El segundo cambio sólo ocurre si nadie tocó el checklist
-- todavía: una vez que el mecánico respondió algo, no se le cambia la pauta
-- abajo de la mano.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_auto_checklist_ot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_tpl        UUID;
    v_inst       UUID;
    v_contrato   UUID;
    v_horas      NUMERIC;
    v_km         NUMERIC;
    v_entrega    UUID;
    v_es_pauta   BOOLEAN := FALSE;
    v_concepto   TEXT;
BEGIN
    BEGIN
        IF EXISTS (SELECT 1 FROM checklist_v2_instance WHERE ot_id = NEW.id) THEN
            RETURN NEW;
        END IF;

        -- [MIG492] Sólo el MPN abre la pauta del fabricante. Una MTN es la
        -- mantención total del equipo: ahí se hace la revisión completa.
        IF NEW.plan_mantenimiento_id IS NOT NULL THEN
            v_concepto := COALESCE(NEW.bono_concepto, fn_taller_ot_concepto(NEW.id));
            IF v_concepto = 'MPN' THEN
                SELECT t.id INTO v_tpl
                  FROM planes_mantenimiento pm
                  JOIN checklist_template_v2 t ON t.pauta_fabricante_id = pm.pauta_fabricante_id
                 WHERE pm.id = NEW.plan_mantenimiento_id AND t.activo;
                v_es_pauta := v_tpl IS NOT NULL;
            END IF;
        END IF;

        IF v_tpl IS NULL THEN
            SELECT id INTO v_tpl FROM checklist_template_v2
             WHERE momento_uso='recepcion_devolucion' AND activo=true
             ORDER BY version DESC LIMIT 1;
        END IF;
        IF v_tpl IS NULL THEN RETURN NEW; END IF;

        IF NOT v_es_pauta THEN
            SELECT id INTO v_inst FROM checklist_v2_instance
             WHERE activo_id = NEW.activo_id
               AND momento_uso = 'recepcion_devolucion'
               AND estado = 'en_progreso'
               AND ot_id IS NULL
             ORDER BY fecha_inicio DESC LIMIT 1;
            IF v_inst IS NOT NULL THEN
                UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;
                IF NOT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                                WHERE ii.instance_id = v_inst
                                  AND COALESCE(ii.resultado, 'pendiente') <> 'pendiente') THEN
                    BEGIN
                        PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;
                END IF;
                RETURN NEW;
            END IF;
        END IF;

        SELECT contrato_id, horas_uso_actual, kilometraje_actual
          INTO v_contrato, v_horas, v_km
          FROM activos WHERE id = NEW.activo_id;

        SELECT id INTO v_entrega FROM checklist_v2_instance
         WHERE activo_id = NEW.activo_id AND momento_uso='entrega_arriendo' AND estado='cerrado'
         ORDER BY fecha_cierre DESC LIMIT 1;

        v_inst := fn_inicializar_checklist_v2(
            v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
            NULL, v_horas, v_km, NULL, v_entrega
        );
        UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_inst;

        IF NOT v_es_pauta THEN
            BEGIN
                PERFORM fn_checklist_v3_arrastrar_nc(v_inst);
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN NEW;
END $function$;

-- ── El planificador declara el tipo después de crear la OT ──────────────────
--
-- Si al declararlo resulta ser MPN y el checklist todavía está virgen, se
-- cambia por la pauta. Y al revés: si deja de ser MPN, vuelve el genérico.
-- Con una sola respuesta puesta, no se toca nada: cambiarle el checklist a
-- alguien que ya empezó es peor que tener el checklist equivocado.
CREATE OR REPLACE FUNCTION fn_ot_concepto_ajusta_checklist()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inst      UUID;
    v_es_pauta  BOOLEAN;
    v_tocado    BOOLEAN;
    v_tpl       UUID;
    v_contrato  UUID;
    v_horas     NUMERIC;
    v_km        NUMERIC;
    v_nuevo     UUID;
BEGIN
    IF NEW.bono_concepto IS NOT DISTINCT FROM OLD.bono_concepto THEN RETURN NEW; END IF;
    IF NEW.plan_mantenimiento_id IS NULL THEN RETURN NEW; END IF;

    SELECT i.id, (t.pauta_fabricante_id IS NOT NULL)
      INTO v_inst, v_es_pauta
      FROM checklist_v2_instance i
      JOIN checklist_template_v2 t ON t.id = i.template_id
     WHERE i.ot_id = NEW.id AND i.estado = 'en_progreso'
     ORDER BY i.fecha_inicio DESC LIMIT 1;

    IF v_inst IS NULL THEN RETURN NEW; END IF;

    -- ¿Ya hay trabajo hecho encima?
    SELECT EXISTS (SELECT 1 FROM checklist_v2_instance_item ii
                    WHERE ii.instance_id = v_inst
                      AND COALESCE(ii.resultado, 'pendiente') <> 'pendiente')
      INTO v_tocado;
    IF v_tocado THEN RETURN NEW; END IF;

    IF NEW.bono_concepto = 'MPN' AND NOT v_es_pauta THEN
        SELECT t.id INTO v_tpl
          FROM planes_mantenimiento pm
          JOIN checklist_template_v2 t ON t.pauta_fabricante_id = pm.pauta_fabricante_id
         WHERE pm.id = NEW.plan_mantenimiento_id AND t.activo;
    ELSIF NEW.bono_concepto IS DISTINCT FROM 'MPN' AND v_es_pauta THEN
        SELECT id INTO v_tpl FROM checklist_template_v2
         WHERE momento_uso = 'recepcion_devolucion' AND activo
         ORDER BY version DESC LIMIT 1;
    END IF;

    IF v_tpl IS NULL THEN RETURN NEW; END IF;

    SELECT contrato_id, horas_uso_actual, kilometraje_actual
      INTO v_contrato, v_horas, v_km FROM activos WHERE id = NEW.activo_id;

    -- El checklist viejo no se borra: se anula. Deja el rastro de que hubo un
    -- cambio de criterio, y no rompe nada que apunte a él.
    UPDATE checklist_v2_instance
       SET estado = 'anulado',
           observaciones = trim(COALESCE(observaciones,'') ||
               ' [MIG492] Reemplazado al declarar el tipo de tarea como ' ||
               COALESCE(NEW.bono_concepto, 'sin declarar') || '.')
     WHERE id = v_inst;

    v_nuevo := fn_inicializar_checklist_v2(
        v_tpl, NEW.activo_id, COALESCE(NEW.contrato_id, v_contrato),
        NULL, v_horas, v_km, NULL, NULL);
    UPDATE checklist_v2_instance SET ot_id = NEW.id WHERE id = v_nuevo;

    IF NEW.bono_concepto IS DISTINCT FROM 'MPN' THEN
        BEGIN
            PERFORM fn_checklist_v3_arrastrar_nc(v_nuevo);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Declarar el tipo de tarea nunca puede fallar por el checklist.
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ot_concepto_ajusta_checklist ON ordenes_trabajo;
CREATE TRIGGER trg_ot_concepto_ajusta_checklist
    AFTER UPDATE OF bono_concepto ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION fn_ot_concepto_ajusta_checklist();

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD; v_mpn INT := 0; v_otros INT := 0;
BEGIN
    FOR r IN SELECT ot.id, ot.tipo::TEXT AS tipo, ot.contrato_id,
                    COALESCE(ot.bono_concepto, fn_taller_ot_concepto(ot.id)) AS concepto
               FROM ordenes_trabajo ot
              WHERE ot.plan_mantenimiento_id IS NOT NULL
    LOOP
        IF r.concepto = 'MPN' THEN v_mpn := v_mpn + 1; ELSE v_otros := v_otros + 1; END IF;
    END LOOP;
    RAISE NOTICE 'OT con plan de mantenimiento: % serían MPN (pauta del fabricante) y % no (checklist genérico)',
                 v_mpn, v_otros;
END $mig$;

COMMIT;
