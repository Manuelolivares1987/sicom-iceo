-- SICOM-ICEO | Fix RLS: Lectura general para usuarios autenticados
-- ============================================================================
-- PROBLEMA RAÍZ:
-- fn_user_rol() lee de JWT user_metadata.rol, pero Supabase Auth no lo setea
-- automáticamente. El fallback lee de usuarios_perfil, pero RLS en esa tabla
-- creaba dependencia circular. Resultado: fn_user_rol() retorna NULL,
-- NINGUNA política aplica, y todos los SELECT fallan.
--
-- SOLUCIÓN:
-- Agregar política simple de SELECT para todos los autenticados en las
-- tablas principales. Las restricciones de escritura (INSERT/UPDATE/DELETE)
-- siguen usando roles vía RLS.
--
-- SEGURIDAD: Los usuarios autenticados pueden VER datos pero no modificarlos
-- sin las políticas de rol correspondientes. Esto es el patrón estándar
-- para aplicaciones con frontend.
-- ============================================================================

-- Función auxiliar mejorada: fn_user_rol con mejor fallback
CREATE OR REPLACE FUNCTION fn_user_rol()
RETURNS TEXT AS $$
DECLARE
    v_rol TEXT;
BEGIN
    -- Intentar desde JWT
    BEGIN
        v_rol := current_setting('request.jwt.claims', true)::JSONB->'user_metadata'->>'rol';
    EXCEPTION WHEN OTHERS THEN
        v_rol := NULL;
    END;

    -- Fallback: consultar tabla (SECURITY DEFINER bypasea RLS)
    IF v_rol IS NULL THEN
        SELECT rol::TEXT INTO v_rol FROM usuarios_perfil WHERE id = auth.uid();
    END IF;

    RETURN v_rol;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;


-- ============================================================================
-- POLÍTICAS DE LECTURA GENERAL PARA AUTENTICADOS
-- ============================================================================
-- Patrón: todo autenticado puede SELECT, pero solo roles específicos
-- pueden INSERT/UPDATE/DELETE (esas políticas ya existen en 05).

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'marcas', 'modelos',
        'activos', 'pautas_fabricante', 'planes_mantenimiento',
        'bodegas', 'productos', 'stock_bodega',
        'ordenes_trabajo', 'checklist_ot', 'evidencias_ot',
        'historial_estado_ot', 'movimientos_inventario',
        'kardex', 'conteos_inventario', 'conteo_detalle',
        'lecturas_pistola'
    ] LOOP
        -- Eliminar políticas de lectura conflictivas
        BEGIN
            EXECUTE format('DROP POLICY IF EXISTS pol_authenticated_select_%1$s ON %1$I', t);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        -- Crear política simple de lectura
        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_authenticated_select_%1$s ON %1$I
                 FOR SELECT TO authenticated
                 USING (true)',
                t
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END LOOP;

    RAISE NOTICE 'OK: Políticas de lectura general creadas para tablas core';
END $$;

-- Lo mismo para tablas de fase 04
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'certificaciones', 'documentos', 'incidentes',
        'rutas_despacho', 'abastecimientos',
        'kpi_definiciones', 'kpi_tramos', 'mediciones_kpi',
        'iceo_periodos', 'iceo_detalle', 'configuracion_iceo',
        'auditoria_eventos', 'alertas'
    ] LOOP
        BEGIN
            EXECUTE format('DROP POLICY IF EXISTS pol_authenticated_select_%1$s ON %1$I', t);
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_authenticated_select_%1$s ON %1$I
                 FOR SELECT TO authenticated
                 USING (true)',
                t
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END LOOP;

    RAISE NOTICE 'OK: Políticas de lectura general creadas para tablas compliance/KPI';
END $$;

-- Tablas nuevas (incentivos, QR, etc.)
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'cargos_incentivo', 'tramos_incentivo', 'incentivos_periodo',
        'log_jobs_automaticos', 'iceo_recalculo_pendiente'
    ] LOOP
        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_authenticated_select_%1$s ON %1$I
                 FOR SELECT TO authenticated
                 USING (true)',
                t
            );
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    END LOOP;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Algunas tablas nuevas no existen aún, ignorando: %', SQLERRM;
END $$;

-- Habilitar RLS en tablas nuevas si no está
DO $$ BEGIN ALTER TABLE cargos_incentivo ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE tramos_incentivo ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE incentivos_periodo ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE log_jobs_automaticos ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE iceo_recalculo_pendiente ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE kpi_snapshots_mensuales ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
    CREATE POLICY pol_authenticated_select_kpi_snapshots ON kpi_snapshots_mensuales
        FOR SELECT TO authenticated USING (true);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(DISTINCT tablename) INTO v_count
    FROM pg_policies
    WHERE policyname LIKE 'pol_authenticated_select_%';

    RAISE NOTICE 'OK: % tablas con política de lectura para autenticados', v_count;

    -- Verificar que ordenes_trabajo tiene la política
    SELECT COUNT(*) INTO v_count FROM pg_policies
    WHERE tablename = 'ordenes_trabajo'
      AND policyname = 'pol_authenticated_select_ordenes_trabajo';

    IF v_count = 0 THEN
        RAISE EXCEPTION 'FALLO: ordenes_trabajo no tiene política de lectura';
    END IF;

    RAISE NOTICE 'OK: ordenes_trabajo accesible para lectura';
END $$;

-- ============================================================================
-- FIN
-- ============================================================================
