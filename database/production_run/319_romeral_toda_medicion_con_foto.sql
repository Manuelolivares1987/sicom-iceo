-- ============================================================================
-- MIG319 · Toda medición de combustible va con foto
-- ----------------------------------------------------------------------------
-- POR QUÉ ES DISTINTO A OTRAS EVIDENCIAS
--   Un número de varilla o de contador no se puede volver a verificar. Mañana
--   el estanque tiene otro nivel y el contador otro numeral: la medición de hoy
--   existe una sola vez y sólo en la cabeza de quien la tomó. Si además el
--   combustible se le factura a un mandante, la foto no es respaldo — es el
--   documento. Es la diferencia entre "medimos 38.400" y "acá está la varilla
--   marcando 38.400 el 22 de agosto".
--
--   El libro de agosto muestra lo que pasa sin foto: el 10-08 alguien anotó un
--   numeral que produjo -2.845.287 L. Con foto, la corrección es mirar la
--   imagen. Sin foto, es llamar a alguien que ya se fue y creerle.
--
-- DÓNDE SE EXIGE
--   Al FIRMAR, no al escribir. Se puede medir el recorrido completo sin señal y
--   sin sacar una sola foto todavía; lo que no se puede es dar el turno por
--   cerrado sin la evidencia. Guardar borrador nunca se bloquea: perder
--   mediciones por una regla es peor que la regla.
--
-- LA SALIDA HONESTA
--   En faena una cámara se moja, se queda sin batería o el estanque está en un
--   lugar donde no se puede sacar el teléfono. "No pude" con motivo escrito es
--   una respuesta válida y queda contada: si aparece todos los días en el mismo
--   punto, eso es información, no una excusa. Lo que NO se acepta es firmar
--   dejando el hueco en blanco.
-- ============================================================================

BEGIN;

ALTER TABLE public.combustible_faena_cierre_punto
    ADD COLUMN IF NOT EXISTS sin_foto_motivo TEXT;

ALTER TABLE public.combustible_faena_cierre_medidor
    ADD COLUMN IF NOT EXISTS sin_foto_motivo TEXT;

COMMENT ON COLUMN public.combustible_faena_cierre_punto.sin_foto_motivo IS
  'Por que no hay foto de esta medicion. Escrito, no un checkbox: un motivo que hay que redactar se piensa. MIG319.';

-- ── Guardar el cierre, ahora con la evidencia ──────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_comb_faena_guardar_cierre(
    p_faena_id  uuid,
    p_fecha     date,
    p_turno     text,
    p_medido_por text,
    p_puntos    jsonb,
    p_medidores jsonb,
    p_observacion text DEFAULT NULL,
    p_firmar    boolean DEFAULT false,
    p_client_uuid text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id       UUID;
    v_r        JSONB;
    v_ini      NUMERIC;
    v_fin      NUMERIC;
    v_faltan   TEXT[] := ARRAY[]::TEXT[];
    v_nombre   TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'No autenticado.' USING ERRCODE = '42501';
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
        RAISE EXCEPTION 'Este cierre ya está firmado. Pida reapertura para corregirlo.'
            USING ERRCODE = '42501';
    END IF;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_puntos, '[]'::jsonb))
    LOOP
        INSERT INTO combustible_faena_cierre_punto
            (cierre_id, estanque_id, mi, rfp, rt, mf, agua_mm, temperatura_c,
             sin_medicion, motivo_sin_medicion, foto_url, sin_foto_motivo)
        VALUES (v_id, (v_r->>'estanque_id')::uuid,
                (v_r->>'mi')::numeric, (v_r->>'rfp')::numeric, (v_r->>'rt')::numeric,
                (v_r->>'mf')::numeric, (v_r->>'agua_mm')::numeric, (v_r->>'temperatura_c')::numeric,
                COALESCE((v_r->>'sin_medicion')::boolean, false),
                NULLIF(v_r->>'motivo_sin_medicion',''), NULLIF(v_r->>'foto_url',''),
                NULLIF(v_r->>'sin_foto_motivo',''))
        ON CONFLICT (cierre_id, estanque_id) DO UPDATE
            SET mi = EXCLUDED.mi, rfp = EXCLUDED.rfp, rt = EXCLUDED.rt, mf = EXCLUDED.mf,
                agua_mm = EXCLUDED.agua_mm, temperatura_c = EXCLUDED.temperatura_c,
                sin_medicion = EXCLUDED.sin_medicion,
                motivo_sin_medicion = EXCLUDED.motivo_sin_medicion,
                -- La foto nunca se borra por un guardado posterior: puede subir
                -- después que el número, cuando aparezca señal.
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_punto.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                updated_at = NOW();
    END LOOP;

    FOR v_r IN SELECT * FROM jsonb_array_elements(COALESCE(p_medidores, '[]'::jsonb))
    LOOP
        v_ini := (v_r->>'numeral_ini')::numeric;
        v_fin := (v_r->>'numeral_fin')::numeric;

        IF v_ini IS NOT NULL AND v_fin IS NOT NULL AND v_fin < v_ini THEN
            RAISE EXCEPTION 'El contador no puede bajar: anotó % y antes marcaba %. Revise el número.',
                v_fin, v_ini USING ERRCODE = '22023';
        END IF;

        INSERT INTO combustible_faena_cierre_medidor
            (cierre_id, medidor_id, numeral_ini, numeral_fin, calibracion,
             foto_url, sin_foto_motivo)
        VALUES (v_id, (v_r->>'medidor_id')::uuid, v_ini, v_fin,
                COALESCE((v_r->>'calibracion')::numeric, 0),
                NULLIF(v_r->>'foto_url',''), NULLIF(v_r->>'sin_foto_motivo',''))
        ON CONFLICT (cierre_id, medidor_id) DO UPDATE
            SET numeral_ini = EXCLUDED.numeral_ini, numeral_fin = EXCLUDED.numeral_fin,
                calibracion = EXCLUDED.calibracion,
                foto_url = COALESCE(EXCLUDED.foto_url, combustible_faena_cierre_medidor.foto_url),
                sin_foto_motivo = EXCLUDED.sin_foto_motivo,
                updated_at = NOW();

        IF v_fin IS NOT NULL THEN
            UPDATE combustible_faena_medidores
               SET ultimo_numeral = v_fin
             WHERE id = (v_r->>'medidor_id')::uuid
               AND (ultimo_numeral IS NULL OR v_fin >= ultimo_numeral);
        END IF;
    END LOOP;

    -- ── La puerta: firmar exige evidencia ──────────────────────────────────
    IF p_firmar THEN
        -- Puntos medidos sin foto ni motivo.
        SELECT array_agg(e.nombre ORDER BY e.orden_cierre)
          INTO v_faltan
          FROM combustible_faena_cierre_punto p
          JOIN combustible_estanques e ON e.id = p.estanque_id
         WHERE p.cierre_id = v_id
           AND NOT p.sin_medicion
           AND p.mf IS NOT NULL
           AND COALESCE(p.foto_url,'') = ''
           AND COALESCE(p.sin_foto_motivo,'') = '';

        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION
                'Falta la foto de la varilla en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ')
                USING ERRCODE = '22023';
        END IF;

        -- Contadores leídos sin foto ni motivo.
        SELECT array_agg(COALESCE(md.etiqueta, md.surtidor || ' ' || md.numero) ORDER BY md.orden)
          INTO v_faltan
          FROM combustible_faena_cierre_medidor cm
          JOIN combustible_faena_medidores md ON md.id = cm.medidor_id
         WHERE cm.cierre_id = v_id
           AND cm.numeral_fin IS NOT NULL
           AND COALESCE(cm.foto_url,'') = ''
           AND COALESCE(cm.sin_foto_motivo,'') = '';

        IF v_faltan IS NOT NULL AND array_length(v_faltan,1) > 0 THEN
            RAISE EXCEPTION
                'Falta la foto del contador en: %. Sáquela, o escriba por qué no pudo.',
                array_to_string(v_faltan, ', ')
                USING ERRCODE = '22023';
        END IF;

        IF NULLIF(trim(COALESCE(p_medido_por,'')),'') IS NULL THEN
            RAISE EXCEPTION 'Falta el nombre de quien midió.' USING ERRCODE = '22023';
        END IF;

        UPDATE combustible_faena_cierre
           SET estado = 'firmado', firmado_at = NOW(), updated_at = NOW()
         WHERE id = v_id;
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(uuid, date, text, text, jsonb, jsonb, text, boolean, text) TO authenticated;

-- ── Cobertura de evidencia, para que se pueda auditar ──────────────────────
-- Un "no pude" aislado es la vida real. El mismo punto sin foto todo el mes es
-- otra cosa, y hay que poder verlo sin abrir cierre por cierre.
CREATE OR REPLACE VIEW public.v_comb_faena_evidencia AS
SELECT
    c.faena_id,
    c.fecha,
    c.turno,
    c.estado,
    c.medido_por,
    COUNT(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL)::int          AS puntos_medidos,
    COUNT(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
                       AND COALESCE(p.foto_url,'') <> '')::int                    AS puntos_con_foto,
    COUNT(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL
                       AND COALESCE(p.foto_url,'') = ''
                       AND COALESCE(p.sin_foto_motivo,'') <> '')::int             AS puntos_sin_foto_justificados,
    COUNT(*) FILTER (WHERE p.sin_medicion)::int                                   AS puntos_no_medidos,
    (SELECT COUNT(*) FILTER (WHERE cm.numeral_fin IS NOT NULL)::int
       FROM combustible_faena_cierre_medidor cm WHERE cm.cierre_id = c.id)        AS medidores_leidos,
    (SELECT COUNT(*) FILTER (WHERE cm.numeral_fin IS NOT NULL
                               AND COALESCE(cm.foto_url,'') <> '')::int
       FROM combustible_faena_cierre_medidor cm WHERE cm.cierre_id = c.id)        AS medidores_con_foto
FROM combustible_faena_cierre c
LEFT JOIN combustible_faena_cierre_punto p ON p.cierre_id = c.id
GROUP BY c.id, c.faena_id, c.fecha, c.turno, c.estado, c.medido_por;

GRANT SELECT ON public.v_comb_faena_evidencia TO authenticated;

COMMENT ON VIEW public.v_comb_faena_evidencia IS
  'Cobertura fotografica del cierre por dia. Un "no pude" aislado es normal; el mismo punto sin foto todo el mes es informacion. MIG319.';

COMMIT;
