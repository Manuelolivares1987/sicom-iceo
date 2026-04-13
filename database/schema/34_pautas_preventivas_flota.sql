-- ============================================================================
-- SICOM-ICEO | Migración 34 — Pautas Preventivas de Fabricante para Flota
-- ============================================================================
-- Propósito : Cargar los intervalos estándar de mantención preventiva por
--             modelo de vehículo, basados en los manuales de fabricante.
--             Al asociar estas pautas con los planes_mantenimiento de cada
--             activo, el sistema detecta automáticamente cuándo un equipo
--             necesita mantención según su km o hrs acumuladas.
--
-- Flujo operativo:
--   1. El técnico actualiza km/hrs del equipo (manual o vía GPS).
--   2. fn_verificar_planes_preventivos() compara con la última ejecución.
--   3. Si un equipo supera el umbral → genera alerta + opcionalmente OT.
--   4. Al cerrar la OT → se actualiza la última ejecución del plan.
-- ============================================================================

-- ============================================================================
-- 1. SEED: PAUTAS DE FABRICANTE ESTÁNDAR PARA CAMIONES PESADOS
-- ============================================================================
-- Nota: Estos intervalos son genéricos/conservadores. Se deben ajustar
-- con los manuales reales de cada fabricante. El prevencionista/jefe de
-- mantenimiento actualiza vía admin o vía sistema.

-- Función helper: insertar pauta solo si el modelo existe
DO $$
DECLARE
    v_modelo_id UUID;
    v_rec RECORD;
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            -- (nombre_modelo, pauta_nombre, tipo_plan, freq_km, freq_hrs, freq_dias, descripcion, items_checklist)
            ('Actros 3336 K',   'Cambio de aceite motor',         'por_km', 10000, 250, 90,  'Cambio de aceite motor + filtro', '["Drenar aceite usado","Reemplazar filtro aceite","Llenar aceite nuevo 15W40","Verificar nivel","Registrar km"]'),
            ('Actros 3336 K',   'Filtros de aire y combustible',  'por_km', 20000, 500, 180, 'Reemplazo filtros aire primario/secundario + combustible', '["Reemplazar filtro aire primario","Reemplazar filtro aire secundario","Reemplazar filtro combustible","Inspeccionar ductos"]'),
            ('Actros 3336 K',   'Frenos y sistema hidráulico',    'por_km', 40000, 1000, 365, 'Inspección de frenos, pastillas, líquido y mangueras', '["Medir espesor pastillas","Verificar discos/tambores","Nivel líquido frenos","Inspeccionar mangueras hidráulicas","Verificar acumulador presión"]'),
            ('Actros 3336 K',   'Engrase general',                'por_km', 5000,  125, 30,   'Engrase de puntos según carta de lubricación', '["Engrase crucetas cardan","Engrase pivotes dirección","Engrase quinta rueda","Engrase muñones"]'),
            ('Actros 3341',     'Cambio de aceite motor',         'por_km', 10000, 250, 90,  'Cambio de aceite motor + filtro', '["Drenar aceite usado","Reemplazar filtro aceite","Llenar aceite nuevo 15W40","Verificar nivel","Registrar km"]'),
            ('Actros 3341',     'Filtros de aire y combustible',  'por_km', 20000, 500, 180, 'Reemplazo filtros', '["Reemplazar filtro aire primario","Reemplazar filtro aire secundario","Reemplazar filtro combustible"]'),
            ('Actros 3341',     'Engrase general',                'por_km', 5000,  125, 30,   'Engrase de puntos', '["Engrase crucetas cardan","Engrase pivotes","Engrase quinta rueda"]'),
            ('Axor 2633',       'Cambio de aceite motor',         'por_km', 10000, 250, 90,  'Cambio aceite motor + filtro', '["Drenar aceite","Reemplazar filtro","Llenar 15W40","Verificar nivel"]'),
            ('Axor 2633',       'Filtros de aire y combustible',  'por_km', 20000, 500, 180, 'Filtros aire y combustible', '["Filtro aire primario","Filtro aire secundario","Filtro combustible"]'),
            ('Axor 2633',       'Engrase general',                'por_km', 5000,  125, 30,   'Engrase según carta', '["Crucetas","Pivotes","Quinta rueda"]'),
            ('Axor 2633/45',    'Cambio de aceite motor',         'por_km', 10000, 250, 90,  'Cambio aceite motor', '["Drenar aceite","Filtro aceite","Llenar 15W40"]'),
            ('Axor 2633/45',    'Engrase general',                'por_km', 5000,  125, 30,   'Engrase', '["Crucetas","Pivotes","Quinta rueda"]'),
            -- Scania
            ('R500',            'Cambio de aceite motor',         'por_km', 15000, 350, 120, 'Cambio aceite motor Scania', '["Drenar aceite","Filtro aceite","Llenar aceite aprobado Scania","Verificar nivel"]'),
            ('R500',            'Filtros de aire y combustible',  'por_km', 30000, 700, 240, 'Filtros', '["Filtro aire","Filtro combustible primario","Filtro combustible secundario"]'),
            ('R500',            'Engrase general',                'por_km', 10000, 250, 60,  'Engrase Scania', '["Engrase puntos carta Scania"]'),
            -- Mack
            ('Granite GU813E',  'Cambio de aceite motor',         'por_km', 12000, 300, 90,  'Cambio aceite motor Mack', '["Drenar aceite","Filtro aceite","Llenar aceite","Verificar nivel"]'),
            ('Granite GU813E',  'Filtros',                        'por_km', 24000, 600, 180, 'Filtros aire y combustible', '["Filtro aire","Filtro combustible"]'),
            ('Granite GU813E',  'Engrase general',                'por_km', 6000,  150, 30,   'Engrase', '["Engrase general según carta"]'),
            -- Volvo
            ('VM330 8x4',       'Cambio de aceite motor',         'por_km', 12000, 300, 90,  'Cambio aceite Volvo', '["Drenar aceite","Filtro aceite","Llenar aceite aprobado Volvo"]'),
            ('VM330 8x4',       'Filtros',                        'por_km', 24000, 600, 180, 'Filtros aire/comb Volvo', '["Filtro aire","Filtro combustible"]'),
            ('VM330 8x4',       'Engrase general',                'por_km', 6000,  150, 30,   'Engrase Volvo', '["Engrase general"]'),
            -- Camionetas genéricas
            ('Hilux 4x4',       'Cambio de aceite motor',         'por_km', 10000, NULL, 180, 'Cambio aceite camioneta', '["Drenar aceite","Filtro aceite","Llenar 5W30"]'),
            ('Hilux 4x4',       'Filtros de aire',                'por_km', 40000, NULL, 365, 'Filtro aire', '["Reemplazar filtro aire"]'),
            ('NP300',           'Cambio de aceite motor',         'por_km', 10000, NULL, 180, 'Cambio aceite', '["Drenar aceite","Filtro aceite","Llenar aceite"]'),
            ('Berlingo',        'Cambio de aceite motor',         'por_km', 15000, NULL, 365, 'Cambio aceite', '["Drenar aceite","Filtro aceite","Llenar aceite"]')
        ) AS t(modelo_nombre, pauta_nombre, tipo_plan, freq_km, freq_hrs, freq_dias, descripcion, items_json)
    LOOP
        SELECT id INTO v_modelo_id FROM modelos WHERE nombre = v_rec.modelo_nombre LIMIT 1;
        IF v_modelo_id IS NOT NULL THEN
            INSERT INTO pautas_fabricante (
                modelo_id, nombre, tipo_plan,
                frecuencia_km, frecuencia_horas, frecuencia_dias,
                descripcion, items_checklist, activo
            ) VALUES (
                v_modelo_id,
                v_rec.pauta_nombre,
                v_rec.tipo_plan::tipo_plan_pm_enum,
                v_rec.freq_km,
                v_rec.freq_hrs,
                v_rec.freq_dias,
                v_rec.descripcion,
                v_rec.items_json::JSONB,
                true
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;
END $$;

-- ============================================================================
-- 2. AUTO-CREAR planes_mantenimiento POR ACTIVO DESDE PAUTAS DEL MODELO
-- ============================================================================
-- Para cada activo de flota, si tiene modelo con pautas y no tiene plan
-- asociado a esa pauta, se crea uno con km_actual como punto de partida.

DO $$
DECLARE
    v_activo RECORD;
    v_pauta RECORD;
BEGIN
    FOR v_activo IN
        SELECT a.id, a.modelo_id, a.contrato_id,
               COALESCE(a.kilometraje_actual, 0) AS km_actual,
               COALESCE(a.horas_uso_actual, 0) AS hrs_actual
        FROM activos a
        WHERE a.estado != 'dado_baja'
          AND a.modelo_id IS NOT NULL
          AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil')
    LOOP
        FOR v_pauta IN
            SELECT * FROM pautas_fabricante
            WHERE modelo_id = v_activo.modelo_id AND activo = true
        LOOP
            -- Solo crear si no existe ya
            IF NOT EXISTS (
                SELECT 1 FROM planes_mantenimiento
                WHERE activo_id = v_activo.id
                  AND pauta_fabricante_id = v_pauta.id
            ) THEN
                INSERT INTO planes_mantenimiento (
                    activo_id, pauta_fabricante_id, nombre,
                    tipo_plan,
                    frecuencia_km, frecuencia_horas, frecuencia_dias,
                    ultima_ejecucion_km, ultima_ejecucion_horas, ultima_ejecucion_fecha,
                    proxima_ejecucion_fecha,
                    anticipacion_dias, prioridad, activo_plan
                ) VALUES (
                    v_activo.id,
                    v_pauta.id,
                    v_pauta.nombre,
                    v_pauta.tipo_plan,
                    v_pauta.frecuencia_km,
                    v_pauta.frecuencia_horas,
                    v_pauta.frecuencia_dias,
                    v_activo.km_actual,
                    v_activo.hrs_actual,
                    CURRENT_DATE,
                    CASE WHEN v_pauta.frecuencia_dias IS NOT NULL
                         THEN CURRENT_DATE + v_pauta.frecuencia_dias
                         ELSE NULL END,
                    7,  -- alerta 7 días antes
                    'normal',
                    true
                );
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- ============================================================================
-- 3. FUNCIÓN: VERIFICAR PLANES PREVENTIVOS POR KM/HRS
-- ============================================================================
-- Compara el km/hrs actual de cada activo con la última ejecución + frecuencia.
-- Retorna los planes vencidos o próximos a vencer.

CREATE OR REPLACE FUNCTION fn_verificar_planes_preventivos()
RETURNS TABLE (
    plan_id UUID,
    activo_id UUID,
    patente VARCHAR,
    plan_nombre VARCHAR,
    tipo_plan VARCHAR,
    km_actual NUMERIC,
    km_ultima_ejecucion NUMERIC,
    km_proxima NUMERIC,
    km_restantes NUMERIC,
    hrs_actual NUMERIC,
    hrs_ultima NUMERIC,
    hrs_proxima NUMERIC,
    hrs_restantes NUMERIC,
    fecha_proxima DATE,
    dias_restantes INTEGER,
    estado_plan VARCHAR
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        pm.id AS plan_id,
        a.id AS activo_id,
        a.patente,
        pm.nombre::VARCHAR AS plan_nombre,
        pm.tipo_plan::VARCHAR,

        COALESCE(a.kilometraje_actual, 0) AS km_actual,
        COALESCE(pm.ultima_ejecucion_km, 0) AS km_ultima_ejecucion,
        COALESCE(pm.ultima_ejecucion_km, 0) + COALESCE(pm.frecuencia_km, 0) AS km_proxima,
        CASE WHEN pm.frecuencia_km IS NOT NULL
             THEN (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km) - COALESCE(a.kilometraje_actual, 0)
             ELSE NULL END AS km_restantes,

        COALESCE(a.horas_uso_actual, 0) AS hrs_actual,
        COALESCE(pm.ultima_ejecucion_horas, 0) AS hrs_ultima,
        COALESCE(pm.ultima_ejecucion_horas, 0) + COALESCE(pm.frecuencia_horas, 0) AS hrs_proxima,
        CASE WHEN pm.frecuencia_horas IS NOT NULL
             THEN (COALESCE(pm.ultima_ejecucion_horas, 0) + pm.frecuencia_horas) - COALESCE(a.horas_uso_actual, 0)
             ELSE NULL END AS hrs_restantes,

        pm.proxima_ejecucion_fecha AS fecha_proxima,
        CASE WHEN pm.proxima_ejecucion_fecha IS NOT NULL
             THEN (pm.proxima_ejecucion_fecha - CURRENT_DATE)::INTEGER
             ELSE NULL END AS dias_restantes,

        CASE
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km)
                 THEN 'VENCIDO_KM'
            WHEN pm.frecuencia_horas IS NOT NULL
                 AND COALESCE(a.horas_uso_actual, 0) >= (COALESCE(pm.ultima_ejecucion_horas, 0) + pm.frecuencia_horas)
                 THEN 'VENCIDO_HRS'
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE
                 THEN 'VENCIDO_FECHA'
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km - 1000)
                 THEN 'PROXIMO_KM'
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE + pm.anticipacion_dias
                 THEN 'PROXIMO_FECHA'
            ELSE 'OK'
        END::VARCHAR AS estado_plan

    FROM planes_mantenimiento pm
    JOIN activos a ON a.id = pm.activo_id
    WHERE pm.activo_plan = true
      AND a.estado != 'dado_baja'
    ORDER BY
        CASE
            WHEN pm.frecuencia_km IS NOT NULL
                 AND COALESCE(a.kilometraje_actual, 0) >= (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km)
                 THEN 0  -- Vencido por km primero
            WHEN pm.proxima_ejecucion_fecha IS NOT NULL
                 AND pm.proxima_ejecucion_fecha <= CURRENT_DATE
                 THEN 1  -- Vencido por fecha
            ELSE 2
        END,
        COALESCE(
            CASE WHEN pm.frecuencia_km IS NOT NULL
                 THEN (COALESCE(pm.ultima_ejecucion_km, 0) + pm.frecuencia_km) - COALESCE(a.kilometraje_actual, 0)
                 ELSE NULL END,
            999999
        );
END;
$$;

COMMENT ON FUNCTION fn_verificar_planes_preventivos() IS
    'Retorna todos los planes de mantención con su estado (VENCIDO_KM, VENCIDO_HRS, VENCIDO_FECHA, PROXIMO_KM, PROXIMO_FECHA, OK) para que el jefe de mantenimiento priorice las intervenciones.';
