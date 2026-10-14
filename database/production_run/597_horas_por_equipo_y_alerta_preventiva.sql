-- ============================================================================
-- SICOM-ICEO | 597 — Horas de cada equipo, próximo preventivo y alerta
-- ============================================================================
-- El horómetro del GPS ya llegaba a activos.horas_uso_actual, pero no quedaba
-- registro por día. El ritmo de uso se calculaba desde la última mantención,
-- y un equipo que estuvo parado meses daba fechas absurdas (JTYK-88: próxima
-- SM2 en el año 2100). Y los preventivos vencidos o por vencer no avisaban a
-- nadie: 17 vencidos y 4 a menos de 50 h el 14-10-2026.
--
--   1. activo_horas_dia: una fila por equipo y día con el primer y último
--      horómetro/odómetro del GPS. La llena un trigger sobre gps_eventos_log
--      (~30 lecturas al día, costo despreciable) + carga de lo ya registrado.
--   2. v_equipo_horas: la tabla de horas. Ritmo = últimos 30 días medidos;
--      próximo preventivo = el peldaño de la escalera que toca primero, y si
--      coinciden varios, el mayor (absorción, MIG513).
--   3. fn_alertas_preventivas_horas(): campanita al jefe de mantenimiento y
--      planificadores cuando faltan ≤ 50 h o ya venció. Una alerta por plan,
--      nivel y ciclo (no se repite cada día). Cron diario 06:30 de Chile (09:30 UTC), después del
--      contador GPS de las 05:00.
--
-- ADITIVA.
-- ============================================================================


-- ############################################################################
-- 1. HORAS POR DÍA
-- ############################################################################

CREATE TABLE IF NOT EXISTS activo_horas_dia (
    activo_id     UUID    NOT NULL REFERENCES activos(id) ON DELETE CASCADE,
    fecha         DATE    NOT NULL,          -- día en hora de Chile
    horometro_ini NUMERIC,
    horometro_fin NUMERIC,
    km_ini        NUMERIC,
    km_fin        NUMERIC,
    lecturas      INTEGER NOT NULL DEFAULT 0,
    actualizado_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (activo_id, fecha)
);

COMMENT ON TABLE activo_horas_dia IS
    'Horómetro y odómetro GPS por equipo y día (primera y última lectura). MIG597.';

ALTER TABLE activo_horas_dia ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_activo_horas_dia_select ON activo_horas_dia;
CREATE POLICY pol_activo_horas_dia_select ON activo_horas_dia
    FOR SELECT TO authenticated USING (true);
REVOKE INSERT, UPDATE, DELETE ON activo_horas_dia FROM anon, authenticated;


CREATE OR REPLACE FUNCTION fn_activo_horas_dia_registrar()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.activo_id IS NULL OR coalesce(NEW.horometro_hrs, 0) <= 0 THEN
        RETURN NEW;
    END IF;
    INSERT INTO activo_horas_dia AS h (activo_id, fecha, horometro_ini, horometro_fin,
                                       km_ini, km_fin, lecturas)
    VALUES (NEW.activo_id, (NEW.ts_gps AT TIME ZONE 'America/Santiago')::DATE,
            NEW.horometro_hrs, NEW.horometro_hrs,
            nullif(NEW.odometro_km, 0), nullif(NEW.odometro_km, 0), 1)
    ON CONFLICT (activo_id, fecha) DO UPDATE SET
        horometro_ini = least(h.horometro_ini, EXCLUDED.horometro_ini),
        horometro_fin = greatest(h.horometro_fin, EXCLUDED.horometro_fin),
        km_ini = least(h.km_ini, EXCLUDED.km_ini),
        km_fin = greatest(h.km_fin, EXCLUDED.km_fin),
        lecturas = h.lecturas + 1,
        actualizado_at = NOW();
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_gps_eventos_horas_dia ON gps_eventos_log;
CREATE TRIGGER trg_gps_eventos_horas_dia
    AFTER INSERT ON gps_eventos_log
    FOR EACH ROW EXECUTE FUNCTION fn_activo_horas_dia_registrar();

-- Lo ya registrado (desde mayo 2026).
INSERT INTO activo_horas_dia (activo_id, fecha, horometro_ini, horometro_fin, km_ini, km_fin, lecturas)
SELECT activo_id, (ts_gps AT TIME ZONE 'America/Santiago')::DATE,
       min(horometro_hrs), max(horometro_hrs),
       min(nullif(odometro_km, 0)), max(nullif(odometro_km, 0)), count(*)
  FROM gps_eventos_log
 WHERE activo_id IS NOT NULL AND horometro_hrs > 0
 GROUP BY 1, 2
ON CONFLICT (activo_id, fecha) DO NOTHING;


-- ############################################################################
-- 2. TABLA DE HORAS + PRÓXIMO PREVENTIVO
-- ############################################################################

-- Horas trabajadas cada día = último horómetro del día − último del día
-- anterior con dato (cubre los días sin lectura). Un salto > 24 h por día de
-- diferencia no es uso: es un cambio de equipo GPS o un error; se descarta.
CREATE OR REPLACE VIEW v_activo_horas_dia AS
SELECT h.activo_id, h.fecha, h.horometro_fin, h.km_fin, h.lecturas,
       CASE
           WHEN p.horometro_fin IS NULL THEN NULL
           WHEN h.horometro_fin - p.horometro_fin < 0 THEN NULL
           WHEN h.horometro_fin - p.horometro_fin > 24 * (h.fecha - p.fecha) THEN NULL
           ELSE round(h.horometro_fin - p.horometro_fin, 1)
       END AS horas,
       CASE
           WHEN p.km_fin IS NULL OR h.km_fin IS NULL THEN NULL
           WHEN h.km_fin - p.km_fin < 0 OR h.km_fin - p.km_fin > 1500 * (h.fecha - p.fecha) THEN NULL
           ELSE round(h.km_fin - p.km_fin)
       END AS km,
       h.fecha - p.fecha AS dias_desde_anterior
  FROM activo_horas_dia h
  LEFT JOIN LATERAL (SELECT a.fecha, a.horometro_fin, a.km_fin FROM activo_horas_dia a
                      WHERE a.activo_id = h.activo_id AND a.fecha < h.fecha
                      ORDER BY a.fecha DESC LIMIT 1) p ON TRUE;

COMMENT ON VIEW v_activo_horas_dia IS
    'Horas y km trabajados por equipo y día (diferencia contra el día anterior con dato). MIG597.';
GRANT SELECT ON v_activo_horas_dia TO authenticated;


CREATE OR REPLACE VIEW v_equipo_horas AS
WITH hoy AS (SELECT (NOW() AT TIME ZONE 'America/Santiago')::DATE AS d),
uso AS (
    SELECT d.activo_id,
           sum(d.horas) FILTER (WHERE d.fecha = (SELECT d FROM hoy) - 1)       AS horas_ayer,
           sum(d.horas) FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 7)       AS horas_7d,
           sum(d.horas) FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 30)      AS horas_30d,
           sum(d.km)    FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 30)      AS km_30d,
           count(*)     FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 30 AND d.horas > 0.5) AS dias_con_uso_30d,
           -- Ritmo: horas medidas en la ventana ÷ días cubiertos por esas lecturas.
           sum(d.horas) FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 30)
             / nullif(sum(d.dias_desde_anterior) FILTER (WHERE d.fecha > (SELECT d FROM hoy) - 30
                                                          AND d.horas IS NOT NULL), 0) AS ritmo_30d,
           max(d.fecha) AS ultima_lectura
      FROM v_activo_horas_dia d
     WHERE d.fecha > (SELECT d FROM hoy) - 60
     GROUP BY d.activo_id
),
planes AS (
    SELECT e.*, pm.pauta_fabricante_id
      FROM v_plan_mantenimiento_estado e
      JOIN planes_mantenimiento pm ON pm.id = e.plan_id AND pm.activo_plan
     WHERE e.frecuencia_horas IS NOT NULL
       AND NOT e.sin_base_horas AND NOT e.horometro_inconsistente
       AND e.horas_faltan IS NOT NULL
),
proximo AS (
    -- El peldaño que toca primero; si varios coinciden (±1 h), el mayor absorbe.
    SELECT DISTINCT ON (p.activo_id)
           p.activo_id, p.plan_id, p.nombre AS pauta, p.frecuencia_horas, p.horas_faltan,
           p.ult_fecha, p.ult_horas
      FROM planes p
      JOIN (SELECT activo_id, min(horas_faltan) AS m FROM planes GROUP BY activo_id) mm
        ON mm.activo_id = p.activo_id AND p.horas_faltan <= mm.m + 1
     ORDER BY p.activo_id, p.frecuencia_horas DESC
)
SELECT a.id AS activo_id, a.patente, a.codigo, a.nombre, a.tipo::TEXT AS tipo,
       a.tipo_equipamiento::TEXT AS tipo_equipamiento,
       f.nombre AS faena,
       a.horas_uso_actual AS horometro,
       a.kilometraje_actual AS odometro,
       g.ts_gps AS gps_ultima_senal,
       u.ultima_lectura,
       round(u.horas_ayer, 1) AS horas_ayer,
       round(u.horas_7d, 1) AS horas_7d,
       round(u.horas_30d, 1) AS horas_30d,
       round(u.km_30d) AS km_30d,
       u.dias_con_uso_30d,
       CASE WHEN u.ritmo_30d > 24 THEN NULL ELSE round(u.ritmo_30d, 2) END AS horas_por_dia,
       pr.plan_id, pr.pauta AS proxima_pauta, pr.frecuencia_horas,
       round(pr.horas_faltan, 1) AS horas_faltan,
       pr.ult_fecha AS ultima_preventiva_fecha, pr.ult_horas AS ultima_preventiva_horas,
       CASE
           WHEN pr.horas_faltan IS NULL OR pr.horas_faltan < -2 * pr.frecuencia_horas THEN NULL
           WHEN pr.horas_faltan <= 0 THEN (SELECT d FROM hoy)
           WHEN coalesce(u.ritmo_30d, 0) < 0.2 OR u.ritmo_30d > 24 THEN NULL   -- sin uso medible
           ELSE (SELECT d FROM hoy) + ceil(pr.horas_faltan / u.ritmo_30d)::INTEGER
       END AS fecha_estimada,
       CASE
           WHEN pr.horas_faltan IS NULL THEN 'sin_plan'
           -- Atrasado en más de dos ciclos completos: no es un atraso, es una
           -- línea base mala (horómetro mal digitado o plan sembrado en 0).
           -- Se pide revisar en vez de alertar todos los días.
           WHEN pr.horas_faltan < -2 * pr.frecuencia_horas THEN 'revisar_base'
           WHEN pr.horas_faltan <= 0 THEN 'vencida'
           WHEN pr.horas_faltan <= 50 THEN 'proxima'
           WHEN pr.horas_faltan <= 100 THEN 'atento'
           ELSE 'al_dia'
       END AS estado_preventiva,
       (SELECT o.folio FROM ordenes_trabajo o
         WHERE o.plan_mantenimiento_id = pr.plan_id
           AND o.estado IN ('creada','asignada','en_ejecucion','pausada')
         ORDER BY o.fecha_programada NULLS LAST LIMIT 1) AS ot_abierta
  FROM activos a
  LEFT JOIN faenas f ON f.id = a.faena_id
  LEFT JOIN gps_estado_actual g ON g.activo_id = a.id
  LEFT JOIN uso u ON u.activo_id = a.id
  LEFT JOIN proximo pr ON pr.activo_id = a.id
 WHERE NOT coalesce(a.es_prueba, false)
   AND a.fecha_baja IS NULL
   AND (pr.plan_id IS NOT NULL OR coalesce(a.horas_uso_actual, 0) > 0 OR u.activo_id IS NOT NULL);

COMMENT ON VIEW v_equipo_horas IS
    'Tabla de horas por equipo: uso medido (GPS) y próximo preventivo por horas con fecha estimada. MIG597.';
GRANT SELECT ON v_equipo_horas TO authenticated;


-- ############################################################################
-- 3. ALERTA DE PREVENTIVO
-- ############################################################################

ALTER TABLE alertas DROP CONSTRAINT IF EXISTS chk_alertas_tipo;
ALTER TABLE alertas ADD CONSTRAINT chk_alertas_tipo CHECK (tipo = ANY (ARRAY[
    'vencimiento','stock_minimo','ot_vencida','incumplimiento','bloqueante',
    'antiguedad_vehiculo','semep_vencido','fatiga_conductor','rt_por_vencer',
    'hermeticidad_vencida','sec_no_vigente','sensor_fuga','accidente_no_reportado',
    'jornada_excedida','pts_faltante','disponibilidad_vencida','gps_sin_senal',
    'no_conformidad','recurso_solicitado','recurso_por_comprar','recurso_recibido',
    'vale_emitido','doc_por_vencer','doc_vencido','doc_vencidos_equipo','doc_sin_fecha',
    'plan_papeles_equipo','preventiva_horas']));

-- Número a la chilena (punto de miles, coma decimal), sin depender del locale.
CREATE OR REPLACE FUNCTION fn_num_cl(p NUMERIC, p_dec INTEGER DEFAULT 0)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p IS NULL THEN NULL ELSE
        translate(to_char(round(p, p_dec),
                  'FM999,999,990' || CASE WHEN p_dec > 0 THEN '.' || repeat('0', p_dec) ELSE '' END),
                  ',.', '.,') END;
$$;

CREATE OR REPLACE FUNCTION fn_alertas_preventivas_horas()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    r RECORD;
    v_sev TEXT;
    v_n INTEGER := 0;
BEGIN
    FOR r IN
        SELECT * FROM v_equipo_horas
         WHERE estado_preventiva IN ('vencida', 'proxima')
    LOOP
        v_sev := CASE WHEN r.estado_preventiva = 'vencida' THEN 'critical' ELSE 'warning' END;

        -- Una vez por plan, nivel y ciclo: si ya se avisó con esta severidad
        -- después de la última preventiva hecha, no se repite.
        IF EXISTS (SELECT 1 FROM alertas al
                    WHERE al.tipo = 'preventiva_horas' AND al.entidad_id = r.plan_id
                      AND al.severidad = v_sev
                      AND al.created_at >= coalesce(r.ultima_preventiva_fecha::TIMESTAMPTZ, '-infinity')) THEN
            CONTINUE;
        END IF;

        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                             destinatario_id, requiere_accion)
        SELECT 'preventiva_horas',
               CASE WHEN r.estado_preventiva = 'vencida'
                    THEN format('%s: %s vencida por %s h', coalesce(r.patente, r.codigo), r.proxima_pauta,
                                fn_num_cl(abs(r.horas_faltan), 0))
                    ELSE format('%s: %s en %s h', coalesce(r.patente, r.codigo), r.proxima_pauta,
                                fn_num_cl(r.horas_faltan, 0))
               END,
               format(E'Horómetro %s h · ritmo %s h/día · %s.\n%s',
                      fn_num_cl(r.horometro, 0),
                      coalesce(fn_num_cl(r.horas_por_dia, 1), 'sin uso medido'),
                      CASE WHEN r.fecha_estimada IS NOT NULL
                           THEN 'fecha estimada ' || to_char(r.fecha_estimada, 'DD-MM-YYYY')
                           ELSE 'sin fecha estimada' END,
                      CASE WHEN r.ot_abierta IS NOT NULL
                           THEN 'Ya tiene OT abierta: ' || r.ot_abierta || '.'
                           ELSE 'No tiene OT abierta: hay que programarla.' END),
               v_sev, 'plan_mantenimiento', r.plan_id, up.id, TRUE
          FROM usuarios_perfil up
         WHERE coalesce(up.activo, TRUE)
           AND up.rol IN ('jefe_mantenimiento', 'planificador');
        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('planes_avisados', v_n);
END $$;

COMMENT ON FUNCTION fn_alertas_preventivas_horas() IS
    'Campanita de preventivo por horas (≤ 50 h o vencido) a jefe de mantenimiento y planificadores. MIG597.';

SELECT cron.unschedule('alertas-preventivas-horas')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'alertas-preventivas-horas');
SELECT cron.schedule('alertas-preventivas-horas', '30 9 * * *', 'SELECT fn_alertas_preventivas_horas()');
