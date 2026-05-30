-- ============================================================================
-- 100_reconciliar_estado_ficha_desde_matriz.sql
-- ----------------------------------------------------------------------------
-- PROBLEMA: el estado de un activo vive en DOS lugares que se desincronizan:
--   - estado_diario_flota (matriz de Confiabilidad, cargada desde Excel) = VERDAD
--   - activos.estado / activos.estado_comercial (ficha, la ven Flota/Mantencion)
-- La carga por Excel escribe solo la matriz; los contratos/recepcion escriben
-- solo la ficha. Resultado: ~24/55 vehiculos con activos.estado distinto al
-- ultimo dia de la matriz (ej. SVBJ-55: matriz=M, ficha=operativo).
--
-- FIX: funcion que reconcilia SOLO el estado OPERATIVO (activos.estado) desde
-- el ultimo dia de la matriz por activo. NO toca estado_comercial, que esta
-- protegido por reglas de negocio (trg_validar_arrendado_checklist requiere
-- checklist de entrega V02; trg_validar_cambio_disponible requiere verificacion
-- vigente). Forzar 'arrendado'/'disponible' por aqui violaria esos gates.
--
-- Mapeo codigo -> estado operativo (igual que rpc_actualizar_estado_diario_manual):
--   M, T, H -> en_mantenimiento ; F -> fuera_servicio ; resto -> operativo
--
-- Idempotente y reutilizable: correr despues de cada carga de Excel.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reconciliar_estado_ficha_desde_matriz()
RETURNS TABLE(revisados integer, actualizados integer)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r          RECORD;
    v_est      estado_activo_enum;
    v_rev      INTEGER := 0;
    v_upd      INTEGER := 0;
BEGIN
    FOR r IN
        SELECT a.id, a.estado AS fic_est, u.cod
        FROM activos a
        JOIN LATERAL (
            SELECT estado_codigo AS cod
            FROM estado_diario_flota e
            WHERE e.activo_id = a.id
            ORDER BY e.fecha DESC
            LIMIT 1
        ) u ON TRUE
        WHERE a.estado <> 'dado_baja'
    LOOP
        v_rev := v_rev + 1;
        v_est := CASE r.cod
                    WHEN 'M' THEN 'en_mantenimiento'
                    WHEN 'T' THEN 'en_mantenimiento'
                    WHEN 'H' THEN 'en_mantenimiento'
                    WHEN 'F' THEN 'fuera_servicio'
                    ELSE 'operativo'
                 END::estado_activo_enum;

        IF v_est IS DISTINCT FROM r.fic_est THEN
            -- Solo estado operativo; estado_comercial intacto (no dispara gates).
            UPDATE activos
               SET estado = v_est, updated_at = NOW()
             WHERE id = r.id;
            v_upd := v_upd + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_rev, v_upd;
END;
$$;

COMMENT ON FUNCTION fn_reconciliar_estado_ficha_desde_matriz IS
    'Reconcilia activos.estado (operativo/mantenimiento/fuera_servicio) desde el ultimo dia de estado_diario_flota. No toca estado_comercial (protegido por gates). Correr tras cada carga de Excel. MIG100.';

GRANT EXECUTE ON FUNCTION fn_reconciliar_estado_ficha_desde_matriz TO authenticated;

-- Ejecucion inmediata:
SELECT * FROM fn_reconciliar_estado_ficha_desde_matriz();

NOTIFY pgrst, 'reload schema';
