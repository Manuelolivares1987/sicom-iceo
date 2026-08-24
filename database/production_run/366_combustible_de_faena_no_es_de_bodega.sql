-- ============================================================================
-- MIG366 · El combustible de faena es de la faena, no de la bodega de Coquimbo
-- ----------------------------------------------------------------------------
-- La bodega de Coquimbo tiene tres estanques y siempre tuvo tres: el principal
-- de 15.000, el secundario de 1.000 y el auxiliar de 600 litros. Eso es lo que
-- el Panel Bodega administra, lo que se valoriza al costo promedio del kardex y
-- lo que sale en el reporte que se envía por correo.
--
-- Con Romeral (MIG317) y Franke (MIG355) el maestro de estanques pasó a tener
-- doce más: cuatro estaciones fijas de Romeral, tres camiones cisterna de
-- Romeral y tres camiones de Franke. Todos entraron a las mismas vistas, porque
-- ninguna distinguía. Hoy el Panel Bodega suma:
--
--     bodega Coquimbo     3.328 L   ← lo que de verdad administra
--     faena Romeral     151.134 L   ← de CMP, en Huasco, con su propio cierre
--     faena Franke            0 L   ← de CM Cenizas, en Taltal
--
-- El reporte que se manda por correo lleva esa misma suma. Y no es un problema
-- de presentación: el combustible de faena no se compró con una orden de
-- compra de Coquimbo, no tiene costo promedio en ese kardex, y se le rinde a
-- otro mandante con otro documento. Mezclarlos hace que el stock de bodega
-- diga cuarenta y cinco veces más de lo que hay.
--
-- LA REGLA, EN UNA LÍNEA
--     Un estanque CON faena_id es de esa faena. SIN faena_id es de la bodega.
--
-- Se aplica en las vistas y no en cada pantalla, porque una regla repetida en
-- seis consultas es una regla que en la séptima se olvida. Las vistas de faena
-- (v_comb_faena_*) no se tocan: ésas ya filtran por faena y son las que le
-- rinden a cada mandante.
--
-- QUÉ SE ARREGLA, UNA POR UNA
--   v_combustible_estanques_resumen        el listado del Panel Bodega
--   v_combustible_stock_valorizado         el valor del stock
--   v_combustible_stock_valorizado_actual  ídem, versión corta
--   v_combustible_demanda_externa_resumen  de acá cuelga la proyección…
--   v_combustible_demanda_externa_diaria   …y el reporte que se envía por correo
--
-- Se agrega además una vista con el otro lado —lo que sí es de faena— para que
-- quien la necesite no tenga que volver a mezclar.
-- ============================================================================

BEGIN;

COMMENT ON COLUMN public.combustible_estanques.faena_id IS
  'La faena dueña del estanque. CON faena_id el combustible es de esa faena y se rinde en su propio cierre; SIN faena_id es de la bodega de Coquimbo y vive en el kardex valorizado. Las vistas de bodega filtran por esto. MIG366.';


-- ── 1. El listado del Panel Bodega ────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_combustible_estanques_resumen AS
SELECT e.id,
    e.codigo,
    e.nombre,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.stock_minimo_alerta_lt,
    e.faena_id,
    f.nombre AS faena_nombre,
    e.ubicacion_detalle,
    e.activo,
    round(e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0::numeric) * 100::numeric, 1) AS pct_llenado,
    e.stock_teorico_lt <= e.stock_minimo_alerta_lt AS bajo_minimo,
    (SELECT count(*) FROM combustible_medidores m
      WHERE m.estanque_id = e.id AND m.activo) AS n_medidores,
    (SELECT max(v.fecha) FROM combustible_varillaje v
      WHERE v.estanque_id = e.id) AS ultima_varillaje_fecha,
    (SELECT v.diferencia_lt FROM combustible_varillaje v
      WHERE v.estanque_id = e.id
      ORDER BY v.fecha DESC, v.created_at DESC LIMIT 1) AS ultima_varillaje_diferencia
   FROM combustible_estanques e
   LEFT JOIN faenas f ON f.id = e.faena_id
  WHERE e.faena_id IS NULL;   -- [MIG366] lo de faena, en faena

COMMENT ON VIEW public.v_combustible_estanques_resumen IS
  'Los estanques de la bodega de Coquimbo. Los de faena quedan fuera a proposito: se rinden en el cierre de su faena. MIG366.';


-- ── 2. El valor del stock ─────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.v_combustible_stock_valorizado AS
SELECT e.id AS estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    e.faena_id,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.stock_minimo_alerta_lt,
    e.costo_promedio_lt AS cpp_actual,
    e.valor_total_stock AS valor_total_clp,
    round(e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0::numeric) * 100::numeric, 1) AS pct_llenado,
    e.activo,
    e.updated_at
   FROM combustible_estanques e
  WHERE e.faena_id IS NULL;   -- El costo promedio sale del kardex de Coquimbo,
                              -- y el combustible de faena nunca pasó por él.

CREATE OR REPLACE VIEW public.v_combustible_stock_valorizado_actual AS
SELECT e.id AS estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.costo_promedio_lt,
    e.valor_total_stock,
    round(e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0::numeric) * 100::numeric, 1) AS pct_llenado
   FROM combustible_estanques e
  WHERE e.activo = true AND e.faena_id IS NULL
  ORDER BY e.codigo;


-- ── 3. La demanda y la proyección — de acá sale el correo ─────────────────
CREATE OR REPLACE VIEW public.v_combustible_demanda_externa_resumen AS
 WITH ventanas AS (
     SELECT k.estanque_id,
        sum(CASE WHEN k.fecha_movimiento >= (now() - '7 days'::interval)
                 THEN k.litros_salida ELSE 0::numeric END) AS litros_7d,
        count(*) FILTER (WHERE k.fecha_movimiento >= (now() - '7 days'::interval)) AS despachos_7d,
        sum(CASE WHEN k.fecha_movimiento >= (now() - '30 days'::interval)
                 THEN k.litros_salida ELSE 0::numeric END) AS litros_30d,
        count(*) FILTER (WHERE k.fecha_movimiento >= (now() - '30 days'::interval)) AS despachos_30d,
        sum(CASE WHEN k.fecha_movimiento::date = CURRENT_DATE
                 THEN k.litros_salida ELSE 0::numeric END) AS litros_hoy,
        count(*) FILTER (WHERE k.fecha_movimiento::date = CURRENT_DATE) AS despachos_hoy
       FROM combustible_kardex_valorizado k
      WHERE k.tipo_movimiento::text = ANY (ARRAY['salida_venta','salida_externa'])
        AND k.litros_salida > 0::numeric
      GROUP BY k.estanque_id
 )
 SELECT e.id AS estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    e.capacidad_lt,
    e.stock_teorico_lt AS stock_actual,
    e.stock_minimo_alerta_lt AS stock_minimo,
    COALESCE(v.litros_hoy, 0::numeric) AS litros_hoy,
    COALESCE(v.despachos_hoy, 0::bigint) AS despachos_hoy,
    COALESCE(v.litros_7d, 0::numeric) AS litros_ultimos_7d,
    COALESCE(v.despachos_7d, 0::bigint) AS despachos_ultimos_7d,
    COALESCE(v.litros_30d, 0::numeric) AS litros_ultimos_30d,
    COALESCE(v.despachos_30d, 0::bigint) AS despachos_ultimos_30d,
    round(COALESCE(v.litros_7d, 0::numeric) / 7.0, 1) AS promedio_diario_7d,
    round(COALESCE(v.litros_30d, 0::numeric) / 30.0, 1) AS promedio_diario_30d
   FROM combustible_estanques e
   LEFT JOIN ventanas v ON v.estanque_id = e.id
  WHERE e.activo = true AND e.faena_id IS NULL;

CREATE OR REPLACE VIEW public.v_combustible_demanda_externa_diaria AS
 SELECT k.fecha_movimiento::date AS fecha,
    COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)'::character varying) AS empresa,
    k.estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    count(*) AS despachos,
    sum(k.litros_salida) AS litros
   FROM combustible_kardex_valorizado k
   LEFT JOIN vehiculos_autorizados_externos ve ON ve.id = k.vehiculo_externo_id
   JOIN combustible_estanques e ON e.id = k.estanque_id
  WHERE k.tipo_movimiento::text = ANY (ARRAY['salida_venta','salida_externa'])
    AND k.litros_salida > 0::numeric
    AND k.fecha_movimiento >= (now() - '90 days'::interval)
    AND e.faena_id IS NULL
  GROUP BY (k.fecha_movimiento::date),
           COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)'::character varying),
           k.estanque_id, e.codigo, e.nombre;


-- ── 4. El otro lado, para quien lo necesite ───────────────────────────────
-- Que exista esta vista es lo que hace que la de bodega pueda filtrar sin
-- esconder nada: lo de faena no desaparece, cambia de lugar.
CREATE OR REPLACE VIEW public.v_combustible_estanques_faena AS
SELECT e.id, e.codigo, e.nombre, e.tipo, e.patente,
       e.faena_id, f.codigo AS faena_codigo, f.nombre AS faena_nombre,
       e.capacidad_lt, e.capacidad_llenado_lt, e.stock_teorico_lt,
       e.clave_cierre, e.orden_cierre, e.grupo_cuadre, e.activo,
       round(e.stock_teorico_lt / NULLIF(e.capacidad_lt, 0::numeric) * 100::numeric, 1) AS pct_llenado
  FROM combustible_estanques e
  JOIN faenas f ON f.id = e.faena_id
 WHERE e.faena_id IS NOT NULL;

GRANT SELECT ON public.v_combustible_estanques_faena TO authenticated;

COMMENT ON VIEW public.v_combustible_estanques_faena IS
  'Los estanques que pertenecen a una faena: estaciones fijas y camiones cisterna de Romeral y Franke. El complemento exacto de v_combustible_estanques_resumen. MIG366.';

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- Bodega tiene que dar 3 estanques y ~3.328 L; faena, 12.
-- SELECT 'bodega' AS donde, count(*), SUM(stock_teorico_lt)
--   FROM v_combustible_estanques_resumen WHERE activo
-- UNION ALL
-- SELECT 'faena', count(*), SUM(stock_teorico_lt)
--   FROM v_combustible_estanques_faena WHERE activo;
