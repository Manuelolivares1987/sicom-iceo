-- ============================================================================
-- MIG527 · El historial de mantenimiento congela el V03, por todos los caminos
-- ============================================================================
--
-- LO QUE VIO MANUEL (04-09-2026)
-- «Volvamos a la OT — ¿todo esto quedó en el historial?». Quedó, pero cojo:
-- la OT-202608-00009 aparece con trabajo_realizado vacío, «0 de 8 tareas» y
-- sin medidores al cierre — con el informe técnico lleno y los 8 trabajos
-- de Joel marcados ok en el V03.
--
-- POR QUÉ (dos causas)
--  1. fn_ot_resumen_trabajo y los conteos de v_historial_mantenimiento_equipo
--     leen SOLO checklist_ot — el genérico pre-V03. Es el CUARTO consumidor
--     de la misma trampa (MIG519 el RPC, MIG521 el trigger de cierre, MIG522
--     el cierre supervisor… y ahora el historial).
--  2. fn_ot_congelar_trabajo solo lo llama rpc_taller_finalizar_ejecucion
--     (tablero, MIG445). Joel finalizó desde el teléfono
--     (rpc_taller_finalizar_mecanico) y Manuel cerró con el cierre
--     supervisor: ninguno de los dos congela.
--
-- QUÉ SE HACE
--  1. fn_ot_resumen_trabajo: si la OT tiene V03, el resumen sale de ahí
--     (visibles con su resultado y la observación del mecánico); el genérico
--     queda de respaldo. Los repuestos siguen igual.
--  2. La vista cuenta tareas del V03 visible cuando existe.
--  3. Trigger en ordenes_trabajo: al entrar a ejecutada_*/cerrada se congela
--     el trabajo POR CUALQUIER CAMINO (guardado: solo si trabajo_realizado
--     está vacío, para no pisar la observación que deja el tablero; y jamás
--     tumba un cierre — EXCEPTION → WARNING).
--  4. Relleno: resumen para todas las OT ejecutadas/cerradas que lo tienen
--     vacío; medidores solo para los cierres de esta semana (los antiguos
--     tomarían la lectura de HOY, que sería mentira).
-- ============================================================================

BEGIN;

-- ── 1 · El resumen sale del V03 cuando existe ───────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_ot_resumen_trabajo(p_ot_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_tareas   TEXT;
    v_no_ok    TEXT;
    v_repuesto TEXT;
    v_partes   TEXT[] := ARRAY[]::TEXT[];
    v_hay_v3   BOOLEAN;
BEGIN
    -- [MIG527] Criterio MIG519/521/522: si la OT tiene V03, él es la vara.
    SELECT EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = p_ot_id)
      INTO v_hay_v3;

    IF v_hay_v3 THEN
        SELECT string_agg(v.descripcion || COALESCE(' (' || NULLIF(v.observacion,'') || ')', ''),
                          '; ' ORDER BY v.bloque_orden, v.orden)
          INTO v_tareas
          FROM v_taller_ot_checklist_v3 v
         WHERE v.ot_id = p_ot_id AND NOT v.excluido AND v.resultado::text = 'ok';

        SELECT string_agg(v.descripcion || COALESCE(' (' || NULLIF(v.observacion,'') || ')', ''),
                          '; ' ORDER BY v.bloque_orden, v.orden)
          INTO v_no_ok
          FROM v_taller_ot_checklist_v3 v
         WHERE v.ot_id = p_ot_id AND NOT v.excluido AND v.resultado::text = 'no_ok';
    ELSE
        SELECT string_agg(c.descripcion, '; ' ORDER BY c.orden)
          INTO v_tareas
          FROM checklist_ot c
         WHERE c.ot_id = p_ot_id AND c.resultado = 'ok';

        SELECT string_agg(c.descripcion || COALESCE(' (' || NULLIF(c.observacion,'') || ')', ''),
                          '; ' ORDER BY c.orden)
          INTO v_no_ok
          FROM checklist_ot c
         WHERE c.ot_id = p_ot_id AND c.resultado = 'no_ok';
    END IF;

    SELECT string_agg(p.nombre || ' x' || trim(to_char(m.cantidad, 'FM999999.99')),
                      '; ' ORDER BY p.nombre)
      INTO v_repuesto
      FROM movimientos_inventario m
      JOIN productos p ON p.id = m.producto_id
     WHERE m.ot_id = p_ot_id AND m.tipo IN ('salida','merma');

    IF v_tareas   IS NOT NULL THEN v_partes := v_partes || ('Ejecutado: ' || v_tareas); END IF;
    IF v_no_ok    IS NOT NULL THEN v_partes := v_partes || ('Pendiente / no conforme: ' || v_no_ok); END IF;
    IF v_repuesto IS NOT NULL THEN v_partes := v_partes || ('Repuestos: ' || v_repuesto); END IF;

    RETURN NULLIF(array_to_string(v_partes, E'\n'), '');
END;
$function$;

-- ── 2 · Los conteos de la vista miran el V03 cuando existe ──────────────────
CREATE OR REPLACE VIEW public.v_historial_mantenimiento_equipo AS
SELECT
    o.activo_id,
    'ot'::text                                     AS origen,
    o.id                                           AS ref_id,
    o.folio::text                                  AS folio,
    o.tipo::text                                   AS tipo,
    o.estado::text                                 AS estado,
    COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio) AS fecha,
    o.fecha_inicio,
    o.fecha_termino,
    o.trabajo_realizado,
    NULLIF(o.observaciones, '')                    AS motivo,
    o.km_al_cierre,
    o.horas_al_cierre,
    o.horas_hombre,
    COALESCE(o.costo_mano_obra, 0) + COALESCE(o.costo_materiales, 0) AS costo,
    COALESCE(resp.nombre_completo, tec.nombre_completo) AS responsable,
    sup.nombre_completo                            AS supervisor,
    -- [MIG527] Con V03 se cuentan sus visibles; el genérico queda de respaldo.
    CASE WHEN EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id)
         THEN (SELECT count(*)::int FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id AND NOT v.excluido)
         ELSE (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id) END          AS tareas_total,
    CASE WHEN EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id)
         THEN (SELECT count(*)::int FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id AND NOT v.excluido AND v.resultado::text = 'ok')
         ELSE (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'ok') END  AS tareas_ok,
    CASE WHEN EXISTS (SELECT 1 FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id)
         THEN (SELECT count(*)::int FROM v_taller_ot_checklist_v3 v WHERE v.ot_id = o.id AND NOT v.excluido AND v.resultado::text = 'no_ok')
         ELSE (SELECT count(*)::int FROM checklist_ot c WHERE c.ot_id = o.id AND c.resultado = 'no_ok') END AS tareas_no_ok,
    (SELECT count(*)::int FROM movimientos_inventario m
      WHERE m.ot_id = o.id AND m.tipo IN ('salida','merma'))                                AS repuestos_total,
    (SELECT count(*)::int FROM evidencias_ot e WHERE e.ot_id = o.id)                        AS evidencias_total,
    (SELECT count(*)::int FROM no_conformidades nc WHERE nc.ot_id = o.id)                   AS hallazgos_total,
    NULL::text                                     AS fuente
FROM ordenes_trabajo o
LEFT JOIN usuarios_perfil resp ON resp.id = o.responsable_id
LEFT JOIN usuarios_perfil tec  ON tec.id  = o.tecnico_id
LEFT JOIN usuarios_perfil sup  ON sup.id  = o.supervisor_cierre_id
WHERE o.activo_id IS NOT NULL
  AND (o.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
       OR o.fecha_inicio IS NOT NULL)
  AND COALESCE(o.fecha_termino, o.fecha_cierre_supervisor, o.fecha_inicio) <= NOW()

UNION ALL

SELECT
    h.activo_id,
    'os_legacy'::text,
    h.id,
    ('OS ' || COALESCE(h.os_cqbo, h.os_numero, left(h.id::text, 8)))::text,
    CASE WHEN h.flag_mant_prev THEN 'preventivo'
         WHEN h.flag_correctivo THEN 'correctivo'
         ELSE 'servicio' END,
    'cerrada'::text,
    (h.fecha_recepcion + TIME '12:00')::timestamptz,
    (h.fecha_recepcion + TIME '12:00')::timestamptz,
    (h.fecha_entrega   + TIME '12:00')::timestamptz,
    COALESCE(h.detalle_trabajos, NULLIF(concat_ws('. ',
        NULLIF(h.num_trabajos::text, '') || ' trabajo(s) registrados',
        CASE WHEN h.flag_neumaticos    THEN 'Neumáticos' END,
        CASE WHEN h.flag_rev_tec       THEN 'Revisión técnica' END,
        CASE WHEN h.flag_hab_estado    THEN 'Habilitación' END,
        CASE WHEN h.flag_serv_externo  THEN 'Servicio externo' END,
        NULLIF('Cumplimiento ' || h.cumplimiento_pct::text || '%', 'Cumplimiento %')
    ), '')),
    COALESCE(NULLIF(h.observacion, ''), NULLIF(h.ubicacion::text, ''), NULLIF(h.faena::text, '')),
    h.kilometraje::numeric,
    h.horometro::numeric,
    h.horas_mo::numeric,
    NULL::numeric,
    h.responsable,
    NULL::text,
    COALESCE(h.num_trabajos, 0)::int,
    COALESCE(h.num_trabajos, 0)::int,
    0, 0, 0, 0,
    h.fuente
FROM historial_os_legacy h
WHERE h.activo_id IS NOT NULL
  AND h.fecha_recepcion <= CURRENT_DATE;

GRANT SELECT ON public.v_historial_mantenimiento_equipo TO authenticated;

-- ── 3 · El congelado corre por CUALQUIER camino de cierre ───────────────────
-- BEFORE y rellenando NEW directo: sin update anidado, y pasa ANTES de que la
-- OT quede inmutable (el candado del cierre definitivo bloquea todo update
-- posterior). Solo rellena lo vacío: la observación del tablero (MIG445) y lo
-- ya congelado no se pisan. Y jamás tumba un cierre.
CREATE OR REPLACE FUNCTION public.fn_ot_congelar_al_ejecutar()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_km NUMERIC; v_h NUMERIC;
BEGIN
    BEGIN
        IF NEW.trabajo_realizado IS NULL THEN
            NEW.trabajo_realizado := public.fn_ot_resumen_trabajo(NEW.id);
        END IF;
        IF NEW.km_al_cierre IS NULL OR NEW.horas_al_cierre IS NULL THEN
            SELECT a.kilometraje_actual, a.horas_uso_actual INTO v_km, v_h
              FROM activos a WHERE a.id = NEW.activo_id;
            NEW.km_al_cierre    := COALESCE(NEW.km_al_cierre, v_km);
            NEW.horas_al_cierre := COALESCE(NEW.horas_al_cierre, v_h);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'MIG527: no se pudo congelar el trabajo de la OT % (%)', NEW.folio, SQLERRM;
    END;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_ot_congelar_al_ejecutar ON ordenes_trabajo;
CREATE TRIGGER trg_ot_congelar_al_ejecutar
BEFORE UPDATE OF estado ON ordenes_trabajo
FOR EACH ROW
WHEN (NEW.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
      AND OLD.estado IS DISTINCT FROM NEW.estado)
EXECUTE FUNCTION public.fn_ot_congelar_al_ejecutar();

-- ── 4 · Relleno de lo que quedó vacío ───────────────────────────────────────
DO $mig$
DECLARE v_n INT; r RECORD;
BEGIN
    -- El candado de la OT cerrada bloquea cualquier update: para RELLENAR el
    -- registro histórico (no modificarlo) se puentean los triggers SOLO
    -- dentro de esta transacción.
    SET LOCAL session_replication_role = replica;

    -- Resumen para toda OT ejecutada/cerrada sin trabajo_realizado (es
    -- atemporal: sale de lo que quedó marcado).
    v_n := 0;
    FOR r IN SELECT o.id FROM ordenes_trabajo o
              WHERE o.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
                AND o.trabajo_realizado IS NULL
    LOOP
        UPDATE ordenes_trabajo o
           SET trabajo_realizado = public.fn_ot_resumen_trabajo(r.id), updated_at = NOW()
         WHERE o.id = r.id
           AND public.fn_ot_resumen_trabajo(r.id) IS NOT NULL;
        v_n := v_n + 1;
    END LOOP;
    RAISE NOTICE 'resumen recalculado para % OT sin trabajo_realizado', v_n;

    -- Medidores solo para los cierres de esta semana: la lectura de hoy aún
    -- es la del cierre. Para lo antiguo sería inventar.
    UPDATE ordenes_trabajo o
       SET km_al_cierre    = COALESCE(o.km_al_cierre, a.kilometraje_actual),
           horas_al_cierre = COALESCE(o.horas_al_cierre, a.horas_uso_actual),
           updated_at = NOW()
      FROM activos a
     WHERE a.id = o.activo_id
       AND o.estado IN ('ejecutada_ok','ejecutada_con_observaciones','cerrada')
       AND COALESCE(o.fecha_termino, o.fecha_cierre_supervisor) >= DATE '2026-09-01'
       AND (o.km_al_cierre IS NULL OR o.horas_al_cierre IS NULL);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'medidores congelados en % OT cerradas esta semana', v_n;

    SET LOCAL session_replication_role = origin;

    -- ── Verificación con la OT que destapó todo ─────────────────────────────
    SELECT h.tareas_total, h.tareas_ok, h.trabajo_realizado IS NOT NULL AS con_resumen,
           h.horas_al_cierre
      INTO r
      FROM v_historial_mantenimiento_equipo h
     WHERE h.folio = 'OT-202608-00009';
    RAISE NOTICE 'OT-202608-00009 en historial: % tareas (% ok) · resumen=% · horas al cierre=%',
        r.tareas_total, r.tareas_ok, r.con_resumen, r.horas_al_cierre;
    IF r.tareas_ok <> 8 OR NOT r.con_resumen OR r.horas_al_cierre IS NULL THEN
        RAISE EXCEPTION 'FALLO: el historial sigue cojo (ok=%, resumen=%, horas=%)',
            r.tareas_ok, r.con_resumen, r.horas_al_cierre;
    END IF;
    RAISE NOTICE 'MIG527 OK · el historial congela el V03 por todos los caminos';
END
$mig$;

COMMIT;
