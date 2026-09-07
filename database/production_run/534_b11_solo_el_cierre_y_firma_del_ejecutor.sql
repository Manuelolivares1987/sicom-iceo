-- ============================================================================
-- MIG534 · B11: solo el cierre, obligatorio, y con la firma del ejecutor
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (07-09-2026, probando con PRUEBA-01)
-- «Próximo horómetro de pauta (planificado) — OBLIGATORIO» y «Tipo de OT a
-- generar (taxonomía OT-XX-XX)» aparecen en B11 y NO deben estar. Solo debe
-- quedar el cierre, no debe ser opcional, y debe pedir solo la firma del
-- ejecutor — después las revisa el jefe de taller.
--
-- QUÉ SE HACE (plantilla V03, bloque b7_cierre_recepcion)
--   · B11.04 y B11.05 → vigente = false. MIG496 dejó el B11.04 visible
--     aunque se llenara solo; ahora sale del checklist. El inicializador ya
--     filtra por vigente (las OT nuevas no los traen) y el RPC de medidores
--     queda inocuo (su UPDATE afecta 0 filas).
--   · En las instancias EN PROGRESO, los dos ítems quedan excluidos si nadie
--     los respondió (lo respondido no se toca: es historia).
--   · B11.03 «Trabajos solicitados» pasa a OBLIGATORIO: es el cierre que
--     documenta qué se pide, y opcional se estaba quedando vacío.
--   · B11.07 pasa a «Firma del técnico ejecutor + RUT»: la firma del
--     responsable de taller sale de B11 — el jefe revisa y aprueba el
--     checklist después, en la verificación (la pantalla va en el mismo PR).
-- ============================================================================

BEGIN;

DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    -- 1 · Retirar B11.04 y B11.05 de la plantilla vigente.
    UPDATE checklist_template_v2_item ti SET vigente = false
      FROM checklist_template_v2 t
     WHERE t.id = ti.template_id AND t.activo AND t.nombre ILIKE '%V03%'
       AND ti.bloque::text = 'b7_cierre_recepcion'
       AND ti.codigo IN ('B11.04', 'B11.05')
       AND ti.vigente;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'ítems retirados de la plantilla: %', v_n;

    -- 2 · El cierre deja de ser opcional.
    UPDATE checklist_template_v2_item ti SET obligatorio = true
      FROM checklist_template_v2 t
     WHERE t.id = ti.template_id AND t.activo AND t.nombre ILIKE '%V03%'
       AND ti.bloque::text = 'b7_cierre_recepcion'
       AND ti.codigo = 'B11.03' AND NOT ti.obligatorio;

    -- 3 · La firma es del ejecutor; el jefe revisa después.
    UPDATE checklist_template_v2_item ti
       SET descripcion = 'Firma del tecnico ejecutor + RUT',
           ayuda = 'El jefe de taller revisa y aprueba el checklist despues de finalizar; su firma no va aqui.'
      FROM checklist_template_v2 t
     WHERE t.id = ti.template_id AND t.activo AND t.nombre ILIKE '%V03%'
       AND ti.bloque::text = 'b7_cierre_recepcion'
       AND ti.codigo = 'B11.07';

    -- 4 · Instancias abiertas: los dos ítems retirados quedan excluidos si
    --     nadie los respondió.
    UPDATE checklist_v2_instance_item ii SET excluido = true
      FROM checklist_v2_instance i, checklist_template_v2_item ti
     WHERE i.id = ii.instance_id AND i.estado = 'en_progreso'
       AND ti.id = ii.template_item_id
       AND ti.codigo IN ('B11.04', 'B11.05') AND ti.bloque::text = 'b7_cierre_recepcion'
       AND COALESCE(ii.resultado::text, 'pendiente') = 'pendiente'
       AND NOT COALESCE(ii.excluido, false);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'ítems excluidos en instancias abiertas: %', v_n;

    -- ── Verificación con la OT de prueba de Manuel ──────────────────────────
    SELECT count(*) INTO v_n
      FROM v_taller_ot_checklist_v3 v
     WHERE v.ot_id = 'd7a64530-c77d-48e3-88fc-d1868589f987'
       AND v.codigo IN ('B11.04', 'B11.05') AND NOT v.excluido;
    IF v_n > 0 THEN RAISE EXCEPTION 'FALLO: la OT de prueba sigue mostrando B11.04/05'; END IF;

    FOR r IN SELECT v.codigo, left(v.descripcion, 50) AS d, v.obligatorio
               FROM v_taller_ot_checklist_v3 v
              WHERE v.ot_id = 'd7a64530-c77d-48e3-88fc-d1868589f987'
                AND v.codigo LIKE 'B11%' AND NOT v.excluido
              ORDER BY v.orden
    LOOP
        RAISE NOTICE 'B11 visible: % [%] oblig=%', r.codigo, r.d, r.obligatorio;
    END LOOP;

    RAISE NOTICE 'MIG534 OK · B11 = cierre obligatorio + firma del ejecutor';
END
$mig$;

COMMIT;
