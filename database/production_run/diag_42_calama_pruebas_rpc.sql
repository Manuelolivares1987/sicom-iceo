-- ============================================================================
-- diag_42_calama_pruebas_rpc.sql
-- ----------------------------------------------------------------------------
-- Test directo de rpc_calama_crear_jornada_prueba_terreno desde SQL Editor.
-- En SQL Editor auth.uid() es NULL por defecto. Impostamos admin via
-- set_config('request.jwt.claim.sub') antes de invocar la RPC.
--
-- Usuarios reales conocidos (seed MIG23):
--   - supcalama@pillado.cl  b6160090-4d00-42f6-b50e-b4a811ab584a  (supervisor)
--   - oocc@pillado.cl       6ee0a371-d8d5-4617-83f7-7d4a28066f07  (colaborador)
--
-- Este script:
--   1. Recarga schema PostgREST (NOTIFY pgrst).
--   2. Impostar admin (busca uno con rol='administrador').
--   3. Llamar rpc_calama_crear_jornada_prueba_terreno.
--   4. Mostrar el resultado.
--   5. Verificar via v_calama_pruebas_terreno.
--
-- IDEMPOTENTE: cada corrida agrega una nueva OT TEST-TERRENO-<timestamp>.
-- ============================================================================

-- ── 1. Recargar schema PostgREST ──────────────────────────────────────────
-- Cuando se crean/modifican funciones o columnas, PostgREST a veces sirve
-- el schema viejo de cache. NOTIFY fuerza el reload.
NOTIFY pgrst, 'reload schema';


-- ── 2. Impostar admin ──────────────────────────────────────────────────────
-- Busca un admin activo en usuarios_perfil y setea el JWT claim.
DO $$
DECLARE v_admin_id UUID;
BEGIN
    SELECT id INTO v_admin_id FROM usuarios_perfil
     WHERE rol = 'administrador' AND activo = true LIMIT 1;
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'STOP - no hay admin activo en usuarios_perfil';
    END IF;
    -- is_local=false -> scope SESSION (no TRANSACCION). En Supabase SQL
    -- Editor, statements separados por ; pueden correr en transacciones
    -- distintas; con scope=true el siguiente SELECT pierde el claim y
    -- auth.uid() vuelve a NULL. Con false persiste hasta cerrar la pestania.
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, false);
    RAISE NOTICE 'Impostado admin %, auth.uid() = %', v_admin_id, auth.uid();
END $$;


-- ── 3. Crear jornada de prueba ─────────────────────────────────────────────
-- Si oocc@pillado.cl existe, lo usa como responsable. Sino default RPC.
WITH oocc AS (
    SELECT id::text FROM usuarios_perfil WHERE email = 'oocc@pillado.cl' LIMIT 1
)
SELECT rpc_calama_crear_jornada_prueba_terreno(
    jsonb_build_object(
        'responsable_id', (SELECT id FROM oocc),
        'fecha_jornada',  CURRENT_DATE::text
    )
) AS resultado;


-- ── 4. Verificar ultima prueba creada ──────────────────────────────────────
SELECT 'ultima_prueba_creada' AS dx,
       folio, titulo, ot_estado, estado_plan,
       responsable_email, fecha_programada,
       evidencias_count, eventos_count, firmas_count,
       motivo_prueba, planificacion_codigo, faena_nombre
FROM v_calama_pruebas_terreno
ORDER BY created_at DESC
LIMIT 1;


-- ── 5. Conteo global de pruebas ────────────────────────────────────────────
SELECT 'total_pruebas_terreno' AS dx,
       COUNT(*)::text          AS val
  FROM v_calama_pruebas_terreno;


-- ============================================================================
-- INTERPRETACION
-- ----------------------------------------------------------------------------
-- Si paso 3 devuelve JSON con success=true y ot_id/url_mobile -> RPC OK.
-- Si falla con "No autenticado" -> el set_config no funciono (raro,
--   reintentar o ejecutar el bloque DO $$ y la RPC en el MISMO statement).
-- Si falla con "Rol % no autorizado" -> el usuario admin tiene rol distinto;
--   ajustar la query del paso 2 o crear un admin.
-- Si falla con "No hay planificacion Calama disponible" -> crear una
--   planificacion Calama antes (vista importar Excel).
-- Si falla con "No hay responsable" -> crear oocc@pillado.cl o pasar
--   responsable_id explicito.
--
-- NOTA: este script usa set_config(..., is_local=false) -> SESSION scope.
-- Persiste durante toda la conexion (hasta cerrar la pestania SQL Editor).
-- Esto evita el problema de set_config(..., true) que es transaction-scoped
-- y se pierde entre statements si Supabase los corre en transacciones
-- separadas. Si necesitas correr otras pruebas en la misma pestania
-- bajo otro usuario, abre una pestania nueva o resetea con:
--   SELECT set_config('request.jwt.claim.sub', '', false);
-- ============================================================================
