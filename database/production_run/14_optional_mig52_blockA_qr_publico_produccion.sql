-- ============================================================================
-- 14_optional_mig52_blockA_qr_publico_produccion.sql  —  OPCIONAL.
-- ----------------------------------------------------------------------------
-- ⚠️ NO ejecutar salvo decisión expresa. Solo Block A de mig 52.
-- Bloques B/C/D requieren auditoría de seguridad dedicada (NO incluidos).
-- ----------------------------------------------------------------------------
-- Si se aplica, requiere ajustar el frontend:
--   - src/lib/services/activos.ts:137 → `rpc_ficha_activo_publica` en lugar de
--     `rpc_ficha_activo` para la ruta /equipo/[id].
-- ============================================================================


-- 1. Flag por activo
ALTER TABLE activos
    ADD COLUMN IF NOT EXISTS qr_publico_habilitado BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN activos.qr_publico_habilitado IS
    'Si TRUE, ficha publica /equipo/[id] muestra datos. Si FALSE, no aparece.';


-- 2. Vista publica
CREATE OR REPLACE VIEW public_activos_qr AS
SELECT
    a.id, a.codigo, a.nombre, a.tipo, a.numero_serie,
    a.criticidad, a.estado,
    a.kilometraje_actual, a.horas_uso_actual, a.ciclos_actual,
    a.anio_fabricacion, a.foto_url, a.qr_code,
    m.nombre AS modelo_nombre, mk.nombre AS marca_nombre
FROM activos a
LEFT JOIN modelos m ON m.id = a.modelo_id
LEFT JOIN marcas mk ON mk.id = m.marca_id
WHERE a.qr_publico_habilitado = true;

GRANT SELECT ON public_activos_qr TO anon, authenticated;


-- 3. RPC pública restringida a la vista
CREATE OR REPLACE FUNCTION rpc_ficha_activo_publica(p_activo_id UUID)
RETURNS public_activos_qr LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
    SELECT * FROM public_activos_qr WHERE id = p_activo_id;
$$;

GRANT EXECUTE ON FUNCTION rpc_ficha_activo_publica(UUID) TO anon, authenticated;


-- 4. (Opcional, MUY cuidadoso) Revocar la RPC privada de anon
-- Solo si el frontend YA fue actualizado para usar la version publica.
-- Comentado por defecto.

-- REVOKE EXECUTE ON FUNCTION rpc_ficha_activo(UUID) FROM anon;


-- Verificación
SELECT 'COL_QR_PUBLICO' AS check_name,
       (SELECT COUNT(*) FROM information_schema.columns
         WHERE table_name='activos' AND column_name='qr_publico_habilitado') AS existe;
SELECT 'VISTA_QR' AS check_name,
       (SELECT COUNT(*) FROM pg_views WHERE viewname='public_activos_qr') AS existe;
SELECT 'RPC_QR_PUBLICA' AS check_name,
       (SELECT COUNT(*) FROM pg_proc WHERE proname='rpc_ficha_activo_publica') AS existe;


-- Log
SELECT fn_log_operacion_migracion(
    'PROD_MIG52_BLOCK_A_QR',
    'Mig 52 Block A aplicada (vista publica QR).',
    'ok',
    'Frontend debe actualizarse: cambiar rpc_ficha_activo → rpc_ficha_activo_publica en /equipo/[id].'
);


-- ============================================================================
-- ROLLBACK
-- DROP FUNCTION rpc_ficha_activo_publica CASCADE;
-- DROP VIEW public_activos_qr;
-- ALTER TABLE activos DROP COLUMN qr_publico_habilitado;
-- ============================================================================
