-- ============================================================================
-- MIG339 · Los CECO se dan de alta solos desde el propio archivo de Orpak
-- ----------------------------------------------------------------------------
-- Quedaban 897 cargas de junio sin imputar por una razón administrativa: el
-- código venía en la transacción, se sabía perfectamente de quién era, y no
-- tenía ficha en la faena. Casi todos son transportistas de Huasco.
--
-- Pedirle a alguien que teclee 60 fichas a mano, copiando RUT y razón social
-- desde una lista en pantalla, es exactamente el tipo de trabajo que hace que
-- un sistema se abandone en la segunda semana. Y es innecesario: el dato ya
-- está adentro. El campo «Department» de Orpak trae el código Y la razón
-- social — «(77243899-0) SOCIEDAD DE TRANSPORTES TAPIA ARGANDONA SPA» — así
-- que la ficha se puede armar sola.
--
-- SE CREAN SIN CONFIRMAR, A PROPÓSITO
-- Nacen con origen='orpak' y confirmado=false, igual que un CECO anotado a
-- mano en terreno. Quedan operativos de inmediato —la imputación cierra— pero
-- marcados para que alguien los revise: una razón social mal escrita en Orpak
-- se arrastra hasta la facturación si nadie la mira. Automatizar el tecleo no
-- es lo mismo que automatizar el criterio.
--
-- NO SE CREAN LOS QUE NO SON CECO
-- El trasvasije entre estanques y la calibración del surtidor viajan con el
-- RUT de ESMAX y de Copec. No se le venden a nadie y no llevan ficha.
-- ============================================================================

BEGIN;

-- La razón social sale del mismo texto, quitándole el código del principio.
CREATE OR REPLACE FUNCTION public.fn_orpak_ceco_nombre(p_departamento text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $f$
    -- «(77243899-0) SOCIEDAD DE TRANSPORTES TAPIA» -> «SOCIEDAD DE TRANSPORTES TAPIA»
    -- «115037 Empresa Santa Elvira»                -> «Empresa Santa Elvira»
    -- «115074»                                     -> NULL (no trae nombre)
    SELECT NULLIF(trim(regexp_replace(trim(COALESCE(p_departamento, '')),
                                      '^\(?\s*[0-9]{4,}(?:-[0-9kK])?\s*\)?\s*', '')), '');
$f$;

CREATE OR REPLACE FUNCTION public.rpc_comb_orpak_dar_de_alta_cecos(p_faena_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_creados INT := 0;
    v_ligados INT := 0;
    v_usuario TEXT;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'No autorizado para dar de alta CECO.' USING ERRCODE = '42501';
    END IF;

    SELECT u.nombre_completo INTO v_usuario FROM usuarios_perfil u WHERE u.id = auth.uid();

    WITH nuevos AS (
        SELECT d.ceco_codigo AS codigo,
               public.fn_orpak_ceco_nombre(d.departamento) AS empresa
          FROM v_comb_orpak_ceco_desconocido d
         WHERE d.faena_id = p_faena_id
    ), insertados AS (
        INSERT INTO combustible_faena_cecos
            (faena_id, codigo, empresa, activo, origen, confirmado, anotado_por, anotado_at,
             observacion)
        SELECT p_faena_id, n.codigo, n.empresa, true, 'orpak', false,
               COALESCE(v_usuario, 'carga de Orpak'), NOW(),
               'Creado desde el archivo de Orpak. Revisar la razon social antes de facturar.'
          FROM nuevos n
         WHERE NOT EXISTS (
                SELECT 1 FROM combustible_faena_cecos c
                 WHERE c.faena_id = p_faena_id AND c.codigo = n.codigo)
        RETURNING 1
    )
    SELECT count(*) INTO v_creados FROM insertados;

    -- Las transacciones que ya estaban cargadas se enganchan a su ficha nueva.
    UPDATE combustible_orpak_transaccion t
       SET ceco_id = c.id
      FROM combustible_faena_cecos c
     WHERE c.faena_id = t.faena_id AND c.codigo = t.ceco_codigo AND c.activo
       AND t.faena_id = p_faena_id AND t.ceco_id IS NULL;
    GET DIAGNOSTICS v_ligados = ROW_COUNT;

    RETURN jsonb_build_object('creados', v_creados, 'transacciones_imputadas', v_ligados);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_orpak_dar_de_alta_cecos(uuid) TO authenticated;

COMMENT ON FUNCTION public.rpc_comb_orpak_dar_de_alta_cecos(uuid) IS
  'Crea la ficha de CECO de los codigos que Orpak usa y el maestro no tiene, con la razon social del propio archivo. Nacen sin confirmar: automatizar el tecleo no es automatizar el criterio. MIG339.';

-- Cada carga nueva de Orpak da de alta lo que traiga. Si el proceso pide una
-- accion manual todos los dias, esa accion se deja de hacer.
CREATE OR REPLACE FUNCTION public.rpc_comb_orpak_cargar(
    p_faena_id uuid,
    p_archivo  text,
    p_filas    jsonb
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_carga    UUID;
    v_r        JSONB;
    v_est      UUID;
    v_bomba    TEXT;
    v_hash     TEXT;
    v_ceco_cod TEXT;
    v_ceco     UUID;
    v_clase    TEXT;
    v_fecha    DATE;
    v_dia      DATE;
    v_litros   NUMERIC;
    v_nuevas   INT := 0;
    v_rep      INT := 0;
    v_rech     INT := 0;
    v_rechazos JSONB := '[]'::jsonb;
    v_ins      INT;
    v_alta     JSONB;
BEGIN
    IF NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'No autorizado para cargar el archivo de Orpak.' USING ERRCODE = '42501';
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

    -- Los CECO nuevos del archivo quedan dados de alta en el mismo paso.
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

GRANT EXECUTE ON FUNCTION public.rpc_comb_orpak_cargar(uuid, text, jsonb) TO authenticated;

-- ── Los CECO recien creados esperan revision, no confirmacion ciega ────────
CREATE OR REPLACE VIEW public.v_comb_faena_ceco_por_revisar AS
SELECT c.faena_id, c.id AS ceco_id, c.codigo, c.empresa, c.origen, c.anotado_at,
       count(t.id)::integer AS transacciones,
       COALESCE(sum(t.litros), 0) AS litros,
       min(t.dia_cierre) AS desde, max(t.dia_cierre) AS hasta
FROM combustible_faena_cecos c
LEFT JOIN combustible_orpak_transaccion t ON t.ceco_id = c.id
WHERE NOT c.confirmado AND c.activo AND c.origen = 'orpak'
GROUP BY c.faena_id, c.id, c.codigo, c.empresa, c.origen, c.anotado_at;

GRANT SELECT ON public.v_comb_faena_ceco_por_revisar TO authenticated;

COMMIT;
