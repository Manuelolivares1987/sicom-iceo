-- ============================================================================
-- SICOM-ICEO | 185 — Seguridad: cierre diario de flota (Fase 0 auditoría C1)
-- ----------------------------------------------------------------------------
-- Problema (validado en prod 2026-07-03):
--   * rpc_confirmar_cierre_diario (MIG106) es SECURITY DEFINER, NO valida
--     auth.uid() ni rol, y tiene GRANT EXECUTE a anon (además del EXECUTE
--     implícito a PUBLIC del default de Postgres). Cualquiera con la anon key
--     puede reescribir estado_comercial/contrato/cliente de toda la flota.
--   * fn_propuesta_cierre_diario también estaba abierta a anon.
--   * estado_diario_flota NO tenía RLS y anon conservaba grants de tabla
--     completos (INSERT/UPDATE/DELETE via PostgREST).
--
-- Fix:
--   1. fn_tiene_permiso_modulo(): autorización centralizada que respeta los
--      overrides configurables de MIG126 (rol_permisos_modulo) con fallback a
--      una lista default explícita. Primera pieza server-side de esa matriz.
--   2. rpc_confirmar_cierre_diario: exige sesión + permiso 'approve' del
--      módulo 'flota'; valida existencia del activo; SET search_path fijo;
--      tablas calificadas con esquema.
--   3. REVOKE a PUBLIC y anon en ambas funciones (GRANT solo authenticated).
--   4. estado_diario_flota: ENABLE RLS + policy de SELECT para authenticated
--      (mismo acceso efectivo que hoy para usuarios logueados; las escrituras
--      quedan solo vía funciones SECURITY DEFINER, cuyo owner ignora RLS) y
--      REVOKE total a anon.
--
-- Roles default para confirmar cierre (editable después desde Admin dando el
-- permiso 'approve' del módulo 'flota' a otro rol vía MIG126):
--   administrador, subgerente_operaciones, jefe_operaciones, supervisor.
--
-- IDEMPOTENTE. No modifica datos. Rollback: ver plan de despliegue Fase 0
-- (re-aplicar MIG106/107 restaura el comportamiento anterior).
-- ============================================================================

-- ── 1. Autorización centralizada (overrides MIG126 + fallback default) ──────
CREATE OR REPLACE FUNCTION public.fn_tiene_permiso_modulo(
    p_modulo        TEXT,
    p_accion        TEXT,
    p_roles_default TEXT[] DEFAULT '{}'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rol      TEXT;
    v_permisos TEXT[];
BEGIN
    -- Fail-closed: acción o módulo desconocidos ⇒ denegar (no depender de que el
    -- caller pase valores válidos). Acciones canónicas = las de MIG126.
    IF p_accion IS NULL OR p_accion NOT IN ('view','create','edit','delete','approve','export') THEN
        RETURN false;
    END IF;
    IF p_modulo IS NULL OR length(trim(p_modulo)) = 0 THEN
        RETURN false;
    END IF;
    IF auth.uid() IS NULL THEN
        RETURN false;
    END IF;
    v_rol := public.fn_user_rol();   -- NULL si no hay perfil o usuario inactivo ⇒ deniega
    IF v_rol IS NULL THEN
        RETURN false;
    END IF;
    -- Anti-lockout: mismo criterio que MIG126 (administrador no es degradable).
    IF v_rol = 'administrador' THEN
        RETURN true;
    END IF;
    -- Override configurado en Admin (rol_permisos_modulo) manda sobre el default.
    SELECT permisos INTO v_permisos
      FROM public.rol_permisos_modulo
     WHERE rol = v_rol AND modulo = p_modulo;
    IF FOUND THEN
        RETURN p_accion = ANY(v_permisos);   -- override negativo también deniega
    END IF;
    RETURN v_rol = ANY(p_roles_default);
END $$;

COMMENT ON FUNCTION public.fn_tiene_permiso_modulo(TEXT, TEXT, TEXT[]) IS
    'Autorización server-side: TRUE si el rol del usuario autenticado tiene la '
    'acción sobre el módulo. Respeta overrides de rol_permisos_modulo (MIG126); '
    'sin override usa p_roles_default. administrador siempre TRUE. MIG185.';

REVOKE ALL ON FUNCTION public.fn_tiene_permiso_modulo(TEXT, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_tiene_permiso_modulo(TEXT, TEXT, TEXT[]) TO authenticated;


-- ── 2. rpc_confirmar_cierre_diario con autorización y search_path ───────────
CREATE OR REPLACE FUNCTION public.rpc_confirmar_cierre_diario(
    p_fecha DATE,
    p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user      UUID := auth.uid();
    v_item      JSONB;
    v_activo    UUID;
    v_estado    CHAR(1);
    v_contrato  UUID;
    v_cliente   VARCHAR;
    v_estado_com estado_comercial_enum;
    v_n         INTEGER := 0;
BEGIN
    -- Autorización (MIG185): sesión + permiso approve sobre módulo flota.
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;
    IF NOT public.fn_tiene_permiso_modulo(
        'flota', 'approve',
        ARRAY['administrador','subgerente_operaciones','jefe_operaciones','supervisor']
    ) THEN
        RAISE EXCEPTION 'No autorizado para confirmar el cierre diario de flota.';
    END IF;

    IF p_fecha IS NULL THEN
        RAISE EXCEPTION 'p_fecha es obligatoria';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_activo   := (v_item->>'activo_id')::uuid;
        v_estado   := upper(v_item->>'estado_codigo')::char(1);
        v_contrato := NULLIF(v_item->>'contrato_id', '')::uuid;

        IF v_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L') THEN
            RAISE EXCEPTION 'Estado invalido % para activo %', v_estado, v_activo;
        END IF;

        -- Activo debe existir y no estar dado de baja: rechaza el lote completo
        -- (la transacción revierte todo → sin cambios parciales).
        PERFORM 1 FROM public.activos WHERE id = v_activo AND estado <> 'dado_baja';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activo % inexistente o dado de baja; cierre rechazado completo.', v_activo;
        END IF;
        -- Contrato, si viene, debe existir.
        IF v_contrato IS NOT NULL THEN
            PERFORM 1 FROM public.contratos WHERE id = v_contrato;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Contrato % inexistente; cierre rechazado completo.', v_contrato;
            END IF;
        END IF;

        -- Cliente: del contrato si viene; si no, el actual del activo
        v_cliente := NULL;
        IF v_contrato IS NOT NULL THEN
            SELECT cliente INTO v_cliente FROM public.contratos WHERE id = v_contrato;
        END IF;
        IF v_cliente IS NULL THEN
            SELECT cliente_actual INTO v_cliente FROM public.activos WHERE id = v_activo;
        END IF;

        -- Upsert del estado del dia (congelado como cierre)
        INSERT INTO public.estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo, cliente,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at, registrado_por, observacion
        ) VALUES (
            v_activo, p_fecha, v_contrato, v_estado, v_cliente,
            true, 'Cierre diario de flota', false,
            v_user, now(), v_user, 'Cierre diario confirmado'
        )
        ON CONFLICT (activo_id, fecha) DO UPDATE SET
            estado_codigo   = EXCLUDED.estado_codigo,
            contrato_id     = EXCLUDED.contrato_id,
            cliente         = EXCLUDED.cliente,
            override_manual = true,
            motivo_override = 'Cierre diario de flota',
            calculado_auto  = false,
            actualizado_por = EXCLUDED.actualizado_por,
            actualizado_at  = now(),
            updated_at      = now();

        -- Reverse-map a estado_comercial (solo codigos comerciales;
        -- M/T/F/H no cambian el comercial: un equipo arrendado en taller
        -- sigue comercialmente arrendado).
        v_estado_com := (CASE v_estado
            WHEN 'A' THEN 'arrendado'
            WHEN 'C' THEN 'arrendado'
            WHEN 'D' THEN 'disponible'
            WHEN 'U' THEN 'uso_interno'
            WHEN 'L' THEN 'leasing'
            WHEN 'R' THEN 'en_recepcion'
            WHEN 'V' THEN 'en_venta'
            ELSE NULL
        END)::estado_comercial_enum;

        -- Propagar a activos: contrato siempre; comercial + cliente solo si mapea
        UPDATE public.activos SET
            contrato_id      = v_contrato,
            estado_comercial = COALESCE(v_estado_com, estado_comercial),
            cliente_actual   = CASE WHEN v_estado_com IS NOT NULL THEN v_cliente
                                    ELSE cliente_actual END,
            updated_at       = now()
        WHERE id = v_activo;

        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'confirmados', v_n);
END $$;

COMMENT ON FUNCTION public.rpc_confirmar_cierre_diario(DATE, JSONB) IS
    'Confirma el cierre diario (escribe estado_diario_flota y propaga a activos). '
    'Requiere sesión + permiso approve del módulo flota (fn_tiene_permiso_modulo). '
    'MIG106/107, endurecida en MIG185.';

-- ── 3. Cerrar acceso anónimo a ambas funciones ──────────────────────────────
REVOKE ALL ON FUNCTION public.rpc_confirmar_cierre_diario(DATE, JSONB) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(DATE, JSONB) TO authenticated;

REVOKE ALL ON FUNCTION public.fn_propuesta_cierre_diario(DATE) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.fn_propuesta_cierre_diario(DATE) TO authenticated;

-- ── 4. estado_diario_flota: RLS + sin grants para anon ──────────────────────
ALTER TABLE public.estado_diario_flota ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_edf_select_authenticated ON public.estado_diario_flota;
CREATE POLICY pol_edf_select_authenticated ON public.estado_diario_flota
    FOR SELECT TO authenticated USING (true);
-- Sin policies de escritura: INSERT/UPDATE/DELETE quedan solo vía funciones
-- SECURITY DEFINER (owner postgres, exento de RLS) y conexiones admin.

REVOKE ALL ON TABLE public.estado_diario_flota FROM anon;

-- ── 5. Verificación ─────────────────────────────────────────────────────────
DO $$
BEGIN
    IF has_function_privilege('anon', 'public.rpc_confirmar_cierre_diario(date, jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon aún puede ejecutar rpc_confirmar_cierre_diario';
    END IF;
    IF has_function_privilege('anon', 'public.fn_propuesta_cierre_diario(date)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: anon aún puede ejecutar fn_propuesta_cierre_diario';
    END IF;
    IF NOT has_function_privilege('authenticated', 'public.rpc_confirmar_cierre_diario(date, jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'FALLO: authenticated perdió EXECUTE de rpc_confirmar_cierre_diario';
    END IF;
    IF NOT (SELECT rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename='estado_diario_flota') THEN
        RAISE EXCEPTION 'FALLO: estado_diario_flota sigue sin RLS';
    END IF;
    IF has_table_privilege('anon', 'public.estado_diario_flota', 'INSERT') THEN
        RAISE EXCEPTION 'FALLO: anon aún puede INSERT en estado_diario_flota';
    END IF;
    RAISE NOTICE 'MIG185 OK: cierre diario cerrado a anon; RLS activo en estado_diario_flota.';
END $$;

SELECT
    has_function_privilege('anon', 'public.rpc_confirmar_cierre_diario(date, jsonb)', 'EXECUTE') AS anon_confirmar,
    has_function_privilege('anon', 'public.fn_propuesta_cierre_diario(date)', 'EXECUTE')          AS anon_propuesta,
    (SELECT rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename='estado_diario_flota') AS edf_rls;
