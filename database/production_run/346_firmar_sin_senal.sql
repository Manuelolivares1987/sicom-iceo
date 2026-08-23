-- ============================================================================
-- MIG346 · El turno se cierra aunque no haya señal
-- ----------------------------------------------------------------------------
-- Romeral tiene mala señal. No «a veces»: es la condición normal del lugar, y
-- todo lo que exija estar en línea a una hora fija se va a dejar de usar.
--
-- Hasta ahora firmar el cierre exigía conexión. A las 18:00, con el estanque
-- medido y las fotos sacadas, el supervisor no podía cerrar el día. Lo que
-- pasa en la vida real cuando eso ocurre: se vuelve al papel.
--
-- EL CONFLICTO QUE HABÍA QUE RESOLVER
-- MIG342 hace que el supervisor declare cuántas cargas revisó, y el sistema
-- lo rechaza si no coincide con lo que hay. Eso es correcto EN LÍNEA: si llegó
-- una carga mientras revisaba, tiene que volver a mirar.
--
-- Sin señal es imposible de cumplir. El teléfono revisó lo que tenía adentro;
-- las cargas que otro operador sincronizó a las 18:10 no las podía ver. Si al
-- sincronizar tres horas después se rechaza el cierre, el día no cierra nunca
-- y el supervisor pierde el trabajo hecho.
--
-- CÓMO SE RESUELVE
-- Un cierre firmado sin señal se acepta, y se marca. Si al llegar al servidor
-- resulta que había más cargas de las que el supervisor vio, no se bloquea:
-- se registra la diferencia y aparece como excepción para la oficina.
--
--     «Este cierre se firmó sin ver 2 cargas que llegaron después.»
--
-- Es la misma decisión que se viene tomando en todo el módulo: no bloquear el
-- turno, hacer visible la diferencia. Un control que impide trabajar se
-- desactiva; uno que muestra el hueco se usa.
-- ============================================================================

BEGIN;

ALTER TABLE public.combustible_faena_cierre
    ADD COLUMN IF NOT EXISTS firmado_sin_senal BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS verificacion_delta INTEGER;

COMMENT ON COLUMN public.combustible_faena_cierre.firmado_sin_senal IS
  'El turno se cerro en el telefono, sin conexion, y subio despues. MIG346.';
COMMENT ON COLUMN public.combustible_faena_cierre.verificacion_delta IS
  'Cuantas cargas mas tenia el dia al sincronizar respecto de las que el supervisor alcanzo a ver. Cero o nulo = vio todo. MIG346.';

CREATE OR REPLACE FUNCTION public.rpc_comb_faena_guardar_cierre(
    p_faena_id  uuid,
    p_fecha     date,
    p_turno     text,
    p_medido_por text,
    p_puntos    jsonb,
    p_medidores jsonb,
    p_observacion text DEFAULT NULL,
    p_firmar    boolean DEFAULT false,
    p_client_uuid text DEFAULT NULL,
    p_verificacion jsonb DEFAULT NULL,
    p_pendientes  jsonb DEFAULT NULL,
    p_sin_senal   boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id      UUID;
    v_r       JSONB;
    v_ini     NUMERIC;
    v_fin     NUMERIC;
    v_faltan  TEXT[];
    v_agua    TEXT[];
    v_rd      INTEGER;
    v_rl      NUMERIC;
    v_vd      INTEGER;
    v_vl      NUMERIC;
    v_pend    INTEGER := 0;
    v_delta   INTEGER := 0;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
    END IF;
    IF p_firmar AND NOT public.fn_comb_puede_cerrar() THEN
        RAISE EXCEPTION 'Puede guardar el turno, pero firmar el cierre le corresponde al supervisor de turno.'
            USING ERRCODE = '42501';
    END IF;

    INSERT INTO combustible_faena_cierre
        (faena_id, fecha, turno, medido_por, observacion, client_uuid, created_by)
    VALUES (p_faena_id, p_fecha, NULLIF(trim(COALESCE(p_turno,'')),''),
            p_medido_por, p_observacion, p_client_uuid, auth.uid())
    ON CONFLICT (faena_id, fecha, turno) DO UPDATE
        SET medido_por = EXCLUDED.medido_por,
            observacion = EXCLUDED.observacion,
            updated_at = NOW()
    RETURNING id INTO v_id;

    IF (SELECT estado FROM combustible_faena_cierre WHERE id = v_id) = 'firmado'
       AND NOT p_firmar THEN
        RAISE EXCEPTION 'Este cierre ya está firmado. Reábralo si necesita corregirlo.'
            USING ERRCODE = '42501';
    END IF;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_puntos, '[]'::jsonb))
    LOOP
        INSERT INTO combustible_faena_cierre_punto
            (cierre_id, estanque_id, mi, rfp, rt, mf, agua_mm, temperatura_c, densidad_api,
             sin_medicion, motivo_sin_medicion, foto_url, sin_foto_motivo)
        VALUES (v_id, (v_r->>'estanque_id')::uuid,
                (v_r->>'mi')::numeric, (v_r->>'rfp')::numeric, (v_r->>'rt')::numeric,
                (v_r->>'mf')::numeric, (v_r->>'agua_mm')::numeric,
                (v_r->>'temperatura_c')::numeric, (v_r->>'densidad_api')::numeric,
                COALESCE((v_r->>'sin_medicion')::boolean, false),
                NULLIF(v_r->>'motivo_sin_medicion',''), NULLIF(v_r->>'foto_url',''),
                NULLIF(v_r->>'sin_foto_motivo',''))
        ON CONFLICT (cierre_id, estanque_id) DO UPDATE
            SET mi = EXCLUDED.mi, rfp = EXCLUDED.rfp, rt = EXCLUDED.rt, mf = EXCLUDED.mf,
                agua_mm = EXCLUDED.agua_mm, temperatura_c = EXCLUDED.temperatura_c,
                densidad_api = EXCLUDED.densidad_api,
                sin_medicion = EXCLUDED.sin_medicion,
                motivo_sin_medicion = EXCLUDED.motivo_sin_medicion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_punto.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                updated_at = NOW();
    END LOOP;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_medidores, '[]'::jsonb))
    LOOP
        v_ini := (v_r->>'numeral_ini')::numeric;
        v_fin := (v_r->>'numeral_fin')::numeric;

        IF v_ini IS NOT NULL AND v_fin IS NOT NULL AND v_fin < v_ini
           AND NOT COALESCE((v_r->>'reinicio_contador')::boolean, false) THEN
            RAISE EXCEPTION 'El contador no puede bajar: anotó % y antes marcaba %. Revise el número, o marque que se cambió el contador.',
                v_fin, v_ini USING ERRCODE = '22023';
        END IF;

        INSERT INTO combustible_faena_cierre_medidor
            (cierre_id, medidor_id, numeral_ini, numeral_fin, calibracion,
             foto_url, sin_foto_motivo, reinicio_contador, motivo_reinicio)
        VALUES (v_id, (v_r->>'medidor_id')::uuid, v_ini, v_fin,
                COALESCE((v_r->>'calibracion')::numeric, 0),
                NULLIF(v_r->>'foto_url',''), NULLIF(v_r->>'sin_foto_motivo',''),
                COALESCE((v_r->>'reinicio_contador')::boolean, false),
                NULLIF(v_r->>'motivo_reinicio',''))
        ON CONFLICT (cierre_id, medidor_id) DO UPDATE
            SET numeral_ini = EXCLUDED.numeral_ini, numeral_fin = EXCLUDED.numeral_fin,
                calibracion = EXCLUDED.calibracion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_medidor.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                reinicio_contador = EXCLUDED.reinicio_contador,
                motivo_reinicio = EXCLUDED.motivo_reinicio,
                updated_at = NOW();

        IF v_fin IS NOT NULL THEN
            UPDATE combustible_faena_medidores
               SET ultimo_numeral = v_fin
             WHERE id = (v_r->>'medidor_id')::uuid
               AND (ultimo_numeral IS NULL OR v_fin >= ultimo_numeral
                    OR COALESCE((v_r->>'reinicio_contador')::boolean, false));
        END IF;
    END LOOP;

    IF p_firmar THEN
        SELECT array_agg(e.nombre ORDER BY e.orden_cierre) INTO v_faltan
          FROM combustible_faena_cierre_punto p
          JOIN combustible_estanques e ON e.id = p.estanque_id
         WHERE p.cierre_id = v_id AND NOT p.sin_medicion AND p.mf IS NOT NULL
           AND COALESCE(p.foto_url,'') = '' AND COALESCE(p.sin_foto_motivo,'') = '';
        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION 'Falta la foto de la varilla en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ') USING ERRCODE = '22023';
        END IF;

        SELECT array_agg(COALESCE(md.etiqueta, md.surtidor || ' ' || md.numero) ORDER BY md.orden)
          INTO v_faltan
          FROM combustible_faena_cierre_medidor cm
          JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
         WHERE cm.cierre_id = v_id AND cm.numeral_fin IS NOT NULL
           AND COALESCE(cm.foto_url,'') = '' AND COALESCE(cm.sin_foto_motivo,'') = '';
        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION 'Falta la foto del contador en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ') USING ERRCODE = '22023';
        END IF;

        IF NULLIF(trim(COALESCE(p_medido_por,'')),'') IS NULL THEN
            RAISE EXCEPTION 'Falta el nombre de quien midió.' USING ERRCODE = '22023';
        END IF;

        v_pend := public.fn_comb_responder_pendientes(
            p_faena_id, v_id, p_fecha, p_turno, p_medido_por, p_pendientes);

        IF p_verificacion IS NOT NULL THEN
            v_vd := (p_verificacion->>'despachos')::integer;
            v_vl := (p_verificacion->>'litros')::numeric;

            SELECT COALESCE(v.despachos, 0), COALESCE(v.litros, 0)
              INTO v_rd, v_rl
              FROM v_comb_faena_dia_para_verificar v
             WHERE v.faena_id = p_faena_id AND v.fecha = p_fecha;
            v_rd := COALESCE(v_rd, 0);
            v_rl := COALESCE(v_rl, 0);
            v_delta := v_rd - COALESCE(v_vd, 0);

            -- En línea, el supervisor puede volver a mirar ahora mismo, así que
            -- se le exige. Sin señal no puede: el teléfono revisó lo que tenía,
            -- y lo que otro sincronizó después no lo podía ver. Bloquearlo ahí
            -- sería perder el turno entero por algo que no estaba en su mano.
            IF NOT p_sin_senal THEN
                IF v_delta <> 0 THEN
                    RAISE EXCEPTION 'Usted revisó % carga(s) y el día tiene %. Puede haber llegado una carga desde terreno mientras revisaba: vuelva a mirar la lista antes de firmar.',
                        COALESCE(v_vd, 0), v_rd USING ERRCODE = '22023';
                END IF;
                IF v_vl IS NOT NULL AND round(v_rl) <> round(v_vl) THEN
                    RAISE EXCEPTION 'Usted revisó % L y el día suma % L. Vuelva a mirar la lista antes de firmar.',
                        round(v_vl), round(v_rl) USING ERRCODE = '22023';
                END IF;
            END IF;

            UPDATE combustible_faena_cierre
               SET despachos_verificados = v_vd, litros_verificados = v_vl,
                   verificado_at = NOW(), verificado_por = p_medido_por,
                   verificacion_delta = v_delta
             WHERE id = v_id;
        END IF;

        SELECT array_agg(e.nombre || ' (' || p.agua_mm || ' mm)') INTO v_agua
          FROM combustible_faena_cierre_punto p
          JOIN combustible_estanques e ON e.id = p.estanque_id
          LEFT JOIN combustible_faena_config c ON c.faena_id = p_faena_id
         WHERE p.cierre_id = v_id
           AND p.agua_mm > COALESCE(c.agua_critica_mm, 25);
        IF v_agua IS NOT NULL THEN
            RAISE WARNING 'AGUA EN ESTANQUE sobre el nivel critico: %. Drenar antes del proximo despacho.',
                array_to_string(v_agua, ', ');
        END IF;

        UPDATE combustible_faena_cierre
           SET estado = 'firmado', firmado_at = NOW(), updated_at = NOW(),
               firmado_sin_senal = p_sin_senal
         WHERE id = v_id;

        INSERT INTO combustible_faena_cierre_bitacora (cierre_id, accion, usuario_id, usuario, motivo)
        VALUES (v_id, 'firmado', auth.uid(), p_medido_por,
                CASE WHEN p_sin_senal THEN 'Firmado en el telefono sin senal. ' ELSE '' END
                || CASE WHEN p_verificacion IS NULL
                        THEN 'Sin verificar las cargas del turno.'
                        ELSE 'Verificadas ' || COALESCE(v_vd,0) || ' carga(s).' END
                || CASE WHEN v_delta <> 0
                        THEN ' Al sincronizar habia ' || v_delta || ' carga(s) mas.' ELSE '' END
                || CASE WHEN v_pend > 0
                        THEN ' Respondio ' || v_pend || ' pendiente(s).' ELSE '' END);
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar,
                              'verificado', p_verificacion IS NOT NULL,
                              'pendientes_respondidos', v_pend,
                              'cargas_no_vistas', v_delta,
                              'sin_senal', p_sin_senal);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text, jsonb, jsonb, boolean) TO authenticated;

-- destructivo-ok: se elimina la firma anterior (sin p_sin_senal) para que no
-- queden dos versiones del RPC. Una firma vieja que sobreviva la puede llamar
-- un telefono con la app cacheada, y en ese caso la verificacion desactualizada
-- volveria a bloquear el cierre offline en vez de marcarlo. No borra datos.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text, jsonb, jsonb);

-- ── Un cierre firmado sin ver todo entra a las excepciones ─────────────────
CREATE OR REPLACE VIEW public.v_comb_faena_cierre_desactualizado AS
SELECT c.faena_id, c.fecha, c.turno, c.medido_por, c.firmado_at,
       c.despachos_verificados AS vio, c.verificacion_delta AS no_vio,
       c.firmado_sin_senal
FROM combustible_faena_cierre c
WHERE c.estado = 'firmado' AND COALESCE(c.verificacion_delta, 0) > 0;

GRANT SELECT ON public.v_comb_faena_cierre_desactualizado TO authenticated;

COMMIT;
