-- ============================================================================
-- MIG368 · Los meses en castellano, y fuera la entrega de prueba
-- ----------------------------------------------------------------------------
-- 1. EL INFORME DECÍA «01 de August»
--    `to_char(fecha, 'TMMonth')` usa el `lc_time` del servidor, que en Supabase
--    viene en inglés. El nombre del mes es de las pocas cosas del informe que
--    lee el mandante sin buscarlas, y salía en otro idioma.
--
--    Se resuelve con una tabla de nombres y no cambiando la configuración del
--    servidor: cambiar `lc_time` afecta a toda la base por una línea de texto, y
--    el día que alguien restaure desde otro entorno vuelve a estar en inglés.
--
-- 2. QUEDÓ UNA ENTREGA DE TURNO DE PRUEBA EN PRODUCCIÓN
--    Al probar la pantalla con la cuenta de Marcelo Espinosa se abrió una
--    entrega del 18 al 24 de agosto que nunca se firmó. Está vacía —sin firma,
--    sin equipos, sin litros— pero aparece en el informe del mes y en la lista
--    del supervisor, y una entrega fantasma en un listado de entregas es
--    exactamente el dato que alguien toma por bueno.
--
--    Se borra sólo si sigue abierta y sin firmar. Una entregada o recibida no
--    se toca: eso es un documento.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_mes_castellano(p_fecha date)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    SELECT (ARRAY['enero','febrero','marzo','abril','mayo','junio',
                  'julio','agosto','septiembre','octubre','noviembre','diciembre'])
           [EXTRACT(MONTH FROM p_fecha)::int];
$f$;

COMMENT ON FUNCTION public.fn_mes_castellano(date) IS
  'El nombre del mes en castellano, sin depender del lc_time del servidor: en Supabase viene en ingles y el informe al mandante salia con «August». MIG368.';


CREATE OR REPLACE FUNCTION public.fn_faena_periodo_texto(
    p_desde date, p_hasta date, p_corte time
)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    SELECT 'Desde el ' || to_char(p_desde, 'DD') || ' de ' || public.fn_mes_castellano(p_desde)
        || ' de ' || to_char(p_desde, 'YYYY')
        || ', a las ' || to_char(p_corte, 'HH24:MI')
        || ' hrs., hasta el ' || to_char(p_hasta + 1, 'DD') || ' de '
        || public.fn_mes_castellano(p_hasta + 1) || ' de ' || to_char(p_hasta + 1, 'YYYY')
        || ', a las ' || to_char(p_corte, 'HH24:MI') || ' hrs.';
$f$;

GRANT EXECUTE ON FUNCTION public.fn_mes_castellano(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_faena_periodo_texto(date, date, time) TO authenticated;


-- El informe usa el texto nuevo. Se reemplaza sólo esa expresión; el resto de
-- la función queda igual.
DO $patch$
DECLARE
    v_def TEXT;
BEGIN
    SELECT pg_get_functiondef('public.fn_faena_informe_mensual(uuid,date,date)'::regprocedure)
      INTO v_def;

    -- Se reemplazan las dos expresiones exactas y nada más. Intentar calzar el
    -- bloque completo falla: pg_get_functiondef devuelve el cuerpo con su
    -- propio espaciado, no con el que uno escribió.
    v_def := replace(v_def, $o1$to_char(p_desde, 'TMMonth')$o1$,
                            $n1$public.fn_mes_castellano(p_desde)$n1$);
    v_def := replace(v_def, $o2$to_char(p_hasta + 1, 'TMMonth')$o2$,
                            $n2$public.fn_mes_castellano(p_hasta + 1)$n2$);

    IF v_def LIKE '%TMMonth%' THEN
        RAISE EXCEPTION 'MIG368: quedó un TMMonth sin reemplazar en fn_faena_informe_mensual';
    END IF;

    EXECUTE v_def;
END
$patch$;


-- ── Fuera la entrega de prueba ────────────────────────────────────────────
DELETE FROM public.faena_entrega_turno e
 WHERE e.estado = 'abierta'
   AND e.entregado_at IS NULL
   AND e.entrega_nombre IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.faena_entrega_equipo q WHERE q.entrega_id = e.id);

COMMIT;

-- ── Verificación ──────────────────────────────────────────────────────────
-- SELECT fn_faena_informe_mensual((SELECT id FROM faenas WHERE codigo='FAE-FRANCKE'),
--                                 DATE '2026-08-01', DATE '2026-08-31')->'periodo';
