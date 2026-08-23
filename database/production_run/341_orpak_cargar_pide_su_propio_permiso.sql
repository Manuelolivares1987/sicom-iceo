-- ============================================================================
-- MIG341 · El error de la carga de Orpak decía otra cosa
-- ----------------------------------------------------------------------------
-- Un operador de camión que intentaba cargar el archivo de Orpak recibía:
--
--     «No autorizado para dar de alta CECO.»
--
-- El bloqueo era correcto pero el mensaje no: la carga pasaba su propia puerta
-- y recién fallaba adentro, en el alta de CECO que corre al final. La persona
-- entiende que el problema son los CECO y no que la carga entera no le
-- corresponde, así que va a insistir por otro lado.
--
-- Un mensaje de error que apunta al lugar equivocado cuesta más que uno feo:
-- manda a alguien a resolver un problema que no existe.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.rpc_comb_orpak_cargar(
    p_faena_id uuid, p_archivo text, p_filas jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_carga UUID; v_r JSONB; v_est UUID; v_bomba TEXT; v_hash TEXT;
    v_ceco_cod TEXT; v_ceco UUID; v_clase TEXT; v_fecha DATE; v_dia DATE;
    v_litros NUMERIC; v_nuevas INT := 0; v_rep INT := 0; v_rech INT := 0;
    v_rechazos JSONB := '[]'::jsonb; v_ins INT; v_alta JSONB;
BEGIN
    IF NOT public.fn_comb_puede_administrar() THEN
        RAISE EXCEPTION 'Cargar el archivo de Orpak le corresponde al supervisor o al jefe de operaciones: reescribe la imputación de todo el período.'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO combustible_orpak_carga (faena_id, archivo, cargado_por, cargado_nombre)
    VALUES (p_faena_id, p_archivo, auth.uid(),
            (SELECT u.nombre_completo FROM usuarios_perfil u WHERE u.id = auth.uid()))
    RETURNING id INTO v_carga;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_filas, '[]'::jsonb))
    LOOP
        v_fecha  := NULLIF(v_r->>'fecha','')::date;
        v_litros := NULLIF(v_r->>'litros','')::numeric;

        IF v_fecha IS NULL OR v_litros IS NULL OR v_litros = 0 THEN
            v_rech := v_rech + 1;
            IF jsonb_array_length(v_rechazos) < 50 THEN
                v_rechazos := v_rechazos || jsonb_build_object(
                    'hoja', v_r->>'hoja', 'fila', v_r->>'serie',
                    'motivo', 'sin fecha o sin litros');
            END IF;
            CONTINUE;
        END IF;

        v_dia := COALESCE(NULLIF(v_r->>'dia_cierre','')::date, v_fecha);

        SELECT f.estanque_id, f.bomba INTO v_est, v_bomba
          FROM fn_orpak_estanque(p_faena_id, v_r->>'estacion', v_r->>'vehiculo', v_r->>'bomba') f;

        IF v_est IS NULL THEN
            v_rech := v_rech + 1;
            IF jsonb_array_length(v_rechazos) < 50 THEN
                v_rechazos := v_rechazos || jsonb_build_object(
                    'hoja', v_r->>'hoja', 'fila', v_r->>'serie',
                    'motivo', 'estacion no reconocida: ' || COALESCE(v_r->>'estacion','(vacia)'));
            END IF;
            CONTINUE;
        END IF;

        v_clase    := fn_orpak_clasificar(p_faena_id, v_r->>'flota', v_r->>'vehiculo');
        v_ceco_cod := fn_orpak_ceco_codigo(v_r->>'departamento');

        SELECT c.id INTO v_ceco FROM combustible_faena_cecos c
         WHERE c.faena_id = p_faena_id AND c.codigo = v_ceco_cod AND c.activo;

        v_hash := md5(concat_ws('|', v_dia::text, COALESCE(v_r->>'hora',''),
                                fn_orpak_norm(v_r->>'vehiculo'), v_litros::text,
                                v_est::text, COALESCE(v_bomba,''),
                                COALESCE(v_r->>'tarjeta',''), COALESCE(v_r->>'serie','')));

        INSERT INTO combustible_orpak_transaccion
            (carga_id, faena_id, hoja, serie, fecha, hora, flota, vehiculo, producto,
             litros, estacion_texto, estanque_id, bomba, departamento, ceco_codigo,
             ceco_id, tarjeta, autorizado_por, clasificacion, dia_cierre, hash_fila)
        VALUES (v_carga, p_faena_id, v_r->>'hoja', v_r->>'serie', v_fecha, v_r->>'hora',
                v_r->>'flota', v_r->>'vehiculo', v_r->>'producto', v_litros,
                v_r->>'estacion', v_est, v_bomba, v_r->>'departamento', v_ceco_cod,
                v_ceco, v_r->>'tarjeta', v_r->>'autorizado_por', v_clase, v_dia, v_hash)
        ON CONFLICT (faena_id, hash_fila) DO NOTHING;

        GET DIAGNOSTICS v_ins = ROW_COUNT;
        IF v_ins = 1 THEN v_nuevas := v_nuevas + 1; ELSE v_rep := v_rep + 1; END IF;
    END LOOP;

    v_alta := public.rpc_comb_orpak_dar_de_alta_cecos(p_faena_id);

    UPDATE combustible_orpak_carga
       SET filas_leidas = jsonb_array_length(COALESCE(p_filas,'[]'::jsonb)),
           filas_nuevas = v_nuevas, filas_repetidas = v_rep,
           filas_rechazadas = v_rech, rechazos = v_rechazos,
           periodo_desde = (SELECT min(dia_cierre) FROM combustible_orpak_transaccion WHERE carga_id = v_carga),
           periodo_hasta = (SELECT max(dia_cierre) FROM combustible_orpak_transaccion WHERE carga_id = v_carga)
     WHERE id = v_carga;

    RETURN jsonb_build_object(
        'carga_id', v_carga, 'nuevas', v_nuevas, 'repetidas', v_rep,
        'rechazadas', v_rech, 'rechazos', v_rechazos,
        'cecos_creados', v_alta->'creados',
        'desde', (SELECT periodo_desde FROM combustible_orpak_carga WHERE id = v_carga),
        'hasta', (SELECT periodo_hasta FROM combustible_orpak_carga WHERE id = v_carga));
END;
$function$;

COMMIT;
