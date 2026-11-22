-- ============================================================================
-- MIG725 — Asignar código de barras a un producto desde el Scanner (22-11-2026)
-- ----------------------------------------------------------------------------
-- El Scanner de bodega se rehízo sobre la salida FIFO y el ingreso simple. Solo
-- 12 de 1.868 productos tienen código de barras, así que la primera vez que se
-- pistolea un código desconocido hay que poder decir «es este producto».
-- productos solo se puede modificar por administrador (RLS); esta función deja
-- hacerlo a los mismos roles que pueden ingresar mercadería (MIG566), solo para
-- el código de barras, y sin pisar un código que ya tiene otro producto.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_producto_asignar_codigo_barras(
    p_producto_id UUID,
    p_codigo      TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_rol  TEXT := fn_user_rol();
    v_cod  TEXT := NULLIF(btrim(p_codigo), '');
    v_prod RECORD;
    v_otro RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor',
                     'operador_abastecimiento','bodeguero') THEN
        RAISE EXCEPTION 'Sin permiso para asignar códigos de barras (rol: %)', v_rol;
    END IF;
    IF v_cod IS NULL THEN RAISE EXCEPTION 'Falta el código de barras'; END IF;
    IF length(v_cod) > 64 THEN RAISE EXCEPTION 'Código de barras demasiado largo'; END IF;

    SELECT id, codigo, nombre, codigo_barras INTO v_prod
      FROM productos WHERE id = p_producto_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe'; END IF;

    IF v_prod.codigo_barras = v_cod THEN
        RETURN jsonb_build_object('success', true, 'sin_cambios', true);
    END IF;

    SELECT id, codigo, nombre INTO v_otro
      FROM productos WHERE codigo_barras = v_cod AND id <> p_producto_id;
    IF FOUND THEN
        RAISE EXCEPTION 'El código % ya es de «%» (%)', v_cod, v_otro.nombre, v_otro.codigo
            USING ERRCODE = '23505';
    END IF;

    UPDATE productos SET codigo_barras = v_cod, updated_at = now() WHERE id = p_producto_id;

    RETURN jsonb_build_object('success', true, 'producto_id', p_producto_id,
                              'codigo_barras', v_cod, 'anterior', v_prod.codigo_barras);
END $$;

REVOKE ALL ON FUNCTION public.rpc_producto_asignar_codigo_barras(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_producto_asignar_codigo_barras(UUID, TEXT) TO authenticated;

-- Validación: la función existe y no la puede ejecutar anon.
SELECT p.proname,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_puede,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_puede
FROM pg_proc p WHERE p.proname = 'rpc_producto_asignar_codigo_barras';
