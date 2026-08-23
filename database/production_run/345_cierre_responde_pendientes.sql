-- ============================================================================
-- MIG345 · El turno no se firma sin decir qué pasó con lo que quedó pendiente
-- ----------------------------------------------------------------------------
-- MIG344 creó los pendientes. Esto los mete donde importa: en la firma.
--
-- El supervisor ya declara cuántas cargas revisó (MIG342). Ahora declara además
-- qué hizo con cada cosa que quedó pendiente del turno anterior. Si no
-- responde, el cierre no se firma — porque el turno que no contesta es
-- exactamente el que rompe la continuidad, y hasta hoy no le costaba nada.
--
-- «Hecho» se explica solo. Lo que necesita explicación es lo que NO se hizo:
-- sin motivo escrito, el turno siguiente recibe el mismo pendiente sin saber
-- qué se intentó y vuelve a empezar de cero. Eso es lo que reclama el mandante.
-- ============================================================================

BEGIN;

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
    p_pendientes  jsonb DEFAULT NULL
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

        -- Lo que quedó pendiente del turno anterior. No se puede cerrar el
        -- turno ignorándolo: el turno que no contesta es exactamente el que
        -- rompe la continuidad, y hasta hoy no le costaba nada.
        v_pend := public.fn_comb_responder_pendientes(
            p_faena_id, v_id, p_fecha, p_turno, p_medido_por, p_pendientes);

        -- ── La verificación del turno ──
        IF p_verificacion IS NOT NULL THEN
            v_vd := (p_verificacion->>'despachos')::integer;
            v_vl := (p_verificacion->>'litros')::numeric;

            SELECT COALESCE(v.despachos, 0), COALESCE(v.litros, 0)
              INTO v_rd, v_rl
              FROM v_comb_faena_dia_para_verificar v
             WHERE v.faena_id = p_faena_id AND v.fecha = p_fecha;
            v_rd := COALESCE(v_rd, 0);
            v_rl := COALESCE(v_rl, 0);

            IF v_rd IS DISTINCT FROM v_vd THEN
                RAISE EXCEPTION 'Usted revisó % carga(s) y el día tiene %. Puede haber llegado una carga desde terreno mientras revisaba: vuelva a mirar la lista antes de firmar.',
                    COALESCE(v_vd, 0), v_rd USING ERRCODE = '22023';
            END IF;
            IF v_vl IS NOT NULL AND round(v_rl) <> round(v_vl) THEN
                RAISE EXCEPTION 'Usted revisó % L y el día suma % L. Vuelva a mirar la lista antes de firmar.',
                    round(v_vl), round(v_rl) USING ERRCODE = '22023';
            END IF;

            UPDATE combustible_faena_cierre
               SET despachos_verificados = v_vd,
                   litros_verificados = v_vl,
                   verificado_at = NOW(),
                   verificado_por = p_medido_por
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
           SET estado = 'firmado', firmado_at = NOW(), updated_at = NOW()
         WHERE id = v_id;

        INSERT INTO combustible_faena_cierre_bitacora (cierre_id, accion, usuario_id, usuario, motivo)
        VALUES (v_id, 'firmado', auth.uid(), p_medido_por,
                CASE WHEN p_verificacion IS NULL
                     THEN 'Firmado sin verificar las cargas del turno.'
                     ELSE 'Verificadas ' || COALESCE(v_vd,0) || ' carga(s) del turno.' END
                || CASE WHEN v_pend > 0
                        THEN ' Respondio ' || v_pend || ' pendiente(s).' ELSE '' END);
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar,
                              'verificado', p_verificacion IS NOT NULL,
                              'pendientes_respondidos', v_pend);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text, jsonb, jsonb) TO authenticated;

-- destructivo-ok: se elimina la firma anterior (sin p_pendientes) para que no
-- queden dos versiones del RPC. Una firma vieja que sobreviva la puede llamar
-- un telefono con la app cacheada y firmar el turno saltandose los pendientes,
-- que es justamente lo que se quiere impedir. No borra datos.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text, jsonb);

COMMIT;
