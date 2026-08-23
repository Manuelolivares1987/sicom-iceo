-- ============================================================================
-- MIG342 · El supervisor de turno firma por lo que verificó, no sólo por lo
--          que midió
-- ----------------------------------------------------------------------------
-- Hasta ahora el cierre del día firmaba las MEDICIONES: la varilla de cada
-- estanque y el numeral de cada cuentalitros. Eso responde «cuánto se movió»,
-- y deja fuera la otra mitad del trabajo del supervisor de turno, que es
-- revisar QUÉ se hizo: las cargas del turno, a quién fueron, si alguna quedó
-- sin CECO, si el trasvasije del aljibe quedó marcado como trasvasije y no
-- como venta.
--
-- El instructivo lo pide explícitamente en el criterio de cierre:
--     «Se revisó la bitácora de despacho de los camiones.»
--
-- QUÉ CAMBIA
-- Al firmar hay que declarar cuántas cargas y cuántos litros se revisaron. Si
-- ese número no coincide con lo que hay en el sistema, el cierre se rechaza y
-- dice la diferencia.
--
-- POR QUÉ ASÍ Y NO CON UN SIMPLE «REVISADO»
-- Una casilla de «ya revisé» se marca sin mirar; es el control que más rápido
-- se degrada. Pedir el número obliga a haber abierto la lista. Y resuelve un
-- caso real que un tilde no ve: el supervisor revisa a las 18:00, un operador
-- que venía sin señal sincroniza a las 18:10, y a las 18:15 se firma un día
-- que ya no es el que se miró. Con el número, ese cierre se detiene solo.
--
-- Se puede firmar igual sin verificar —hay días en que no hay nadie más y el
-- turno tiene que cerrar— pero entonces queda registrado que no se verificó,
-- que es distinto a que no hubiera nada que verificar.
-- ============================================================================

BEGIN;

ALTER TABLE public.combustible_faena_cierre
    ADD COLUMN IF NOT EXISTS despachos_verificados INTEGER,
    ADD COLUMN IF NOT EXISTS litros_verificados    NUMERIC,
    ADD COLUMN IF NOT EXISTS verificado_at         TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS verificado_por        TEXT;

COMMENT ON COLUMN public.combustible_faena_cierre.despachos_verificados IS
  'Cuantas cargas declaro haber revisado el supervisor de turno al firmar. Si no coincide con las que hay, el cierre se rechaza. MIG342.';

-- ── Lo que el supervisor de turno tiene que mirar antes de firmar ──────────
CREATE OR REPLACE VIEW public.v_comb_faena_dia_para_verificar AS
SELECT d.faena_id, d.fecha,
       count(*)::integer                                   AS despachos,
       COALESCE(sum(d.litros), 0)                          AS litros,
       count(*) FILTER (WHERE d.tipo_movimiento = 'venta')::integer      AS ventas,
       count(*) FILTER (WHERE d.tipo_movimiento = 'trasvasije')::integer AS trasvasijes,
       COALESCE(sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije'), 0) AS litros_trasvasije,
       count(*) FILTER (WHERE d.ceco_id IS NULL AND COALESCE(d.ceco_texto,'') = ''
                          AND d.tipo_movimiento = 'venta')::integer      AS sin_ceco,
       count(*) FILTER (WHERE COALESCE(d.foto_meter_final_url,'') = ''
                          AND COALESCE(d.sin_foto_motivo,'') = '')::integer AS sin_foto,
       count(DISTINCT d.operador_nombre)::integer          AS operadores
FROM combustible_faena_despachos d
WHERE NOT d.anulado
GROUP BY d.faena_id, d.fecha;

GRANT SELECT ON public.v_comb_faena_dia_para_verificar TO authenticated;

COMMENT ON VIEW public.v_comb_faena_dia_para_verificar IS
  'El resumen del turno que el supervisor revisa antes de firmar: cuantas cargas, cuantos litros, cuales quedaron sin CECO o sin foto. MIG342.';

-- ── Firmar declarando qué se verificó ──────────────────────────────────────
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
    p_verificacion jsonb DEFAULT NULL
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
                     ELSE 'Verificadas ' || COALESCE(v_vd,0) || ' carga(s) del turno.' END);
    END IF;

    RETURN jsonb_build_object('cierre_id', v_id, 'firmado', p_firmar,
                              'verificado', p_verificacion IS NOT NULL);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text, jsonb) TO authenticated;

-- destructivo-ok: se elimina la firma anterior de rpc_comb_faena_guardar_cierre
-- (sin p_verificacion) para que no queden dos versiones. Una firma vieja que
-- sobreviva la puede llamar un telefono con la app cacheada y saltarse la
-- verificacion del turno sin dejar rastro. No borra datos.
DROP FUNCTION IF EXISTS public.rpc_comb_faena_guardar_cierre(
    uuid, date, text, text, jsonb, jsonb, text, boolean, text);

-- ── Un cierre firmado sin verificar es un dato, no un delito ───────────────
CREATE OR REPLACE VIEW public.v_comb_faena_cierre_sin_verificar AS
SELECT c.faena_id, c.fecha, c.turno, c.medido_por, c.firmado_at,
       COALESCE(v.despachos, 0) AS despachos_del_dia,
       COALESCE(v.litros, 0)    AS litros_del_dia
FROM combustible_faena_cierre c
LEFT JOIN v_comb_faena_dia_para_verificar v
       ON v.faena_id = c.faena_id AND v.fecha = c.fecha
WHERE c.estado = 'firmado'
  AND c.verificado_at IS NULL
  AND COALESCE(v.despachos, 0) > 0;

GRANT SELECT ON public.v_comb_faena_cierre_sin_verificar TO authenticated;

COMMIT;
