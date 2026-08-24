-- ============================================================================
-- MIG363 · El ticket printer entra al sistema: folio, surtidor y deriva
-- ----------------------------------------------------------------------------
-- Romeral resuelve la imputación con el archivo del tótem Orpak. Franke no
-- tiene tótem: tiene un ticket printer arriba del camión que emite un folio
-- correlativo por cada transacción. En julio fueron 1.001 tickets, del 20385 al
-- 21383, y todo el control de esa correlatividad se hace hoy contando a mano en
-- una planilla de 4.989 filas.
--
-- TRES CONTROLES QUE HOY NO SE HACEN PORQUE SON CAROS A MANO
--
-- 1. CONTINUIDAD DE FOLIOS. Un salto en la numeración es un ticket que no se
--    registró. Con 1.001 tickets al mes, detectarlo exige recorrer la lista
--    entera; con el folio guardado, el hueco salta solo.
--
-- 2. DERIVA DEL CUENTALITROS. El informe de julio la calcula: 227.650 L por el
--    contador acumulativo contra 227.421 L por el parcial de cada transacción,
--    −229 L, −0,101 %. Es un cálculo correcto y hecho a mano una vez al mes. El
--    dato para hacerlo todos los días ya está en cada carga (medidor inicial y
--    final), sólo faltaba compararlo.
--
-- 3. DÓNDE SE CARGÓ. En julio se usó exclusivamente el surtidor 3 de EDS Mina,
--    y eso importa: es el dato con el que se concilia contra la estación. La
--    recepción del módulo de faena estaba pensada para un camión de flota
--    primaria que llega con guía; en Franke el camión va a la EDS y carga de un
--    surtidor. Es el mismo movimiento —combustible que entra— con otros campos.
--
-- POR QUÉ EL FOLIO ES ÚNICO POR FAENA Y NO GLOBAL
-- Cada faena tiene su propio talonario. Dos faenas pueden emitir el folio 500 el
-- mismo día sin que eso sea un error.
--
-- LOS FOLIOS QUE NO SON VENTA CUENTAN IGUAL
-- El trasvasije de inicio y fin de turno también consume folio —en julio fueron
-- 16 tickets— y el ticket nulo de cero litros también. Para el control de
-- continuidad todos valen; para el de litros, no. Por eso el folio vive en la
-- carga y no en un contador aparte.
-- ============================================================================

BEGIN;

-- ── El folio del ticket ───────────────────────────────────────────────────
ALTER TABLE public.combustible_faena_despachos
    ADD COLUMN IF NOT EXISTS folio_ticket INTEGER;

COMMENT ON COLUMN public.combustible_faena_despachos.folio_ticket IS
  'Numero correlativo del ticket printer del camion. Un salto en la numeracion es un ticket que no se registro. MIG363.';

-- Un folio no se emite dos veces en la misma faena. Parcial porque la mayoría
-- de las cargas históricas no lo tienen y no se les puede inventar.
CREATE UNIQUE INDEX IF NOT EXISTS ux_comb_despacho_folio
    ON public.combustible_faena_despachos(faena_id, folio_ticket)
 WHERE folio_ticket IS NOT NULL AND NOT anulado;


-- ── Dónde carga el camión ─────────────────────────────────────────────────
ALTER TABLE public.combustible_faena_recepcion
    ADD COLUMN IF NOT EXISTS eds        TEXT,
    ADD COLUMN IF NOT EXISTS surtidor   TEXT,
    ADD COLUMN IF NOT EXISTS folio_ticket INTEGER,
    ADD COLUMN IF NOT EXISTS meter_inicial NUMERIC,
    ADD COLUMN IF NOT EXISTS meter_final   NUMERIC;

COMMENT ON COLUMN public.combustible_faena_recepcion.eds IS
  'Estacion de servicio donde cargo el camion (Mina, Planta). En julio 2026 se uso exclusivamente EDS Mina. MIG363.';
COMMENT ON COLUMN public.combustible_faena_recepcion.surtidor IS
  'Surtidor de la EDS. En julio 2026, exclusivamente el 3. Es el dato con el que se concilia contra la estacion. MIG363.';


-- ══════════════════════════════════════════════════════════════════════════
-- CONTROL 1 · LOS FOLIOS QUE FALTAN
-- ══════════════════════════════════════════════════════════════════════════
-- Recorre la numeración emitida y dice qué números no están. No adivina por
-- qué faltan: un folio ausente puede ser un ticket anulado, uno que no se
-- registró o uno que se registró en otra fecha. Lo que hace es dejar de ser
-- invisible.

CREATE OR REPLACE FUNCTION public.fn_faena_folios_faltantes(
    p_faena_id uuid, p_desde date, p_hasta date
)
RETURNS TABLE (folio integer, folio_anterior integer, folio_siguiente integer, salto integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    WITH emitidos AS (
        SELECT DISTINCT folio_ticket AS f
          FROM combustible_faena_despachos
         WHERE faena_id = p_faena_id AND NOT anulado
           AND folio_ticket IS NOT NULL
           AND fecha BETWEEN p_desde AND p_hasta
    ), rango AS (
        SELECT generate_series(MIN(f), MAX(f)) AS f FROM emitidos
    )
    SELECT r.f::int,
           (SELECT MAX(e.f) FROM emitidos e WHERE e.f < r.f)::int,
           (SELECT MIN(e.f) FROM emitidos e WHERE e.f > r.f)::int,
           ((SELECT MIN(e.f) FROM emitidos e WHERE e.f > r.f)
            - (SELECT MAX(e.f) FROM emitidos e WHERE e.f < r.f) - 1)::int
      FROM rango r
     WHERE NOT EXISTS (SELECT 1 FROM emitidos e WHERE e.f = r.f)
     ORDER BY 1;
$f$;

GRANT EXECUTE ON FUNCTION public.fn_faena_folios_faltantes(uuid, date, date) TO authenticated;


-- ══════════════════════════════════════════════════════════════════════════
-- CONTROL 2 · LA DERIVA DEL CUENTALITROS
-- ══════════════════════════════════════════════════════════════════════════
-- Dos formas de medir el mismo combustible:
--   PARCIAL       lo que dice cada transacción (columna litros)
--   ACUMULATIVO   la resta entre el medidor final y el inicial de esa misma
--                 transacción
-- La diferencia son saltos del cuentalitros y redondeos de la fracción de
-- litro. Julio cerró en −0,101 %, dentro de lo aceptable — pero eso se supo el
-- 3 de agosto. Acá se sabe todos los días.

CREATE OR REPLACE VIEW public.v_faena_deriva_cuentalitros AS
SELECT d.faena_id,
       d.fecha,
       d.turno,
       d.camion_patente,
       count(*)::int                                   AS transacciones,
       SUM(d.litros)                                   AS litros_parcial,
       SUM(d.meter_final - d.meter_inicial)            AS litros_acumulativo,
       SUM(d.litros) - SUM(d.meter_final - d.meter_inicial) AS deriva_lt,
       ROUND(100.0 * (SUM(d.litros) - SUM(d.meter_final - d.meter_inicial))
             / NULLIF(SUM(d.litros), 0), 3)            AS deriva_pct
  FROM combustible_faena_despachos d
 WHERE NOT d.anulado
   AND d.meter_inicial IS NOT NULL AND d.meter_final IS NOT NULL
 GROUP BY d.faena_id, d.fecha, d.turno, d.camion_patente;

GRANT SELECT ON public.v_faena_deriva_cuentalitros TO authenticated;

COMMENT ON VIEW public.v_faena_deriva_cuentalitros IS
  'Contador parcial contra acumulativo, por dia y camion. El calculo que el informe mensual hace a mano una vez al mes. MIG363.';


-- ══════════════════════════════════════════════════════════════════════════
-- CONTROL 3 · EL BALANCE DEL PERIODO
-- ══════════════════════════════════════════════════════════════════════════
-- Es la tabla que cierra el informe de gestión: stock inicial, cargas, ventas,
-- stock teórico y stock físico, con la diferencia entre los dos últimos. El de
-- julio se armó a mano y terminó con +366 L de ajustes sin respaldo.

CREATE OR REPLACE FUNCTION public.fn_faena_balance_periodo(
    p_faena_id uuid, p_desde date, p_hasta date
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
DECLARE
    v_ini    NUMERIC;
    v_cargas NUMERIC;
    v_ventas NUMERIC;
    v_tras   NUMERIC;
    v_otros  NUMERIC;
    v_fis    NUMERIC;
    v_teo    NUMERIC;
BEGIN
    -- El stock inicial es el físico que dejó firmado la entrega anterior. Si no
    -- hay ninguna, no se inventa: queda nulo y el balance lo dice.
    SELECT e.stock_fisico_lt INTO v_ini
      FROM faena_entrega_turno e
     WHERE e.faena_id = p_faena_id AND e.hasta < p_desde
       AND e.conteo_fisico_hecho AND e.stock_fisico_lt IS NOT NULL
     ORDER BY e.hasta DESC LIMIT 1;

    SELECT COALESCE(SUM(r.litros_guia), 0) INTO v_cargas
      FROM combustible_faena_recepcion r
     WHERE r.faena_id = p_faena_id AND NOT r.anulada
       AND r.fecha BETWEEN p_desde AND p_hasta;

    SELECT COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta'), 0),
           COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije'), 0),
           COALESCE(SUM(d.litros) FILTER (WHERE d.tipo_movimiento IN ('recirculacion','calibracion')), 0)
      INTO v_ventas, v_tras, v_otros
      FROM combustible_faena_despachos d
     WHERE d.faena_id = p_faena_id AND NOT d.anulado
       AND d.fecha BETWEEN p_desde AND p_hasta;

    -- El trasvasije entre camiones del propio servicio no sale del inventario:
    -- cambia de estanque, no de dueño. Contarlo como salida es el error que el
    -- instructivo de Romeral pone como Ejemplo 1.
    v_teo := COALESCE(v_ini, 0) + v_cargas - v_ventas;

    SELECT e.stock_fisico_lt INTO v_fis
      FROM faena_entrega_turno e
     WHERE e.faena_id = p_faena_id AND e.hasta BETWEEN p_desde AND p_hasta
       AND e.conteo_fisico_hecho AND e.stock_fisico_lt IS NOT NULL
     ORDER BY e.hasta DESC LIMIT 1;

    RETURN jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta,
      'stock_inicial', v_ini,
      'stock_inicial_verificado', v_ini IS NOT NULL,
      'cargas', v_cargas,
      'ventas', v_ventas,
      'trasvasijes', v_tras,
      'recirculacion_calibracion', v_otros,
      'stock_teorico', v_teo,
      'stock_fisico', v_fis,
      'stock_fisico_verificado', v_fis IS NOT NULL,
      'diferencia', CASE WHEN v_fis IS NOT NULL THEN v_fis - v_teo END,
      'diferencia_pct', CASE WHEN v_fis IS NOT NULL AND v_ventas > 0
                            THEN ROUND(100.0 * (v_fis - v_teo) / v_ventas, 3) END,
      'transacciones', (SELECT count(*) FROM combustible_faena_despachos d
                         WHERE d.faena_id = p_faena_id AND NOT d.anulado
                           AND d.fecha BETWEEN p_desde AND p_hasta),
      'folios', (SELECT jsonb_build_object(
                          'desde', MIN(folio_ticket), 'hasta', MAX(folio_ticket),
                          'emitidos', count(folio_ticket),
                          'faltantes', (SELECT count(*) FROM fn_faena_folios_faltantes(p_faena_id, p_desde, p_hasta)))
                   FROM combustible_faena_despachos d
                  WHERE d.faena_id = p_faena_id AND NOT d.anulado
                    AND d.fecha BETWEEN p_desde AND p_hasta),
      'ventas_por_ceco', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('ceco', c.codigo, 'empresa', c.empresa, 'litros', s.lt)
                         ORDER BY s.lt DESC)
          FROM (SELECT d.ceco_id, SUM(d.litros) AS lt
                  FROM combustible_faena_despachos d
                 WHERE d.faena_id = p_faena_id AND NOT d.anulado
                   AND d.tipo_movimiento = 'venta'
                   AND d.fecha BETWEEN p_desde AND p_hasta
                 GROUP BY d.ceco_id) s
          LEFT JOIN combustible_faena_cecos c ON c.id = s.ceco_id), '[]'::jsonb));
END;
$f$;

GRANT EXECUTE ON FUNCTION public.fn_faena_balance_periodo(uuid, date, date) TO authenticated;

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT fn_faena_balance_periodo(
--          (SELECT id FROM faenas WHERE codigo='FAE-FRANCKE'),
--          DATE '2026-08-01', DATE '2026-08-31');
