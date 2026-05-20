-- ============================================================================
-- 71_portal_cliente_union_kardex.sql
-- ----------------------------------------------------------------------------
-- FIX portal cliente: v_combustible_movimientos_cliente (MIG63) lee SOLO de
-- combustible_movimientos (tabla legacy del modulo de medidores). Pero el RPC
-- rpc_registrar_salida_combustible_valorizada (MIG64+) escribe en
-- combustible_kardex_valorizado. Resultado: las salidas/despachos hechos por
-- el bodeguero NO aparecen en el portal cliente.
--
-- Esta migracion:
--   1. Republica la vista con UNION ALL de ambas tablas, mapeando columnas.
--   2. Agrega politica RLS en combustible_kardex_valorizado para que los
--      usuarios portal puedan leer despachos a sus contratos o empresas
--      externas (mismo criterio que MIG63).
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Vista con UNION ALL + security_invoker=true ─────────────────────────
-- CRITICO: security_invoker=true hace que la vista APLIQUE las RLS de las
-- tablas base con el rol del que CONSULTA (no del owner). Sin esto, la vista
-- bypasea las policies y el portal cliente veria todos los despachos.
CREATE OR REPLACE VIEW v_combustible_movimientos_cliente
WITH (security_invoker = true)
AS

-- (a) Movimientos legacy (combustible_movimientos / pantalla /movimiento)
SELECT
    m.id,
    m.tipo,
    m.litros,
    m.lectura_inicial_lt,
    m.lectura_final_lt,
    m.costo_unitario_clp,
    m.costo_total_clp,
    m.created_at         AS fecha,
    m.observaciones,
    e.nombre             AS estanque_nombre,
    e.codigo             AS estanque_codigo,
    m.destino_tipo,
    m.destino_descripcion,
    m.vehiculo_activo_id,
    af.codigo            AS activo_codigo,
    af.patente           AS activo_patente,
    cf.id                AS activo_contrato_id,
    cf.codigo            AS activo_contrato_codigo,
    cf.cliente           AS activo_cliente,
    m.vehiculo_externo_id,
    ve.patente           AS externo_patente,
    ve.empresa           AS externo_empresa,
    m.foto_medidor_inicial_url,
    m.foto_medidor_final_url,
    m.foto_patente_url,
    m.nombre_receptor,
    m.rut_receptor,
    m.firma_receptor_url,
    m.horometro_vehiculo,
    m.kilometraje_vehiculo
  FROM combustible_movimientos m
  LEFT JOIN combustible_estanques e             ON e.id  = m.estanque_id
  LEFT JOIN activos af                          ON af.id = m.vehiculo_activo_id
  LEFT JOIN contratos cf                        ON cf.id = af.contrato_id
  LEFT JOIN vehiculos_autorizados_externos ve   ON ve.id = m.vehiculo_externo_id
 WHERE m.tipo = 'despacho'

UNION ALL

-- (b) Kardex valorizado (combustible_kardex_valorizado / pantalla /salida)
SELECT
    k.id,
    'despacho'::text                  AS tipo,
    k.litros_salida                   AS litros,
    k.lectura_medidor_inicial_lt      AS lectura_inicial_lt,
    k.lectura_medidor_final_lt        AS lectura_final_lt,
    k.costo_unitario_movimiento       AS costo_unitario_clp,
    k.valor_salida                    AS costo_total_clp,
    k.fecha_movimiento                AS fecha,
    k.observacion                     AS observaciones,
    e2.nombre                         AS estanque_nombre,
    e2.codigo                         AS estanque_codigo,
    -- destino_tipo se reconstruye desde tipo_movimiento (compat con UI portal)
    CASE k.tipo_movimiento
       WHEN 'salida_venta'    THEN 'venta_externa'
       WHEN 'salida_equipo'   THEN 'equipo'
       WHEN 'salida_despacho' THEN 'despacho'
       ELSE k.tipo_movimiento::text
    END                               AS destino_tipo,
    NULL::text                        AS destino_descripcion,
    k.equipo_id                       AS vehiculo_activo_id,
    af2.codigo                        AS activo_codigo,
    af2.patente                       AS activo_patente,
    cf2.id                            AS activo_contrato_id,
    cf2.codigo                        AS activo_contrato_codigo,
    cf2.cliente                       AS activo_cliente,
    k.vehiculo_externo_id,
    ve2.patente                       AS externo_patente,
    ve2.empresa                       AS externo_empresa,
    k.foto_medidor_inicial_url,
    k.foto_medidor_final_url,
    k.foto_patente_url,
    k.nombre_receptor,
    k.rut_receptor,
    k.firma_receptor_url,
    NULL::numeric                     AS horometro_vehiculo,
    NULL::numeric                     AS kilometraje_vehiculo
  FROM combustible_kardex_valorizado k
  LEFT JOIN combustible_estanques e2            ON e2.id  = k.estanque_id
  LEFT JOIN activos af2                         ON af2.id = k.equipo_id
  LEFT JOIN contratos cf2                       ON cf2.id = af2.contrato_id
  LEFT JOIN vehiculos_autorizados_externos ve2  ON ve2.id = k.vehiculo_externo_id
 WHERE k.tipo_movimiento IN ('salida_venta','salida_equipo','salida_despacho')
;

GRANT SELECT ON v_combustible_movimientos_cliente TO authenticated;


-- ── 2. RLS en combustible_kardex_valorizado para usuarios portal ───────────
ALTER TABLE combustible_kardex_valorizado ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_kardex_valorizado_portal_cliente ON combustible_kardex_valorizado;
CREATE POLICY pol_kardex_valorizado_portal_cliente
    ON combustible_kardex_valorizado
    FOR SELECT
    TO authenticated
    USING (
        -- Usuario interno con rol Pillado ve todo
        fn_user_rol() IS NOT NULL
        OR
        -- Usuario portal ve solo despachos que le corresponden
        EXISTS (
            SELECT 1
              FROM cliente_portal_perfil cp
              LEFT JOIN activos a  ON a.id = combustible_kardex_valorizado.equipo_id
              LEFT JOIN vehiculos_autorizados_externos ve
                     ON ve.id = combustible_kardex_valorizado.vehiculo_externo_id
             WHERE cp.user_id = auth.uid()
               AND cp.activo = true
               AND combustible_kardex_valorizado.tipo_movimiento IN (
                   'salida_venta','salida_equipo','salida_despacho'
               )
               AND (
                    (a.contrato_id IS NOT NULL AND a.contrato_id = ANY(cp.contratos_ids))
                    OR (ve.empresa IS NOT NULL AND ve.empresa  = ANY(cp.empresas_externas))
               )
        )
    );


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'vista_union', EXISTS(SELECT 1 FROM information_schema.views
                          WHERE table_name='v_combustible_movimientos_cliente'),
    'vista_security_invoker', (
        SELECT 'security_invoker=true' = ANY(c.reloptions)
          FROM pg_class c
         WHERE c.relname='v_combustible_movimientos_cliente'
    ),
    'rls_kardex', EXISTS(SELECT 1 FROM pg_policies
                         WHERE tablename='combustible_kardex_valorizado'
                           AND policyname='pol_kardex_valorizado_portal_cliente'),
    'n_filas_kardex_visibles_legacy_join',
        (SELECT COUNT(*) FROM combustible_kardex_valorizado
          WHERE tipo_movimiento IN ('salida_venta','salida_equipo','salida_despacho'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
