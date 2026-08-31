-- ============================================================================
-- MIG460 · El bono todavía no se le muestra al taller
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL
-- 31-08-2026, apenas vio la cartola en producción: «todo lo que es cálculo de
-- bono sólo tiene que tener vista el administrador y jefe de taller,
-- operaciones. Hasta que estemos seguros que todo está bien».
--
-- Y tiene razón. Un número de bono equivocado que el mecánico ya vio no se
-- desmiente con una migración: se arrastra en la conversación del taller durante
-- meses. La cartola se abre DESPUÉS de que la marcha blanca demuestre que el
-- cálculo es correcto, no antes.
--
-- DÓNDE VA EL CANDADO
-- En el RPC, no en la pantalla. Sacar el link del teléfono esconde la puerta;
-- no la cierra. Cualquiera con la sesión abierta puede llamar al RPC igual. Es
-- la misma lección de MIG437: el candado va en la base, y la pantalla sólo lo
-- refleja.
--
-- Y EN UNA FILA, NO EN CÓDIGO
-- Abrir el bono a los mecánicos va a ser una decisión de criterio —cuando el
-- acta esté firmada y el primer corte cuadre—, así que tiene que ser un INSERT
-- y no una migración nueva:
--
--     INSERT INTO taller_bono_acceso (rol, puede_ver, nota)
--     VALUES ('operador_taller', TRUE, 'Abierto tras el acta del <fecha>');
--
-- Mientras tanto ven el bono los cuatro cargos que responden por él:
-- administrador, subgerente de operaciones, jefe de operaciones y jefe de
-- mantenimiento —que es el jefe de taller—.
--
-- LO QUE SE CIERRA
--   · fn_taller_bono_periodo / _kpi_periodo / _resumen  · el cálculo
--   · rpc_taller_bono_cartola                           · la cartola de alguien
--   · rpc_taller_bono_periodos                          · los cortes cerrados
--   · rpc_taller_bono_acusar_recibo                     · el acuse del trabajador
--
-- El acuse queda escrito y funcionando, pero no lo puede usar nadie todavía:
-- firmar una cartola que no se puede leer no significa nada. Se reactiva solo
-- cuando su rol entre en la tabla.
--
-- Lo que NO se cierra es `fn_taller_disponibilidad_periodo`: la disponibilidad
-- de flota es un indicador de operación que ya se mira en otras pantallas, y no
-- dice cuánto gana nadie.
-- ============================================================================

BEGIN;

-- ── 1 · Quién ve el bono, en una fila ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS taller_bono_acceso (
    rol         TEXT PRIMARY KEY,
    puede_ver   BOOLEAN NOT NULL DEFAULT TRUE,
    nota        TEXT,
    creado_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE taller_bono_acceso IS
    'Cargos que pueden ver el cálculo del bono. Mientras dure la marcha blanca '
    'sólo jefatura. Abrirlo a los mecánicos es un INSERT, no una migración.';

INSERT INTO taller_bono_acceso (rol, puede_ver, nota) VALUES
    ('administrador',          TRUE, 'Responde por el sistema'),
    ('subgerente_operaciones', TRUE, 'Operaciones'),
    ('jefe_operaciones',       TRUE, 'Operaciones'),
    ('jefe_mantenimiento',     TRUE, 'Jefe de taller')
ON CONFLICT (rol) DO UPDATE SET puede_ver = EXCLUDED.puede_ver;

-- ── 2 · El candado ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_taller_bono_puede_ver()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM taller_bono_acceso a
         WHERE a.rol = fn_user_rol() AND a.puede_ver
    );
$$;

-- Un solo mensaje para todas las puertas: si alguien lo ve, tiene que entender
-- que no es un error del sistema sino una decisión que todavía no se toma.
CREATE OR REPLACE FUNCTION fn_taller_bono_exigir_vista()
RETURNS VOID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_bono_puede_ver() THEN
        RAISE EXCEPTION 'El cálculo del bono todavía no está abierto. Mientras dure '
                        'la marcha blanca lo revisan administración, operaciones y la '
                        'jefatura de taller.';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_bono_puede_ver() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_exigir_vista() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_bono_puede_ver() TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_exigir_vista() TO authenticated;

ALTER TABLE taller_bono_acceso ENABLE ROW LEVEL SECURITY;
-- Sin políticas: se lee sólo desde las funciones SECURITY DEFINER de arriba.

-- ── 3 · La cartola, ahora sólo para jefatura ────────────────────────────────
--
-- Antes cada técnico veía la suya sin pedir permiso. Ahora la puerta es una
-- sola y la cruza quien está en la tabla; `p_tecnico_id` deja de ser el caso
-- excepcional y pasa a ser lo normal: jefatura mirando la de alguien.
CREATE OR REPLACE FUNCTION rpc_taller_bono_cartola(
    p_desde      DATE,
    p_hasta      DATE,
    p_tecnico_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_tec  UUID;
    v_per  RECORD;
    v_lin  JSONB;
    v_det  JSONB;
BEGIN
    PERFORM fn_taller_bono_exigir_vista();

    -- Sin técnico explícito devuelve la propia, si quien pregunta además es
    -- técnico. Hoy eso sólo puede pasar con alguien de jefatura que además esté
    -- en el catálogo del taller.
    v_tec := COALESCE(p_tecnico_id, fn_taller_tecnico_de_usuario(v_user));
    IF v_tec IS NULL THEN
        RAISE EXCEPTION 'Elige de quién quieres ver la cartola.';
    END IF;

    SELECT * INTO v_per FROM taller_bono_periodo
     WHERE desde = p_desde AND hasta = p_hasta
     ORDER BY cerrado_at DESC LIMIT 1;

    IF v_per.id IS NOT NULL THEN
        SELECT to_jsonb(l) INTO v_lin
          FROM taller_bono_periodo_linea l
         WHERE l.periodo_id = v_per.id AND l.tecnico_id = v_tec;

        SELECT COALESCE(jsonb_agg(to_jsonb(d) ORDER BY d.ot_folio), '[]'::jsonb) INTO v_det
          FROM taller_bono_periodo_detalle d
         WHERE d.periodo_id = v_per.id AND d.tecnico_id = v_tec;

        RETURN jsonb_build_object(
            'cerrado', true,
            'borrador', false,
            'periodo', jsonb_build_object(
                'id', v_per.id, 'nombre', v_per.nombre,
                'desde', v_per.desde, 'hasta', v_per.hasta,
                'estado', v_per.estado,
                'disponibilidad_pct', v_per.disponibilidad_pct,
                'disponibilidad_fuente', v_per.disponibilidad_fuente,
                'cerrado_at', v_per.cerrado_at,
                'cerrado_por', (SELECT up.nombre_completo FROM usuarios_perfil up WHERE up.id = v_per.cerrado_por),
                'motivo_reapertura', v_per.motivo_reapertura),
            'linea', v_lin,
            'detalle', v_det);
    END IF;

    SELECT to_jsonb(r) INTO v_lin
      FROM fn_taller_bono_resumen(p_desde, p_hasta) r
     WHERE r.tecnico_id = v_tec;

    SELECT COALESCE(jsonb_agg(to_jsonb(b) ORDER BY b.ot_folio), '[]'::jsonb) INTO v_det
      FROM fn_taller_bono_periodo(p_desde, p_hasta) b
     WHERE b.tecnico_id = v_tec;

    RETURN jsonb_build_object(
        'cerrado', false,
        'borrador', true,
        'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta),
        'linea', v_lin,
        'detalle', v_det);
END;
$$;

-- ── 4 · Los cortes cerrados ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_periodos()
RETURNS TABLE (
    id            UUID,
    nombre        TEXT,
    desde         DATE,
    hasta         DATE,
    estado        TEXT,
    total_clp     NUMERIC,
    personas      INT,
    acusadas      INT,
    disponibilidad_pct NUMERIC,
    cerrado_at    TIMESTAMPTZ,
    cerrado_por   TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY
    -- Los casts son obligatorios: al pasar de LANGUAGE sql a plpgsql, RETURN
    -- QUERY exige que los tipos calcen exacto, y `nombre_completo` es VARCHAR.
    SELECT p.id, p.nombre::TEXT, p.desde, p.hasta, p.estado::TEXT, p.total_clp,
           (SELECT count(*)::INT FROM taller_bono_periodo_linea l WHERE l.periodo_id = p.id),
           (SELECT count(*)::INT FROM taller_bono_periodo_linea l WHERE l.periodo_id = p.id AND l.acuse_at IS NOT NULL),
           p.disponibilidad_pct, p.cerrado_at,
           (SELECT up.nombre_completo::TEXT FROM usuarios_perfil up WHERE up.id = p.cerrado_por)
      FROM taller_bono_periodo p
     ORDER BY p.desde DESC;
END;
$$;

-- ── 5 · El acuse, dormido hasta que la cartola se abra ──────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_bono_acusar_recibo(
    p_linea_id   UUID,
    p_comentario TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user UUID := auth.uid();
    v_tec  UUID;
    v_due  UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    -- Firmar una cartola que no se puede leer no significa nada.
    IF NOT fn_taller_bono_puede_ver() THEN
        RAISE EXCEPTION 'La cartola todavía no está abierta a los trabajadores.';
    END IF;

    SELECT tecnico_id INTO v_due FROM taller_bono_periodo_linea WHERE id = p_linea_id;
    IF v_due IS NULL THEN RAISE EXCEPTION 'Esa cartola no existe.'; END IF;

    v_tec := fn_taller_tecnico_de_usuario(v_user);
    IF v_tec IS DISTINCT FROM v_due THEN
        RAISE EXCEPTION 'Sólo el dueño de la cartola puede acusar recibo.';
    END IF;

    UPDATE taller_bono_periodo_linea
       SET acuse_at = NOW(), acuse_por = v_user,
           acuse_comentario = NULLIF(TRIM(COALESCE(p_comentario, '')), '')
     WHERE id = p_linea_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 6 · El cálculo mismo ────────────────────────────────────────────────────
--
-- Las tres funciones que devuelven pesos se envuelven con el mismo candado.
-- Cambiar el cuerpo entero sería copiar 200 líneas para agregar una: se
-- renombran a `_calc` y la función pública queda como envoltorio.
ALTER FUNCTION fn_taller_bono_periodo(DATE, DATE)              RENAME TO fn_taller_bono_periodo_calc;
ALTER FUNCTION fn_taller_bono_kpi_periodo(DATE, DATE, NUMERIC) RENAME TO fn_taller_bono_kpi_periodo_calc;
ALTER FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC)     RENAME TO fn_taller_bono_resumen_calc;

CREATE OR REPLACE FUNCTION fn_taller_bono_periodo(p_desde DATE, p_hasta DATE)
RETURNS TABLE (
    tecnico_id        UUID, tecnico TEXT, cargo TEXT, ot_id UUID, ot_folio TEXT,
    concepto TEXT, dias NUMERIC, tramo TEXT, participacion NUMERIC,
    base_reparto TEXT, monto_formula NUMERIC, monto_propuesto NUMERIC,
    falta TEXT, aviso TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY SELECT * FROM fn_taller_bono_periodo_calc(p_desde, p_hasta);
END;
$$;

CREATE OR REPLACE FUNCTION fn_taller_bono_kpi_periodo(
    p_desde DATE, p_hasta DATE, p_disponibilidad NUMERIC DEFAULT NULL)
RETURNS TABLE (
    tecnico_id UUID, tecnico TEXT, cargo TEXT, disponibilidad NUMERIC,
    tramo TEXT, factor NUMERIC, kpi_base NUMERIC, dias_cargo INT,
    dias_corte INT, prorrateo NUMERIC, monto_kpi NUMERIC, falta TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY SELECT * FROM fn_taller_bono_kpi_periodo_calc(p_desde, p_hasta, p_disponibilidad);
END;
$$;

CREATE OR REPLACE FUNCTION fn_taller_bono_resumen(
    p_desde DATE, p_hasta DATE, p_disponibilidad NUMERIC DEFAULT NULL)
RETURNS TABLE (
    tecnico_id UUID, tecnico TEXT, cargo TEXT, ots INT, plan_formula NUMERIC,
    plan_calculado NUMERIC, plan_tope NUMERIC, plan_pagado NUMERIC,
    kpi_pagado NUMERIC, total NUMERIC, dias_cargo INT, dias_corte INT,
    disponibilidad NUMERIC, tramo TEXT, falta TEXT, aviso TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
    PERFORM fn_taller_bono_exigir_vista();
    RETURN QUERY SELECT * FROM fn_taller_bono_resumen_calc(p_desde, p_hasta, p_disponibilidad);
END;
$$;

-- Las `_calc` no se llaman nunca desde afuera: son el cuerpo, no la puerta.
REVOKE ALL ON FUNCTION fn_taller_bono_periodo_calc(DATE, DATE) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_taller_bono_kpi_periodo_calc(DATE, DATE, NUMERIC) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION fn_taller_bono_resumen_calc(DATE, DATE, NUMERIC) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION fn_taller_bono_periodo(DATE, DATE) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_kpi_periodo(DATE, DATE, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_cartola(DATE, DATE, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_periodos() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION rpc_taller_bono_acusar_recibo(UUID, TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION fn_taller_bono_periodo(DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_kpi_periodo(DATE, DATE, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_taller_bono_resumen(DATE, DATE, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_cartola(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_periodos() TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_taller_bono_acusar_recibo(UUID, TEXT) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE
    v_n INT; r RECORD;
BEGIN
    SELECT count(*) INTO v_n FROM taller_bono_acceso WHERE puede_ver;
    IF v_n <> 4 THEN RAISE EXCEPTION 'FALLO: quedaron % cargos con vista, se esperaban 4', v_n; END IF;

    FOR r IN SELECT rol, nota FROM taller_bono_acceso WHERE puede_ver ORDER BY rol LOOP
        RAISE NOTICE 've el bono: % (%)', rpad(r.rol, 24), r.nota;
    END LOOP;

    -- Ninguna función de plata puede quedar con una sola firma sin candado.
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_taller_bono_periodo','fn_taller_bono_kpi_periodo','fn_taller_bono_resumen')
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    IF v_n <> 3 THEN RAISE EXCEPTION 'FALLO: las 3 puertas del cálculo no quedaron abiertas a authenticated (%)', v_n; END IF;

    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname LIKE 'fn_taller_bono%_calc'
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    IF v_n <> 0 THEN RAISE EXCEPTION 'FALLO: % funciones _calc quedaron alcanzables sin candado', v_n; END IF;
    RAISE NOTICE 'el cuerpo del cálculo (_calc) no es alcanzable desde afuera';
END
$mig$;

COMMIT;
