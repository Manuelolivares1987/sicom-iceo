-- ============================================================================
-- 74_corregir_patente_despacho.sql
-- ----------------------------------------------------------------------------
-- RPC para que un administrador corrija la patente/vehiculo de un despacho ya
-- registrado (caso tipico: bodeguero anoto el vehiculo equivocado).
--
-- Modifica equipo_id o vehiculo_externo_id (exactamente uno) en:
--   - combustible_kardex_valorizado (movimientos nuevos)
--   - combustible_movimientos       (movimientos legacy)
--
-- NO toca: litros, fecha, CPP, costo, fotos, firma. Solo el vinculo a vehiculo.
--
-- Auditoria: anexa a la observacion una linea
--   [CORRECCION PATENTE 2026-05-20 user@email] PATENTE_VIEJA -> PATENTE_NUEVA | motivo: ...
--
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_corregir_patente_despacho(
    p_id                       UUID,    -- id del despacho (puede ser kardex o movimientos)
    p_nuevo_equipo_id          UUID,    -- nuevo activo de flota propia (o NULL)
    p_nuevo_vehiculo_externo_id UUID,   -- nuevo vehiculo externo autorizado (o NULL)
    p_motivo                   TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id    UUID := auth.uid();
    v_user_email TEXT;
    v_rol        TEXT;
    v_origen     TEXT;  -- 'kardex' | 'movimientos'
    v_patente_vieja TEXT;
    v_patente_nueva TEXT;
    v_marca      TEXT;
    v_obs_anterior TEXT;
    v_obs_nueva  TEXT;
BEGIN
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Rol % no autorizado para corregir patente (solo administrador/subgerente)', v_rol;
    END IF;

    IF p_motivo IS NULL OR length(trim(p_motivo)) < 10 THEN
        RAISE EXCEPTION 'Motivo obligatorio (minimo 10 caracteres)';
    END IF;

    IF (p_nuevo_equipo_id IS NULL AND p_nuevo_vehiculo_externo_id IS NULL)
       OR (p_nuevo_equipo_id IS NOT NULL AND p_nuevo_vehiculo_externo_id IS NOT NULL) THEN
        RAISE EXCEPTION 'Debe especificar exactamente UNO: equipo_id o vehiculo_externo_id';
    END IF;

    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;

    -- Resolver patente NUEVA (para mensaje)
    IF p_nuevo_equipo_id IS NOT NULL THEN
        SELECT patente INTO v_patente_nueva FROM activos WHERE id = p_nuevo_equipo_id;
        IF v_patente_nueva IS NULL THEN
            RAISE EXCEPTION 'Activo % no existe en el maestro', p_nuevo_equipo_id;
        END IF;
    ELSE
        SELECT patente INTO v_patente_nueva FROM vehiculos_autorizados_externos
         WHERE id = p_nuevo_vehiculo_externo_id;
        IF v_patente_nueva IS NULL THEN
            RAISE EXCEPTION 'Vehiculo externo % no existe / no autorizado', p_nuevo_vehiculo_externo_id;
        END IF;
    END IF;

    -- Buscar en kardex_valorizado primero
    IF EXISTS (SELECT 1 FROM combustible_kardex_valorizado WHERE id = p_id) THEN
        v_origen := 'kardex';
        -- Resolver patente VIEJA
        SELECT COALESCE(
            (SELECT patente FROM activos WHERE id = k.equipo_id),
            (SELECT patente FROM vehiculos_autorizados_externos WHERE id = k.vehiculo_externo_id),
            '(sin patente)'
        )
          INTO v_patente_vieja
          FROM combustible_kardex_valorizado k
         WHERE k.id = p_id;

        SELECT observacion INTO v_obs_anterior
          FROM combustible_kardex_valorizado WHERE id = p_id;

        v_marca := format('[CORRECCION PATENTE %s %s] %s -> %s | motivo: %s',
            TO_CHAR(NOW(),'YYYY-MM-DD HH24:MI'),
            COALESCE(v_user_email, v_user_id::text),
            v_patente_vieja, v_patente_nueva, trim(p_motivo));
        v_obs_nueva := COALESCE(v_obs_anterior || E'\n', '') || v_marca;

        UPDATE combustible_kardex_valorizado
           SET equipo_id           = p_nuevo_equipo_id,
               vehiculo_externo_id = p_nuevo_vehiculo_externo_id,
               observacion         = v_obs_nueva
         WHERE id = p_id;

    -- Si no esta en kardex, buscar en movimientos legacy
    ELSIF EXISTS (SELECT 1 FROM combustible_movimientos WHERE id = p_id) THEN
        v_origen := 'movimientos';
        SELECT COALESCE(
            (SELECT patente FROM activos WHERE id = m.vehiculo_activo_id),
            (SELECT patente FROM vehiculos_autorizados_externos WHERE id = m.vehiculo_externo_id),
            '(sin patente)'
        )
          INTO v_patente_vieja
          FROM combustible_movimientos m
         WHERE m.id = p_id;

        SELECT observaciones INTO v_obs_anterior
          FROM combustible_movimientos WHERE id = p_id;

        v_marca := format('[CORRECCION PATENTE %s %s] %s -> %s | motivo: %s',
            TO_CHAR(NOW(),'YYYY-MM-DD HH24:MI'),
            COALESCE(v_user_email, v_user_id::text),
            v_patente_vieja, v_patente_nueva, trim(p_motivo));
        v_obs_nueva := COALESCE(v_obs_anterior || E'\n', '') || v_marca;

        UPDATE combustible_movimientos
           SET vehiculo_activo_id  = p_nuevo_equipo_id,
               vehiculo_externo_id = p_nuevo_vehiculo_externo_id,
               observaciones       = v_obs_nueva
         WHERE id = p_id;

    ELSE
        RAISE EXCEPTION 'No se encontro despacho con id % en kardex ni en movimientos', p_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'origen', v_origen,
        'kardex_id', p_id,
        'patente_anterior', v_patente_vieja,
        'patente_nueva',    v_patente_nueva,
        'usuario',          v_user_email
    );
END;
$$;

COMMENT ON FUNCTION rpc_admin_corregir_patente_despacho IS
'Cambia la patente/vehiculo de un despacho. Solo admin/subgerente. Detecta automaticamente si esta en kardex_valorizado o movimientos. Anexa marca de auditoria a observacion. MIG74.';


-- ============================================================================
-- VALIDACION
-- ============================================================================
SELECT jsonb_build_object(
    'rpc_creado', EXISTS(SELECT 1 FROM pg_proc
                          WHERE proname='rpc_admin_corregir_patente_despacho')
) AS resultado;

NOTIFY pgrst, 'reload schema';
