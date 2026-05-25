-- ============================================================================
-- 91_portal_cliente_incluir_salida_externa.sql
-- ----------------------------------------------------------------------------
-- BUG: la vista del portal cliente v_combustible_movimientos_cliente filtra el
-- kardex por tipo_movimiento IN ('salida_venta','salida_equipo','salida_despacho').
-- MIG77/78 introdujeron 'salida_externa' (despacho a vehiculo externo) pero NO
-- se agrego aqui -> los despachos a externos NO aparecen en el portal
-- (confirmado: 8 de hoy ocultos, 0 visibles).
--
-- Base: definicion vigente = MIG73 (agrega precio_venta_clp_lt y total_venta_clp).
-- FIX: agregar 'salida_externa' en (1) WHERE kardex, (2) CASE destino_tipo
-- (-> 'venta_externa'), (3) policy RLS. DROP+CREATE como MIG73. ADITIVO.
-- ============================================================================

DROP VIEW IF EXISTS v_combustible_movimientos_cliente CASCADE;

CREATE VIEW v_combustible_movimientos_cliente
WITH (security_invoker = true)
AS

-- (a) Movimientos legacy
SELECT
    m.id,
    m.tipo::text         AS tipo,
    m.litros,
    m.lectura_inicial_lt,
    m.lectura_final_lt,
    m.costo_unitario_clp,
    m.costo_total_clp,
    fn_precio_venta_vigente(ve.empresa, cf.id, m.created_at) AS precio_venta_clp_lt,
    ROUND(
        COALESCE(fn_precio_venta_vigente(ve.empresa, cf.id, m.created_at), 0)
        * m.litros, 2
    )                    AS total_venta_clp,
    m.created_at         AS fecha,
    m.observaciones,
    e.nombre             AS estanque_nombre,
    e.codigo             AS estanque_codigo,
    m.destino_tipo::text AS destino_tipo,
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

-- (b) Kardex valorizado
SELECT
    k.id,
    'despacho'::text                  AS tipo,
    k.litros_salida                   AS litros,
    k.lectura_medidor_inicial_lt      AS lectura_inicial_lt,
    k.lectura_medidor_final_lt        AS lectura_final_lt,
    k.costo_unitario_movimiento       AS costo_unitario_clp,
    k.valor_salida                    AS costo_total_clp,
    fn_precio_venta_vigente(ve2.empresa, cf2.id, k.fecha_movimiento) AS precio_venta_clp_lt,
    ROUND(
        COALESCE(fn_precio_venta_vigente(ve2.empresa, cf2.id, k.fecha_movimiento), 0)
        * k.litros_salida, 2
    )                                 AS total_venta_clp,
    k.fecha_movimiento                AS fecha,
    k.observacion                     AS observaciones,
    e2.nombre                         AS estanque_nombre,
    e2.codigo                         AS estanque_codigo,
    CASE k.tipo_movimiento
       WHEN 'salida_venta'    THEN 'venta_externa'
       WHEN 'salida_equipo'   THEN 'equipo'
       WHEN 'salida_despacho' THEN 'despacho'
       WHEN 'salida_externa'  THEN 'venta_externa'   -- <-- NUEVO (despacho a vehiculo externo)
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
 WHERE k.tipo_movimiento IN ('salida_venta','salida_equipo','salida_despacho','salida_externa')
;

GRANT SELECT ON v_combustible_movimientos_cliente TO authenticated;


-- ── Politica RLS: incluir 'salida_externa' ─────────────────────────────────
DROP POLICY IF EXISTS pol_kardex_valorizado_portal_cliente ON combustible_kardex_valorizado;
CREATE POLICY pol_kardex_valorizado_portal_cliente
    ON combustible_kardex_valorizado
    FOR SELECT
    TO authenticated
    USING (
        fn_user_rol() IS NOT NULL
        OR EXISTS (
            SELECT 1
              FROM cliente_portal_perfil cp
              LEFT JOIN activos a  ON a.id = combustible_kardex_valorizado.equipo_id
              LEFT JOIN vehiculos_autorizados_externos ve
                     ON ve.id = combustible_kardex_valorizado.vehiculo_externo_id
             WHERE cp.user_id = auth.uid()
               AND cp.activo = true
               AND combustible_kardex_valorizado.tipo_movimiento IN (
                   'salida_venta','salida_equipo','salida_despacho','salida_externa'
               )
               AND (
                    (a.contrato_id IS NOT NULL AND a.contrato_id = ANY(cp.contratos_ids))
                    OR (ve.empresa IS NOT NULL AND ve.empresa  = ANY(cp.empresas_externas))
               )
        )
    );

NOTIFY pgrst, 'reload schema';

SELECT
    count(*) FILTER (WHERE tipo_movimiento = 'salida_externa') AS externos_totales,
    count(*) FILTER (WHERE tipo_movimiento IN ('salida_venta','salida_equipo','salida_despacho','salida_externa')) AS visibles_portal
FROM combustible_kardex_valorizado;
