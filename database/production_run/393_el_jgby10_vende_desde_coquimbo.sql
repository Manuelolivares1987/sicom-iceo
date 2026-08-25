-- ============================================================================
-- MIG393 · El JGBY-10 vende desde Coquimbo, y el filtro deja de mirar el nombre
-- ----------------------------------------------------------------------------
-- QUÉ SE ROMPIÓ
-- Las ventas a Tololo/AURA de agosto no aparecían en ninguna pantalla. Estaban
-- en el kardex, bien registradas:
--
--   10-ago  SCB-202608-00244  Tololo  14.965 L  (recibe Marco Nuñez)
--   19-ago  SCB-202608-00274  Ecomac   2.000 L  (recibe Jorge Castro)
--   24-ago  SCB-202608-00281  Tololo  15.000 L  (recibe Jorge Castro)
--
-- Las tres salieron del estanque CAM-JGBY10. Y todas las pantallas de Coquimbo
-- excluían los camiones con el filtro `estanque_codigo NOT LIKE 'CAM-%'`.
--
-- POR QUÉ EXISTÍA ESE FILTRO
-- MIG366 tuvo que sacar del consolidado de Coquimbo el combustible que se rinde
-- en faena: las estaciones de Romeral y los camiones de Franke se rinden en el
-- cierre de su faena, con otro documento y a otro mandante. La forma rápida de
-- decir «camión de faena» fue el prefijo del código.
--
-- POR QUÉ ESTABA MAL
-- El prefijo del código no es el dato: es cómo se llama el estanque. El JGBY-10
-- quedó marcado `operacion = 'Franke'` por herencia, pero nunca operó en Franke
-- —0 cargas de camión, 0 despachos de faena, `faena_id` nulo—. Su historia
-- completa son compras y ventas externas desde Coquimbo. El camión está
-- arrendado a AURA en Cerro Tololo (activo CC-15-13, patente JGBY-10).
--
-- Resultado: la venta caía en tierra de nadie. Coquimbo la filtraba por el
-- prefijo, y la sección Franke listaba el camión pero ahí no había nada que
-- cuadrar.
--
-- QUÉ SE HACE
--   1. El JGBY-10 sale de la operación Franke. Vuelve a ser un estanque móvil
--      de la bodega de Coquimbo.
--   2. La regla «esto es de Coquimbo» deja de vivir repetida en 11 filtros de
--      frontend y pasa a ser una columna calculada: sin faena y sin operación.
--      Cuando mañana entre otro camión, la regla lo clasifica sola.
--
-- LO QUE NO CAMBIA
-- Romeral (todos con faena_id) y los tres camiones de Franke (HHWB-42, HHWB-44,
-- LCSX-78, todos con faena_id) siguen fuera de Coquimbo exactamente igual que
-- hoy. El KVWD-27 sigue marcado Franke: está inactivo, tiene 0 movimientos y esa
-- decisión no es de esta migración.
-- ============================================================================

BEGIN;

-- ── 1. La regla, en un solo lugar ─────────────────────────────────────────
-- Un estanque es de la bodega de Coquimbo cuando no pertenece a una faena ni a
-- una operación en terreno. Generada y almacenada: no se puede desincronizar
-- de los datos que la definen.
ALTER TABLE public.combustible_estanques
  ADD COLUMN IF NOT EXISTS es_bodega BOOLEAN
  GENERATED ALWAYS AS (faena_id IS NULL AND operacion IS NULL) STORED;

COMMENT ON COLUMN public.combustible_estanques.es_bodega IS
  'MIG393: TRUE si el estanque es de la bodega de Coquimbo (sin faena y sin operacion en terreno). Reemplaza el filtro por prefijo de codigo NOT LIKE CAM-%, que escondia el CAM-JGBY10 —un camion de venta de Coquimbo— junto con los camiones de Franke.';

-- ── 2. El JGBY-10 sale de Franke ──────────────────────────────────────────
UPDATE public.combustible_estanques
   SET operacion = NULL,
       observaciones = COALESCE(observaciones || ' | ', '')
                     || 'MIG393 (2026-08-25): sale de la operación Franke. Nunca operó allá '
                     || '(0 cargas de camión, 0 despachos de faena, sin faena_id): es el camión '
                     || 'de venta de Coquimbo, arrendado a AURA en Cerro Tololo. Estaba marcado '
                     || 'Franke por herencia y eso escondía sus ventas de todas las pantallas.',
       updated_at = NOW()
 WHERE codigo = 'CAM-JGBY10'
   AND operacion IS NOT NULL;

-- ── 3. Las vistas publican la regla ───────────────────────────────────────
-- Se agrega la columna al final de cada vista: CREATE OR REPLACE exige que las
-- columnas existentes conserven nombre, tipo y orden.

-- 3.1 Control de estanques (kardex vs varillaje)
CREATE OR REPLACE VIEW public.v_combustible_control_kardex_varillaje AS
 WITH ultima_varilla AS (
         SELECT DISTINCT ON (v.estanque_id) v.estanque_id,
            v.fecha AS varilla_fecha,
            v.medicion_fisica_lt AS varilla_fisico_lt,
            v.stock_teorico_snapshot_lt,
            v.diferencia_lt,
            v.observaciones AS varilla_observaciones
           FROM combustible_varillaje v
          ORDER BY v.estanque_id, v.fecha DESC, v.created_at DESC
        ), ultimo_kardex AS (
         SELECT DISTINCT ON (k.estanque_id) k.estanque_id,
            k.fecha_movimiento AS kardex_fecha,
            k.tipo_movimiento AS kardex_tipo,
            k.stock_lt_despues AS kardex_stock_lt,
            k.costo_promedio_lt_despues AS kardex_cpp,
            k.valor_stock_despues AS kardex_valor
           FROM combustible_kardex_valorizado k
          ORDER BY k.estanque_id, k.fecha_movimiento DESC, k.created_at DESC
        )
 SELECT e.id AS estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    e.activo,
    e.faena_id,
    e.capacidad_lt,
    e.stock_teorico_lt,
    e.costo_promedio_lt AS cpp_actual,
    e.valor_total_stock AS valor_teorico_clp,
    uv.varilla_fecha AS fecha_ultimo_varillaje,
    uv.varilla_fisico_lt AS ultimo_varillaje_lt,
    uk.kardex_fecha AS fecha_ultimo_movimiento,
    uk.kardex_tipo AS tipo_ultimo_movimiento,
        CASE
            WHEN uv.varilla_fisico_lt IS NOT NULL THEN round(uv.varilla_fisico_lt - e.stock_teorico_lt, 2)
            ELSE NULL::numeric
        END AS delta_lt,
        CASE
            WHEN uv.varilla_fisico_lt IS NOT NULL AND e.stock_teorico_lt > 0::numeric THEN round((uv.varilla_fisico_lt - e.stock_teorico_lt) / e.stock_teorico_lt * 100::numeric, 2)
            ELSE NULL::numeric
        END AS delta_pct,
        CASE
            WHEN uv.varilla_fecha IS NOT NULL THEN CURRENT_DATE - uv.varilla_fecha
            ELSE NULL::integer
        END AS dias_desde_varilla,
        CASE
            WHEN e.stock_teorico_lt < 0::numeric THEN 'stock_negativo'::text
            WHEN uv.varilla_fecha IS NULL THEN 'sin_varillaje'::text
            WHEN (CURRENT_DATE - uv.varilla_fecha) > 7 THEN 'varillaje_atrasado'::text
            WHEN uv.varilla_fisico_lt IS NOT NULL AND abs(uv.varilla_fisico_lt - e.stock_teorico_lt) > 50::numeric THEN 'desviacion_fisica'::text
            ELSE 'cuadrado'::text
        END AS estado,
    e.stock_minimo_alerta_lt,
    e.stock_teorico_lt <= e.stock_minimo_alerta_lt AS bajo_minimo,
    e.operacion,
    e.es_bodega
   FROM combustible_estanques e
     LEFT JOIN ultima_varilla uv ON uv.estanque_id = e.id
     LEFT JOIN ultimo_kardex uk ON uk.estanque_id = e.id
  ORDER BY e.codigo;

-- 3.2 Movimientos valorizados (kardex de Coquimbo)
CREATE OR REPLACE VIEW public.v_combustible_movimientos_valorizados AS
 SELECT ckv.id AS kardex_id,
    ckv.fecha_movimiento,
    ckv.tipo_movimiento,
    ckv.folio_movimiento,
    ckv.estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    ckv.litros_entrada,
    ckv.litros_salida,
    ckv.costo_unitario_movimiento,
    ckv.stock_lt_despues,
    ckv.costo_promedio_lt_despues AS cpp_despues,
    ckv.valor_stock_despues,
    ckv.proveedor_id,
    pr.nombre AS proveedor_nombre,
    ckv.equipo_id,
    a.codigo AS equipo_codigo,
    a.nombre AS equipo_nombre,
    ckv.ceco_id,
    cc.codigo AS ceco_codigo,
    cc.nombre AS ceco_nombre,
    ckv.cliente_nombre_manual,
    ckv.documento_numero,
    ckv.observacion,
    ckv.evidencia_url,
    ckv.created_by,
    ckv.created_at,
    e.es_bodega AS estanque_es_bodega
   FROM combustible_kardex_valorizado ckv
     JOIN combustible_estanques e ON e.id = ckv.estanque_id
     LEFT JOIN proveedores pr ON pr.id = ckv.proveedor_id
     LEFT JOIN activos a ON a.id = ckv.equipo_id
     LEFT JOIN centros_costo cc ON cc.id = ckv.ceco_id;

-- 3.3 Movimientos hacia el cliente (portal + comercial). Conserva security_invoker.
CREATE OR REPLACE VIEW public.v_combustible_movimientos_cliente
WITH (security_invoker = true) AS
 SELECT m.id,
    m.tipo::text AS tipo,
    m.litros,
    m.lectura_inicial_lt,
    m.lectura_final_lt,
    m.costo_unitario_clp,
    m.costo_total_clp,
    fn_precio_venta_vigente(ve.empresa::text, cf.id, m.created_at) AS precio_venta_clp_lt,
    round(COALESCE(fn_precio_venta_vigente(ve.empresa::text, cf.id, m.created_at), 0::numeric) * m.litros, 2) AS total_venta_clp,
    m.created_at AS fecha,
    m.observaciones,
    e.nombre AS estanque_nombre,
    e.codigo AS estanque_codigo,
    m.destino_tipo::text AS destino_tipo,
    m.destino_descripcion,
    m.vehiculo_activo_id,
    af.codigo AS activo_codigo,
    af.patente AS activo_patente,
    cf.id AS activo_contrato_id,
    cf.codigo AS activo_contrato_codigo,
    cf.cliente AS activo_cliente,
    m.vehiculo_externo_id,
    ve.patente AS externo_patente,
    ve.empresa AS externo_empresa,
    m.foto_medidor_inicial_url,
    m.foto_medidor_final_url,
    m.foto_patente_url,
    m.nombre_receptor,
    m.rut_receptor,
    m.firma_receptor_url,
    m.horometro_vehiculo,
    m.kilometraje_vehiculo,
    NULL::text AS cliente_nombre_manual,
    NULL::text AS folio_movimiento,
    NULL::text AS documento_numero,
    e.es_bodega AS estanque_es_bodega
   FROM combustible_movimientos m
     LEFT JOIN combustible_estanques e ON e.id = m.estanque_id
     LEFT JOIN activos af ON af.id = m.vehiculo_activo_id
     LEFT JOIN contratos cf ON cf.id = af.contrato_id
     LEFT JOIN vehiculos_autorizados_externos ve ON ve.id = m.vehiculo_externo_id
  WHERE m.tipo = 'despacho'::tipo_movimiento_combustible_enum
UNION ALL
 SELECT k.id,
    'despacho'::text AS tipo,
    k.litros_salida AS litros,
    k.lectura_medidor_inicial_lt AS lectura_inicial_lt,
    k.lectura_medidor_final_lt AS lectura_final_lt,
    k.costo_unitario_movimiento AS costo_unitario_clp,
    k.valor_salida AS costo_total_clp,
    fn_precio_venta_vigente(COALESCE(ve2.empresa, k.cliente_nombre_manual)::text, cf2.id, k.fecha_movimiento) AS precio_venta_clp_lt,
    round(COALESCE(fn_precio_venta_vigente(COALESCE(ve2.empresa, k.cliente_nombre_manual)::text, cf2.id, k.fecha_movimiento), 0::numeric) * k.litros_salida, 2) AS total_venta_clp,
    k.fecha_movimiento AS fecha,
    k.observacion AS observaciones,
    e2.nombre AS estanque_nombre,
    e2.codigo AS estanque_codigo,
        CASE k.tipo_movimiento
            WHEN 'salida_venta'::text THEN 'venta_externa'::text
            WHEN 'salida_equipo'::text THEN 'equipo'::text
            WHEN 'salida_despacho'::text THEN 'despacho'::text
            WHEN 'salida_externa'::text THEN 'venta_externa'::text
            ELSE k.tipo_movimiento::text
        END AS destino_tipo,
    NULL::text AS destino_descripcion,
    k.equipo_id AS vehiculo_activo_id,
    af2.codigo AS activo_codigo,
    af2.patente AS activo_patente,
    cf2.id AS activo_contrato_id,
    cf2.codigo AS activo_contrato_codigo,
    cf2.cliente AS activo_cliente,
    k.vehiculo_externo_id,
    ve2.patente AS externo_patente,
    ve2.empresa AS externo_empresa,
    k.foto_medidor_inicial_url,
    k.foto_medidor_final_url,
    k.foto_patente_url,
    k.nombre_receptor,
    k.rut_receptor,
    k.firma_receptor_url,
    NULL::numeric AS horometro_vehiculo,
    NULL::numeric AS kilometraje_vehiculo,
    k.cliente_nombre_manual,
    k.folio_movimiento,
    k.documento_numero,
    e2.es_bodega AS estanque_es_bodega
   FROM combustible_kardex_valorizado k
     LEFT JOIN combustible_estanques e2 ON e2.id = k.estanque_id
     LEFT JOIN activos af2 ON af2.id = k.equipo_id
     LEFT JOIN contratos cf2 ON cf2.id = af2.contrato_id
     LEFT JOIN vehiculos_autorizados_externos ve2 ON ve2.id = k.vehiculo_externo_id
  WHERE k.tipo_movimiento::text = ANY (ARRAY['salida_venta'::character varying, 'salida_equipo'::character varying, 'salida_despacho'::character varying, 'salida_externa'::character varying]::text[]);

-- 3.4 Demanda externa (base de la proyección de stock)
CREATE OR REPLACE VIEW public.v_combustible_demanda_externa_resumen AS
 WITH ventanas AS (
         SELECT k.estanque_id,
            sum(
                CASE
                    WHEN k.fecha_movimiento >= (now() - '7 days'::interval) THEN k.litros_salida
                    ELSE 0::numeric
                END) AS litros_7d,
            count(*) FILTER (WHERE k.fecha_movimiento >= (now() - '7 days'::interval)) AS despachos_7d,
            sum(
                CASE
                    WHEN k.fecha_movimiento >= (now() - '30 days'::interval) THEN k.litros_salida
                    ELSE 0::numeric
                END) AS litros_30d,
            count(*) FILTER (WHERE k.fecha_movimiento >= (now() - '30 days'::interval)) AS despachos_30d,
            sum(
                CASE
                    WHEN k.fecha_movimiento::date = CURRENT_DATE THEN k.litros_salida
                    ELSE 0::numeric
                END) AS litros_hoy,
            count(*) FILTER (WHERE k.fecha_movimiento::date = CURRENT_DATE) AS despachos_hoy
           FROM combustible_kardex_valorizado k
          WHERE (k.tipo_movimiento::text = ANY (ARRAY['salida_venta'::text, 'salida_externa'::text])) AND k.litros_salida > 0::numeric
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
    round(COALESCE(v.litros_30d, 0::numeric) / 30.0, 1) AS promedio_diario_30d,
    e.es_bodega
   FROM combustible_estanques e
     LEFT JOIN ventanas v ON v.estanque_id = e.id
  WHERE e.activo = true AND e.faena_id IS NULL;

-- 3.5 Proyección de stock (arrastra la bandera)
CREATE OR REPLACE VIEW public.v_combustible_proyeccion_stock AS
 SELECT estanque_id,
    estanque_codigo,
    estanque_nombre,
    capacidad_lt,
    stock_actual,
    stock_minimo,
    litros_hoy,
    despachos_hoy,
    litros_ultimos_7d,
    despachos_ultimos_7d,
    litros_ultimos_30d,
    despachos_ultimos_30d,
    promedio_diario_7d,
    promedio_diario_30d,
        CASE
            WHEN promedio_diario_7d > 0::numeric THEN round(stock_actual / promedio_diario_7d, 1)
            WHEN promedio_diario_30d > 0::numeric THEN round(stock_actual / promedio_diario_30d, 1)
            ELSE NULL::numeric
        END AS dias_cobertura,
        CASE
            WHEN promedio_diario_7d > 0::numeric THEN CURRENT_DATE + (stock_actual / promedio_diario_7d)::integer
            WHEN promedio_diario_30d > 0::numeric THEN CURRENT_DATE + (stock_actual / promedio_diario_30d)::integer
            ELSE NULL::date
        END AS fecha_agotamiento_estimada,
        CASE
            WHEN promedio_diario_7d > 0::numeric AND stock_minimo > 0::numeric AND stock_actual > stock_minimo THEN round((stock_actual - stock_minimo) / promedio_diario_7d, 1)
            ELSE NULL::numeric
        END AS dias_hasta_minimo,
    COALESCE(promedio_diario_7d, promedio_diario_30d, 0::numeric) AS demanda_base_diaria,
        CASE
            WHEN promedio_diario_7d > 0::numeric THEN '7d'::text
            WHEN promedio_diario_30d > 0::numeric THEN '30d'::text
            ELSE 'sin_datos'::text
        END AS ventana_usada,
        CASE
            WHEN stock_actual <= 0::numeric THEN 'agotado'::text
            WHEN stock_actual <= stock_minimo THEN 'critico'::text
            WHEN promedio_diario_7d > 0::numeric AND (stock_actual / promedio_diario_7d) <= 3::numeric THEN 'urgente'::text
            WHEN promedio_diario_7d > 0::numeric AND (stock_actual / promedio_diario_7d) <= 7::numeric THEN 'atencion'::text
            ELSE 'ok'::text
        END AS severidad,
    es_bodega
   FROM v_combustible_demanda_externa_resumen r;

-- 3.6 Demanda externa diaria por empresa
CREATE OR REPLACE VIEW public.v_combustible_demanda_externa_diaria AS
 SELECT k.fecha_movimiento::date AS fecha,
    COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)'::character varying) AS empresa,
    k.estanque_id,
    e.codigo AS estanque_codigo,
    e.nombre AS estanque_nombre,
    count(*) AS despachos,
    sum(k.litros_salida) AS litros,
    e.es_bodega
   FROM combustible_kardex_valorizado k
     LEFT JOIN vehiculos_autorizados_externos ve ON ve.id = k.vehiculo_externo_id
     JOIN combustible_estanques e ON e.id = k.estanque_id
  WHERE (k.tipo_movimiento::text = ANY (ARRAY['salida_venta'::text, 'salida_externa'::text])) AND k.litros_salida > 0::numeric AND k.fecha_movimiento >= (now() - '90 days'::interval) AND e.faena_id IS NULL
  GROUP BY (k.fecha_movimiento::date), (COALESCE(ve.empresa, k.cliente_nombre_manual, '(sin empresa)'::character varying)), k.estanque_id, e.codigo, e.nombre, e.es_bodega;

-- ── 4. El informe de fiabilidad usa la misma regla ────────────────────────
-- El filtro por prefijo también vivía adentro del RPC. Se reescribe la función
-- desde su propia definición cambiando sólo esa línea: transcribir a mano las
-- 140 líneas del informe para tocar una es la forma segura de romper otra cosa.
DO $r$
DECLARE
    v_viejo CONSTANT TEXT := 'WHERE estanque_codigo NOT LIKE ''CAM-%''';
    v_nuevo  CONSTANT TEXT := 'WHERE es_bodega   -- MIG393: la bodega de Coquimbo, por operación y no por nombre';
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_reporte_fiabilidad_publico';

    IF v_def IS NULL THEN
        RAISE EXCEPTION 'MIG393: no existe fn_reporte_fiabilidad_publico';
    END IF;

    IF position(v_viejo IN v_def) = 0 THEN
        IF position('WHERE es_bodega' IN v_def) > 0 THEN
            RAISE NOTICE 'MIG393: el informe de fiabilidad ya filtra por es_bodega. Nada que hacer.';
            RETURN;
        END IF;
        RAISE EXCEPTION 'MIG393: fn_reporte_fiabilidad_publico cambió y no se encontró el filtro por prefijo. Revisar a mano el bloque de combustible.';
    END IF;

    EXECUTE replace(v_def, v_viejo, v_nuevo);
    RAISE NOTICE 'MIG393: informe de fiabilidad reescrito (filtro de combustible por es_bodega).';
END
$r$;

-- ── 5. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE v_bodega TEXT; v_fuera TEXT; v_lt NUMERIC; v_n INT;
BEGIN
    SELECT string_agg(codigo, ', ' ORDER BY codigo) INTO v_bodega
      FROM public.combustible_estanques WHERE es_bodega;
    SELECT string_agg(codigo, ', ' ORDER BY codigo) INTO v_fuera
      FROM public.combustible_estanques WHERE NOT es_bodega;
    RAISE NOTICE 'Bodega Coquimbo: %', v_bodega;
    RAISE NOTICE 'Fuera (faena u operación): %', v_fuera;

    IF NOT EXISTS (SELECT 1 FROM public.combustible_estanques
                    WHERE codigo = 'CAM-JGBY10' AND es_bodega) THEN
        RAISE EXCEPTION 'MIG393: el CAM-JGBY10 no quedó en la bodega de Coquimbo.';
    END IF;

    -- Las ventas de agosto que estaban escondidas.
    SELECT count(*), COALESCE(sum(litros), 0) INTO v_n, v_lt
      FROM public.v_combustible_movimientos_cliente
     WHERE estanque_es_bodega
       AND estanque_codigo = 'CAM-JGBY10'
       AND destino_tipo = 'venta_externa'
       AND fecha >= '2026-08-01' AND fecha < '2026-09-01';
    RAISE NOTICE 'Ventas del JGBY-10 visibles en agosto: % movimientos, % L', v_n, v_lt;

    IF v_n < 3 THEN
        RAISE WARNING 'Se esperaban 3 ventas del JGBY-10 en agosto (Tololo 14.965 + Ecomac 2.000 + Tololo 15.000). Aparecen %.', v_n;
    END IF;
END
$r$;

COMMIT;
