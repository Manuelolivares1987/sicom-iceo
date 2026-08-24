-- ============================================================================
-- MIG359 · La agenda del mecánico tiene que decir cuánto falta desde el día uno
-- ----------------------------------------------------------------------------
-- La vista de MIG357 calculaba «cuánto falta para el próximo servicio» contra
-- la última ejecución REGISTRADA EN EL SISTEMA. El primer día no hay ninguna,
-- así que la columna sale vacía justo cuando más se necesita — y el mecánico
-- vuelve a mirar la planilla.
--
-- El dato existe: está en el plan de mantención, que MIG358 cargó con los
-- números reales de la entrega de turno. Se usa como respaldo: manda la última
-- ejecución si la hay, y si no, la que declara el plan.
--
-- LA PRUEBA DE QUE EL CÁLCULO ES EL CORRECTO, Y LO QUE DESTAPÓ
-- El turno B escribió a mano en su entrega: «LLBP96 OPERATIVO RESTA 6997 KM
-- PARA PRÓXIMA MANTENCIÓN». La vista da 7.002 km. La fórmula es la misma; lo
-- que difiere son 5 km de odómetro: la ficha del activo trae 98.553,8 km y el
-- «Formato km hr» del 12-08 anotó 98.559.
--
-- Cinco kilómetros no importan. Lo que importa es que sean DOS números: hoy el
-- kilometraje vive en dos lados y nadie los concilia. Desde que el mecánico lo
-- tome dentro de la pauta hay uno solo, y el de la planilla deja de existir.
--
-- SE AGREGA TAMBIÉN EL ESTADO DEL DÍA
-- Si la pauta de hoy ya se hizo, la agenda lo dice. Sin eso el mecánico no
-- sabe si le falta o si ya la cerró el otro turno, y la respuesta segura —
-- volver a hacerla — es la que hace que se marque todo OK sin mirar.
-- ============================================================================

BEGIN;

-- CREATE OR REPLACE no puede insertar columnas en medio de una vista. Se
-- reemplaza entera; no hay nada colgando de ella todavía.
DROP VIEW IF EXISTS public.v_faena_pauta_agenda;

CREATE VIEW public.v_faena_pauta_agenda AS
SELECT
    a.faena_id,
    a.id                AS activo_id,
    a.codigo            AS activo_codigo,
    a.patente,
    a.nombre            AS activo_nombre,
    a.estado            AS activo_estado,
    mo.nombre           AS modelo,
    a.horas_uso_actual,
    a.kilometraje_actual,
    p.id                AS pauta_id,
    p.codigo            AS pauta_codigo,
    p.nombre            AS pauta_nombre,
    p.tipo              AS pauta_tipo,
    p.disparo_horas,
    p.disparo_km,
    p.aviso_horas,
    p.aviso_km,
    (SELECT count(*) FROM faena_pauta_item i WHERE i.pauta_id = p.id)::int AS items,

    -- Última ejecución conocida: manda lo que se registró en el sistema; si
    -- todavía no hay nada, lo que declara el plan de mantención.
    COALESCE(ult.horometro,   pm.ultima_ejecucion_horas)  AS ultima_horometro,
    COALESCE(ult.kilometraje, pm.ultima_ejecucion_km)     AS ultima_kilometraje,
    COALESCE(ult.fecha,       pm.ultima_ejecucion_fecha)  AS ultima_fecha,
    CASE WHEN ult.horometro IS NULL AND pm.id IS NOT NULL THEN 'plan' ELSE 'ejecucion' END
                                                          AS origen_ultima,

    CASE WHEN p.disparo_horas IS NOT NULL
         THEN ROUND(COALESCE(ult.horometro, pm.ultima_ejecucion_horas)
                    + p.disparo_horas - COALESCE(a.horas_uso_actual, 0), 1)
    END AS faltan_horas,
    CASE WHEN p.disparo_km IS NOT NULL
         THEN ROUND(COALESCE(ult.kilometraje, pm.ultima_ejecucion_km)
                    + p.disparo_km - COALESCE(a.kilometraje_actual, 0), 1)
    END AS faltan_km,

    -- Vencida, por vencer o al día. Una programada sin números de partida no es
    -- «al día»: es «no se sabe», y así se muestra.
    CASE
      WHEN p.tipo = 'diaria' THEN 'diaria'
      WHEN COALESCE(ult.horometro, pm.ultima_ejecucion_horas) IS NULL
       AND COALESCE(ult.kilometraje, pm.ultima_ejecucion_km)  IS NULL THEN 'sin_datos'
      WHEN (p.disparo_horas IS NOT NULL
            AND COALESCE(ult.horometro, pm.ultima_ejecucion_horas) + p.disparo_horas
                <= COALESCE(a.horas_uso_actual, 0))
        OR (p.disparo_km IS NOT NULL
            AND COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) + p.disparo_km
                <= COALESCE(a.kilometraje_actual, 0))       THEN 'vencida'
      WHEN (p.disparo_horas IS NOT NULL
            AND COALESCE(ult.horometro, pm.ultima_ejecucion_horas) + p.disparo_horas
                - COALESCE(a.horas_uso_actual, 0) <= p.aviso_horas)
        OR (p.disparo_km IS NOT NULL
            AND COALESCE(ult.kilometraje, pm.ultima_ejecucion_km) + p.disparo_km
                - COALESCE(a.kilometraje_actual, 0) <= p.aviso_km) THEN 'por_vencer'
      ELSE 'al_dia'
    END AS senal,

    -- Lo de hoy: si ya se hizo, la agenda lo dice.
    hoy.id      AS ejecucion_hoy_id,
    hoy.estado  AS ejecucion_hoy_estado,
    hoy.turno   AS ejecucion_hoy_turno,
    hoy.ejecutado_por_nombre AS ejecucion_hoy_por
FROM public.activos a
JOIN public.faena_pauta p
      ON p.faena_id = a.faena_id
     AND p.activo
     AND (p.modelo_id IS NULL OR p.modelo_id = a.modelo_id)
LEFT JOIN public.modelos mo ON mo.id = a.modelo_id
LEFT JOIN LATERAL (
    SELECT e.horometro, e.kilometraje, e.fecha
      FROM public.faena_pauta_ejecucion e
     WHERE e.pauta_id = p.id AND e.activo_id = a.id AND e.estado = 'cerrada'
     ORDER BY e.fecha DESC, e.cerrada_at DESC
     LIMIT 1
) ult ON TRUE
LEFT JOIN LATERAL (
    -- El plan de mantención del mismo equipo con el mismo intervalo. Es el que
    -- MIG358 cargó con los números de la entrega de turno.
    SELECT pm2.id, pm2.ultima_ejecucion_horas, pm2.ultima_ejecucion_km,
           pm2.ultima_ejecucion_fecha
      FROM public.planes_mantenimiento pm2
     WHERE pm2.activo_id = a.id AND pm2.activo_plan
       AND (   (p.disparo_horas IS NOT NULL AND pm2.frecuencia_horas = p.disparo_horas)
            OR (p.disparo_km    IS NOT NULL AND pm2.frecuencia_km    = p.disparo_km))
     ORDER BY pm2.updated_at DESC
     LIMIT 1
) pm ON TRUE
LEFT JOIN LATERAL (
    SELECT e2.id, e2.estado, e2.turno, e2.ejecutado_por_nombre
      FROM public.faena_pauta_ejecucion e2
     WHERE e2.pauta_id = p.id AND e2.activo_id = a.id AND e2.fecha = CURRENT_DATE
     ORDER BY e2.updated_at DESC
     LIMIT 1
) hoy ON TRUE
WHERE a.fecha_baja IS NULL;

GRANT SELECT ON public.v_faena_pauta_agenda TO authenticated;

COMMENT ON VIEW public.v_faena_pauta_agenda IS
  'Lo que le toca revisar al mecanico, por equipo, con cuanto falta para el proximo servicio y si la de hoy ya se hizo. MIG357, completada en MIG359.';

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- El LLBP-96 tiene que dar 6.997 km, que es el numero escrito a mano en la
-- entrega de turno B del 06-12 de agosto de 2026.
-- SELECT patente, pauta_codigo, senal, faltan_horas, faltan_km, origen_ultima
--   FROM v_faena_pauta_agenda
--  WHERE faena_id = (SELECT id FROM faenas WHERE codigo = 'FAE-FRANCKE')
--  ORDER BY patente, pauta_tipo;
