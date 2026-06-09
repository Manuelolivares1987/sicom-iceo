-- ============================================================================
-- SICOM-ICEO | 141 — Auto-generar No Conformidades al cerrar la inspección
-- ----------------------------------------------------------------------------
-- Cuando el grupo cierra la inspección de recepción (fn_cerrar_inspeccion_
-- recepcion pasa el informe a estado='borrador'), se generan automáticamente
-- las No Conformidades desde los ítems 'no_ok' del checklist (ya no es un botón
-- manual). El botón "Generar del checklist" sigue existiendo como respaldo
-- (es idempotente). Defensivo: nunca bloquea el cierre.
-- IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_trg_generar_nc_al_cerrar_recepcion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.estado = 'borrador' AND OLD.estado = 'en_inspeccion' THEN
        BEGIN
            PERFORM fn_generar_nc_desde_recepcion(NEW.id);
        EXCEPTION WHEN OTHERS THEN
            NULL;  -- nunca bloquear el cierre de la inspección
        END;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_generar_nc_al_cerrar_recepcion ON informes_recepcion;
CREATE TRIGGER trg_generar_nc_al_cerrar_recepcion
    AFTER UPDATE OF estado ON informes_recepcion
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_generar_nc_al_cerrar_recepcion();

SELECT (SELECT count(*) FROM pg_trigger WHERE tgname='trg_generar_nc_al_cerrar_recepcion') AS trigger_ok;
