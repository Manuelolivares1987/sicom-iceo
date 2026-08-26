-- ============================================================================
-- MIG402 · El grupo de trabajo deja de duplicarse solo
-- ----------------------------------------------------------------------------
-- LO QUE SE VE EN PANTALLA
-- En la bandeja de No Conformidades, la columna «Recursos del conjunto» del
-- SVBJ-57 dice:
--
--     Joel Coo, Yusdel Sarduy, Yusdel Sarduy, Joel Coo · 16h
--
-- Dos mecánicos, cuatro nombres. Y está así en las 32 NC del equipo.
--
-- POR QUÉ SE DUPLICA — Y POR QUÉ IBA A EMPEORAR
-- El modal de recursos lee `equipo.grupos`, que es la suma de los
-- `grupo_trabajo` de TODAS las NC del equipo, y al guardar lo escribe de vuelta
-- en CADA UNA. O sea: lee un agregado y lo devuelve como si fuera un valor
-- individual.
--
-- Cada vez que alguien abre y guarda ese modal, la lista se vuelve a concatenar
-- consigo misma. Dos nombres pasan a cuatro, cuatro a ocho. No es un dato mal
-- escrito una vez: es una bola de nieve que crece con el uso normal.
--
-- QUÉ SE HACE
--   1. El RPC deja de aceptar duplicados. La UI se arregla aparte, pero la base
--      no puede depender de que quien escriba lo haga bien: normaliza y guarda
--      cada nombre una sola vez, respetando el orden en que se eligieron.
--   2. Se limpia lo que ya está escrito.
--
-- POR QUÉ TAMBIÉN EN LA BASE Y NO SÓLO EN LA UI
-- Hay dos pantallas que escriben este campo —el modal de la NC y el del
-- conjunto del equipo— y mañana puede haber una tercera. Una regla que vive en
-- un solo componente se olvida en el siguiente.
-- ============================================================================

BEGIN;

-- ── 1. Normalizar una lista de nombres separados por coma ─────────────────
CREATE OR REPLACE FUNCTION public.fn_normalizar_grupo_trabajo(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $function$
  SELECT NULLIF(
    (SELECT string_agg(nombre, ', ' ORDER BY orden)
       FROM (
         SELECT DISTINCT ON (lower(btrim(t.nombre)))
                btrim(t.nombre) AS nombre,
                t.orden
           FROM unnest(string_to_array(COALESCE(p_texto, ''), ',')) WITH ORDINALITY AS t(nombre, orden)
          WHERE btrim(t.nombre) <> ''
          -- El primero que aparece es el que manda: se conserva el orden en que
          -- los eligieron, no un alfabético que nadie pidió.
          ORDER BY lower(btrim(t.nombre)), t.orden
       ) u),
    '');
$function$;

COMMENT ON FUNCTION public.fn_normalizar_grupo_trabajo(text) IS
  'MIG402: quita repetidos y espacios sobrantes de una lista de nombres separados por coma, conservando el orden de la primera aparición.';

-- ── 2. El RPC ya no acepta duplicados ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_nc_recursos_mo(
    p_nc_id uuid,
    p_grupo text DEFAULT NULL,
    p_horas numeric DEFAULT NULL,
    p_tiempo_dias numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_rol TEXT := fn_user_rol(); v_grupo TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento',
                     'supervisor','planificador') THEN
        RAISE EXCEPTION 'Sin permiso para definir recursos (rol: %)', v_rol; END IF;
    IF NOT EXISTS (SELECT 1 FROM no_conformidades WHERE id = p_nc_id) THEN
        RAISE EXCEPTION 'La no conformidad no existe'; END IF;

    -- [MIG402] Cada nombre una sola vez. La pantalla lee un agregado del equipo
    -- y lo escribe de vuelta en cada NC, así que sin esto la lista se concatena
    -- consigo misma en cada guardado.
    v_grupo := fn_normalizar_grupo_trabajo(p_grupo);

    UPDATE no_conformidades
       SET grupo_trabajo        = COALESCE(v_grupo, grupo_trabajo),
           horas_estimadas      = COALESCE(p_horas, horas_estimadas),
           tiempo_estimado_dias = COALESCE(p_tiempo_dias, tiempo_estimado_dias),
           updated_at           = NOW()
     WHERE id = p_nc_id;

    RETURN jsonb_build_object('success', true, 'grupo_trabajo', v_grupo);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_nc_recursos_mo(uuid, text, numeric, numeric) TO authenticated;

-- ── 3. Limpiar lo que ya está escrito ─────────────────────────────────────
DO $r$
DECLARE v_n INT;
BEGIN
    UPDATE no_conformidades
       SET grupo_trabajo = fn_normalizar_grupo_trabajo(grupo_trabajo),
           updated_at    = NOW()
     WHERE grupo_trabajo IS NOT NULL
       AND grupo_trabajo IS DISTINCT FROM fn_normalizar_grupo_trabajo(grupo_trabajo);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'No conformidades con el grupo de trabajo corregido: %', v_n;

    FOR v_n IN SELECT 1 LOOP EXIT; END LOOP;
END
$r$;

DO $r$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT DISTINCT grupo_trabajo FROM no_conformidades
              WHERE grupo_trabajo IS NOT NULL AND grupo_trabajo LIKE '%,%'
    LOOP RAISE NOTICE 'Grupo tras la limpieza: «%»', r.grupo_trabajo; END LOOP;
END
$r$;

COMMIT;
