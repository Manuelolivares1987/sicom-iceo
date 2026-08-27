-- ============================================================================
-- MIG428 · Control documental filtrable por zona y por el status del camión
-- ----------------------------------------------------------------------------
-- LO QUE PIDIÓ MANUEL
-- 27-08-2026: «necesito que esta página filtre por zona (Coquimbo / Calama) y
-- por el status de los camiones. Que el primer filtro sea el status de los
-- camiones, que es el que se entrega de sugerencias GPS».
--
-- Hoy la lista de equipos de Control documental sólo se puede buscar por
-- patente. Con 63 equipos eso alcanza para encontrar uno; no alcanza para lo
-- que pide la pregunta de verdad: «de los camiones que están arrendados en
-- Calama, ¿cuáles tienen papeles vencidos?».
--
-- ── DE DÓNDE SALE CADA COSA ────────────────────────────────────────────────
-- No se inventa ningún criterio nuevo: los dos ya existen en el sistema y hay
-- que traerlos, no crearlos.
--
--   ZONA    `activos.operacion` — 'Coquimbo' o 'Calama'. Es exactamente el
--           mismo campo con el que el Panel de Gerencia arma sus cuadrantes
--           (fn_panel_disponibilidad). Si Control documental usara otro
--           criterio, dos pantallas contarían distinto la misma flota.
--
--   STATUS  `v_activos_estado_planificador.estado_codigo` — A arrendado,
--           C en contrato, D disponible, M mantención, T taller, F fuera de
--           servicio, S siniestrado, etc. Es el que manda el planificador y el
--           que Sugerencias GPS propone cambiar (`estado_sugerido`), así que
--           filtrar por él y por lo que propone el GPS habla el mismo idioma.
--
-- `activos.estado` NO sirve para esto: sólo tiene tres valores —operativo, en
-- mantenimiento, fuera de servicio— y es derivado. El estado lo manda el
-- planificador (MIG307).
--
-- ── 13 EQUIPOS SIN ZONA ────────────────────────────────────────────────────
-- `operacion` viene en NULL en 13 equipos, todos en mantención o fuera de
-- servicio: están en el taller, sin operación asignada. Se devuelven con la
-- zona en NULL y la pantalla los agrupa aparte, en vez de repartirlos a alguna
-- de las dos por conveniencia.
-- ============================================================================

BEGIN;

-- Las columnas nuevas van en medio, así que CREATE OR REPLACE no basta:
-- Postgres no permite renombrar columnas de una vista existente.
DROP VIEW IF EXISTS public.v_control_documental_equipo;
CREATE VIEW public.v_control_documental_equipo AS
SELECT d.activo_id,
       d.patente,
       d.activo_codigo,
       d.activo_nombre,
       d.activo_tipo,
       d.activo_estado,
       -- [MIG428] Zona y status, para poder filtrar.
       a.operacion                    AS zona,
       ep.estado_codigo               AS status_codigo,
       ep.fecha_estado                AS status_fecha,
       ep.confirmado_hoy              AS status_confirmado_hoy,
       count(*)                                                        AS total,
       count(*) FILTER (WHERE d.estado = 'vencido')                    AS vencidos,
       count(*) FILTER (WHERE d.estado = 'sin_fecha')                  AS sin_fecha,
       count(*) FILTER (WHERE d.estado = 'por_vencer')                 AS por_vencer,
       count(*) FILTER (WHERE d.estado = 'vigente')                    AS vigentes,
       count(*) FILTER (WHERE d.estado = 'no_aplica')                  AS no_aplica,
       count(*) FILTER (WHERE d.propuesta_id IS NOT NULL)              AS con_propuesta,
       count(*) FILTER (WHERE d.propuesta_vencida)                     AS propuestas_vencidas,
       count(*) FILTER (WHERE d.estado = 'vencido' AND d.bloqueante)   AS vencidos_bloqueantes
  FROM v_control_documental d
  JOIN activos a ON a.id = d.activo_id
  LEFT JOIN v_activos_estado_planificador ep ON ep.activo_id = d.activo_id
 GROUP BY d.activo_id, d.patente, d.activo_codigo, d.activo_nombre, d.activo_tipo,
          d.activo_estado, a.operacion, ep.estado_codigo, ep.fecha_estado, ep.confirmado_hoy;

GRANT SELECT ON public.v_control_documental_equipo TO authenticated;

COMMENT ON VIEW public.v_control_documental_equipo IS
  'MIG428: resumen documental por equipo, con la zona (activos.operacion, igual que el Panel de Gerencia) y el status del planificador (el mismo que propone Sugerencias GPS).';

DO $r$
DECLARE r RECORD;
BEGIN
    RAISE NOTICE 'Equipos por zona y status:';
    FOR r IN
        SELECT COALESCE(zona,'(en taller, sin operación)') AS zona,
               COALESCE(status_codigo,'—') AS st, count(*) AS n,
               sum(vencidos_bloqueantes) AS bloq
          FROM v_control_documental_equipo GROUP BY 1,2 ORDER BY 1, 3 DESC
    LOOP
        RAISE NOTICE '  % % : % equipos, % bloqueantes vencidos',
            rpad(r.zona,28), rpad(r.st,3), r.n, r.bloq;
    END LOOP;
END
$r$;

COMMIT;
