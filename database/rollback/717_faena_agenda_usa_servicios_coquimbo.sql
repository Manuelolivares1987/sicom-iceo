-- Rollback MIG717: vuelve v_faena_pauta_agenda a la definición de MIG359 (solo plan activo de frecuencia exacta).
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
    COALESCE(ult.horometro, pm.ultima_ejecucion_horas) AS ultima_horometro,
    COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) AS ultima_kilometraje,
    COALESCE(ult.fecha::timestamp with time zone, pm.ultima_ejecucion_fecha) AS ultima_fecha,
        CASE
            WHEN ult.horometro IS NULL AND pm.id IS NOT NULL THEN 'plan'::text
            ELSE 'ejecucion'::text
        END AS origen_ultima,
        CASE
            WHEN p.disparo_horas IS NOT NULL THEN round(COALESCE(ult.horometro, pm.ultima_ejecucion_horas) + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_horas,
        CASE
            WHEN p.disparo_km IS NOT NULL THEN round(COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric), 1)
            ELSE NULL::numeric
        END AS faltan_km,
        CASE
            WHEN p.tipo = 'diaria'::text THEN 'diaria'::text
            WHEN COALESCE(ult.horometro, pm.ultima_ejecucion_horas) IS NULL AND COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) IS NULL THEN 'sin_datos'::text
            WHEN p.disparo_horas IS NOT NULL AND (COALESCE(ult.horometro, pm.ultima_ejecucion_horas) + p.disparo_horas) <= COALESCE(a.horas_uso_actual, 0::numeric) OR p.disparo_km IS NOT NULL AND (COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) + p.disparo_km) <= COALESCE(a.kilometraje_actual, 0::numeric) THEN 'vencida'::text
            WHEN p.disparo_horas IS NOT NULL AND (COALESCE(ult.horometro, pm.ultima_ejecucion_horas) + p.disparo_horas - COALESCE(a.horas_uso_actual, 0::numeric)) <= p.aviso_horas OR p.disparo_km IS NOT NULL AND (COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) + p.disparo_km - COALESCE(a.kilometraje_actual, 0::numeric)) <= p.aviso_km THEN 'por_vencer'::text
            ELSE 'al_dia'::text
        END AS senal,
    hoy.id AS ejecucion_hoy_id,
    hoy.estado AS ejecucion_hoy_estado,
    hoy.turno AS ejecucion_hoy_turno,
    hoy.ejecutado_por_nombre AS ejecucion_hoy_por
   FROM activos a
     JOIN faena_pauta p ON p.faena_id = a.faena_id AND p.activo AND (p.modelo_id IS NULL OR p.modelo_id = a.modelo_id)
     LEFT JOIN modelos mo ON mo.id = a.modelo_id
     LEFT JOIN LATERAL ( SELECT e.horometro,
            e.kilometraje,
            e.fecha
           FROM faena_pauta_ejecucion e
          WHERE e.pauta_id = p.id AND e.activo_id = a.id AND e.estado = 'cerrada'::text
          ORDER BY e.fecha DESC, e.cerrada_at DESC
         LIMIT 1) ult ON true
     LEFT JOIN LATERAL ( SELECT pm2.id,
            pm2.ultima_ejecucion_horas,
            pm2.ultima_ejecucion_km,
            pm2.ultima_ejecucion_fecha
           FROM planes_mantenimiento pm2
          WHERE pm2.activo_id = a.id AND pm2.activo_plan AND (p.disparo_horas IS NOT NULL AND pm2.frecuencia_horas = p.disparo_horas OR p.disparo_km IS NOT NULL AND pm2.frecuencia_km = p.disparo_km)
          ORDER BY pm2.updated_at DESC
         LIMIT 1) pm ON true
     LEFT JOIN LATERAL ( SELECT e2.id,
            e2.estado,
            e2.turno,
            e2.ejecutado_por_nombre
           FROM faena_pauta_ejecucion e2
          WHERE e2.pauta_id = p.id AND e2.activo_id = a.id AND e2.fecha = CURRENT_DATE
          ORDER BY e2.updated_at DESC
         LIMIT 1) hoy ON true
  WHERE a.fecha_baja IS NULL;
