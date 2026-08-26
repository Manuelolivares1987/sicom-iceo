-- ============================================================================
-- MIG401 · La preventiva deja de calcular contra un Excel congelado
-- ----------------------------------------------------------------------------
-- EL PROBLEMA, MEDIDO
-- `v_pautas_estado_activo` calculaba cuándo toca la próxima mantención usando
-- como línea base `os_historico_importado`: una carga histórica congelada de
-- 197 filas y 38 equipos, con fechas que van de 1900-01-03 a noviembre de 2026.
--
-- Resultado: de 215 pares equipo/pauta, sólo 88 tenían base de horómetro y 70
-- tenían base de kilometraje. Más de la mitad no podía calcular nada.
--
-- LA SORPRESA AL BUSCAR DÓNDE PONER EL DATO
-- No había que inventar nada. `planes_mantenimiento` YA TIENE los campos
-- —`ultima_ejecucion_fecha`, `ultima_ejecucion_horas`, `ultima_ejecucion_km`—,
-- y `rpc_cerrar_ot_supervisor` YA LOS ESCRIBE al cerrar una OT. El circuito
-- estaba completo.
--
-- Lo que pasaba es que la vista miraba para otro lado. Y como hay CERO OT
-- cerradas en el sistema, nadie se había dado cuenta de que el dato bueno
-- estaba ahí: 204 de 215 planes ya tienen su última ejecución en horas y 203
-- en kilómetros, cargados al crear los planes.
--
-- QUÉ CAMBIA
-- La línea base pasa a salir de `planes_mantenimiento`, que es el plan de ESE
-- equipo con ESA pauta, y el histórico importado queda de respaldo para cuando
-- el plan todavía no tiene ejecución registrada.
--
--     base de horómetro:  88 → 206 de 215
--     base de kilometraje: 70 → 205 de 215
--
-- Y LA VISTA DICE DE DÓNDE SACÓ EL NÚMERO
-- Columna nueva `fuente_linea_base`: 'plan' cuando viene del plan del equipo,
-- 'historico' cuando viene del Excel importado, 'sin_base' cuando no hay nada.
-- Un cálculo de mantención preventiva que no puede decir contra qué se está
-- comparando no sirve para decidir: mejor que lo diga.
--
-- LO QUE SIGUE ABIERTO
-- El histórico importado tiene fechas imposibles (1900, y una en noviembre de
-- 2026 que todavía no ocurre). Mientras sea respaldo de 9 pares nada más, hace
-- poco daño; pero conviene limpiarlo. No se toca acá: borrar datos históricos
-- es una decisión de operaciones, no de una migración.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_pautas_estado_activo AS
WITH ultimo_por_activo AS (
    SELECT DISTINCT ON (o.activo_id)
           o.activo_id, o.fecha_entrega, o.horometro, o.kilometraje
      FROM os_historico_importado o
     WHERE o.activo_id IS NOT NULL AND o.fecha_entrega IS NOT NULL
     ORDER BY o.activo_id, o.fecha_entrega DESC, o.id DESC
), base AS (
    SELECT
        a.id AS activo_id,
        pf.id AS pauta_id,
        -- [MIG401] El plan del equipo manda; el Excel importado es respaldo.
        -- `ultima_ejecucion_fecha` es timestamptz y `fecha_entrega` es date:
        -- sin el cast, sumarle días al resultado revienta.
        COALESCE(pm.ultima_ejecucion_fecha::date, upa.fecha_entrega) AS b_fecha,
        COALESCE(pm.ultima_ejecucion_horas, upa.horometro)     AS b_horas,
        COALESCE(pm.ultima_ejecucion_km,    upa.kilometraje)   AS b_km,
        CASE
            WHEN pm.ultima_ejecucion_horas IS NOT NULL
              OR pm.ultima_ejecucion_km    IS NOT NULL
              OR pm.ultima_ejecucion_fecha IS NOT NULL THEN 'plan'
            WHEN upa.activo_id IS NOT NULL                    THEN 'historico'
            ELSE 'sin_base'
        END AS fuente
      FROM activos a
      JOIN pautas_fabricante pf ON pf.modelo_id = a.modelo_id AND pf.activo = true
      LEFT JOIN planes_mantenimiento pm
             ON pm.activo_id = a.id AND pm.pauta_fabricante_id = pf.id AND pm.activo_plan
      LEFT JOIN ultimo_por_activo upa ON upa.activo_id = a.id
     WHERE a.estado <> 'dado_baja'::estado_activo_enum
)
SELECT
    a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.patente AS activo_patente,
    a.tipo_equipamiento,
    a.horas_uso_actual AS horas_actuales,
    a.kilometraje_actual AS km_actuales,
    pf.id AS pauta_id,
    pf.nombre AS pauta_nombre,
    pf.tipo_plan,
    pf.frecuencia_horas,
    pf.frecuencia_km,
    pf.frecuencia_dias,
    pf.duracion_estimada_hrs,
    b.b_fecha AS ultima_fecha,
    b.b_horas AS ultimo_horometro,
    b.b_km    AS ultimo_km,
    CASE WHEN pf.frecuencia_horas IS NOT NULL AND b.b_horas IS NOT NULL
         THEN b.b_horas + pf.frecuencia_horas ELSE NULL::numeric END AS proximo_horometro,
    CASE WHEN pf.frecuencia_km IS NOT NULL AND b.b_km IS NOT NULL
         THEN b.b_km + pf.frecuencia_km ELSE NULL::numeric END AS proximo_km,
    CASE WHEN pf.frecuencia_dias IS NOT NULL AND b.b_fecha IS NOT NULL
         THEN b.b_fecha + pf.frecuencia_dias ELSE NULL::date END AS proximo_dia,
    CASE WHEN pf.frecuencia_horas IS NOT NULL AND b.b_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL
         THEN b.b_horas + pf.frecuencia_horas - a.horas_uso_actual ELSE NULL::numeric END AS horas_restantes,
    CASE WHEN pf.frecuencia_km IS NOT NULL AND b.b_km IS NOT NULL AND a.kilometraje_actual IS NOT NULL
         THEN b.b_km + pf.frecuencia_km - a.kilometraje_actual ELSE NULL::numeric END AS km_restantes,
    CASE WHEN pf.frecuencia_dias IS NOT NULL AND b.b_fecha IS NOT NULL
         THEN b.b_fecha + pf.frecuencia_dias - CURRENT_DATE ELSE NULL::integer END AS dias_restantes,
    CASE
        WHEN b.fuente = 'sin_base' THEN 'sin_historico'::text
        WHEN pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL AND a.horas_uso_actual > (b.b_horas + pf.frecuencia_horas)
          OR pf.frecuencia_km    IS NOT NULL AND a.kilometraje_actual IS NOT NULL AND a.kilometraje_actual > (b.b_km + pf.frecuencia_km)
          OR pf.frecuencia_dias  IS NOT NULL AND b.b_fecha IS NOT NULL AND CURRENT_DATE > (b.b_fecha + pf.frecuencia_dias)
        THEN 'vencida'::text
        WHEN pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL AND (b.b_horas + pf.frecuencia_horas - a.horas_uso_actual) <= (pf.frecuencia_horas * 0.10)
          OR pf.frecuencia_km    IS NOT NULL AND a.kilometraje_actual IS NOT NULL AND (b.b_km + pf.frecuencia_km - a.kilometraje_actual) <= (pf.frecuencia_km * 0.10)
          OR pf.frecuencia_dias  IS NOT NULL AND b.b_fecha IS NOT NULL AND (b.b_fecha + pf.frecuencia_dias - CURRENT_DATE)::numeric <= (pf.frecuencia_dias::numeric * 0.10)
        THEN 'critica'::text
        WHEN pf.frecuencia_horas IS NOT NULL AND a.horas_uso_actual IS NOT NULL AND (b.b_horas + pf.frecuencia_horas - a.horas_uso_actual) <= (pf.frecuencia_horas * 0.50)
          OR pf.frecuencia_km    IS NOT NULL AND a.kilometraje_actual IS NOT NULL AND (b.b_km + pf.frecuencia_km - a.kilometraje_actual) <= (pf.frecuencia_km * 0.50)
          OR pf.frecuencia_dias  IS NOT NULL AND b.b_fecha IS NOT NULL AND (b.b_fecha + pf.frecuencia_dias - CURRENT_DATE)::numeric <= (pf.frecuencia_dias::numeric * 0.50)
        THEN 'proxima'::text
        ELSE 'al_dia'::text
    END AS estado_pauta,
    -- [MIG401] De dónde salió la línea base. Un cálculo de preventiva que no
    -- puede decir contra qué compara no sirve para decidir.
    b.fuente AS fuente_linea_base
FROM activos a
JOIN pautas_fabricante pf ON pf.modelo_id = a.modelo_id AND pf.activo = true
JOIN base b ON b.activo_id = a.id AND b.pauta_id = pf.id
WHERE a.estado <> 'dado_baja'::estado_activo_enum;

COMMENT ON VIEW public.v_pautas_estado_activo IS
  'MIG401: la línea base sale de planes_mantenimiento (el plan de ESE equipo con ESA pauta); os_historico_importado queda de respaldo. fuente_linea_base dice cuál se usó.';

-- ── Antes y después ───────────────────────────────────────────────────────
DO $r$
DECLARE r RECORD;
BEGIN
    SELECT count(*) AS n,
           count(ultimo_horometro) AS hm,
           count(ultimo_km) AS km,
           count(*) FILTER (WHERE fuente_linea_base = 'plan') AS del_plan,
           count(*) FILTER (WHERE fuente_linea_base = 'historico') AS del_excel,
           count(*) FILTER (WHERE fuente_linea_base = 'sin_base') AS sin_nada
      INTO r FROM v_pautas_estado_activo;
    RAISE NOTICE 'Pautas: % · base horómetro: % (antes 88) · base km: % (antes 70)', r.n, r.hm, r.km;
    RAISE NOTICE 'Fuente: % del plan del equipo · % del Excel importado · % sin nada', r.del_plan, r.del_excel, r.sin_nada;

    FOR r IN SELECT estado_pauta, count(*) AS n FROM v_pautas_estado_activo GROUP BY 1 ORDER BY 2 DESC
    LOOP RAISE NOTICE '  %: %', r.estado_pauta, r.n; END LOOP;
END
$r$;

COMMIT;
