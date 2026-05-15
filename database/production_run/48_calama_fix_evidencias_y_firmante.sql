-- ============================================================================
-- 48_calama_fix_evidencias_y_firmante.sql
-- ----------------------------------------------------------------------------
-- 3 fixes que cierran las observaciones detectadas en D1_diagnostico:
--
-- FIX A: Bucket `calama-evidencias` quedo en public=false. El frontend usa
--        `getPublicUrl()` que solo funciona contra buckets publicos. Por eso
--        las 19 fotos en BD existen pero no se renderizan en el dashboard
--        (devuelven 400/403). Mismo patron que `calama-firmas` que ya esta
--        public=true desde el inicio.
--
-- FIX B: Trigger BEFORE INSERT en `calama_firmas_jornada` que autocompleta
--        `firmante_nombre` y `firmante_rut` desde `usuarios_perfil` cuando
--        viene `firmante_id` pero no nombre. Esto evita firmas operador con
--        nombre NULL (problema observado en BLOQUE_8).
--
-- FIX C: Backfill de las firmas ya insertadas con nombre NULL.
--
-- ADITIVA, IDEMPOTENTE. No toca migs anteriores. RPCs existentes (mig 30
-- aceptacion mandante, mig 33/43 finalizar jornada) NO requieren cambios:
-- el trigger BEFORE INSERT del FIX B aplica antes de cualquier insert,
-- venga del RPC del operador, del mandante o de un INSERT directo.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'calama-evidencias') THEN
        RAISE EXCEPTION 'STOP - bucket calama-evidencias no existe.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='calama_firmas_jornada') THEN
        RAISE EXCEPTION 'STOP - MIG29 no aplicada (falta calama_firmas_jornada).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='usuarios_perfil') THEN
        RAISE EXCEPTION 'STOP - usuarios_perfil no existe.';
    END IF;
END $$;


-- ============================================================================
-- FIX A: Hacer publico el bucket calama-evidencias
-- ============================================================================
UPDATE storage.buckets
   SET public = true
 WHERE id = 'calama-evidencias'
   AND public IS DISTINCT FROM true;

-- Verifica que quedo en true; si no, el resto de la migracion sigue corriendo
-- pero las fotos no se veran. Lanza un WARNING informativo.
DO $$
DECLARE
    v_public BOOLEAN;
BEGIN
    SELECT public INTO v_public FROM storage.buckets WHERE id = 'calama-evidencias';
    IF v_public IS NOT true THEN
        RAISE WARNING 'MIG48 FIX A: bucket calama-evidencias NO quedo en public=true (valor actual: %). Revisa permisos de service_role sobre storage.buckets.', v_public;
    ELSE
        RAISE NOTICE 'MIG48 FIX A: bucket calama-evidencias en public=true OK.';
    END IF;
END $$;


-- ============================================================================
-- FIX B: Trigger BEFORE INSERT que completa firmante_nombre / firmante_rut
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_calama_completar_firmante()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    -- Solo aplica cuando hay firmante_id (firma de usuario interno) y falta
    -- el nombre. Si quien firma es un mandante externo, el RPC ya pasa los
    -- datos explicitos y firmante_nombre viene con valor.
    IF NEW.firmante_id IS NOT NULL
       AND (NEW.firmante_nombre IS NULL OR length(trim(NEW.firmante_nombre)) = 0) THEN
        SELECT u.nombre_completo,
               COALESCE(NEW.firmante_rut, u.rut)
          INTO NEW.firmante_nombre, NEW.firmante_rut
          FROM usuarios_perfil u
         WHERE u.id = NEW.firmante_id;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_calama_firmas_completar_nombre ON calama_firmas_jornada;
CREATE TRIGGER trg_calama_firmas_completar_nombre
    BEFORE INSERT ON calama_firmas_jornada
    FOR EACH ROW
    EXECUTE FUNCTION fn_calama_completar_firmante();

COMMENT ON FUNCTION fn_calama_completar_firmante() IS
'MIG48 - Autocompleta firmante_nombre/firmante_rut desde usuarios_perfil cuando el INSERT viene con firmante_id pero sin nombre. Activado por trg_calama_firmas_completar_nombre BEFORE INSERT.';


-- ============================================================================
-- FIX C: Backfill firmas existentes con nombre NULL
-- ============================================================================
WITH backfill AS (
    UPDATE calama_firmas_jornada f
       SET firmante_nombre = u.nombre_completo,
           firmante_rut    = COALESCE(f.firmante_rut, u.rut)
      FROM usuarios_perfil u
     WHERE f.firmante_id = u.id
       AND (f.firmante_nombre IS NULL OR length(trim(f.firmante_nombre)) = 0)
    RETURNING f.id, f.firmante_tipo, f.firmante_nombre
)
SELECT 'MIG48 FIX C backfill: ' || COUNT(*) || ' firmas actualizadas' AS resultado
  FROM backfill;


-- ============================================================================
-- VALIDACION FINAL
-- ============================================================================
SELECT jsonb_build_object(
    'fix_a_bucket_publico',
        (SELECT public FROM storage.buckets WHERE id='calama-evidencias'),
    'fix_b_trigger_creado',
        EXISTS (SELECT 1 FROM pg_trigger
                 WHERE tgname='trg_calama_firmas_completar_nombre'
                   AND tgrelid='public.calama_firmas_jornada'::regclass),
    'fix_c_firmas_con_nombre_null_restantes',
        (SELECT COUNT(*) FROM calama_firmas_jornada
          WHERE firmante_id IS NOT NULL
            AND (firmante_nombre IS NULL OR length(trim(firmante_nombre)) = 0)),
    'firmas_totales',
        (SELECT COUNT(*) FROM calama_firmas_jornada),
    'firmas_con_nombre',
        (SELECT COUNT(*) FROM calama_firmas_jornada
          WHERE firmante_nombre IS NOT NULL AND length(trim(firmante_nombre)) > 0),
    'evidencias_totales',
        (SELECT COUNT(*) FROM calama_evidencias),
    'evidencias_sync_pending_error',
        (SELECT COUNT(*) FROM calama_evidencias
          WHERE sync_status NOT IN ('sincronizado'))
) AS resultado_validacion;

NOTIFY pgrst, 'reload schema';
