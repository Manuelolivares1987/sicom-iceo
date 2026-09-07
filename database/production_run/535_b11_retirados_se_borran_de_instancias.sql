-- ============================================================================
-- MIG535 · B11.04/05 retirados: se BORRAN de las instancias, no solo se excluyen
-- ============================================================================
-- Manuel: «sigo viendo el B11 tal cual» — en la página de la OT del
-- escritorio, el modo edición muestra a propósito también los excluidos
-- (para poder re-incluir un «no aplica», MIG270). Pero B11.04 y B11.05 no
-- son «no aplica de este equipo»: son preguntas RETIRADAS de la plantilla
-- (MIG534). Un ítem retirado no se re-incluye — se borra de las instancias
-- donde nadie lo respondió. Lo respondido (histórico) no se toca.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE v_n INT;
BEGIN
    DELETE FROM checklist_v2_instance_item ii
     USING checklist_template_v2_item ti
     WHERE ti.id = ii.template_item_id
       AND ti.codigo IN ('B11.04', 'B11.05')
       AND ti.bloque::text = 'b7_cierre_recepcion'
       AND NOT ti.vigente
       AND COALESCE(ii.resultado::text, 'pendiente') = 'pendiente'
       AND ii.valor_numerico IS NULL
       AND COALESCE(TRIM(ii.observacion), '') = '';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'ítems B11.04/05 borrados de instancias (sin respuesta): %', v_n;

    -- La OT de prueba de Manuel ya no los tiene, ni siquiera en modo edición.
    SELECT count(*) INTO v_n
      FROM v_taller_ot_checklist_v3 v
     WHERE v.ot_id = 'd7a64530-c77d-48e3-88fc-d1868589f987'
       AND v.codigo IN ('B11.04', 'B11.05');
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: la OT de prueba aún trae B11.04/05 (%)', v_n; END IF;

    RAISE NOTICE 'MIG535 OK · los retirados ya no existen en ningún checklist abierto';
END
$mig$;

COMMIT;
