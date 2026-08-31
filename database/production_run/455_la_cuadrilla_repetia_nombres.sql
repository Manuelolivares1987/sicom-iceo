-- ============================================================================
-- MIG455 · La cuadrilla repetía nombres en el teléfono del mecánico
-- ============================================================================
--
-- ENCONTRADO PROBANDO EN PRODUCCIÓN, NO LEYENDO CÓDIGO
-- En /m/taller, la OT-202606-00037 mostraba su cuadrilla así:
--
--     Brian Alday, Felipe López, Marco Díaz, Joel Coo, Marco Díaz, Marco Díaz,
--     Joel Coo…
--
-- Siete nombres para cuatro personas. En una OT de 248 horas y 213 tareas, que
-- es exactamente donde el mecánico necesita leer rápido quién está con él.
--
-- POR QUÉ PASABA
-- `v_taller_mecanico_ots` juntaba las cuadrillas de todas las jornadas de la OT
-- con `string_agg(DISTINCT t.cuadrilla, ', ')`. El DISTINCT estaba aplicado al
-- TEXTO COMPLETO de cada jornada, no a los nombres. Tres jornadas escritas como
--
--     «Marco Díaz, Joel Coo»    «Marco Díaz»    «Joel Coo, Marco Díaz»
--
-- son tres textos distintos, así que los tres pasaban el DISTINCT y se pegaban
-- uno detrás del otro. Mientras más días duraba la OT, más se repetía.
--
-- QUÉ SE HACE
-- Se abren los textos por coma, se deduplica por NOMBRE y se vuelve a juntar,
-- en orden alfabético para que la lista sea estable entre jornadas. Es un
-- cambio de presentación: no toca `taller_ot_cuadrilla`, que es lo que reparte
-- el bono y donde una persona SÍ debe aparecer una vez por cada jornada que
-- trabajó.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW v_taller_mecanico_ots AS
 SELECT ot.id AS ot_id,
    ot.folio AS ot_folio,
    ot.tipo AS ot_tipo,
    ot.estado AS ot_estado,
    ot.prioridad AS ot_prioridad,
    ot.preparacion_ok_at,
    ot.fecha_programada,
    ot.activo_id,
    a.codigo AS activo_codigo,
    a.nombre AS activo_nombre,
    a.patente AS activo_patente,
    ( SELECT string_agg(n.nombre, ', '::text ORDER BY n.nombre)
           FROM ( SELECT DISTINCT TRIM(BOTH FROM x.nombre) AS nombre
                    FROM taller_plan_semanal_ots t,
                         LATERAL unnest(string_to_array(t.cuadrilla, ','::text)) AS x(nombre)
                   WHERE t.ot_id = ot.id
                     AND NULLIF(TRIM(BOTH FROM x.nombre), ''::text) IS NOT NULL) n) AS cuadrilla,
    ot.responsable_id,
    COALESCE(tt.nombre, up.nombre_completo) AS responsable,
    fn_taller_ot_asignada_al_usuario(ot.id) AS asignada_a_mi,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false) AS checklist_total,
    ( SELECT count(*) AS count
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false AND v.resultado IS NOT NULL AND v.resultado <> 'pendiente'::resultado_item_enum) AS checklist_completados,
    ( SELECT COALESCE(sum(v.tiempo_min), 0::numeric) AS "coalesce"
           FROM v_taller_ot_checklist_v3 v
          WHERE v.ot_id = ot.id AND v.excluido = false) AS tiempo_estimado_total_min
   FROM ordenes_trabajo ot
     JOIN activos a ON a.id = ot.activo_id
     LEFT JOIN taller_tecnicos tt ON tt.id = ot.tecnico_id
     LEFT JOIN usuarios_perfil up ON up.id = ot.responsable_id
  WHERE ot.preparacion_ok_at IS NOT NULL AND (ot.estado = ANY (ARRAY['asignada'::estado_ot_enum, 'en_ejecucion'::estado_ot_enum, 'pausada'::estado_ot_enum]))
  ORDER BY (
        CASE ot.estado
            WHEN 'en_ejecucion'::estado_ot_enum THEN 1
            WHEN 'pausada'::estado_ot_enum THEN 2
            ELSE 3
        END), (
        CASE ot.prioridad
            WHEN 'emergencia'::prioridad_enum THEN 1
            WHEN 'urgente'::prioridad_enum THEN 2
            WHEN 'alta'::prioridad_enum THEN 3
            WHEN 'normal'::prioridad_enum THEN 4
            ELSE 5
        END), ot.fecha_programada;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE
    r     RECORD;
    v_mal INT := 0;
    v_ej  TEXT;
BEGIN
    FOR r IN SELECT ot_folio, cuadrilla FROM v_taller_mecanico_ots
              WHERE cuadrilla IS NOT NULL
    LOOP
        IF (SELECT count(*)          FROM unnest(string_to_array(r.cuadrilla, ', ')) x)
         <> (SELECT count(DISTINCT x) FROM unnest(string_to_array(r.cuadrilla, ', ')) x)
        THEN
            v_mal := v_mal + 1;
            v_ej  := COALESCE(v_ej, r.ot_folio || ': ' || r.cuadrilla);
        END IF;
    END LOOP;

    IF v_mal > 0 THEN
        RAISE EXCEPTION 'FALLO: % OT siguen repitiendo nombres. Ej. %', v_mal, v_ej;
    END IF;
    RAISE NOTICE 'ninguna OT repite nombres en la cuadrilla';

    -- El caso que se vio en el teléfono.
    SELECT cuadrilla INTO v_ej FROM v_taller_mecanico_ots WHERE ot_folio = 'OT-202606-00037';
    RAISE NOTICE 'OT-202606-00037 ahora dice: %', COALESCE(v_ej, '(sin cuadrilla)');
END
$mig$;

COMMIT;
