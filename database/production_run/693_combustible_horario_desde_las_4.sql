-- ============================================================================
-- MIG693 · Horario normal de carga: lunes a viernes 04:00-19:00 (antes 07:00)
-- ----------------------------------------------------------------------------
-- Manuel, 15-11-2026: «dejemos desde las 04:00 de lunes a viernes, porque
-- muchas veces van a lugares alejados». Solo cambia la hora de inicio de la
-- alerta fuera_horario (MIG691). Se reescribe la vista base desde su propia
-- definición para no duplicar 400 líneas; aborta si el texto no calza.
-- Las justificaciones ya hechas quedan; las cargas 04:00-07:00 dejan de ser
-- diferencia.
-- ============================================================================
DO $$
DECLARE
    v_def TEXT := pg_get_viewdef('public.v_combustible_tarjeta_cargas_base'::regclass, true);
    v_old TEXT := '< ''07:00:00''::time without time zone';
    v_new TEXT := '< ''04:00:00''::time without time zone';
BEGIN
    IF position(v_new IN v_def) > 0 THEN
        RAISE NOTICE 'Ya estaba en 04:00.';
        RETURN;
    END IF;
    IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
        RAISE EXCEPTION 'La regla de horario no aparece exactamente una vez en la vista base.';
    END IF;
    EXECUTE 'CREATE OR REPLACE VIEW public.v_combustible_tarjeta_cargas_base AS ' || replace(v_def, v_old, v_new);
END $$;
REVOKE ALL ON public.v_combustible_tarjeta_cargas_base FROM PUBLIC, anon, authenticated;

SELECT 'MIG693 OK' AS resultado,
       position('''04:00:00''' IN pg_get_viewdef('public.v_combustible_tarjeta_cargas_base'::regclass)) > 0 AS horario_04;
