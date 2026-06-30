-- ============================================================================
-- 174_preventivas_multieje.sql
-- ----------------------------------------------------------------------------
-- Afinar "las preventivas que se vienen".
--
-- Problema: el planificador y el plan semanal listan preventivas con
-- getPreventivasDue(), que filtra SOLO por planes_mantenimiento.proxima_ejecucion_fecha.
-- Pero 206 de 212 planes son por_horas / por_kilometraje / mixto, y al cerrar la
-- OT su proxima_ejecucion_fecha no se recalcula (solo si hay frecuencia_dias).
-- Resultado: la mayoria de las preventivas por km/horas NUNCA aparecian como
-- proximas.
--
-- Solucion: vista v_taller_preventivas_due que evalua los 3 ejes (fecha, km,
-- horas) tomando el mas critico, calculando km/horas restantes contra el
-- kilometraje/horas ACTUALES del activo (no depende de proxima_ejecucion_fecha).
--
-- ADITIVA. Solo crea una vista. Re-ejecutable.
-- ============================================================================

CREATE OR REPLACE VIEW v_taller_preventivas_due AS
WITH base AS (
    SELECT
        pm.id                         AS plan_id,
        pm.activo_id,
        pm.nombre                     AS plan_nombre,
        pm.tipo_plan::text            AS tipo_plan,
        pm.prioridad::text            AS prioridad,
        a.patente,
        a.codigo,
        a.nombre                      AS equipamiento,
        a.kilometraje_actual,
        a.horas_uso_actual,
        pf.nombre                     AS pauta_nombre,
        pf.duracion_estimada_hrs,
        pm.frecuencia_dias,
        pm.frecuencia_km,
        pm.frecuencia_horas,
        pm.anticipacion_dias,
        -- Fecha de vencimiento (eje fecha): proxima persistida o ultima+frecuencia
        COALESCE(pm.proxima_ejecucion_fecha,
                 (pm.ultima_ejecucion_fecha::date + pm.frecuencia_dias)) AS vencimiento_fecha,
        -- Objetivo km/horas = ultima ejecucion + frecuencia
        CASE WHEN pm.frecuencia_km IS NOT NULL AND pm.ultima_ejecucion_km IS NOT NULL
             THEN pm.ultima_ejecucion_km + pm.frecuencia_km END        AS km_objetivo,
        CASE WHEN pm.frecuencia_horas IS NOT NULL AND pm.ultima_ejecucion_horas IS NOT NULL
             THEN pm.ultima_ejecucion_horas + pm.frecuencia_horas END  AS horas_objetivo
    FROM planes_mantenimiento pm
    JOIN activos a              ON a.id = pm.activo_id
    LEFT JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
    WHERE pm.activo_plan = true
),
calc AS (
    SELECT b.*,
        CASE WHEN b.vencimiento_fecha IS NOT NULL
             THEN (b.vencimiento_fecha - CURRENT_DATE) END                  AS dias_restante,
        CASE WHEN b.km_objetivo IS NOT NULL AND b.kilometraje_actual IS NOT NULL
             THEN (b.km_objetivo - b.kilometraje_actual) END                AS km_restante,
        CASE WHEN b.horas_objetivo IS NOT NULL AND b.horas_uso_actual IS NOT NULL
             THEN (b.horas_objetivo - b.horas_uso_actual) END               AS horas_restante
    FROM base b
),
frac AS (
    SELECT c.*,
        CASE WHEN c.dias_restante IS NOT NULL AND c.frecuencia_dias > 0
             THEN c.dias_restante::numeric / c.frecuencia_dias END   AS frac_dias,
        CASE WHEN c.km_restante IS NOT NULL AND c.frecuencia_km > 0
             THEN c.km_restante / c.frecuencia_km END                AS frac_km,
        CASE WHEN c.horas_restante IS NOT NULL AND c.frecuencia_horas > 0
             THEN c.horas_restante / c.frecuencia_horas END          AS frac_horas
    FROM calc c
),
ev AS (
    SELECT f.*,
        LEAST(COALESCE(f.frac_dias, 9999), COALESCE(f.frac_km, 9999), COALESCE(f.frac_horas, 9999)) AS frac_min,
        (COALESCE(f.dias_restante, 1) <= 0
         OR COALESCE(f.km_restante, 1) <= 0
         OR COALESCE(f.horas_restante, 1) <= 0)                      AS vencida,
        CASE
            WHEN COALESCE(f.frac_dias, 9999) <= LEAST(COALESCE(f.frac_km, 9999), COALESCE(f.frac_horas, 9999)) THEN 'fecha'
            WHEN COALESCE(f.frac_km, 9999)   <= COALESCE(f.frac_horas, 9999) THEN 'km'
            ELSE 'horas'
        END AS eje_critico
    FROM frac f
    -- Solo planes con al menos un eje evaluable
    WHERE f.dias_restante IS NOT NULL OR f.km_restante IS NOT NULL OR f.horas_restante IS NOT NULL
)
SELECT
    plan_id, activo_id, plan_nombre, tipo_plan, prioridad,
    patente, codigo, equipamiento,
    kilometraje_actual, horas_uso_actual,
    pauta_nombre, duracion_estimada_hrs,
    frecuencia_dias, frecuencia_km, frecuencia_horas, anticipacion_dias,
    vencimiento_fecha AS proxima_fecha,
    dias_restante, km_restante, horas_restante,
    frac_min, vencida, eje_critico,
    -- Criticidad: MAYOR = mas urgente (para dedup/orden en el frontend)
    CASE WHEN vencida
         THEN 1000 + LEAST(900, GREATEST(0, ROUND(-frac_min * 100)))
         ELSE 100 - LEAST(100, GREATEST(0, ROUND(frac_min * 100)))
    END AS criticidad,
    -- Texto legible del eje critico
    CASE eje_critico
        WHEN 'fecha' THEN CASE WHEN COALESCE(dias_restante, 1) <= 0
                               THEN 'Vencida hace ' || ABS(dias_restante) || ' días'
                               ELSE 'Faltan ' || dias_restante || ' días' END
        WHEN 'km'    THEN CASE WHEN COALESCE(km_restante, 1) <= 0
                               THEN 'Vencida por ' || ABS(ROUND(km_restante)) || ' km'
                               ELSE 'Faltan ' || ROUND(km_restante) || ' km' END
        ELSE              CASE WHEN COALESCE(horas_restante, 1) <= 0
                               THEN 'Vencida por ' || ABS(ROUND(horas_restante)) || ' h'
                               ELSE 'Faltan ' || ROUND(horas_restante) || ' h' END
    END AS detalle,
    -- Linea base confiable: la magnitud del eje critico no excede 3 ciclos
    -- (si lo excede, la ultima_ejecucion_km/horas del plan esta desfasada y
    --  hay que corregir la lectura antes de confiar en el vencimiento km/horas).
    NOT (
        (eje_critico = 'km'    AND frecuencia_km    > 0 AND ABS(km_restante)    > frecuencia_km    * 3)
     OR (eje_critico = 'horas' AND frecuencia_horas > 0 AND ABS(horas_restante) > frecuencia_horas * 3)
    ) AS baseline_confiable
FROM ev;

GRANT SELECT ON v_taller_preventivas_due TO authenticated;

COMMENT ON VIEW v_taller_preventivas_due IS
    'Preventivas vencidas/proximas evaluando los 3 ejes (fecha/km/horas), eje mas critico. '
    'km/horas restantes contra el valor ACTUAL del activo (no depende de proxima_ejecucion_fecha). MIG174.';

-- ── Validacion ──────────────────────────────────────────────────────────────
DO $$
DECLARE v_n INT; v_venc INT;
BEGIN
    SELECT COUNT(*), COUNT(*) FILTER (WHERE vencida) INTO v_n, v_venc FROM v_taller_preventivas_due;
    RAISE NOTICE '== MIG174 OK == v_taller_preventivas_due: % planes evaluables, % vencidos', v_n, v_venc;
END $$;

NOTIFY pgrst, 'reload schema';
