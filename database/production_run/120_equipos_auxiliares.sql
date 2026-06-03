-- ============================================================================
-- SICOM-ICEO | 120 — Equipos auxiliares de camión (jerarquía + pautas)
-- ============================================================================
-- Cada camión puede tener equipos AUXILIARES (aljibe, bomba, pluma, manguera…)
-- modelados como activos HIJO (activo_padre_id = camión), con su propia pauta.
--   - rpc_crear_auxiliar(padre, nombre, tipo): crea el activo hijo (hereda
--     contrato/faena/cliente del padre; código autogenerado).
--   - rpc_asignar_pauta(activo, pauta): crea un plan de mantención para el activo.
-- ============================================================================

-- Marca + modelo genérico para auxiliares (modelo_id es obligatorio en activos).
INSERT INTO marcas (id, nombre)
SELECT gen_random_uuid(), 'Auxiliar'
WHERE NOT EXISTS (SELECT 1 FROM marcas WHERE nombre = 'Auxiliar');

INSERT INTO modelos (id, marca_id, nombre, tipo_activo)
SELECT gen_random_uuid(), (SELECT id FROM marcas WHERE nombre = 'Auxiliar'), 'Equipo Auxiliar', 'equipo_menor'
WHERE NOT EXISTS (SELECT 1 FROM modelos WHERE nombre = 'Equipo Auxiliar');

-- ── Crear auxiliar (activo hijo) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_crear_auxiliar(
    p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_p      RECORD;
    v_modelo uuid;
    v_codigo text;
    v_n      integer;
    v_id     uuid;
BEGIN
    SELECT * INTO v_p FROM activos WHERE id = p_padre_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo padre no existe'; END IF;

    SELECT id INTO v_modelo FROM modelos WHERE nombre = 'Equipo Auxiliar' LIMIT 1;
    SELECT count(*) INTO v_n FROM activos WHERE activo_padre_id = p_padre_id;
    v_codigo := COALESCE(v_p.codigo, 'EQ') || '-AUX-' || LPAD((v_n + 1)::text, 2, '0');
    v_id := gen_random_uuid();

    INSERT INTO activos (id, codigo, nombre, tipo, modelo_id, activo_padre_id, estado,
                         contrato_id, faena_id, cliente_actual, operacion)
    VALUES (v_id, v_codigo, p_nombre, p_tipo, v_modelo, p_padre_id, 'operativo',
            v_p.contrato_id, v_p.faena_id, v_p.cliente_actual, v_p.operacion);

    RETURN jsonb_build_object('id', v_id, 'codigo', v_codigo);
END $$;

-- ── Asignar una pauta a un activo (crea plan) ───────────────────────────────
CREATE OR REPLACE FUNCTION rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_pf RECORD; v_id uuid;
BEGIN
    SELECT * INTO v_pf FROM pautas_fabricante WHERE id = p_pauta_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pauta no existe'; END IF;

    IF EXISTS (SELECT 1 FROM planes_mantenimiento WHERE activo_id = p_activo_id AND pauta_fabricante_id = p_pauta_id) THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    v_id := gen_random_uuid();
    INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan,
                                      frecuencia_dias, frecuencia_km, frecuencia_horas, activo_plan, created_by)
    VALUES (v_id, p_activo_id, p_pauta_id, v_pf.nombre, v_pf.tipo_plan,
            v_pf.frecuencia_dias, v_pf.frecuencia_km, v_pf.frecuencia_horas, true, auth.uid());

    RETURN jsonb_build_object('id', v_id);
END $$;

GRANT EXECUTE ON FUNCTION rpc_crear_auxiliar(uuid, text, tipo_activo_enum) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_asignar_pauta(uuid, uuid) TO authenticated;

DO $$ BEGIN RAISE NOTICE 'MIG120 OK: rpc_crear_auxiliar + rpc_asignar_pauta'; END $$;
