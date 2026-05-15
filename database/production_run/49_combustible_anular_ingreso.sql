-- ============================================================================
-- 49_combustible_anular_ingreso.sql
-- ----------------------------------------------------------------------------
-- Permite corregir un ingreso de combustible mal cargado (precio o litros
-- erroneos). El RPC anula un movimiento tipo `ingreso_compra` del kardex
-- valorizado y revierte stock + CPP del estanque al estado previo.
--
-- REGLA CONTABLE: solo se puede anular si NO hay movimientos posteriores en
-- el mismo estanque. Si los hubo (salidas, otros ingresos, varillajes), el
-- RPC bloquea y obliga al usuario a hacer un asiento correctivo manual via
-- "ingreso compensatorio inverso + nuevo ingreso correcto".
--
-- ROL: solo administrador / subgerente_operaciones. No es operativo del
-- dia a dia — afecta valorizacion contable.
--
-- ADITIVA. NO toca migs anteriores. Solo agrega columnas opcionales al
-- kardex y 1 RPC nuevo.
-- ============================================================================

-- ── Precheck ───────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                    WHERE table_schema='public' AND table_name='combustible_kardex_valorizado') THEN
        RAISE EXCEPTION 'STOP - MIG57/40 no aplicada (falta combustible_kardex_valorizado).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_registrar_ingreso_combustible_valorizado') THEN
        RAISE EXCEPTION 'STOP - MIG40 no aplicada (falta rpc_registrar_ingreso_combustible_valorizado).';
    END IF;
END $$;


-- ============================================================================
-- 1. Columnas de anulacion en kardex valorizado
-- ============================================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public'
                      AND table_name='combustible_kardex_valorizado'
                      AND column_name='anulado_at') THEN
        ALTER TABLE combustible_kardex_valorizado ADD COLUMN anulado_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public'
                      AND table_name='combustible_kardex_valorizado'
                      AND column_name='anulado_by') THEN
        ALTER TABLE combustible_kardex_valorizado ADD COLUMN anulado_by UUID REFERENCES auth.users(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public'
                      AND table_name='combustible_kardex_valorizado'
                      AND column_name='motivo_anulacion') THEN
        ALTER TABLE combustible_kardex_valorizado ADD COLUMN motivo_anulacion TEXT;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ckv_anulados
    ON combustible_kardex_valorizado (estanque_id)
    WHERE anulado_at IS NOT NULL;


-- ============================================================================
-- 2. RPC: rpc_anular_ingreso_combustible(p_kardex_id, p_motivo)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_anular_ingreso_combustible(
    p_kardex_id UUID,
    p_motivo    TEXT
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_uid              UUID := auth.uid();
    v_rol              TEXT;
    v_kardex           combustible_kardex_valorizado%ROWTYPE;
    v_posteriores      INT;
    v_cpp_anterior     NUMERIC;
    v_stock_anterior   NUMERIC;
    v_valor_anterior   NUMERIC;
    v_now              TIMESTAMPTZ := NOW();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para anular ingreso de combustible (solo administrador / subgerente_operaciones)', v_rol;
    END IF;

    IF p_motivo IS NULL OR length(trim(p_motivo)) < 10 THEN
        RAISE EXCEPTION 'motivo obligatorio (minimo 10 caracteres)';
    END IF;

    -- Cargar y validar el movimiento
    SELECT * INTO v_kardex
      FROM combustible_kardex_valorizado
     WHERE id = p_kardex_id
     FOR UPDATE;
    IF v_kardex.id IS NULL THEN
        RAISE EXCEPTION 'Movimiento de kardex no encontrado: %', p_kardex_id;
    END IF;
    IF v_kardex.tipo_movimiento <> 'ingreso_compra' THEN
        RAISE EXCEPTION 'Solo se pueden anular movimientos tipo ingreso_compra. Este es: %', v_kardex.tipo_movimiento;
    END IF;
    IF v_kardex.anulado_at IS NOT NULL THEN
        RAISE EXCEPTION 'Este movimiento ya fue anulado el % por %', v_kardex.anulado_at, v_kardex.anulado_by;
    END IF;

    -- REGLA CONTABLE: bloquear si hay movimientos posteriores en el mismo estanque
    SELECT COUNT(*) INTO v_posteriores
      FROM combustible_kardex_valorizado
     WHERE estanque_id = v_kardex.estanque_id
       AND anulado_at IS NULL
       AND (
           fecha_movimiento > v_kardex.fecha_movimiento
        OR (fecha_movimiento = v_kardex.fecha_movimiento AND created_at > v_kardex.created_at)
       );
    IF v_posteriores > 0 THEN
        RAISE EXCEPTION 'No se puede anular: hay % movimiento(s) posterior(es) en este estanque. Haz asiento correctivo manual (ingreso inverso + nuevo ingreso correcto).', v_posteriores;
    END IF;

    -- Calcular estado anterior del estanque desde el movimiento previo
    SELECT stock_lt_despues, costo_promedio_lt_despues, valor_stock_despues
      INTO v_stock_anterior, v_cpp_anterior, v_valor_anterior
      FROM combustible_kardex_valorizado
     WHERE estanque_id = v_kardex.estanque_id
       AND anulado_at IS NULL
       AND (
           fecha_movimiento < v_kardex.fecha_movimiento
        OR (fecha_movimiento = v_kardex.fecha_movimiento AND created_at < v_kardex.created_at)
       )
     ORDER BY fecha_movimiento DESC, created_at DESC
     LIMIT 1;

    -- Si no hay movimiento anterior, el estanque estaba en 0
    IF v_stock_anterior IS NULL THEN
        v_stock_anterior := 0;
        v_cpp_anterior   := 0;
        v_valor_anterior := 0;
    END IF;

    -- Marcar kardex como anulado (NO se borra — auditoria preservada)
    UPDATE combustible_kardex_valorizado
       SET anulado_at        = v_now,
           anulado_by        = v_uid,
           motivo_anulacion  = trim(p_motivo)
     WHERE id = p_kardex_id;

    -- Revertir estado del estanque
    UPDATE combustible_estanques
       SET stock_teorico_lt  = v_stock_anterior,
           costo_promedio_lt = v_cpp_anterior,
           valor_total_stock = v_valor_anterior,
           updated_at        = v_now
     WHERE id = v_kardex.estanque_id;

    -- Si el ingreso original esta vinculado a ingresos_combustible, marcarlo
    -- (la tabla puede no tener columna 'anulado_at'; este UPDATE es best-effort).
    IF v_kardex.ingreso_combustible_id IS NOT NULL THEN
        BEGIN
            EXECUTE format(
                'UPDATE ingresos_combustible SET observacion = COALESCE(observacion, '''') || %L WHERE id = %L',
                ' [ANULADO MIG49 ' || v_now::text || ' motivo: ' || trim(p_motivo) || ']',
                v_kardex.ingreso_combustible_id
            );
        EXCEPTION WHEN OTHERS THEN
            NULL; -- ignorar si la tabla no acepta el UPDATE
        END;
    END IF;

    RETURN jsonb_build_object(
        'success',           true,
        'kardex_id',         p_kardex_id,
        'estanque_id',       v_kardex.estanque_id,
        'litros_revertidos', v_kardex.litros_entrada,
        'cpp_restaurado',    v_cpp_anterior,
        'stock_restaurado',  v_stock_anterior,
        'anulado_at',        v_now,
        'anulado_by',        v_uid
    );
END $$;

COMMENT ON FUNCTION rpc_anular_ingreso_combustible(UUID, TEXT) IS
'MIG49 - Anula un movimiento ingreso_compra del kardex valorizado y revierte stock + CPP del estanque. Bloquea si hay movimientos posteriores. Solo admin / subgerente_operaciones. Motivo minimo 10 chars.';

GRANT EXECUTE ON FUNCTION rpc_anular_ingreso_combustible(UUID, TEXT) TO authenticated;


-- ============================================================================
-- 3. Vista helper: ingresos anulables (para el frontend listar candidatos)
-- ============================================================================
CREATE OR REPLACE VIEW v_combustible_ingresos_anulables AS
SELECT
    k.id                                AS kardex_id,
    k.estanque_id,
    e.codigo                            AS estanque_codigo,
    e.nombre                            AS estanque_nombre,
    k.fecha_movimiento,
    k.folio_movimiento,
    k.litros_entrada                    AS litros,
    k.costo_unitario_movimiento         AS precio_unitario,
    (k.litros_entrada * k.costo_unitario_movimiento)::NUMERIC(16,2) AS valor_ingreso,
    k.proveedor_id,
    p.nombre                            AS proveedor_nombre,
    k.documento_numero,
    k.observacion,
    k.created_at,
    k.created_by,
    -- Flag: si hay posteriores, NO se puede anular (regla contable)
    EXISTS (
        SELECT 1 FROM combustible_kardex_valorizado k2
         WHERE k2.estanque_id = k.estanque_id
           AND k2.anulado_at IS NULL
           AND (
               k2.fecha_movimiento > k.fecha_movimiento
            OR (k2.fecha_movimiento = k.fecha_movimiento AND k2.created_at > k.created_at)
           )
    ) AS tiene_posteriores
  FROM combustible_kardex_valorizado k
  JOIN combustible_estanques e ON e.id = k.estanque_id
  LEFT JOIN proveedores p      ON p.id = k.proveedor_id
 WHERE k.tipo_movimiento = 'ingreso_compra'
   AND k.anulado_at IS NULL
 ORDER BY k.fecha_movimiento DESC, k.created_at DESC;

GRANT SELECT ON v_combustible_ingresos_anulables TO authenticated;

NOTIFY pgrst, 'reload schema';
