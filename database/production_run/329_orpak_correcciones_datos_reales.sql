-- ============================================================================
-- MIG329 · Dos cosas que sólo se ven cargando el archivo de verdad
-- ----------------------------------------------------------------------------
-- Al pasar junio 2026 completo por la ingesta (1.368 transacciones) salieron
-- dos errores que ninguna prueba sintética habría mostrado.
--
-- 1. LA ESTACIÓN MANDA SOBRE EL VEHÍCULO
--    Un trasvasije aparece en la hoja MINA así:
--        Station Name = «ROM Mina»   ·   Vehicle = «TRASVASIJE CAMION FSLZ67»
--    El combustible SALE de Mina y ENTRA al camión 67. La estación dice de
--    dónde salió; el vehículo dice quién lo recibió. Yo tenía las reglas por
--    vehículo antes que las de estación, así que esos 24 movimientos se
--    descontaban del camión — que no los había entregado todavía — en vez de
--    Mina, que era donde faltaban. El estanque de Mina cuadraba de más y el
--    del camión de menos, por 125.789 litros en nueve días.
--    Las reglas por vehículo pasan al final: son el último recurso cuando la
--    estación no dice nada.
--
-- 2. EL CECO TAMBIÉN VIENE ENTRE PARÉNTESIS
--    En la hoja BIMODAL los transportistas se identifican así:
--        «(77243899-0) SOCIEDAD DE TRANSPORTES TAPIA ARGANDONA SPA»
--    y no como «115037 Empresa Santa Elvira». Son 723 de 1.368 filas — más de
--    la mitad del archivo quedaba sin imputar por un paréntesis.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_orpak_ceco_codigo(p_departamento text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    -- Tres formas conviven en el mismo archivo:
    --   «115037 Empresa Santa Elvira»                    -> 115037
    --   «79588870-5 ESMAX»                               -> 79588870-5
    --   «(77243899-0) SOCIEDAD DE TRANSPORTES TAPIA ...» -> 77243899-0
    SELECT NULLIF((regexp_match(trim(COALESCE(p_departamento,'')),
                                '^\(?\s*([0-9]{4,}(?:-[0-9kK])?)\s*\)?'))[1], '');
$f$;

-- Las reglas por vehículo bajan al final. Ojo con el orden del UPDATE: si se
-- suma 80 a las que ya están sobre 80 se vuelven a mover, por eso se acota a
-- las tres reglas de vehículo puro.
UPDATE public.combustible_orpak_estacion_map
   SET prioridad = 80 + prioridad
 WHERE patron_estacion IS NULL
   AND patron_vehiculo IS NOT NULL
   AND prioridad < 80;

-- Recalcular el CECO de lo ya cargado: la corrección tiene que alcanzar a las
-- filas que entraron antes, no sólo a las próximas.
UPDATE public.combustible_orpak_transaccion t
   SET ceco_codigo = public.fn_orpak_ceco_codigo(t.departamento)
 WHERE t.departamento IS NOT NULL
   AND t.ceco_codigo IS DISTINCT FROM public.fn_orpak_ceco_codigo(t.departamento);

UPDATE public.combustible_orpak_transaccion t
   SET ceco_id = c.id
  FROM public.combustible_faena_cecos c
 WHERE c.faena_id = t.faena_id AND c.codigo = t.ceco_codigo AND c.activo
   AND t.ceco_id IS NULL;

COMMIT;
