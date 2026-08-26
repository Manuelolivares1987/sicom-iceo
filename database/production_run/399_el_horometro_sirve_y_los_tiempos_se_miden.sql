-- ============================================================================
-- MIG399 · El horómetro llega a la preventiva, y los tiempos se pueden medir
-- ----------------------------------------------------------------------------
-- TRES COSAS, 26-08-2026.
--
-- ── 1. «¿el horómetro anotado actualiza la próxima preventiva?» ─────────────
-- La respuesta era NO, a medias, y conviene decirlo completo:
--
--   · El KILOMETRAJE sí, desde ayer: MIG397 mueve `activos.kilometraje_actual`
--     y de ahí sale `km_restantes` en v_pautas_estado_activo.
--   · El HORÓMETRO no. Se guardaba en el checklist y moría ahí:
--     `activos.horas_uso_actual` —que es de donde la vista saca `horas_actuales`
--     y calcula `horas_restantes`— no lo tocaba nadie.
--
-- Acá se cierra ese hueco, con la misma regla que el kilometraje: sólo hacia
-- adelante. El horómetro de un equipo no baja porque alguien anotó mal.
--
-- LO QUE ESTO NO ARREGLA — Y HAY QUE DECIRLO
-- La LÍNEA BASE de la preventiva (`ultimo_horometro`, `ultimo_km`: cuándo fue la
-- última mantención) NO sale de las OT que cierra este sistema. Sale de
-- `os_historico_importado`, una carga histórica congelada de 197 filas y 38
-- equipos, con fechas que van de 1900 a noviembre de 2026.
--
-- Por eso hoy, de 215 pautas, 127 no tienen base de horómetro y 145 no tienen
-- base de kilometraje: más de la mitad no puede calcular cuándo toca. Y no es
-- que el circuito falle: es que nunca corrió. Hay CERO OT cerradas en el
-- sistema, así que ninguna mantención hecha acá alimentó todavía esa línea.
--
-- Anotar el horómetro mejora el numerador. El denominador sigue viniendo de un
-- Excel viejo. Eso es un rediseño del motor de preventivas y se decide aparte:
-- no se toca a escondidas dentro de una migración de otra cosa.
--
-- ── 2. Los tiempos que impactan la remuneración ─────────────────────────────
-- Manuel: «necesito empezar a medir cuánto me estoy demorando en checklist, en
-- la ejecución de las NC, en conseguir repuestos».
--
-- Los relojes YA EXISTEN. Lo que no existía era dónde leerlos:
--
--   · Checklist  → taller_ot_ejecuciones.tiempo_efectivo_segundos (descuenta
--                  pausas y colación) + respondido_at ítem por ítem
--   · Repuestos  → ot_recursos_solicitados.created_at → validado_at →
--                  bodega_tickets.created_at → .entregado_at
--   · NC         → no_conformidades.created_at → plan_ot_id → cierre de la OT
--
-- Tres vistas, una por tramo. Ninguna inventa datos: donde no hay reloj, sale
-- NULL, porque un cero fingido en algo que paga sueldos es peor que un hueco.
--
-- LO QUE HOY SE PUEDE MEDIR DE VERDAD, MEDIDO
--   Repuestos: 31 pedidos · 47,3 h de pedir a aprobar · 83,5 h de aprobar a
--              vale · 0 entregados (nadie ha despachado todavía)
--   Checklist: 5 ejecuciones, 1,23 h promedio — el taller casi no usa play/pausa
--   NC:        114 abiertas, 0 resueltas, 0 con fecha de cierre
--
-- Las 83,5 h de aprobar a vale son el «antes» de MIG395: ahora ese tramo es
-- cero, porque aprobar emite el vale. Queda como línea base para comparar.
--
-- ── 3. Brian y Geran ────────────────────────────────────────────────────────
-- Dos mecánicos más en el taller de Coquimbo.
-- ============================================================================

BEGIN;

-- ── 1. El horómetro llega al maestro ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_registrar_medidores(
    p_ot_id       uuid,
    p_horometro   numeric DEFAULT NULL,
    p_kilometraje numeric DEFAULT NULL,
    p_confirmado  boolean DEFAULT FALSE
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_inst RECORD; v_activo UUID; v_exige_km BOOLEAN;
    v_hm_ant NUMERIC; v_km_ant NUMERIC; v_retro TEXT[] := ARRAY[]::TEXT[];
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para anotar medidores (rol: %)', v_rol; END IF;

    SELECT i.id, i.activo_id, i.horometro, i.kilometraje
      INTO v_inst
      FROM checklist_v2_instance i
     WHERE i.ot_id = p_ot_id
     ORDER BY i.created_at DESC
     LIMIT 1;
    IF v_inst.id IS NULL THEN
        RAISE EXCEPTION 'Esta OT no tiene checklist: no hay dónde anotar los medidores'; END IF;

    v_activo   := v_inst.activo_id;
    v_exige_km := fn_activo_exige_kilometraje(v_activo);

    IF p_horometro IS NOT NULL AND p_horometro < 0 THEN
        RAISE EXCEPTION 'El horómetro no puede ser negativo'; END IF;
    IF p_kilometraje IS NOT NULL AND p_kilometraje < 0 THEN
        RAISE EXCEPTION 'El kilometraje no puede ser negativo'; END IF;

    SELECT max(i.horometro), max(i.kilometraje) INTO v_hm_ant, v_km_ant
      FROM checklist_v2_instance i
     WHERE i.activo_id = v_activo AND i.id <> v_inst.id;
    v_hm_ant := GREATEST(COALESCE(v_hm_ant, 0),
                         COALESCE((SELECT a.horas_uso_actual FROM activos a WHERE a.id = v_activo), 0));
    v_km_ant := GREATEST(COALESCE(v_km_ant, 0),
                         COALESCE((SELECT a.kilometraje_actual FROM activos a WHERE a.id = v_activo), 0));

    IF p_horometro IS NOT NULL AND v_hm_ant > 0 AND p_horometro < v_hm_ant THEN
        v_retro := array_append(v_retro,
            format('horómetro (antes %s h, ahora %s h)', v_hm_ant, p_horometro)::TEXT);
    END IF;
    IF p_kilometraje IS NOT NULL AND v_km_ant > 0 AND p_kilometraje < v_km_ant THEN
        v_retro := array_append(v_retro,
            format('kilometraje (antes %s km, ahora %s km)', v_km_ant, p_kilometraje)::TEXT);
    END IF;

    IF array_length(v_retro, 1) > 0 AND NOT p_confirmado THEN
        RETURN jsonb_build_object(
            'success', FALSE, 'requiere_confirmacion', TRUE,
            'motivo', 'El número es menor que la última lectura: ' || array_to_string(v_retro, ' y ') ||
                      '. Si el medidor se cambió, confirma; si no, corrige el número.');
    END IF;

    UPDATE checklist_v2_instance
       SET horometro     = COALESCE(p_horometro, horometro),
           kilometraje   = COALESCE(p_kilometraje, kilometraje),
           medidores_por = v_user,
           medidores_at  = NOW(),
           observaciones = CASE
               WHEN array_length(v_retro, 1) > 0
               THEN COALESCE(observaciones || ' · ', '')
                    || 'Medidor confirmado a mano pese a retroceder: ' || array_to_string(v_retro, ' y ')
               ELSE observaciones END,
           updated_at    = NOW()
     WHERE id = v_inst.id;

    -- [MIG399] El maestro, con las dos lecturas. `horas_uso_actual` es de donde
    -- v_pautas_estado_activo saca `horas_actuales` para calcular cuánto falta
    -- para la próxima preventiva: sin esto, el horómetro que anotó el mecánico
    -- se quedaba en el checklist y no servía para nada. Sólo hacia adelante.
    IF p_horometro IS NOT NULL THEN
        UPDATE activos
           SET horas_uso_actual = p_horometro, updated_at = NOW()
         WHERE id = v_activo
           AND COALESCE(horas_uso_actual, 0) < p_horometro;
    END IF;
    IF p_kilometraje IS NOT NULL THEN
        UPDATE activos
           SET kilometraje_actual = p_kilometraje, updated_at = NOW()
         WHERE id = v_activo
           AND COALESCE(kilometraje_actual, 0) < p_kilometraje;
    END IF;

    RETURN jsonb_build_object('success', TRUE,
        'horometro', COALESCE(p_horometro, v_inst.horometro),
        'kilometraje', COALESCE(p_kilometraje, v_inst.kilometraje),
        'exige_kilometraje', v_exige_km);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_registrar_medidores(uuid,numeric,numeric,boolean) TO authenticated;

-- ── 2a. Cuánto se demora un checklist ─────────────────────────────────────
CREATE OR REPLACE VIEW public.v_taller_tiempo_checklist AS
SELECT
    e.id                        AS ejecucion_id,
    e.ot_id,
    o.folio                     AS ot_folio,
    o.tipo                      AS ot_tipo,
    a.codigo                    AS activo_codigo,
    a.patente                   AS activo_patente,
    e.ejecutor_id,
    COALESCE(u.nombre_completo, 'Sin asignar') AS ejecutor,
    e.estado,
    e.started_at,
    e.finished_at,
    -- El efectivo descuenta pausas y colación: es el que puede pagar horas.
    round(e.tiempo_efectivo_segundos / 3600.0, 2) AS horas_efectivas,
    round(e.tiempo_pausado_segundos  / 3600.0, 2) AS horas_pausado,
    round(e.tiempo_colacion_segundos / 3600.0, 2) AS horas_colacion,
    ci.items_totales,
    ci.items_hechos,
    -- Minutos por ítem: la medida comparable entre checklists de distinto largo.
    CASE WHEN COALESCE(ci.items_hechos,0) > 0 AND e.tiempo_efectivo_segundos > 0
         THEN round((e.tiempo_efectivo_segundos / 60.0) / ci.items_hechos, 2)
         ELSE NULL END          AS min_por_item,
    e.avance_final
FROM taller_ot_ejecuciones e
JOIN ordenes_trabajo o ON o.id = e.ot_id
LEFT JOIN activos a ON a.id = o.activo_id
LEFT JOIN usuarios_perfil u ON u.id = e.ejecutor_id
LEFT JOIN LATERAL (
    SELECT count(*) AS items_totales,
           count(*) FILTER (WHERE ii.resultado IS NOT NULL
                              AND ii.resultado::text <> 'pendiente') AS items_hechos
      FROM checklist_v2_instance i
      JOIN checklist_v2_instance_item ii ON ii.instance_id = i.id
     WHERE i.ot_id = e.ot_id AND NOT COALESCE(ii.excluido, false)
) ci ON TRUE;

COMMENT ON VIEW public.v_taller_tiempo_checklist IS
  'MIG399: cuánto se demoró cada checklist. horas_efectivas descuenta pausas y colación. min_por_item permite comparar checklists de distinto largo.';

-- ── 2b. Cuánto se demora conseguir un repuesto ────────────────────────────
CREATE OR REPLACE VIEW public.v_taller_tiempo_repuesto AS
SELECT
    r.id                        AS recurso_id,
    o.folio                     AS ot_folio,
    a.codigo                    AS activo_codigo,
    a.patente                   AS activo_patente,
    COALESCE(pr.nombre, r.descripcion) AS que_se_pidio,
    pr.codigo                   AS producto_codigo,
    r.estado,
    COALESCE(r.solicitado_nombre, us.nombre_completo) AS lo_pidio,
    uv.nombre_completo          AS lo_aprobo,
    r.created_at                AS pedido_at,
    r.validado_at               AS aprobado_at,
    bt.folio                    AS vale_folio,
    bt.created_at               AS vale_at,
    bt.entregado_at,
    -- Los tres tramos, en horas. NULL donde el reloj todavía no corrió: un cero
    -- fingido en algo que paga sueldos es peor que un hueco.
    round((EXTRACT(EPOCH FROM (r.validado_at  - r.created_at))  / 3600.0)::numeric, 1) AS h_pedir_a_aprobar,
    round((EXTRACT(EPOCH FROM (bt.created_at  - r.validado_at)) / 3600.0)::numeric, 1) AS h_aprobar_a_vale,
    round((EXTRACT(EPOCH FROM (bt.entregado_at - bt.created_at))/ 3600.0)::numeric, 1) AS h_vale_a_entrega,
    round((EXTRACT(EPOCH FROM (bt.entregado_at - r.created_at)) / 3600.0)::numeric, 1) AS h_total,
    -- Lo que lleva esperando si todavía no llega.
    CASE WHEN bt.entregado_at IS NULL
         THEN round((EXTRACT(EPOCH FROM (NOW() - r.created_at)) / 3600.0)::numeric, 1)
         ELSE NULL END          AS h_esperando
FROM ot_recursos_solicitados r
LEFT JOIN ordenes_trabajo o ON o.id = r.ot_id
LEFT JOIN activos a ON a.id = o.activo_id
LEFT JOIN productos pr ON pr.id = r.producto_id
LEFT JOIN usuarios_perfil us ON us.id = r.solicitado_por
LEFT JOIN usuarios_perfil uv ON uv.id = r.validado_por
LEFT JOIN bodega_tickets bt ON bt.id = r.ticket_id;

COMMENT ON VIEW public.v_taller_tiempo_repuesto IS
  'MIG399: el embudo del repuesto en horas — pedir, aprobar, vale, entrega. h_esperando dice cuánto lleva parado lo que aún no llega.';

-- ── 2c. Cuánto se demora resolver una no conformidad ──────────────────────
CREATE OR REPLACE VIEW public.v_taller_tiempo_nc AS
SELECT
    nc.id                       AS nc_id,
    a.codigo                    AS activo_codigo,
    a.patente                   AS activo_patente,
    nc.descripcion,
    nc.severidad,
    nc.origen,
    nc.estado_planificacion,
    nc.resuelto,
    nc.created_at               AS detectada_at,
    ot.fecha_programada         AS programada_para,
    ot.fecha_inicio             AS ot_inicio,
    ot.fecha_termino            AS ot_termino,
    nc.resuelto_en,
    round((EXTRACT(EPOCH FROM (ot.fecha_inicio - nc.created_at)) / 86400.0)::numeric, 1) AS dias_detectada_a_taller,
    round((EXTRACT(EPOCH FROM (nc.resuelto_en  - nc.created_at)) / 86400.0)::numeric, 1) AS dias_detectada_a_resuelta,
    -- Lo que lleva abierta. Es el número que duele y el único que hoy tiene
    -- datos: no hay ninguna NC resuelta todavía.
    CASE WHEN NOT COALESCE(nc.resuelto, false)
         THEN round((EXTRACT(EPOCH FROM (NOW() - nc.created_at)) / 86400.0)::numeric, 1)
         ELSE NULL END          AS dias_abierta
FROM no_conformidades nc
LEFT JOIN activos a ON a.id = nc.activo_id
LEFT JOIN ordenes_trabajo ot ON ot.id = nc.plan_ot_id;

COMMENT ON VIEW public.v_taller_tiempo_nc IS
  'MIG399: cuánto pasa entre que se detecta una NC y se resuelve. dias_abierta es el único con datos hoy: no hay ninguna NC resuelta.';

GRANT SELECT ON public.v_taller_tiempo_checklist  TO authenticated;
GRANT SELECT ON public.v_taller_tiempo_repuesto   TO authenticated;
GRANT SELECT ON public.v_taller_tiempo_nc         TO authenticated;

-- ── 3. Brian y Geran ──────────────────────────────────────────────────────
INSERT INTO public.taller_tecnicos (nombre, especialidad, operacion, activo)
SELECT v.nombre, 'MECANICO', 'Coquimbo', TRUE
  FROM (VALUES ('Brian'), ('Geran')) AS v(nombre)
 WHERE NOT EXISTS (
    SELECT 1 FROM public.taller_tecnicos t
     WHERE lower(trim(t.nombre)) = lower(trim(v.nombre)));

-- ── 4. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE v_tec TEXT; v_rep RECORD; v_pautas INT; v_sin_base INT;
BEGIN
    SELECT string_agg(nombre, ', ' ORDER BY nombre) INTO v_tec
      FROM taller_tecnicos WHERE activo AND operacion = 'Coquimbo';
    RAISE NOTICE 'Mecánicos de Coquimbo: %', v_tec;

    SELECT count(*), count(*) FILTER (WHERE ultimo_horometro IS NULL)
      INTO v_pautas, v_sin_base FROM v_pautas_estado_activo;
    RAISE NOTICE 'Pautas: % · sin línea base de horómetro: % (viene de os_historico_importado, no de las OT del sistema)',
        v_pautas, v_sin_base;

    SELECT count(*) AS n,
           round(avg(h_pedir_a_aprobar),1) AS a,
           round(avg(h_aprobar_a_vale),1)  AS b,
           count(entregado_at)             AS ent
      INTO v_rep FROM v_taller_tiempo_repuesto;
    RAISE NOTICE 'Repuestos: % pedidos · % h pedir→aprobar · % h aprobar→vale · % entregados',
        v_rep.n, v_rep.a, v_rep.b, v_rep.ent;
END
$r$;

COMMIT;
