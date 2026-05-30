-- ============================================================================
-- 103_reconciliar_comercial_ficha_desde_matriz.sql
-- ----------------------------------------------------------------------------
-- Complemento de MIG100 (que alineo activos.estado operativo): ahora alinea
-- activos.estado_comercial desde el ultimo dia de la matriz de Confiabilidad,
-- aprovechando el PERIODO DE GRACIA de MIG102 (los gates de checklist no
-- bloquean hasta el 31-may). Cada fila se procesa con manejo de excepcion para
-- que un bloqueo legal (DS 298, > 15 anios en sustancias peligrosas) no aborte
-- el lote: esas filas se reportan como bloqueadas.
--
-- Mapeo codigo -> estado_comercial:
--   A,C -> arrendado ; D -> disponible ; U -> uso_interno ; L -> leasing ;
--   R -> en_recepcion ; V -> en_venta ; M,T,F,H -> SE MANTIENE (no redefine).
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_reconciliar_comercial_ficha_desde_matriz()
RETURNS TABLE(revisados integer, actualizados integer, bloqueados integer, detalle_bloqueados text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    r       RECORD;
    v_com   estado_comercial_enum;
    v_rev   INTEGER := 0;
    v_upd   INTEGER := 0;
    v_blk   INTEGER := 0;
    v_det   TEXT := '';
BEGIN
    FOR r IN
        SELECT a.id, a.patente, a.estado_comercial AS fic_com, u.cod
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
        v_com := CASE r.cod
                    WHEN 'A' THEN 'arrendado'
                    WHEN 'C' THEN 'arrendado'
                    WHEN 'D' THEN 'disponible'
                    WHEN 'U' THEN 'uso_interno'
                    WHEN 'L' THEN 'leasing'
                    WHEN 'R' THEN 'en_recepcion'
                    WHEN 'V' THEN 'en_venta'
                    ELSE NULL  -- M/T/F/H: no redefine comercial
                 END::estado_comercial_enum;

        IF v_com IS NOT NULL AND v_com IS DISTINCT FROM r.fic_com THEN
            BEGIN
                UPDATE activos
                   SET estado_comercial = v_com, updated_at = NOW()
                 WHERE id = r.id;
                v_upd := v_upd + 1;
            EXCEPTION WHEN OTHERS THEN
                v_blk := v_blk + 1;
                v_det := v_det || COALESCE(r.patente, r.id::text) || ' (' || r.cod || '->' || v_com || '): ' || SQLERRM || ' | ';
            END;
        END IF;
    END LOOP;

    RETURN QUERY SELECT v_rev, v_upd, v_blk, NULLIF(v_det, '');
END;
$$;

COMMENT ON FUNCTION fn_reconciliar_comercial_ficha_desde_matriz IS
    'Alinea activos.estado_comercial desde el ultimo dia de la matriz (A/C->arrendado, D->disponible, etc). Pensada para el periodo de gracia (MIG102). Captura bloqueos DS298 por fila. MIG103.';

GRANT EXECUTE ON FUNCTION fn_reconciliar_comercial_ficha_desde_matriz TO authenticated;

-- Ejecucion inmediata:
SELECT * FROM fn_reconciliar_comercial_ficha_desde_matriz();

NOTIFY pgrst, 'reload schema';
