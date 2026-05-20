-- ============================================================================
-- 73_precios_venta_combustible.sql
-- ----------------------------------------------------------------------------
-- Precios de venta de combustible por empresa externa o contrato propio,
-- con historico de vigencias.
--
-- Modelo:
--   - Una fila por (empresa_externa O contrato_id, vigente_desde).
--   - vigente_hasta = NULL -> precio vigente actual.
--   - Cuando se setea un precio nuevo, el vigente anterior se cierra
--     (vigente_hasta = nuevo.vigente_desde - 1 microsegundo).
--   - Auditoria: created_by, created_at, observacion.
--
-- Funciones:
--   fn_precio_venta_vigente(empresa, contrato_id, fecha) -> NUMERIC
--     Retorna el precio_clp_lt aplicable a esa fecha (o NULL si no hay).
--
--   rpc_admin_set_precio_venta(...) -> JSONB
--     Setea un precio nuevo cerrando el anterior. Solo admin/subgerente/comercial.
--
-- Vista actualizada:
--   v_combustible_movimientos_cliente: agrega precio_venta_clp_lt y
--   total_venta_clp calculados por LEFT JOIN LATERAL con fn_precio_venta_vigente.
--
-- RLS:
--   precios_venta_combustible: solo internos (admin/subgerente/comercial)
--   pueden SELECT/INSERT/UPDATE/DELETE. Los usuarios portal NO consultan esta
--   tabla directamente, solo via la vista.
--
-- ADITIVA. IDEMPOTENTE.
-- ============================================================================

-- ── 1. Tabla precios_venta_combustible ────────────────────────────────────
CREATE TABLE IF NOT EXISTS precios_venta_combustible (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    empresa_externa TEXT,
    contrato_id     UUID REFERENCES contratos(id),
    precio_clp_lt   NUMERIC(14,4) NOT NULL CHECK (precio_clp_lt > 0),
    vigente_desde   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    vigente_hasta   TIMESTAMPTZ,
    moneda          TEXT NOT NULL DEFAULT 'CLP',
    observacion     TEXT,
    created_by      UUID REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_pvc_target_uno CHECK (
        (empresa_externa IS NOT NULL AND contrato_id IS NULL) OR
        (empresa_externa IS NULL     AND contrato_id IS NOT NULL)
    ),
    CONSTRAINT chk_pvc_vigencia CHECK (
        vigente_hasta IS NULL OR vigente_hasta > vigente_desde
    )
);

CREATE INDEX IF NOT EXISTS idx_pvc_empresa_vigente
    ON precios_venta_combustible (empresa_externa, vigente_desde DESC)
 WHERE empresa_externa IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pvc_contrato_vigente
    ON precios_venta_combustible (contrato_id, vigente_desde DESC)
 WHERE contrato_id IS NOT NULL;

COMMENT ON TABLE precios_venta_combustible IS
'Historial de precios de venta de combustible por empresa externa o contrato propio. MIG73.';


-- ── 2. fn_precio_venta_vigente: resuelve precio aplicable a fecha ─────────
CREATE OR REPLACE FUNCTION fn_precio_venta_vigente(
    p_empresa     TEXT,
    p_contrato_id UUID,
    p_fecha       TIMESTAMPTZ
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT precio_clp_lt
      FROM precios_venta_combustible
     WHERE (
              (p_empresa IS NOT NULL AND empresa_externa = p_empresa)
           OR (p_contrato_id IS NOT NULL AND contrato_id = p_contrato_id)
           )
       AND vigente_desde <= p_fecha
       AND (vigente_hasta IS NULL OR vigente_hasta > p_fecha)
     ORDER BY vigente_desde DESC
     LIMIT 1;
$$;

COMMENT ON FUNCTION fn_precio_venta_vigente IS
'Retorna el precio_clp_lt aplicable a (empresa o contrato) en la fecha indicada. NULL si no hay precio definido. MIG73.';


-- ── 3. RPC rpc_admin_set_precio_venta ─────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_admin_set_precio_venta(
    p_empresa       TEXT,            -- pasar NULL si es por contrato
    p_contrato_id   UUID,            -- pasar NULL si es por empresa
    p_precio_clp_lt NUMERIC,
    p_vigente_desde TIMESTAMPTZ DEFAULT NULL,  -- NULL => NOW()
    p_observacion   TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id      UUID := auth.uid();
    v_rol          TEXT;
    v_fecha        TIMESTAMPTZ;
    v_cerrado_id   UUID;
    v_nuevo_id     UUID;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','comercial') THEN
        RAISE EXCEPTION 'Rol % no autorizado para gestionar precios de venta', v_rol;
    END IF;

    IF (p_empresa IS NULL AND p_contrato_id IS NULL)
       OR (p_empresa IS NOT NULL AND p_contrato_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Debe especificar exactamente UNO de: empresa_externa o contrato_id.';
    END IF;
    IF p_precio_clp_lt IS NULL OR p_precio_clp_lt <= 0 THEN
        RAISE EXCEPTION 'precio_clp_lt debe ser > 0';
    END IF;

    v_fecha := COALESCE(p_vigente_desde, NOW());

    -- Cerrar precio vigente anterior (si existe)
    UPDATE precios_venta_combustible
       SET vigente_hasta = v_fecha
     WHERE vigente_hasta IS NULL
       AND (
            (p_empresa IS NOT NULL AND empresa_externa = p_empresa)
         OR (p_contrato_id IS NOT NULL AND contrato_id = p_contrato_id)
       )
    RETURNING id INTO v_cerrado_id;

    -- Insertar el nuevo
    v_nuevo_id := gen_random_uuid();
    INSERT INTO precios_venta_combustible (
        id, empresa_externa, contrato_id, precio_clp_lt,
        vigente_desde, vigente_hasta, observacion, created_by
    ) VALUES (
        v_nuevo_id, p_empresa, p_contrato_id, p_precio_clp_lt,
        v_fecha, NULL, p_observacion, v_user_id
    );

    RETURN jsonb_build_object(
        'success', true,
        'nuevo_id', v_nuevo_id,
        'cerrado_id', v_cerrado_id,
        'empresa', p_empresa,
        'contrato_id', p_contrato_id,
        'precio_clp_lt', p_precio_clp_lt,
        'vigente_desde', v_fecha
    );
END;
$$;

COMMENT ON FUNCTION rpc_admin_set_precio_venta IS
'Setea un nuevo precio de venta cerrando el vigente anterior. Solo admin/subgerente/comercial. MIG73.';


-- ── 4. Recrear vista v_combustible_movimientos_cliente con precio venta ───
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
    -- MIG73: precio de venta vigente al momento del despacho
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


-- ── 5. RLS en precios_venta_combustible: solo internos ───────────────────
ALTER TABLE precios_venta_combustible ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_pvc_interno_all ON precios_venta_combustible;
CREATE POLICY pol_pvc_interno_all
    ON precios_venta_combustible
    FOR ALL
    TO authenticated
    USING (fn_user_rol() IS NOT NULL)
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','comercial'));


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'tabla_creada', EXISTS(SELECT 1 FROM information_schema.tables
                           WHERE table_name='precios_venta_combustible'),
    'fn_vigente', EXISTS(SELECT 1 FROM pg_proc WHERE proname='fn_precio_venta_vigente'),
    'rpc_set', EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_admin_set_precio_venta'),
    'vista_tiene_precio', EXISTS(
        SELECT 1 FROM information_schema.columns
         WHERE table_name='v_combustible_movimientos_cliente'
           AND column_name='precio_venta_clp_lt'
    ),
    'rls_pvc', EXISTS(SELECT 1 FROM pg_policies
                      WHERE tablename='precios_venta_combustible'
                        AND policyname='pol_pvc_interno_all')
) AS resultado;

NOTIFY pgrst, 'reload schema';
