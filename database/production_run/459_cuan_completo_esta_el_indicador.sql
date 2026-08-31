-- ============================================================================
-- MIG459 · Cuán completo está el indicador que paga
-- ============================================================================
--
-- ENCONTRADO MIRANDO LA PANTALLA NUEVA EN PRODUCCIÓN
-- El tablero del bono mostró, para el corte del 24-ago al 23-sep:
--
--     flota 88,16 %   ·   promedio diario 73,77 %
--
-- Catorce puntos de diferencia entre las dos formas de medir lo mismo. Al abrir
-- el detalle día por día apareció la razón:
--
--     24-ago   55 equipos   85,2 %
--     25-ago   55 equipos   88,9 %
--     26-ago   55 equipos   88,9 %
--     27-ago   55 equipos   88,9 %
--     28-ago   55 equipos   90,7 %
--     29-ago    — sin registro —
--     30-ago    — sin registro —
--     31-ago    1 equipo     0,0 %
--
-- El registro diario de estado de flota se detuvo el viernes 28. El lunes 31
-- tiene UN equipo cargado de 55, y ese equipo está caído: el día completo
-- «vale» 0 %. En el promedio de porcentajes diarios ese día pesa lo mismo que
-- un día con la flota entera, y hunde el indicador catorce puntos.
--
-- Los fines de semana anteriores de agosto SÍ tienen registro, así que no es el
-- patrón normal: es una interrupción.
--
-- DOS COSAS DISTINTAS, Y LAS DOS IMPORTAN
--
--   1. La forma de medir. MIG454 ya eligió la razón de totales precisamente por
--      esto, y acá se ve por qué: 88,16 % contra 73,77 %. La razón de totales
--      casi no se mueve con un día flaco; el promedio de porcentajes se
--      desploma. Para pagar, la razón de totales.
--
--   2. Que el indicador esté COMPLETO. Ninguna forma de medir arregla que
--      falten días. Un 88 % calculado sobre 6 de 8 días transcurridos no es
--      mentira, pero tampoco es el mes: quien va a firmar un pago tiene que
--      saberlo antes de firmarlo, no después.
--
-- QUÉ SE HACE
-- La función que mide la disponibilidad pasa a decir también cuán completa está
-- la medición: cuántos días del corte ya transcurrieron, cuántos tienen
-- registro, y cuántos lo tienen a medias —menos de la mitad de los equipos que
-- se registran en un día normal del corte—. La pantalla lo muestra al lado del
-- número, y el cierre del período lo deja escrito en la nota del corte.
--
-- No bloquea nada: un corte se puede cerrar con días faltantes si la jefatura
-- lo decide. Lo que no puede pasar es que se cierre sin que nadie lo sepa.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS fn_taller_disponibilidad_periodo(DATE, DATE);

CREATE OR REPLACE FUNCTION fn_taller_disponibilidad_periodo(
    p_desde DATE,
    p_hasta DATE
)
RETURNS TABLE (
    disponibilidad_pct   NUMERIC,
    promedio_diario_pct  NUMERIC,
    dias_equipo          BIGINT,
    dias_equipo_buenos   BIGINT,
    dias_con_registro    BIGINT,
    dias_transcurridos   INT,
    dias_sin_registro    INT,
    dias_incompletos     INT,
    equipos_dia_normal   INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Un corte del futuro no tiene días «faltantes»: tiene días que no han
    -- pasado. Sólo se cuenta lo que ya ocurrió.
    v_tope  DATE := LEAST(p_hasta, CURRENT_DATE);
    v_trans INT  := GREATEST(0, (v_tope - p_desde) + 1);
    v_normal INT;
BEGIN
    -- «Un día normal» es la mediana de equipos registrados por día en el corte.
    -- Sirve de vara para reconocer un día cargado a medias sin fijar un número
    -- a mano que envejezca con la flota.
    SELECT COALESCE(percentile_disc(0.5) WITHIN GROUP (ORDER BY n), 0)::INT
      INTO v_normal
      FROM (SELECT fecha, count(*) n FROM estado_diario_flota
             WHERE fecha BETWEEN p_desde AND v_tope GROUP BY fecha) x;

    RETURN QUERY
    WITH base AS (
        SELECT * FROM estado_diario_flota
         WHERE fecha BETWEEN p_desde AND p_hasta
           AND estado_codigo <> 'S'
    ),
    por_dia AS (
        SELECT fecha, count(*) n FROM estado_diario_flota
         WHERE fecha BETWEEN p_desde AND v_tope GROUP BY fecha
    )
    SELECT
        round(100.0 * count(*) FILTER (WHERE b.estado_codigo NOT IN ('M','T','F','H'))::numeric
              / NULLIF(count(*), 0), 2),
        (SELECT round(avg(disponibilidad_mecanica_pct), 2)
           FROM v_resumen_diario_flota WHERE fecha BETWEEN p_desde AND p_hasta),
        count(*),
        count(*) FILTER (WHERE b.estado_codigo NOT IN ('M','T','F','H')),
        (SELECT count(*) FROM por_dia),
        v_trans,
        v_trans - (SELECT count(*)::INT FROM por_dia),
        (SELECT count(*)::INT FROM por_dia WHERE n < v_normal / 2.0),
        v_normal
      FROM base b;
END;
$$;

REVOKE ALL ON FUNCTION fn_taller_disponibilidad_periodo(DATE, DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_taller_disponibilidad_periodo(DATE, DATE) TO authenticated;

-- ── Verificación (sólo lectura) ─────────────────────────────────────────────
DO $mig$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT * FROM fn_taller_disponibilidad_periodo(DATE '2026-08-24', DATE '2026-09-23') LOOP
        RAISE NOTICE 'corte 24-ago a 23-sep · disponibilidad % (promedio diario %)',
            r.disponibilidad_pct, r.promedio_diario_pct;
        RAISE NOTICE '   % de % días transcurridos tienen registro · % sin registro · % a medias · día normal = % equipos',
            r.dias_con_registro, r.dias_transcurridos, r.dias_sin_registro,
            r.dias_incompletos, r.equipos_dia_normal;
    END LOOP;

    -- El corte cerrado de agosto, que sí está completo, para comparar.
    FOR r IN SELECT * FROM fn_taller_disponibilidad_periodo(DATE '2026-07-24', DATE '2026-08-23') LOOP
        RAISE NOTICE 'corte 24-jul a 23-ago · disponibilidad % · % de % días con registro',
            r.disponibilidad_pct, r.dias_con_registro, r.dias_transcurridos;
    END LOOP;
END
$mig$;

COMMIT;
