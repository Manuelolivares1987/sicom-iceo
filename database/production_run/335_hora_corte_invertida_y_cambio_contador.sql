-- ============================================================================
-- MIG335 · Dos fallas que encontró la prueba de uso real
-- ----------------------------------------------------------------------------
-- La prueba de punta a punta anterior simulaba un día que sale bien, y un día
-- que sale bien no prueba casi nada. Esta jugó lo que de verdad pasa en un
-- turno — el operador se equivoca, la app reintenta sola, dos personas graban
-- lo mismo, alguien firma antes de tiempo, se cambia un cuentalitros — y dos
-- de los veintiún escenarios fallaron.
--
-- 1. LA HORA DE CORTE ESTABA AL REVÉS
--    Romeral cierra a las 00:00, o sea el día de cierre es el día calendario y
--    ninguna carga debería aparecer corrida. Aparecían todas: yo escribí
--    «si la hora es mayor o igual al corte, la carga es del día siguiente», y
--    con corte a medianoche eso es cierto para toda hora del día.
--
--    La regla correcta es al revés, y sirve para las dos convenciones que se
--    usan en faena: la carga pertenece al día de cierre en curso si su hora ya
--    pasó el corte; si es anterior al corte, todavía pertenece al día que
--    está cerrando. Con corte a las 06:00, una carga de las 03:00 del día 12
--    cierra con el 11 — que es como opera un turno de noche. Con corte a las
--    00:00, nada se mueve, que es lo que corresponde acá.
--
-- 2. UN CUENTALITROS NO SE PODÍA REEMPLAZAR
--    El RPC de MIG327 retira el contador viejo y crea el nuevo con el mismo
--    surtidor y el mismo número — porque es el mismo punto de despacho, sólo
--    que con otro aparato. Y había un UNIQUE sobre (estanque, surtidor,
--    número) que lo impedía. La función existía y no funcionaba: el día que
--    cambiaran un cuentalitros, nadie habría podido cerrar.
--
--    La unicidad tiene que valer sólo entre los contadores ACTIVOS. Uno
--    retirado conserva su surtidor y su número porque el histórico no se
--    reescribe: eso es lo que permite leer un numeral de hace seis meses y
--    saber de qué aparato salió.
-- ============================================================================

BEGIN;

-- ── 1. La hora de corte ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_comb_dia_cierre(p_faena_id uuid, p_fecha date, p_hora text)
RETURNS date
LANGUAGE sql STABLE
AS $f$
    -- El dia operacional corre de corte a corte. Una carga cuya hora todavia
    -- no llega al corte pertenece al dia de cierre ANTERIOR: con corte a las
    -- 06:00, lo que se despacha a las 03:00 del 12 cierra con el 11, que es
    -- como trabaja el turno de noche. Con corte a las 00:00 nada se mueve.
    SELECT CASE
      WHEN p_hora IS NULL OR p_hora !~ '^[0-9]{1,2}:[0-9]{2}' THEN p_fecha
      WHEN COALESCE((SELECT c.hora_corte FROM combustible_faena_config c
                      WHERE c.faena_id = p_faena_id), TIME '00:00') = TIME '00:00'
           THEN p_fecha
      WHEN p_hora::time < (SELECT c.hora_corte FROM combustible_faena_config c
                            WHERE c.faena_id = p_faena_id)
           THEN p_fecha - 1
      ELSE p_fecha
    END;
$f$;

COMMENT ON FUNCTION public.fn_comb_dia_cierre(uuid, date, text) IS
  'A que dia de cierre pertenece una carga segun la hora de corte de la faena. Con corte a las 00:00 el dia de cierre es el dia calendario. MIG330, corregida en MIG335.';

-- ── 2. Un contador retirado ya no compite por su lugar ─────────────────────
-- destructivo-ok: se cambia un UNIQUE por su version parcial. No se pierde
-- ningun dato ni ninguna fila; lo que cambia es el alcance de la unicidad, que
-- pasa a aplicar solo entre contadores activos. La restriccion anterior hacia
-- imposible reemplazar un cuentalitros, que es un evento normal de faena.
ALTER TABLE public.combustible_faena_medidores
    DROP CONSTRAINT IF EXISTS combustible_faena_medidores_estanque_id_surtidor_numero_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_medidor_activo_por_surtidor
    ON public.combustible_faena_medidores (estanque_id, surtidor, numero)
    WHERE activo;

COMMENT ON INDEX public.uq_medidor_activo_por_surtidor IS
  'Un solo contador ACTIVO por surtidor y numero. Los retirados conservan los suyos: sin eso no se puede leer un numeral viejo y saber de que aparato salio. MIG335.';

COMMIT;
