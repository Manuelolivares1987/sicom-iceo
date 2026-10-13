-- ############################################################################
-- MIG587 · 'V' en venta vuelve a contar en el indicador
-- ----------------------------------------------------------------------------
-- MIG585 sacó del denominador de fiabilidad los días 'V' (en venta) junto con
-- 'B' (vendido). Manuel lo corrigió el mismo día: un equipo en venta sigue
-- siendo flota y SÍ debe afectar el indicador, como antes. Lo único que sale
-- es lo vendido, y sale de todo el sistema (la ficha queda 'dado_baja').
--
-- Queda así:
--   · 'V' en venta  → cuenta como antes (día arriba) y aparece en el status.
--   · 'B' vendido   → fuera del denominador y fuera de las listas.
--   · 'S' siniestro → sin cambios (MIG306).
-- ############################################################################

BEGIN;

DO $patch$
DECLARE
    r       RECORD;
    v_def   TEXT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
          ('fn_calcular_fiabilidad_activo',     $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('fn_calcular_fiabilidad_flota',      $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('calcular_oee_activo',               $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('fn_panel_disponibilidad',           $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('fn_panel_equipos_detenidos',        $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('fn_calcular_oee_fiabilidad_activo', $$NOT IN ('S','V','B')$$, $$NOT IN ('S','B')$$),
          ('fn_reporte_fiabilidad_publico',     $$NOT IN ('V','B')$$,     $$<> 'B'$$)
        ) AS t(fn, viejo, nuevo)
    LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = r.fn AND p.prokind = 'f';
        IF v_def IS NULL THEN RAISE EXCEPTION 'MIG587: no existe %', r.fn; END IF;
        IF position(r.viejo IN v_def) = 0 THEN
            RAISE EXCEPTION 'MIG587: en % no aparece %', r.fn, r.viejo;
        END IF;
        EXECUTE replace(v_def, r.viejo, r.nuevo);
        RAISE NOTICE 'MIG587: % — V vuelve a contar', r.fn;
    END LOOP;
END $patch$;

COMMIT;

SELECT a.patente, f.dias_observados, f.disponibilidad_fisica
  FROM activos a
  CROSS JOIN LATERAL fn_calcular_fiabilidad_activo(a.id, date_trunc('month', CURRENT_DATE)::date, CURRENT_DATE) f
 WHERE a.estado_comercial = 'en_venta'
 ORDER BY 1;
