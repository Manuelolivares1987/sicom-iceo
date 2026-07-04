-- ============================================================================
-- SICOM-ICEO | Tests de seguridad Fase 0 (MIG185/186/187)
-- ----------------------------------------------------------------------------
-- ⚠️  EJECUTAR SOLO DESPUÉS de aplicar MIG185+186+187, y solo con autorización
--     ("APLICAR EN PRODUCCIÓN" cubre también esta verificación) o en staging.
--     Todo corre dentro de UNA transacción que TERMINA EN ROLLBACK: no persiste
--     ningún cambio. Simula los contextos anon / authenticated con SET LOCAL
--     ROLE + request.jwt.claims (mismo mecanismo que PostgREST); NO usa el
--     owner para las aserciones de RLS/permisos.
--
-- Uso:  node database/scripts/psql-cli.mjs -f database/tests/fase0_seguridad_rpc.sql
--
-- Matriz cubierta:
--   T01 anon           → rpc_confirmar_cierre_diario  → DENEGADO (sin EXECUTE)
--   T02 anon           → INSERT directo estado_diario_flota → DENEGADO (RLS/grants)
--   T03 auth sin rol de cierre (tecnico) → confirmar  → DENEGADO ('No autorizado')
--   T04 auth autorizado (administrador)  → confirmar  → PERMITIDO (1 confirmado)
--   T05 auth autorizado + activo inexistente → RECHAZADO completo (sin parciales)
--   T06 anon           → fn_reporte_fiabilidad_publico → DENEGADO
--   T07 auth con perfil → reporte → PERMITIDO + claves completas (incl combustible)
--   T08 auth rol bodeguero → salida combustible → litros Y valor bajan juntos
--   T09 salida > stock → DENEGADO (sin stock negativo)
--   Nota: idempotencia de reintento (doble movimiento) NO está cubierta por el
--   diseño actual de las RPC (sin idempotency-key); queda como pendiente Fase 1.
-- ============================================================================

BEGIN;

-- Helpers de contexto ---------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.como_anon() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
$$;
CREATE OR REPLACE FUNCTION pg_temp.como_usuario(p_uid UUID, p_rol TEXT) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated',
                      'user_metadata', json_build_object('rol', p_rol))::text, true);
$$;

DO $$
DECLARE
    v_admin    UUID;
    v_tecnico  UUID;
    v_bodeguero UUID;
    v_activo   UUID;
    v_estanque UUID;
    v_stock0   NUMERIC; v_valor0 NUMERIC; v_cpp0 NUMERIC;
    v_stock1   NUMERIC; v_valor1 NUMERIC;
    v_r        JSONB;
    v_ok       BOOLEAN;
BEGIN
    SELECT id INTO v_admin     FROM usuarios_perfil WHERE rol::text = 'administrador' LIMIT 1;
    SELECT id INTO v_tecnico   FROM usuarios_perfil WHERE rol::text = 'tecnico_mantenimiento' LIMIT 1;
    SELECT id INTO v_bodeguero FROM usuarios_perfil WHERE rol::text = 'bodeguero' LIMIT 1;
    SELECT id INTO v_activo FROM activos
     WHERE estado <> 'dado_baja'
       AND tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor') LIMIT 1;
    SELECT id, stock_teorico_lt, valor_total_stock, COALESCE(costo_promedio_lt,0)
      INTO v_estanque, v_stock0, v_valor0, v_cpp0
      FROM combustible_estanques WHERE activo AND stock_teorico_lt >= 10 LIMIT 1;
    IF v_admin IS NULL OR v_tecnico IS NULL OR v_activo IS NULL THEN
        RAISE EXCEPTION 'Precondición tests: faltan usuarios/activos de referencia.';
    END IF;

    ---------------------------------------------------------------------------
    -- T01: anon no puede ejecutar el cierre diario
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_anon();
    SET LOCAL ROLE anon;
    v_ok := false;
    BEGIN
        PERFORM rpc_confirmar_cierre_diario(CURRENT_DATE,
            jsonb_build_array(jsonb_build_object('activo_id', v_activo, 'estado_codigo', 'D')));
    EXCEPTION
        WHEN insufficient_privilege THEN v_ok := true;   -- sin EXECUTE
        WHEN OTHERS THEN v_ok := true;                   -- guard interno también vale
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'T01 FALLÓ: anon pudo confirmar cierre diario'; END IF;
    RAISE NOTICE 'T01 OK: anon denegado en rpc_confirmar_cierre_diario';

    ---------------------------------------------------------------------------
    -- T02: anon no puede escribir estado_diario_flota directo
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_anon();
    SET LOCAL ROLE anon;
    v_ok := false;
    BEGIN
        INSERT INTO estado_diario_flota (activo_id, fecha, estado_codigo)
        VALUES (v_activo, CURRENT_DATE + 1, 'D');
    EXCEPTION WHEN insufficient_privilege THEN v_ok := true;
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'T02 FALLÓ: anon insertó en estado_diario_flota'; END IF;
    RAISE NOTICE 'T02 OK: anon sin INSERT directo en estado_diario_flota';

    ---------------------------------------------------------------------------
    -- T03: autenticado SIN permiso (tecnico_mantenimiento) → denegado
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_usuario(v_tecnico, 'tecnico_mantenimiento');
    SET LOCAL ROLE authenticated;
    v_ok := false;
    BEGIN
        PERFORM rpc_confirmar_cierre_diario(CURRENT_DATE,
            jsonb_build_array(jsonb_build_object('activo_id', v_activo, 'estado_codigo', 'D')));
    EXCEPTION WHEN OTHERS THEN
        v_ok := SQLERRM LIKE '%No autorizado%';
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'T03 FALLÓ: tecnico pudo confirmar cierre (o error inesperado)'; END IF;
    RAISE NOTICE 'T03 OK: rol sin permiso denegado con mensaje controlado';

    ---------------------------------------------------------------------------
    -- T04: administrador → permitido (y escribe; se revierte con el ROLLBACK)
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_usuario(v_admin, 'administrador');
    SET LOCAL ROLE authenticated;
    v_r := rpc_confirmar_cierre_diario(CURRENT_DATE,
        jsonb_build_array(jsonb_build_object('activo_id', v_activo, 'estado_codigo', 'D')));
    RESET ROLE;
    IF COALESCE((v_r->>'confirmados')::int, 0) <> 1 THEN
        RAISE EXCEPTION 'T04 FALLÓ: administrador no pudo confirmar (resp %)', v_r;
    END IF;
    RAISE NOTICE 'T04 OK: administrador confirma cierre (confirmados=1)';

    ---------------------------------------------------------------------------
    -- T05: activo inexistente → rechazo completo del lote
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_usuario(v_admin, 'administrador');
    SET LOCAL ROLE authenticated;
    v_ok := false;
    BEGIN
        PERFORM rpc_confirmar_cierre_diario(CURRENT_DATE,
            jsonb_build_array(
                jsonb_build_object('activo_id', v_activo, 'estado_codigo', 'D'),
                jsonb_build_object('activo_id', gen_random_uuid(), 'estado_codigo', 'D')));
    EXCEPTION WHEN OTHERS THEN
        v_ok := SQLERRM LIKE '%inexistente%';
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'T05 FALLÓ: lote con activo inexistente no fue rechazado'; END IF;
    RAISE NOTICE 'T05 OK: lote con activo inexistente rechazado completo';

    ---------------------------------------------------------------------------
    -- T06: anon no puede leer el reporte de fiabilidad
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_anon();
    SET LOCAL ROLE anon;
    v_ok := false;
    BEGIN
        PERFORM fn_reporte_fiabilidad_publico();
    EXCEPTION
        WHEN insufficient_privilege THEN v_ok := true;
        WHEN OTHERS THEN v_ok := SQLERRM LIKE '%no autorizado%' OR SQLERRM LIKE '%No autenticado%' OR SQLERRM LIKE '%Acceso%';
    END;
    RESET ROLE;
    IF NOT v_ok THEN RAISE EXCEPTION 'T06 FALLÓ: anon leyó el reporte de fiabilidad'; END IF;
    RAISE NOTICE 'T06 OK: anon denegado en fn_reporte_fiabilidad_publico';

    ---------------------------------------------------------------------------
    -- T07: usuario interno → reporte completo (contrato incl. combustible)
    ---------------------------------------------------------------------------
    PERFORM pg_temp.como_usuario(v_admin, 'administrador');
    SET LOCAL ROLE authenticated;
    v_r := fn_reporte_fiabilidad_publico();
    RESET ROLE;
    IF NOT (v_r ? 'categorias' AND v_r ? 'equipos' AND v_r ? 'matriz' AND v_r ? 'combustible') THEN
        RAISE EXCEPTION 'T07 FALLÓ: contrato incompleto del reporte';
    END IF;
    RAISE NOTICE 'T07 OK: reporte completo para usuario interno (equipos=%, combustible=%)',
        jsonb_array_length(v_r->'equipos'), jsonb_array_length(v_r->'combustible');

    ---------------------------------------------------------------------------
    -- T08: salida de combustible baja litros Y valor (consumo_interno evita
    --      exigir evidencia; se revierte con el ROLLBACK final)
    ---------------------------------------------------------------------------
    IF v_estanque IS NOT NULL AND v_bodeguero IS NOT NULL THEN
        PERFORM pg_temp.como_usuario(v_bodeguero, 'bodeguero');
        SET LOCAL ROLE authenticated;
        v_r := rpc_registrar_salida_combustible_valorizada(
            p_estanque_id => v_estanque, p_litros => 10,
            p_destino_tipo => 'consumo_interno',
            p_motivo => 'Test seguridad Fase 0 (rollback)');
        RESET ROLE;
        SELECT stock_teorico_lt, valor_total_stock INTO v_stock1, v_valor1
          FROM combustible_estanques WHERE id = v_estanque;
        IF v_stock1 <> v_stock0 - 10 THEN
            RAISE EXCEPTION 'T08 FALLÓ: stock no bajó (% → %)', v_stock0, v_stock1;
        END IF;
        IF ABS(v_valor1 - ROUND((v_stock1 * v_cpp0)::numeric, 2)) > 0.011 THEN
            RAISE EXCEPTION 'T08 FALLÓ: valor no acompañó a los litros (valor=% esperado=%)',
                v_valor1, ROUND((v_stock1 * v_cpp0)::numeric, 2);
        END IF;
        RAISE NOTICE 'T08 OK: salida baja litros y valor juntos (stock %→%, valor %→%)',
            v_stock0, v_stock1, v_valor0, v_valor1;

        -----------------------------------------------------------------------
        -- T09: salida mayor al stock → denegada
        -----------------------------------------------------------------------
        PERFORM pg_temp.como_usuario(v_bodeguero, 'bodeguero');
        SET LOCAL ROLE authenticated;
        v_ok := false;
        BEGIN
            PERFORM rpc_registrar_salida_combustible_valorizada(
                p_estanque_id => v_estanque, p_litros => v_stock1 + 1000,
                p_destino_tipo => 'consumo_interno',
                p_motivo => 'Test stock insuficiente');
        EXCEPTION WHEN OTHERS THEN v_ok := SQLERRM LIKE '%insuficiente%';
        END;
        RESET ROLE;
        IF NOT v_ok THEN RAISE EXCEPTION 'T09 FALLÓ: permitió salida sobre el stock'; END IF;
        RAISE NOTICE 'T09 OK: salida sobre stock denegada';
    ELSE
        RAISE NOTICE 'T08/T09 OMITIDOS: sin estanque con stock >= 10 o sin bodeguero.';
    END IF;

    RAISE NOTICE '════ TODOS LOS TESTS FASE 0 PASARON (los cambios se revierten) ════';
END $$;

ROLLBACK;
