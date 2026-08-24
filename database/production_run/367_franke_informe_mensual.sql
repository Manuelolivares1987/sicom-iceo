-- ============================================================================
-- MIG367 · El informe de gestión se arma solo
-- ----------------------------------------------------------------------------
-- El informe mensual del contrato FRK 220/2024 son ocho páginas que hoy se
-- escriben a mano el día 3 del mes siguiente, cruzando una planilla de 4.989
-- filas. Todos sus números salen de datos que el sistema ya tiene: las cargas,
-- los tickets, los folios, las entregas de turno firmadas.
--
-- QUÉ CALCULA Y QUÉ NO
-- Calcula lo que es aritmética sobre registros: litros por concepto, tickets y
-- folios, deriva del cuentalitros, ventas por cargo, cargas por camión y por
-- surtidor, y el balance del periodo. Eso es la sección 4 completa, que es la
-- que hoy toma el día entero.
--
-- NO inventa las novedades del mes, las horas hombre ni las conclusiones. Esas
-- son criterio del Administrador de Contrato y el sistema no las tiene. Lo que
-- sí hace es decir cuáles faltan, para que el informe no se emita a medias
-- creyendo que está completo.
--
-- EL MES NO EMPIEZA A MEDIANOCHE
-- El propio informe de julio lo declara: «Inicio: 1 de julio, desde las 08:00
-- hrs. AM (turno día). Término: 1 de agosto, hasta las 08:00 hrs. AM». El
-- periodo va de cambio de turno a cambio de turno, no de medianoche a
-- medianoche. Con el corte a medianoche, las cargas del turno de noche del
-- último día se irían al mes equivocado — y son las que después no cuadran.
-- La hora de corte ya existe en la configuración de la faena; acá se le pone el
-- valor real y se usa.
--
-- LOS CONCEPTOS QUE NO SON VENTA CUENTAN PARA EL FOLIO Y NO PARA EL LITRO
-- El trasvasije de inicio y fin de turno consume folio —en julio fueron 16
-- tickets— y el ticket nulo de cero litros también. Para la continuidad de la
-- numeración todos valen; para el balance de litros, sólo la venta. Mezclarlos
-- es el error que genera un faltante ficticio.
-- ============================================================================

BEGIN;

-- El periodo de Franke corre de cambio de turno a cambio de turno.
UPDATE public.combustible_faena_config
   SET hora_corte = TIME '08:00',
       observacion = COALESCE(observacion, '')
         || ' El periodo corre de 08:00 a 08:00, como lo declara el informe de gestion (MIG367).',
       updated_at = NOW()
 WHERE faena_id = (SELECT id FROM public.faenas WHERE codigo = 'FAE-FRANCKE');


CREATE OR REPLACE FUNCTION public.fn_faena_informe_mensual(
    p_faena_id uuid,
    p_desde    date,
    p_hasta    date          -- inclusive: el último día del periodo
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
DECLARE
    v_corte   TIME;
    v_ini_ts  TIMESTAMPTZ;
    v_fin_ts  TIMESTAMPTZ;
    v_bal     JSONB;
    v_falta   TEXT[] := '{}';
BEGIN
    SELECT COALESCE(hora_corte, TIME '00:00') INTO v_corte
      FROM combustible_faena_config WHERE faena_id = p_faena_id;
    v_corte := COALESCE(v_corte, TIME '00:00');

    -- De las 08:00 del primer día a las 08:00 del día siguiente al último.
    v_ini_ts := (p_desde + v_corte)::timestamptz;
    v_fin_ts := ((p_hasta + 1) + v_corte)::timestamptz;

    v_bal := public.fn_faena_balance_periodo(p_faena_id, p_desde, p_hasta);

    -- Lo que el sistema NO sabe y alguien tiene que escribir. Se declara para
    -- que el informe no salga a medias creyendo que está entero.
    IF NOT (v_bal->>'stock_inicial_verificado')::boolean THEN
        v_falta := v_falta || ('El stock inicial no viene de un conteo físico verificado: falta la entrega de turno del cierre anterior.')::text;
    END IF;
    IF NOT (v_bal->>'stock_fisico_verificado')::boolean THEN
        v_falta := v_falta || ('No hay conteo físico de cierre del periodo. El stock final quedaría como valor informado, sin respaldo.')::text;
    END IF;
    IF (v_bal->'folios'->>'faltantes')::int > 0 THEN
        v_falta := v_falta || ('Faltan ' || (v_bal->'folios'->>'faltantes') || ' folio(s) en la numeración: revisar si son tickets anulados o cargas sin registrar.')::text;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM combustible_faena_recepcion r
                    WHERE r.faena_id = p_faena_id AND NOT r.anulada
                      AND r.fecha BETWEEN p_desde AND p_hasta) THEN
        v_falta := v_falta || ('No hay cargas de camión registradas en el periodo: sin ellas el balance no cierra contra la estación de servicio.')::text;
    END IF;

    RETURN jsonb_build_object(
      'faena', (SELECT jsonb_build_object('codigo', codigo, 'nombre', nombre)
                  FROM faenas WHERE id = p_faena_id),
      'periodo', jsonb_build_object(
          'desde', p_desde, 'hasta', p_hasta,
          'hora_corte', v_corte,
          'texto', 'Desde el ' || to_char(p_desde, 'DD') || ' de ' ||
                   to_char(p_desde, 'TMMonth') || ' a las ' || to_char(v_corte, 'HH24:MI') ||
                   ' hasta el ' || to_char(p_hasta + 1, 'DD') || ' de ' ||
                   to_char(p_hasta + 1, 'TMMonth') || ' a las ' || to_char(v_corte, 'HH24:MI') || ' hrs.'),

      -- ── 2. Dotación ────────────────────────────────────────────────────
      'dotacion', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'nombre', up.nombre_completo, 'cargo', up.cargo, 'rol', up.rol)
                 ORDER BY up.cargo, up.nombre_completo)
          FROM usuarios_perfil up
         WHERE up.faena_id = p_faena_id AND up.activo), '[]'::jsonb),

      -- ── 3. Equipos ─────────────────────────────────────────────────────
      -- El estado al cierre sale de la última entrega de turno FIRMADA del
      -- periodo; si no hay ninguna, de la ficha del activo. Se dice cuál de las
      -- dos, porque un estado firmado y uno inferido no valen lo mismo.
      'equipos', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'patente', a.patente,
                 'equipo', COALESCE(a.nombre, a.codigo),
                 'estado', COALESCE(q.estado, a.estado::text),
                 'origen_estado', CASE WHEN q.estado IS NOT NULL THEN 'entrega firmada' ELSE 'ficha del activo' END,
                 'horometro', COALESCE(q.horometro, a.horas_uso_actual),
                 'kilometraje', COALESCE(q.kilometraje, a.kilometraje_actual),
                 'desviaciones', COALESCE(q.desviaciones, 0))
                 ORDER BY a.patente)
          FROM activos a
          LEFT JOIN LATERAL (
              SELECT qq.estado, qq.horometro, qq.kilometraje, qq.desviaciones
                FROM faena_entrega_equipo qq
                JOIN faena_entrega_turno ee ON ee.id = qq.entrega_id
               WHERE qq.activo_id = a.id AND ee.faena_id = p_faena_id
                 AND ee.hasta BETWEEN p_desde AND p_hasta
                 AND ee.estado <> 'abierta'
               ORDER BY ee.hasta DESC LIMIT 1) q ON TRUE
         WHERE a.faena_id = p_faena_id AND a.fecha_baja IS NULL), '[]'::jsonb),

      -- ── 4. Abastecimiento ──────────────────────────────────────────────
      'litros_por_concepto', (
        SELECT jsonb_build_object(
                 'transacciones',  COALESCE(SUM(litros), 0),
                 'ventas',         COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'venta'), 0),
                 'trasvasijes',    COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'trasvasije'), 0),
                 'calibraciones',  COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'calibracion'), 0),
                 'recirculaciones',COALESCE(SUM(litros) FILTER (WHERE tipo_movimiento = 'recirculacion'), 0))
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p_faena_id AND NOT d.anulado
           AND (d.fecha + COALESCE(d.hora, v_corte))::timestamptz >= v_ini_ts
           AND (d.fecha + COALESCE(d.hora, v_corte))::timestamptz <  v_fin_ts),

      'tickets', (
        SELECT jsonb_build_object(
                 'emitidos',        count(*) FILTER (WHERE folio_ticket IS NOT NULL),
                 'ventas',          count(*) FILTER (WHERE tipo_movimiento = 'venta'),
                 'ventas_validas',  count(*) FILTER (WHERE tipo_movimiento = 'venta' AND litros > 0),
                 'nulos_cero_litros', count(*) FILTER (WHERE tipo_movimiento = 'venta' AND litros = 0),
                 'trasvasije_y_stock', count(*) FILTER (WHERE tipo_movimiento = 'trasvasije'),
                 'calibracion_recirculacion', count(*) FILTER (WHERE tipo_movimiento IN ('calibracion','recirculacion')),
                 'sin_folio',       count(*) FILTER (WHERE folio_ticket IS NULL),
                 'folio_desde',     MIN(folio_ticket),
                 'folio_hasta',     MAX(folio_ticket))
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p_faena_id AND NOT d.anulado
           AND d.fecha BETWEEN p_desde AND p_hasta),

      'folios_faltantes', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('folio', folio, 'entre', folio_anterior, 'y', folio_siguiente)
                         ORDER BY folio)
          FROM fn_faena_folios_faltantes(p_faena_id, p_desde, p_hasta)), '[]'::jsonb),

      -- El control cruzado que el informe hace a mano: lo que dijo cada
      -- transacción contra lo que movió el cuentalitros.
      'deriva', (
        SELECT jsonb_build_object(
                 'parcial',     COALESCE(SUM(litros), 0),
                 'acumulativo', COALESCE(SUM(meter_final - meter_inicial), 0),
                 'diferencia',  COALESCE(SUM(litros) - SUM(meter_final - meter_inicial), 0),
                 'pct', ROUND(100.0 * (COALESCE(SUM(litros),0) - COALESCE(SUM(meter_final - meter_inicial),0))
                              / NULLIF(SUM(litros), 0), 3),
                 'transacciones_medidas', count(*))
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p_faena_id AND NOT d.anulado
           AND d.tipo_movimiento = 'venta'
           AND d.meter_inicial IS NOT NULL AND d.meter_final IS NOT NULL
           AND d.fecha BETWEEN p_desde AND p_hasta),

      'ventas_por_cargo', v_bal->'ventas_por_ceco',

      'no_venta_por_concepto', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('concepto', tipo_movimiento, 'litros', lt, 'tickets', n)
                         ORDER BY lt DESC)
          FROM (SELECT d.tipo_movimiento, SUM(d.litros) AS lt, count(*) AS n
                  FROM combustible_faena_despachos d
                 WHERE d.faena_id = p_faena_id AND NOT d.anulado
                   AND d.tipo_movimiento <> 'venta'
                   AND d.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY d.tipo_movimiento) s), '[]'::jsonb),

      -- ── Las cargas del camión en la estación ───────────────────────────
      'cargas_por_camion', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('camion', camion, 'litros', lt, 'cargas', n)
                         ORDER BY lt DESC)
          FROM (SELECT COALESCE(r.camion, '(sin camión)') AS camion,
                       SUM(r.litros_guia) AS lt, count(*) AS n
                  FROM combustible_faena_recepcion r
                 WHERE r.faena_id = p_faena_id AND NOT r.anulada
                   AND r.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY 1) s), '[]'::jsonb),

      'cargas_por_surtidor', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('eds', eds, 'surtidor', surtidor, 'litros', lt, 'cargas', n)
                         ORDER BY eds, surtidor)
          FROM (SELECT COALESCE(r.eds, '(sin EDS)') AS eds,
                       COALESCE(r.surtidor, '(sin surtidor)') AS surtidor,
                       SUM(r.litros_guia) AS lt, count(*) AS n
                  FROM combustible_faena_recepcion r
                 WHERE r.faena_id = p_faena_id AND NOT r.anulada
                   AND r.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY 1, 2) s), '[]'::jsonb),

      'balance', v_bal,

      -- ── El acumulado del año, para la sección 5 ────────────────────────
      'anio', (
        SELECT jsonb_build_object(
                 'anio', EXTRACT(YEAR FROM p_hasta)::int,
                 'ventas', COALESCE(SUM(d.litros), 0),
                 'transacciones', count(*))
          FROM combustible_faena_despachos d
         WHERE d.faena_id = p_faena_id AND NOT d.anulado
           AND d.tipo_movimiento = 'venta'
           AND EXTRACT(YEAR FROM d.fecha) = EXTRACT(YEAR FROM p_hasta)),

      'mayores_consumidores_anio', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('ceco', c.codigo, 'empresa', c.empresa, 'litros', s.lt)
                         ORDER BY s.lt DESC)
          FROM (SELECT d.ceco_id, SUM(d.litros) AS lt
                  FROM combustible_faena_despachos d
                 WHERE d.faena_id = p_faena_id AND NOT d.anulado
                   AND d.tipo_movimiento = 'venta'
                   AND EXTRACT(YEAR FROM d.fecha) = EXTRACT(YEAR FROM p_hasta)
                 GROUP BY d.ceco_id ORDER BY 2 DESC LIMIT 10) s
          LEFT JOIN combustible_faena_cecos c ON c.id = s.ceco_id), '[]'::jsonb),

      -- ── Las entregas de turno del periodo ──────────────────────────────
      'entregas_turno', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'desde', e.desde, 'hasta', e.hasta,
                 'turno_saliente', e.turno_saliente, 'turno_entrante', e.turno_entrante,
                 'estado', e.estado,
                 'conteo_fisico', e.conteo_fisico_hecho,
                 'conteo_omitido_motivo', e.conteo_omitido_motivo,
                 'stock_fisico', e.stock_fisico_lt,
                 'entrega_nombre', e.entrega_nombre, 'recibe_nombre', e.recibe_nombre,
                 'reparos', e.reparos)
                 ORDER BY e.hasta)
          FROM faena_entrega_turno e
         WHERE e.faena_id = p_faena_id
           AND e.hasta BETWEEN p_desde AND p_hasta), '[]'::jsonb),

      -- ── Lo que hay que escribir a mano ─────────────────────────────────
      'redaccion_pendiente', jsonb_build_array(
        'Novedades del periodo: cambios de personal, condición de las instalaciones, actividades de prevención.',
        'Horas hombre regulares ejecutadas en el periodo.',
        'Conclusiones del Administrador de Contrato.'),
      'advertencias', to_jsonb(v_falta));
END;
$f$;

GRANT EXECUTE ON FUNCTION public.fn_faena_informe_mensual(uuid, date, date) TO authenticated;

COMMENT ON FUNCTION public.fn_faena_informe_mensual(uuid, date, date) IS
  'La seccion 4 del informe de gestion mensual, calculada. No inventa novedades ni conclusiones: dice cuales faltan. MIG367.';

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT jsonb_pretty(fn_faena_informe_mensual(
--          (SELECT id FROM faenas WHERE codigo='FAE-FRANCKE'),
--          DATE '2026-08-01', DATE '2026-08-31'));
