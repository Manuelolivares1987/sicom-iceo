-- ============================================================================
-- MIG717 — La agenda de faena ve las mantenciones hechas en Coquimbo (19-11-2026)
-- ----------------------------------------------------------------------------
-- v_faena_pauta_agenda (MIG359) buscaba la «última mantención» en:
--   1) la última pauta de faena cerrada, o
--   2) un plan de Coquimbo con frecuencia EXACTAMENTE igual al disparo de la
--      pauta (300 h) y activo_plan = true.
-- MIG358 apagó los planes de 300 h (SL y «Servicio programado 300 h») y el
-- taller de Coquimbo registra los servicios mayores (SM2 1200 h, SM3 2400 h),
-- así que los Mack de Franke salían «Falta la última mantención» aunque
-- Coquimbo les hizo el SM3 el 16-10 (LCSX-78) y el SM2+SM3 el 12-11 (HHWB-44).
--
-- Ahora:
--   - Cuenta cualquier plan del equipo cuya frecuencia sea MÚLTIPLO del disparo
--     (un SM3 de 2400 h incluye el servicio de 300 h — escalera), esté o no
--     activo, porque lo que importa es la ejecución registrada.
--   - Entre la pauta de faena y el plan de Coquimbo gana la MÁS NUEVA (mayor
--     horómetro / km), no siempre la de faena.
-- Solo cambia una vista de lectura. Mismas columnas, mismo orden.
-- Autorizado por Manuel 19-11.
-- ============================================================================

CREATE OR REPLACE VIEW public.v_faena_pauta_agenda AS
SELECT a.faena_id,
    a.id AS activo_id,
    a.codigo AS activo_codigo,
    a.patente,
    a.nombre AS activo_nombre,
    a.estado AS activo_estado,
    mo.nombre AS modelo,
    a.horas_uso_actual,
    a.kilometraje_actual,
    p.id AS pauta_id,
    p.codigo AS pauta_codigo,
    p.nombre AS pauta_nombre,
    p.tipo AS pauta_tipo,
    p.disparo_horas,
    p.disparo_km,
    p.aviso_horas,
    p.aviso_km,
    (( SELECT count(*) AS count
           FROM faena_pauta_item i
          WHERE i.pauta_id = p.id))::integer AS items,
    u.horometro AS ultima_horometro,
    u.kilometraje AS ultima_kilometraje,
    u.fecha AS ultima_fecha,
    u.origen AS origen_ultima,
        CASE
            WHEN p.disparo_horas IS NOT NULL THEN round(u.horometro + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_horas,
        CASE
            WHEN p.disparo_km IS NOT NULL THEN round(u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_km,
        CASE
            WHEN p.tipo = 'diaria'::text THEN 'diaria'::text
            WHEN u.horometro IS NULL AND u.kilometraje IS NULL THEN 'sin_datos'::text
            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas) <= COALESCE(a.horas_uso_actual, 0::numeric)
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km) <= COALESCE(a.kilometraje_actual, 0::numeric) THEN 'vencida'::text
            WHEN p.disparo_horas IS NOT NULL AND (u.horometro + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric)) <= p.aviso_horas
              OR p.disparo_km IS NOT NULL AND (u.kilometraje + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric)) <= p.aviso_km THEN 'por_vencer'::text
            ELSE 'al_dia'::text
        END AS senal,
    hoy.id AS ejecucion_hoy_id,
    hoy.estado AS ejecucion_hoy_estado,
    hoy.turno AS ejecucion_hoy_turno,
    hoy.ejecutado_por_nombre AS ejecucion_hoy_por
   FROM activos a
     JOIN faena_pauta p ON p.faena_id = a.faena_id AND p.activo AND (p.modelo_id IS NULL OR p.modelo_id = a.modelo_id)
     LEFT JOIN modelos mo ON mo.id = a.modelo_id
     -- Última pauta de faena cerrada.
     LEFT JOIN LATERAL ( SELECT e.horometro,
            e.kilometraje,
            e.fecha
           FROM faena_pauta_ejecucion e
          WHERE e.pauta_id = p.id AND e.activo_id = a.id AND e.estado = 'cerrada'::text
          ORDER BY e.fecha DESC, e.cerrada_at DESC
         LIMIT 1) ult ON true
     -- Último servicio de Coquimbo que cubre el disparo (frecuencia múltiplo).
     LEFT JOIN LATERAL ( SELECT pm2.id,
            pm2.ultima_ejecucion_horas,
            pm2.ultima_ejecucion_km,
            pm2.ultima_ejecucion_fecha
           FROM planes_mantenimiento pm2
          WHERE pm2.activo_id = a.id
            AND (   (p.disparo_horas IS NOT NULL AND pm2.frecuencia_horas IS NOT NULL AND pm2.frecuencia_horas > 0
                     AND pm2.frecuencia_horas % p.disparo_horas = 0 AND pm2.ultima_ejecucion_horas IS NOT NULL)
                 OR (p.disparo_km IS NOT NULL AND pm2.frecuencia_km IS NOT NULL AND pm2.frecuencia_km > 0
                     AND pm2.frecuencia_km % p.disparo_km = 0 AND pm2.ultima_ejecucion_km IS NOT NULL))
          ORDER BY CASE WHEN p.disparo_horas IS NOT NULL THEN pm2.ultima_ejecucion_horas ELSE pm2.ultima_ejecucion_km END DESC NULLS LAST,
                   pm2.ultima_ejecucion_fecha DESC NULLS LAST
         LIMIT 1) pm ON true
     -- Gana la más nueva de las dos.
     LEFT JOIN LATERAL ( SELECT
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_horas, ult.horometro) ELSE COALESCE(ult.horometro, pm.ultima_ejecucion_horas) END AS horometro,
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_km, ult.kilometraje) ELSE COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) END AS kilometraje,
            CASE WHEN usa_plan THEN COALESCE(pm.ultima_ejecucion_fecha, ult.fecha::timestamp with time zone) ELSE COALESCE(ult.fecha::timestamp with time zone, pm.ultima_ejecucion_fecha) END AS fecha,
            CASE WHEN usa_plan THEN 'plan'::text ELSE 'ejecucion'::text END AS origen
           FROM ( SELECT pm.id IS NOT NULL AND NOT COALESCE(
                        CASE WHEN p.disparo_horas IS NOT NULL THEN ult.horometro >= pm.ultima_ejecucion_horas
                             ELSE ult.kilometraje >= pm.ultima_ejecucion_km END, false) AS usa_plan) s
         ) u ON true
     LEFT JOIN LATERAL ( SELECT e2.id,
            e2.estado,
            e2.turno,
            e2.ejecutado_por_nombre
           FROM faena_pauta_ejecucion e2
          WHERE e2.pauta_id = p.id AND e2.activo_id = a.id AND e2.fecha = CURRENT_DATE
          ORDER BY e2.updated_at DESC
         LIMIT 1) hoy ON true
  WHERE a.fecha_baja IS NULL;

-- Resultado para Franke (programadas).
SELECT v.patente, v.pauta_codigo, v.horas_uso_actual, v.ultima_horometro, v.ultima_kilometraje,
       v.ultima_fecha::date, v.origen_ultima, v.faltan_horas, v.faltan_km, v.senal
FROM public.v_faena_pauta_agenda v JOIN public.faenas f ON f.id = v.faena_id
WHERE f.codigo = 'FAE-FRANCKE' AND v.pauta_tipo <> 'diaria'
ORDER BY v.patente;
