-- ============================================================================
-- MIG400 · Un checklist dura varias jornadas, y la noche no es tiempo perdido
-- ----------------------------------------------------------------------------
-- LO QUE CORRIGIÓ MANUEL
-- 26-08-2026: «un checklist se puede hacer en varias jornadas, por lo tanto
-- también hay que considerar pausar, dentro de los tiempos».
--
-- TIENE RAZÓN, Y EL NÚMERO DE AYER ESTABA MAL
-- `tiempo_pausado_segundos` suma TODO lo que pasa entre un `pause` y el
-- `resume` siguiente. Si el mecánico pausa a las 18:00 y retoma a las 08:00 del
-- día siguiente, eso suma **catorce horas de "pausa"**. No hubo catorce horas de
-- nadie esperando: hubo una noche.
--
-- Con esa cuenta, un checklist honesto repartido en tres días se ve peor que
-- uno hecho de corrido, y si eso toca la remuneración castiga justo al que
-- respeta la jornada.
--
-- QUÉ CAMBIA
--
--   1. LA PAUSA SE CLASIFICA. Hasta hoy `motivo` era texto libre y estaba
--      SIEMPRE en null: nadie declaraba por qué paraba, y la única distinción
--      era un LIKE '%colacion%' sobre ese texto. Ahora la pausa dice de qué
--      tipo es, y cada tipo cuenta distinto:
--
--        fin_jornada        → NO es tiempo perdido. Se acabó el día.
--        colacion           → no es trabajo, pero tampoco demora.
--        espera_repuesto    → SÍ duele, y es la que hay que perseguir.
--        equipo_no_disponible → el equipo no estaba. No es del mecánico.
--        otro               → lo que no cae en las anteriores.
--
--   2. LO QUE NO SE DECLARA, SE INFIERE — Y SE DICE QUE SE INFIRIÓ. Las pausas
--      viejas y las que nadie clasifique se leen por su duración: si cruza la
--      medianoche o dura más de 10 horas, es fin de jornada. La vista marca esas
--      con `motivo_inferido = true` para que nadie las confunda con un dato
--      declarado.
--
--   3. SE MIDEN LAS JORNADAS. Cuántos días distintos se trabajó, y cuántos días
--      de calendario pasaron de punta a punta. Un checklist de 6 horas
--      efectivas repartido en 4 días es una historia muy distinta a uno de 6
--      horas hecho en una tarde, y hasta ahora las dos se veían iguales.
--
-- POR QUÉ POR EVENTOS Y NO POR EL CONTADOR
-- Los totales acumulados no se pueden desarmar: una vez sumadas, las catorce
-- horas de la noche no se distinguen de catorce horas esperando un repuesto.
-- Los eventos sí guardan cuándo empezó y terminó cada tramo, así que la verdad
-- está ahí y se puede reconstruir. El contador se deja como está —lo usa la
-- pantalla del mecánico— pero deja de ser la fuente para medir.
-- ============================================================================

BEGIN;

-- ── 1. La pausa dice de qué tipo es ───────────────────────────────────────
ALTER TABLE public.taller_ot_ejecucion_eventos
  ADD COLUMN IF NOT EXISTS motivo_tipo TEXT;

ALTER TABLE public.taller_ot_ejecucion_eventos
  DROP CONSTRAINT IF EXISTS chk_taller_ejecev_motivo_tipo;
ALTER TABLE public.taller_ot_ejecucion_eventos
  ADD CONSTRAINT chk_taller_ejecev_motivo_tipo CHECK (
    motivo_tipo IS NULL OR motivo_tipo = ANY (ARRAY[
      'fin_jornada','colacion','espera_repuesto','equipo_no_disponible','otro']));

COMMENT ON COLUMN public.taller_ot_ejecucion_eventos.motivo_tipo IS
  'MIG400: por qué se pausó. fin_jornada y colacion NO son demora; espera_repuesto sí. NULL = no se declaró y la vista lo infiere por la duración.';

-- ── 2. Los tramos, reconstruidos ──────────────────────────────────────────
-- Cada pausa con su inicio, su fin y su tipo. De acá sale todo lo demás.
CREATE OR REPLACE VIEW public.v_taller_ejecucion_tramos AS
WITH ev AS (
    SELECT e.ejecucion_id, e.ot_id, e.tipo, e.motivo, e.motivo_tipo, e.created_at,
           LEAD(e.created_at) OVER (PARTITION BY e.ejecucion_id ORDER BY e.created_at) AS hasta
      FROM taller_ot_ejecucion_eventos e
     WHERE e.tipo IN ('start','pause','resume','finish')
)
SELECT
    ev.ejecucion_id,
    ev.ot_id,
    ev.created_at                                   AS desde,
    COALESCE(ev.hasta, NOW())                       AS hasta,
    ev.tipo,
    -- Un tramo que arranca en pause es pausa; el resto es trabajo.
    (ev.tipo = 'pause')                             AS es_pausa,
    round((EXTRACT(EPOCH FROM (COALESCE(ev.hasta, NOW()) - ev.created_at)) / 3600.0)::numeric, 2) AS horas,
    -- El tipo declarado manda. Si no lo hay, se infiere por la forma del tramo.
    COALESCE(
        ev.motivo_tipo,
        CASE WHEN ev.tipo <> 'pause' THEN NULL
             WHEN ev.created_at::date <> COALESCE(ev.hasta, NOW())::date THEN 'fin_jornada'
             WHEN EXTRACT(EPOCH FROM (COALESCE(ev.hasta, NOW()) - ev.created_at)) > 36000 THEN 'fin_jornada'
             WHEN lower(COALESCE(ev.motivo,'')) LIKE '%colacion%'
               OR lower(COALESCE(ev.motivo,'')) LIKE '%colación%' THEN 'colacion'
             ELSE 'otro' END
    )                                               AS motivo_efectivo,
    (ev.motivo_tipo IS NULL AND ev.tipo = 'pause')  AS motivo_inferido
FROM ev;

COMMENT ON VIEW public.v_taller_ejecucion_tramos IS
  'MIG400: cada tramo de una ejecución con su duración y, si es pausa, por qué. motivo_inferido = nadie lo declaró y se dedujo de la duración.';

-- ── 3. El tiempo del checklist, contado como corresponde ──────────────────
CREATE OR REPLACE VIEW public.v_taller_tiempo_checklist AS
SELECT
    e.id                        AS ejecucion_id,
    e.ot_id,
    o.folio                     AS ot_folio,
    o.tipo                      AS ot_tipo,
    a.codigo                    AS activo_codigo,
    a.patente                   AS activo_patente,
    e.ejecutor_id,
    COALESCE(u.nombre_completo, 'Sin asignar') AS ejecutor,
    e.estado,
    e.started_at,
    e.finished_at,
    round(e.tiempo_efectivo_segundos / 3600.0, 2) AS horas_efectivas,
    round(e.tiempo_pausado_segundos  / 3600.0, 2) AS horas_pausado,
    round(e.tiempo_colacion_segundos / 3600.0, 2) AS horas_colacion,
    ci.items_totales,
    ci.items_hechos,
    CASE WHEN COALESCE(ci.items_hechos,0) > 0 AND e.tiempo_efectivo_segundos > 0
         THEN round((e.tiempo_efectivo_segundos / 60.0) / ci.items_hechos, 2)
         ELSE NULL END          AS min_por_item,
    e.avance_final,
    -- ── [MIG400] Lo nuevo ─────────────────────────────────────────────────
    -- En cuántos días distintos se trabajó de verdad.
    tr.jornadas,
    -- Cuántos días pasaron de punta a punta. Un checklist de 6 h repartido en 4
    -- días no es lo mismo que uno de 6 h hecho en una tarde.
    round((EXTRACT(EPOCH FROM (COALESCE(e.finished_at, NOW()) - e.started_at)) / 86400.0)::numeric, 1)
                                AS dias_calendario,
    -- La demora que SÍ duele: nadie trabajando, dentro del día.
    tr.horas_espera_repuesto,
    tr.horas_equipo_no_disponible,
    tr.horas_pausa_otro,
    -- La noche y la colación, aparte: no son demora de nadie.
    tr.horas_fin_jornada,
    tr.horas_colacion_tramos,
    -- Suma de lo que de verdad frenó el trabajo. Es el número comparable.
    round(COALESCE(tr.horas_espera_repuesto,0)
        + COALESCE(tr.horas_equipo_no_disponible,0)
        + COALESCE(tr.horas_pausa_otro,0), 2) AS horas_demora_real,
    -- Cuántas de esas pausas nadie clasificó.
    tr.pausas_sin_declarar
FROM taller_ot_ejecuciones e
JOIN ordenes_trabajo o ON o.id = e.ot_id
LEFT JOIN activos a ON a.id = o.activo_id
LEFT JOIN usuarios_perfil u ON u.id = e.ejecutor_id
LEFT JOIN LATERAL (
    SELECT count(*) AS items_totales,
           count(*) FILTER (WHERE ii.resultado IS NOT NULL
                              AND ii.resultado::text <> 'pendiente') AS items_hechos
      FROM checklist_v2_instance i
      JOIN checklist_v2_instance_item ii ON ii.instance_id = i.id
     WHERE i.ot_id = e.ot_id AND NOT COALESCE(ii.excluido, false)
) ci ON TRUE
LEFT JOIN LATERAL (
    SELECT
      count(DISTINCT t.desde::date) FILTER (WHERE NOT t.es_pausa)      AS jornadas,
      round(sum(t.horas) FILTER (WHERE t.motivo_efectivo = 'espera_repuesto'), 2)      AS horas_espera_repuesto,
      round(sum(t.horas) FILTER (WHERE t.motivo_efectivo = 'equipo_no_disponible'), 2) AS horas_equipo_no_disponible,
      round(sum(t.horas) FILTER (WHERE t.motivo_efectivo = 'otro'), 2)                 AS horas_pausa_otro,
      round(sum(t.horas) FILTER (WHERE t.motivo_efectivo = 'fin_jornada'), 2)          AS horas_fin_jornada,
      round(sum(t.horas) FILTER (WHERE t.motivo_efectivo = 'colacion'), 2)             AS horas_colacion_tramos,
      count(*) FILTER (WHERE t.es_pausa AND t.motivo_inferido)                         AS pausas_sin_declarar
      FROM v_taller_ejecucion_tramos t
     WHERE t.ejecucion_id = e.id
) tr ON TRUE;

COMMENT ON VIEW public.v_taller_tiempo_checklist IS
  'MIG400: el checklist puede durar varias jornadas. horas_demora_real es lo que de verdad frenó el trabajo (espera de repuesto, equipo no disponible, otro); la noche y la colación van aparte y NO cuentan como demora.';

-- ── 4. Pausar declarando el motivo ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_taller_pausar_ejecucion(
    p_ejecucion_id uuid,
    p_motivo character varying DEFAULT NULL,
    p_motivo_tipo text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_e RECORD; v_delta INT; v_tipo TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    v_tipo := NULLIF(TRIM(COALESCE(p_motivo_tipo, '')), '');
    IF v_tipo IS NOT NULL AND v_tipo NOT IN
       ('fin_jornada','colacion','espera_repuesto','equipo_no_disponible','otro') THEN
        RAISE EXCEPTION 'Motivo de pausa desconocido: %', v_tipo; END IF;

    SELECT id, estado, last_event_at, ot_id, plan_semanal_ot_id, tiempo_efectivo_segundos
      INTO v_e FROM taller_ot_ejecuciones WHERE id = p_ejecucion_id FOR UPDATE;
    IF v_e.id IS NULL THEN RAISE EXCEPTION 'La ejecución no existe'; END IF;
    IF v_e.estado <> 'en_ejecucion' THEN
        RAISE EXCEPTION 'La ejecución está en %: sólo se pausa lo que está corriendo', v_e.estado; END IF;

    v_delta := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_e.last_event_at))::INT);

    UPDATE taller_ot_ejecuciones
       SET estado = 'pausada',
           tiempo_efectivo_segundos = COALESCE(tiempo_efectivo_segundos,0) + v_delta,
           last_event_at = NOW(),
           updated_at = NOW()
     WHERE id = p_ejecucion_id;

    INSERT INTO taller_ot_ejecucion_eventos (ejecucion_id, ot_id, tipo, motivo, motivo_tipo, created_by, created_at)
    VALUES (p_ejecucion_id, v_e.ot_id, 'pause', p_motivo, v_tipo, v_user, NOW());

    RETURN jsonb_build_object('success', true, 'motivo_tipo', v_tipo,
                              'tiempo_efectivo_seg', COALESCE(v_e.tiempo_efectivo_segundos,0) + v_delta);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_taller_pausar_ejecucion(uuid, character varying, text) TO authenticated;
GRANT SELECT ON public.v_taller_ejecucion_tramos TO authenticated;

-- ── 5. Qué se ve con los datos de hoy ─────────────────────────────────────
DO $r$
DECLARE r RECORD;
BEGIN
    FOR r IN
        SELECT ot_folio, jornadas, dias_calendario, horas_efectivas,
               horas_pausado AS pausado_viejo, horas_demora_real, horas_fin_jornada,
               pausas_sin_declarar
          FROM v_taller_tiempo_checklist ORDER BY started_at DESC NULLS LAST
    LOOP
        RAISE NOTICE '% · % jornada(s) · % días · %h efectivas · demora real %h (el contador viejo decía %h de pausa; % eran fin de jornada) · % pausas sin declarar',
            r.ot_folio, COALESCE(r.jornadas,0), COALESCE(r.dias_calendario,0),
            COALESCE(r.horas_efectivas,0), COALESCE(r.horas_demora_real,0),
            COALESCE(r.pausado_viejo,0), COALESCE(r.horas_fin_jornada,0),
            COALESCE(r.pausas_sin_declarar,0);
    END LOOP;
END
$r$;

COMMIT;
