-- 634 — El informe de fiabilidad (link público) dice quién está fuera del
-- cálculo en el rango y desde cuándo (MIG633), para que se entienda por qué
-- un equipo no aparece. Parche a la definición viva.
DO $$
DECLARE
    v_def TEXT := replace(pg_get_functiondef('public.fn_reporte_fiabilidad_publico'::regproc), chr(13), '');
    a     TEXT := E'    ''combustible'', COALESCE((';
BEGIN
    IF position('fuera_de_calculo' IN v_def) > 0 THEN RETURN; END IF;
    IF position(a IN v_def) = 0 THEN RAISE EXCEPTION 'MIG634: no se encontró el bloque combustible'; END IF;
    EXECUTE replace(v_def, a,
        E'    ''fuera_de_calculo'', COALESCE((SELECT jsonb_agg(to_jsonb(z)) FROM fn_fiabilidad_excluidos(p_ini, p_fin) z), ''[]''::jsonb),\n' || a);
END $$;
