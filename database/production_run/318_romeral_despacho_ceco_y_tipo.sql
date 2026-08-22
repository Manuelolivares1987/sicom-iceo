-- ============================================================================
-- MIG318 · El despacho acepta el CECO que el catálogo todavía no tiene
-- ----------------------------------------------------------------------------
-- LA REGLA
--   Si el equipo está en el catálogo, su CECO viaja solo y nadie lo escribe.
--   Si no está —o está sin CECO— quien despacha lo ANOTA en el momento, y el
--   sistema lo guarda como propuesto. Nunca se bloquea el despacho por esto:
--   el combustible ya salió, negarse a registrarlo no lo devuelve al estanque.
--
--   Anotar un CECO nuevo NO lo mete al catálogo oficial. Queda marcado
--   `origen='terreno', confirmado=false` para que alguien con permiso lo
--   confirme. Es la diferencia entre "el operador registró lo que sabe" y
--   "el operador modificó el maestro", que no es lo mismo.
--
-- POR QUÉ IMPORTA
--   En junio, el 65 % de las transacciones del tag maestro llegó sin CECO y se
--   completó después en oficina, de memoria. El dato lo tiene quien está
--   cargando, en el momento de cargar. Pedírselo ahí cuesta un campo; pedírselo
--   tres días después cuesta una investigación.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_despachar(
    p_faena_id uuid, p_fecha date, p_turno text, p_estanque_id uuid,
    p_equipo_id uuid, p_ubicacion_id uuid, p_meter_inicial numeric,
    p_meter_final numeric, p_litros numeric,
    p_operador_nombre text DEFAULT NULL::text,
    p_hora time without time zone DEFAULT NULL::time without time zone,
    p_equipo_texto text DEFAULT NULL::text,
    p_ubicacion_texto text DEFAULT NULL::text,
    p_camion_patente text DEFAULT NULL::text,
    p_horometro numeric DEFAULT NULL::numeric,
    p_kilometraje numeric DEFAULT NULL::numeric,
    p_observacion text DEFAULT NULL::text,
    p_client_uuid text DEFAULT NULL::text,
    p_foto_meter_inicial text DEFAULT NULL::text,
    p_foto_meter_final text DEFAULT NULL::text,
    p_sin_foto_motivo text DEFAULT NULL::text,
    -- [MIG318] Lo nuevo, todo al final y con default: las llamadas que ya
    -- existen siguen funcionando sin tocarlas.
    p_ceco_texto text DEFAULT NULL::text,
    p_tipo_movimiento text DEFAULT 'venta',
    p_flota text DEFAULT NULL::text,
    p_destino_estanque_id uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_id     UUID;
    v_litros NUMERIC;
    v_ceco   UUID;
    v_codigo TEXT;
    v_tipo   TEXT := lower(trim(COALESCE(p_tipo_movimiento, 'venta')));
BEGIN
    IF fn_user_rol() IS NULL THEN RAISE EXCEPTION 'Sesión requerida'; END IF;
    IF p_faena_id IS NULL THEN RAISE EXCEPTION 'Falta la faena'; END IF;
    IF v_tipo NOT IN ('venta','trasvasije','recirculacion','calibracion') THEN
        v_tipo := 'venta';
    END IF;

    -- Reintento del teléfono sin señal: si ya se guardó, se devuelve el mismo.
    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM combustible_faena_despachos WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            UPDATE combustible_faena_despachos
               SET foto_meter_inicial_url = COALESCE(p_foto_meter_inicial, foto_meter_inicial_url),
                   foto_meter_final_url   = COALESCE(p_foto_meter_final, foto_meter_final_url)
             WHERE id = v_id;
            RETURN jsonb_build_object('success', true, 'despacho_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    v_litros := COALESCE(
        CASE WHEN p_meter_final IS NOT NULL AND p_meter_inicial IS NOT NULL
                  AND p_meter_final >= p_meter_inicial
             THEN p_meter_final - p_meter_inicial END,
        p_litros);
    IF v_litros IS NULL OR v_litros < 0 THEN RAISE EXCEPTION 'Litros inválidos'; END IF;

    -- 1. El CECO del equipo del catálogo manda.
    SELECT ceco_id INTO v_ceco FROM combustible_faena_equipos WHERE id = p_equipo_id;

    -- 2. Si no hay, se usa el que anotó quien despacha. Se busca antes de
    --    crear: escribir "115037" dos veces no puede generar dos CECO.
    v_codigo := upper(trim(COALESCE(p_ceco_texto, '')));
    IF v_ceco IS NULL AND length(v_codigo) >= 2 THEN
        SELECT id INTO v_ceco FROM combustible_faena_cecos
         WHERE faena_id = p_faena_id AND upper(trim(codigo)) = v_codigo
         LIMIT 1;

        IF v_ceco IS NULL THEN
            INSERT INTO combustible_faena_cecos
                (faena_id, codigo, activo, origen, confirmado, anotado_por, anotado_at,
                 observacion)
            VALUES (p_faena_id, v_codigo, true, 'terreno', false,
                    NULLIF(TRIM(COALESCE(p_operador_nombre,'')),''), NOW(),
                    'Anotado en terreno al despachar. Falta confirmar.')
            RETURNING id INTO v_ceco;
        END IF;
    END IF;

    INSERT INTO combustible_faena_despachos (
        faena_id, fecha, turno, estanque_id, camion_patente,
        equipo_id, equipo_texto, ceco_id, ceco_texto, ubicacion_id, ubicacion_texto,
        meter_inicial, meter_final, litros,
        operador_id, operador_nombre, horometro, kilometraje, observacion, hora,
        client_uuid, created_by,
        foto_meter_inicial_url, foto_meter_final_url, sin_foto_motivo,
        tipo_movimiento, flota, destino_estanque_id)
    VALUES (
        p_faena_id, COALESCE(p_fecha, CURRENT_DATE), NULLIF(TRIM(COALESCE(p_turno,'')),''),
        p_estanque_id, NULLIF(TRIM(COALESCE(p_camion_patente,'')),''),
        p_equipo_id, NULLIF(TRIM(COALESCE(p_equipo_texto,'')),''), v_ceco,
        NULLIF(v_codigo,''),
        p_ubicacion_id, NULLIF(TRIM(COALESCE(p_ubicacion_texto,'')),''),
        p_meter_inicial, p_meter_final, v_litros,
        auth.uid(), NULLIF(TRIM(COALESCE(p_operador_nombre,'')),''),
        p_horometro, p_kilometraje, NULLIF(TRIM(COALESCE(p_observacion,'')),''),
        p_hora, p_client_uuid, auth.uid(),
        NULLIF(TRIM(COALESCE(p_foto_meter_inicial,'')),''),
        NULLIF(TRIM(COALESCE(p_foto_meter_final,'')),''),
        NULLIF(TRIM(COALESCE(p_sin_foto_motivo,'')),''),
        v_tipo, NULLIF(TRIM(COALESCE(p_flota,'')),''), p_destino_estanque_id)
    RETURNING id INTO v_id;

    RETURN jsonb_build_object(
        'success', true, 'despacho_id', v_id, 'litros', v_litros,
        'ceco_id', v_ceco, 'ceco_anotado', (v_ceco IS NOT NULL AND length(v_codigo) >= 2));
END $function$;

-- ── Bandeja: lo que quedó anotado en terreno y falta confirmar ─────────────
CREATE OR REPLACE VIEW public.v_comb_faena_ceco_por_confirmar AS
SELECT
    c.id            AS ceco_id,
    c.faena_id,
    c.codigo,
    c.empresa,
    c.anotado_por,
    c.anotado_at,
    COUNT(d.id)::int                      AS despachos,
    COALESCE(SUM(d.litros), 0)::numeric   AS litros,
    MIN(d.fecha)                          AS desde,
    MAX(d.fecha)                          AS hasta,
    -- Con qué nombres de equipo se usó: es la pista para saber a qué CECO real
    -- corresponde cuando alguien lo vaya a confirmar.
    (ARRAY_AGG(DISTINCT COALESCE(e.nombre, d.equipo_texto))
       FILTER (WHERE COALESCE(e.nombre, d.equipo_texto) IS NOT NULL))[1:8] AS equipos
FROM combustible_faena_cecos c
LEFT JOIN combustible_faena_despachos d ON d.ceco_id = c.id AND NOT d.anulado
LEFT JOIN combustible_faena_equipos  e  ON e.id = d.equipo_id
WHERE c.origen = 'terreno' AND NOT c.confirmado
GROUP BY c.id, c.faena_id, c.codigo, c.empresa, c.anotado_por, c.anotado_at;

GRANT SELECT ON public.v_comb_faena_ceco_por_confirmar TO authenticated;

COMMENT ON VIEW public.v_comb_faena_ceco_por_confirmar IS
  'CECO anotados en terreno esperando confirmacion, con cuantos litros arrastran y con que equipos se usaron. MIG318.';

-- ── Confirmar o corregir un CECO anotado ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_confirmar_ceco(
    p_ceco_id uuid,
    p_codigo  text DEFAULT NULL,   -- si venía mal escrito, se corrige acá
    p_empresa text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_faena UUID; v_nuevo TEXT; v_existente UUID; v_movidos INT := 0;
BEGIN
    IF NOT public.fn_tiene_permiso_modulo('combustible', 'edit', ARRAY[
           'administrador','gerencia','subgerente_operaciones',
           'jefe_operaciones','supervisor','planificador'])
    THEN
        RAISE EXCEPTION 'No autorizado para confirmar CECO.' USING ERRCODE = '42501';
    END IF;

    SELECT faena_id INTO v_faena FROM combustible_faena_cecos WHERE id = p_ceco_id;
    IF v_faena IS NULL THEN RAISE EXCEPTION 'CECO no existe.'; END IF;

    v_nuevo := upper(trim(COALESCE(p_codigo, '')));

    -- Si se corrige hacia un CECO que ya existe, no se duplica: se reapuntan
    -- los despachos al bueno y el anotado se retira.
    IF length(v_nuevo) >= 2 THEN
        SELECT id INTO v_existente FROM combustible_faena_cecos
         WHERE faena_id = v_faena AND upper(trim(codigo)) = v_nuevo AND id <> p_ceco_id
         LIMIT 1;
    END IF;

    IF v_existente IS NOT NULL THEN
        UPDATE combustible_faena_despachos SET ceco_id = v_existente WHERE ceco_id = p_ceco_id;
        GET DIAGNOSTICS v_movidos = ROW_COUNT;
        UPDATE combustible_faena_cecos SET activo = false WHERE id = p_ceco_id;
        RETURN jsonb_build_object('fusionado_con', v_existente, 'despachos_movidos', v_movidos);
    END IF;

    UPDATE combustible_faena_cecos
       SET codigo     = COALESCE(NULLIF(v_nuevo,''), codigo),
           empresa    = COALESCE(NULLIF(trim(COALESCE(p_empresa,'')),''), empresa),
           confirmado = true,
           origen     = 'maestro'
     WHERE id = p_ceco_id;

    RETURN jsonb_build_object('confirmado', true, 'ceco_id', p_ceco_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_confirmar_ceco(uuid, text, text) TO authenticated;

COMMIT;
