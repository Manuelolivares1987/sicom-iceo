-- ============================================================================
-- 13_optional_mig52_blockA_qr_publico.sql  —  SOLO Block A de mig 52.
-- ----------------------------------------------------------------------------
-- Propósito: vista publica para /equipo/[id] sin exponer columnas sensibles.
-- NO incluye Block B/C/D (role-checks RPCs, RLS hardening masivo).
--
-- APLICAR SOLO si se va a habilitar el QR publico en terreno.
-- Si se aplica, requiere cambio en frontend para llamar `rpc_ficha_activo_publica`
-- en lugar de `rpc_ficha_activo` desde la ruta publica.
-- ============================================================================


-- ── 1. Flag por activo: habilitacion publica ─────────────────────────

ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS qr_publico_habilitado BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN activos.qr_publico_habilitado IS
    'Si TRUE, la ficha publica /equipo/[id] muestra datos del activo. Si FALSE, no aparece.';


-- ── 2. Vista publica solo con columnas seguras ───────────────────────

CREATE OR REPLACE VIEW public_activos_qr AS
SELECT
    a.id,
    a.codigo,
    a.nombre,
    a.tipo,
    a.numero_serie,
    a.criticidad,
    a.estado,
    a.kilometraje_actual,
    a.horas_uso_actual,
    a.ciclos_actual,
    a.anio_fabricacion,
    a.foto_url,
    a.qr_code,
    m.nombre AS modelo_nombre,
    mk.nombre AS marca_nombre
FROM activos a
LEFT JOIN modelos m ON m.id = a.modelo_id
LEFT JOIN marcas mk ON mk.id = m.marca_id
WHERE a.qr_publico_habilitado = true;

GRANT SELECT ON public_activos_qr TO anon, authenticated;


-- ── 3. RPC publica restringida a la vista ────────────────────────────

CREATE OR REPLACE FUNCTION rpc_ficha_activo_publica(p_activo_id UUID)
RETURNS public_activos_qr
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT * FROM public_activos_qr WHERE id = p_activo_id;
$$;

GRANT EXECUTE ON FUNCTION rpc_ficha_activo_publica(UUID) TO anon, authenticated;


-- ── 4. (Opcional) Revocar la RPC privada de anon ─────────────────────
-- IMPORTANTE: si se hace, debe ajustarse el frontend ANTES.
-- /equipo/[id] hoy llama `rpc_ficha_activo`. Cambiar a `rpc_ficha_activo_publica`.

-- REVOKE EXECUTE ON FUNCTION rpc_ficha_activo(UUID) FROM anon;


-- ============================================================================
-- VERIFICACION
-- ============================================================================

SELECT 'COL_QR_PUBLICO' AS check_name,
       column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'activos' AND column_name = 'qr_publico_habilitado';

SELECT 'VISTA_PUBLIC_QR' AS check_name, COUNT(*) AS existe
  FROM pg_views WHERE viewname = 'public_activos_qr';

SELECT 'RPC_FICHA_PUBLICA' AS check_name, COUNT(*) AS existe
  FROM pg_proc WHERE proname = 'rpc_ficha_activo_publica';


-- ============================================================================
-- INSTRUCCIONES PARA OPERADOR
-- ============================================================================
-- 1. Ejecutar este script en staging.
-- 2. Probar con anon key (sin login):
--    SELECT * FROM rpc_ficha_activo_publica('<UUID-DE-UN-ACTIVO>');
--    Deberia devolver fila SI qr_publico_habilitado = true, sino vacia.
-- 3. Ajustar el frontend (src/lib/services/activos.ts:137):
--    - Cambiar `supabase.rpc('rpc_ficha_activo', ...)` por
--      `supabase.rpc('rpc_ficha_activo_publica', ...)`.
-- 4. Habilitar activos para el QR publico:
--    UPDATE activos SET qr_publico_habilitado = true WHERE id IN (...);
-- 5. NO ejecutar Blocks B/C/D de mig 52 sin auditoria adicional.
-- ============================================================================
