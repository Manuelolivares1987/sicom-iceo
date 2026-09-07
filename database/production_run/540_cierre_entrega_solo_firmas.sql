-- ============================================================================
-- MIG540 · El cierre de la entrega son las firmas, nada más
-- ============================================================================
-- Manuel vio el bloque «Cierre de la entrega» en su OT de prueba: «Trabajos
-- no realizados», «Repuestos pendientes/garantía», «Próxima OT programada»,
-- «Recomendaciones operador», «% Cumplimiento OT», «HH totales ejecutadas»,
-- «Días calendario taller» — «esto hay que sacarlo». Es jerga de cierre de
-- OT de taller que se coló en la plantilla de entrega; en una entrega no
-- significan nada. Quedan solo ED.08 y ED.09 (firma del que entrega y firma
-- del que acepta).
--
-- Mismo criterio que MIG534/535: vigente=false en la plantilla Y se BORRAN
-- de las instancias existentes (todas son pruebas de estos días; así el
-- checklist y el acta de la OT actual también quedan limpios).
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_tpl UUID;
    v_ret INT;
    v_del INT;
BEGIN
    SELECT id INTO v_tpl FROM checklist_template_v2
     WHERE momento_uso = 'entrega_arriendo' AND activo
     ORDER BY version DESC LIMIT 1;
    IF v_tpl IS NULL THEN RAISE EXCEPTION 'FALLO: no hay plantilla de entrega activa'; END IF;

    UPDATE checklist_template_v2_item
       SET vigente = false
     WHERE template_id = v_tpl AND bloque = 'd_cierre_entrega'
       AND codigo IN ('ED.01','ED.02','ED.03','ED.04','ED.05','ED.06','ED.07');
    GET DIAGNOSTICS v_ret = ROW_COUNT;
    IF v_ret <> 7 THEN
        RAISE EXCEPTION 'FALLO: se esperaban 7 ítems a retirar, se tocaron %', v_ret;
    END IF;

    DELETE FROM checklist_v2_instance_item ii
     USING checklist_template_v2_item ti
     WHERE ti.id = ii.template_item_id
       AND ti.template_id = v_tpl AND ti.bloque = 'd_cierre_entrega'
       AND ti.codigo IN ('ED.01','ED.02','ED.03','ED.04','ED.05','ED.06','ED.07');
    GET DIAGNOSTICS v_del = ROW_COUNT;

    -- Las firmas siguen vigentes; las entregas nuevas nacen sin los 7.
    IF (SELECT count(*) FROM checklist_template_v2_item
         WHERE template_id = v_tpl AND bloque = 'd_cierre_entrega'
           AND vigente AND tipo_respuesta = 'firma') <> 2 THEN
        RAISE EXCEPTION 'FALLO: el cierre debe quedar con exactamente las 2 firmas';
    END IF;

    RAISE NOTICE 'MIG540 OK · 7 ítems retirados de la plantilla y % filas borradas de instancias', v_del;
END
$mig$;

COMMIT;
