-- SICOM-ICEO | FIX CRÍTICO: Corregir nombres de funciones KPI
-- ============================================================================
-- BUG: kpi_definiciones.funcion_calculo apunta a funciones que NO EXISTEN
--      (fn_kpi_nombre_largo) en vez de las funciones reales (calcular_kpi_XX)
--
-- IMPACTO: SIN ESTE FIX, TODOS LOS KPIs CALCULAN 0 Y EL ICEO ES SIEMPRE 0
--
-- Ejecutar inmediatamente después de detectar el problema.
-- ============================================================================

-- Actualizar CADA KPI con el nombre correcto de su función de cálculo

UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a1' WHERE codigo = 'A1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a2' WHERE codigo = 'A2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a3' WHERE codigo = 'A3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a4' WHERE codigo = 'A4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a5' WHERE codigo = 'A5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a6' WHERE codigo = 'A6';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a7' WHERE codigo = 'A7';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_a8' WHERE codigo = 'A8';

UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b1' WHERE codigo = 'B1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b2' WHERE codigo = 'B2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b3' WHERE codigo = 'B3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b4' WHERE codigo = 'B4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b5' WHERE codigo = 'B5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_b6' WHERE codigo = 'B6';

UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c1' WHERE codigo = 'C1';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c2' WHERE codigo = 'C2';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c3' WHERE codigo = 'C3';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c4' WHERE codigo = 'C4';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c5' WHERE codigo = 'C5';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c6' WHERE codigo = 'C6';
UPDATE kpi_definiciones SET funcion_calculo = 'calcular_kpi_c7' WHERE codigo = 'C7';

-- Verificar la corrección
DO $$
DECLARE
    v_count INTEGER;
    v_bad INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM kpi_definiciones WHERE activo = true;
    SELECT COUNT(*) INTO v_bad FROM kpi_definiciones
    WHERE activo = true
      AND funcion_calculo NOT LIKE 'calcular_kpi_%';

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'ERROR: Aún hay % KPIs con nombre de función incorrecto', v_bad;
    END IF;

    RAISE NOTICE 'OK: % KPIs con funcion_calculo correcta (calcular_kpi_*)', v_count;
END $$;

-- También corregir el seed file para futuras instalaciones
-- (esto no afecta la BD actual, solo documenta la corrección)
COMMENT ON TABLE kpi_definiciones IS
'Definiciones de KPI. IMPORTANTE: funcion_calculo debe ser calcular_kpi_XX (no fn_kpi_nombre).';

-- ============================================================================
-- VERIFICAR QUE LAS FUNCIONES EXISTEN
-- ============================================================================

DO $$
DECLARE
    v_kpi RECORD;
    v_exists BOOLEAN;
BEGIN
    FOR v_kpi IN SELECT codigo, funcion_calculo FROM kpi_definiciones WHERE activo = true
    LOOP
        SELECT EXISTS(
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE p.proname = v_kpi.funcion_calculo
              AND n.nspname = 'public'
        ) INTO v_exists;

        IF NOT v_exists THEN
            RAISE WARNING 'FUNCIÓN NO ENCONTRADA: % (KPI %)', v_kpi.funcion_calculo, v_kpi.codigo;
        ELSE
            RAISE NOTICE 'OK: % → %', v_kpi.codigo, v_kpi.funcion_calculo;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- FIN — Después de ejecutar este archivo, el ICEO calculará valores reales.
-- ============================================================================
