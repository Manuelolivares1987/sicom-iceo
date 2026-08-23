-- ============================================================================
-- MIG349 · El día tiene dos turnos, y hasta ahora el sistema veía uno
-- ----------------------------------------------------------------------------
-- En Romeral se trabaja 4x4 con turno de día y turno de noche. El cierre por
-- turno ya existía —la tabla es única por (faena, fecha, turno)— pero tres
-- cosas seguían razonando por día calendario, y con dos turnos eso deja de ser
-- un detalle:
--
-- 1. LA MEDICIÓN INICIAL VENÍA DEL DÍA ANTERIOR
--    Al supervisor de noche se le ofrecía el nivel del estanque de hace 24
--    horas en vez del que le acababa de dejar el turno de día. Empezar el
--    turno con el número equivocado descuadra los dos turnos: al de noche le
--    sobra o le falta todo lo que el de día movió.
--
-- 2. LA VERIFICACIÓN DEL TURNO MIRABA TODO EL DÍA
--    El supervisor de noche veía «12 cargas» —las suyas y las del turno de
--    día— y firmaba por todas. Eso rompe exactamente la separación que el
--    cierre por turno existe para sostener: cada uno responde por lo suyo.
--
-- 3. EL DÍA SE VEÍA CERRADO CON UN TURNO ABIERTO
--    El estado del día salía de `max(estado)` de los dos cierres. Entre
--    'borrador' y 'firmado' gana 'firmado' por orden alfabético, así que un
--    día con el turno de noche sin cerrar aparecía como cerrado. El peor tipo
--    de error en un tablero: dice que está listo lo que no lo está.
--
-- EL ORDEN DE LOS TURNOS
-- Día antes que Noche dentro de la misma fecha. Se escribe una vez, acá, y no
-- se vuelve a decidir en cada consulta.
-- ============================================================================

BEGIN;

-- Sin extension unaccent: se resuelve con translate, que alcanza de sobra para
-- las dos palabras que importan.
CREATE OR REPLACE FUNCTION public.unaccent_simple(p_txt text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    SELECT translate(COALESCE(p_txt,''), 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN');
$f$;


CREATE OR REPLACE FUNCTION public.fn_comb_orden_turno(p_turno text)
RETURNS integer
LANGUAGE sql IMMUTABLE
AS $f$
    -- Dia antes que Noche. Lo que no se reconozca queda al final, para que un
    -- turno escrito distinto no se cuele al principio de la fila.
    SELECT CASE lower(unaccent_simple(COALESCE(p_turno, '')))
             WHEN 'dia'   THEN 1
             WHEN 'day'   THEN 1
             WHEN 'noche' THEN 2
             WHEN 'night' THEN 2
             ELSE 9
           END;
$f$;

-- ── De quién recibe cada turno, y con qué nivel ────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_turno_anterior AS
SELECT c.faena_id, c.fecha, c.turno,
       ant.fecha        AS fecha_anterior,
       ant.turno        AS turno_anterior,
       ant.medido_por   AS entrego,
       ant.estado       AS estado_anterior,
       ant.firmado_at   AS firmado_anterior_at
FROM combustible_faena_cierre c
LEFT JOIN LATERAL (
    SELECT a.fecha, a.turno, a.medido_por, a.estado, a.firmado_at
      FROM combustible_faena_cierre a
     WHERE a.faena_id = c.faena_id
       AND (a.fecha, public.fn_comb_orden_turno(a.turno))
         < (c.fecha, public.fn_comb_orden_turno(c.turno))
     ORDER BY a.fecha DESC, public.fn_comb_orden_turno(a.turno) DESC
     LIMIT 1
) ant ON true;

GRANT SELECT ON public.v_comb_faena_turno_anterior TO authenticated;

-- ── El nivel con el que arranca un turno: el que dejó el turno anterior ────
CREATE OR REPLACE FUNCTION public.rpc_comb_medicion_del_turno_anterior(
    p_faena_id uuid, p_fecha date, p_turno text
)
RETURNS TABLE (estanque_id uuid, mf numeric, fecha date, turno text, medido_por text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $f$
    -- Para cada estanque, la ultima medicion final ANTES de este turno. No del
    -- dia anterior: del turno anterior, que con dos turnos son doce horas de
    -- diferencia y todo lo que se movio en medio.
    SELECT DISTINCT ON (p.estanque_id)
           p.estanque_id, p.mf, c.fecha, c.turno, c.medido_por
      FROM combustible_faena_cierre c
      JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
     WHERE c.faena_id = p_faena_id
       AND p.mf IS NOT NULL AND NOT p.sin_medicion
       AND (c.fecha, public.fn_comb_orden_turno(c.turno))
         < (p_fecha, public.fn_comb_orden_turno(p_turno))
     ORDER BY p.estanque_id, c.fecha DESC, public.fn_comb_orden_turno(c.turno) DESC;
$f$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_medicion_del_turno_anterior(uuid, date, text) TO authenticated;

-- ── Lo que se hizo en ESTE turno, no en todo el día ────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_turno_para_verificar AS
SELECT d.faena_id, d.fecha, COALESCE(d.turno, 'Día') AS turno,
       count(*)::integer                                   AS despachos,
       COALESCE(sum(d.litros), 0)                          AS litros,
       count(*) FILTER (WHERE d.tipo_movimiento = 'venta')::integer      AS ventas,
       count(*) FILTER (WHERE d.tipo_movimiento = 'trasvasije')::integer AS trasvasijes,
       COALESCE(sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije'), 0) AS litros_trasvasije,
       count(*) FILTER (WHERE d.ceco_id IS NULL AND COALESCE(d.ceco_texto,'') = ''
                          AND d.tipo_movimiento = 'venta')::integer      AS sin_ceco,
       count(*) FILTER (WHERE COALESCE(d.foto_meter_final_url,'') = ''
                          AND COALESCE(d.sin_foto_motivo,'') = '')::integer AS sin_foto,
       count(DISTINCT d.operador_nombre)::integer          AS operadores
FROM combustible_faena_despachos d
WHERE NOT d.anulado
GROUP BY d.faena_id, d.fecha, COALESCE(d.turno, 'Día');

GRANT SELECT ON public.v_comb_faena_turno_para_verificar TO authenticated;

-- La vista por día se conserva: el mandante y el FORM AC 066 miran el día
-- completo. Lo que cambia es que la firma del turno ya no la usa.
COMMENT ON VIEW public.v_comb_faena_dia_para_verificar IS
  'El dia completo, para la oficina y los entregables. Para FIRMAR un turno se usa v_comb_faena_turno_para_verificar: cada supervisor responde por lo suyo. MIG342, acotada en MIG349.';

-- ── El día no está cerrado si falta un turno ───────────────────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_turnos_del_dia AS
SELECT c.faena_id, c.fecha,
       count(*)::integer AS turnos,
       count(*) FILTER (WHERE c.estado = 'firmado')::integer AS turnos_firmados,
       string_agg(c.turno || CASE WHEN c.estado <> 'firmado' THEN ' (sin firmar)' ELSE '' END,
                  ' · ' ORDER BY public.fn_comb_orden_turno(c.turno)) AS detalle,
       bool_and(c.estado = 'firmado') AS dia_completo
FROM combustible_faena_cierre c
GROUP BY c.faena_id, c.fecha;

GRANT SELECT ON public.v_comb_faena_turnos_del_dia TO authenticated;

COMMIT;
