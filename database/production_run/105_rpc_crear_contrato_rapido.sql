-- ============================================================================
-- 105_rpc_crear_contrato_rapido.sql
-- ----------------------------------------------------------------------------
-- Permite crear un contrato "al vuelo" desde el flujo de cambio de estado
-- (cuando un equipo queda arrendado a una faena cuyo contrato aun no existe).
-- La tabla contratos solo permite INSERT al rol admin (RLS), por eso se expone
-- via RPC SECURITY DEFINER con chequeo de rol propio.
--
-- Minimo: codigo + cliente (nombre se autocompleta con el codigo si no viene).
-- estado='activo', moneda='CLP', fecha_inicio=hoy. Si el codigo ya existe,
-- devuelve ese contrato (ya_existia=true) en vez de fallar.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_crear_contrato_rapido(
    p_codigo  TEXT,
    p_cliente TEXT DEFAULT NULL,
    p_nombre  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_rol     TEXT;
    v_id      UUID;
    v_codigo  TEXT := upper(trim(p_codigo));
    v_existe  RECORD;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones','supervisor',
                     'planificador','comercial','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para crear contratos', v_rol;
    END IF;

    IF v_codigo IS NULL OR length(v_codigo) < 2 THEN
        RAISE EXCEPTION 'El código del contrato es obligatorio (mín 2 caracteres).';
    END IF;

    -- Si ya existe ese código, devolverlo (no duplicar)
    SELECT id, codigo, cliente INTO v_existe FROM contratos WHERE upper(codigo) = v_codigo LIMIT 1;
    IF FOUND THEN
        RETURN jsonb_build_object(
            'id', v_existe.id, 'codigo', v_existe.codigo,
            'cliente', v_existe.cliente, 'ya_existia', true
        );
    END IF;

    INSERT INTO contratos (codigo, nombre, cliente, estado, moneda, fecha_inicio, created_by)
    VALUES (
        v_codigo,
        COALESCE(NULLIF(trim(p_nombre), ''), v_codigo),
        NULLIF(trim(p_cliente), ''),
        'activo', 'CLP', CURRENT_DATE, v_user_id
    )
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'id', v_id, 'codigo', v_codigo,
        'cliente', NULLIF(trim(p_cliente), ''), 'ya_existia', false
    );
END;
$$;

COMMENT ON FUNCTION rpc_crear_contrato_rapido IS
    'Crea un contrato minimo (codigo + cliente) al vuelo desde el cambio de estado. SECURITY DEFINER con chequeo de rol. Si el codigo existe, lo devuelve. MIG105.';

GRANT EXECUTE ON FUNCTION rpc_crear_contrato_rapido TO authenticated;

NOTIFY pgrst, 'reload schema';
