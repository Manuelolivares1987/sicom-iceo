-- ============================================================================
-- SICOM-ICEO | 180 — RPC para guardar lugar físico y operación del equipo
-- ============================================================================
-- Bug (2026-06-30, Sugerencias GPS → modal "Contrato"): al cambiar SOLO el lugar
-- físico (ubicacion_actual) y/o la operación (sin cambiar el estado del día), el
-- frontend hacía .update() DIRECTO sobre `activos`. RLS en `activos` solo tiene
-- política de escritura para 'administrador' (pol_admin_all_activos); el resto de
-- roles solo SELECT. Postgres entonces actualiza 0 filas SIN error → el cambio se
-- pierde en silencio ("no lo toma ni lo guarda ni nada").
--
-- El cambio de contrato (rpc_cambiar_contrato_activo) y el de estado
-- (rpc_actualizar_estado_manual, que ya escribe p_ubicacion) van por RPC
-- SECURITY DEFINER y por eso sí funcionan. La operación nunca tuvo RPC, y el
-- lugar solo se guardaba cuando además cambiaba el estado.
--
-- Fix: RPC SECURITY DEFINER que fija ubicacion_actual y/o operacion (cada una
-- con su flag "aplicar" para distinguir "no tocar" de "dejar en NULL"). Igual
-- que rpc_actualizar_estado_manual, exige solo usuario autenticado (paridad: si
-- puedes cambiar estado+lugar, puedes cambiar lugar/operación solos). La RLS de
-- `activos` queda intacta. El trigger de historial (MIG152) registra el cambio.
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_actualizar_atributos_activo(
    p_activo_id          UUID,
    p_aplicar_ubicacion  BOOLEAN DEFAULT false,
    p_ubicacion          TEXT    DEFAULT NULL,
    p_aplicar_operacion  BOOLEAN DEFAULT false,
    p_operacion          TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;
    IF NOT (p_aplicar_ubicacion OR p_aplicar_operacion) THEN
        RETURN jsonb_build_object('success', true, 'activo_id', p_activo_id, 'sin_cambios', true);
    END IF;

    UPDATE activos SET
        ubicacion_actual = CASE WHEN p_aplicar_ubicacion
                                THEN NULLIF(btrim(p_ubicacion), '') ELSE ubicacion_actual END,
        operacion        = CASE WHEN p_aplicar_operacion
                                THEN NULLIF(btrim(p_operacion), '')::varchar ELSE operacion END,
        updated_at = NOW()
     WHERE id = p_activo_id;

    RETURN jsonb_build_object(
        'success', true, 'activo_id', p_activo_id,
        'aplico_ubicacion', p_aplicar_ubicacion, 'aplico_operacion', p_aplicar_operacion
    );
END $$;

COMMENT ON FUNCTION rpc_actualizar_atributos_activo(UUID,BOOLEAN,TEXT,BOOLEAN,TEXT) IS
    'Fija lugar físico (ubicacion_actual) y/o operación del activo, sorteando la RLS admin-only de activos. MIG180.';

REVOKE ALL ON FUNCTION rpc_actualizar_atributos_activo(UUID,BOOLEAN,TEXT,BOOLEAN,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_actualizar_atributos_activo(UUID,BOOLEAN,TEXT,BOOLEAN,TEXT) TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'rpc_existe', EXISTS(SELECT 1 FROM pg_proc WHERE proname='rpc_actualizar_atributos_activo')
) AS resultado;

NOTIFY pgrst, 'reload schema';
