-- ============================================================================
-- MIG350 · Cada supervisor firma por SU turno, y el día no cierra a medias
-- ----------------------------------------------------------------------------
-- Dos correcciones que aparecen recién cuando el día tiene dos turnos.
--
-- 1. LA VERIFICACIÓN MIRABA EL DÍA COMPLETO
--    El supervisor de noche veía las cargas del turno de día sumadas a las
--    suyas y firmaba por todas. Rompe la separación que el cierre por turno
--    existe para sostener: cada uno responde por lo que pasó mientras estuvo.
--    Ahora la cuenta es del turno. El día completo se sigue mirando desde la
--    oficina y en los entregables, que es donde corresponde.
--
-- 2. EL DÍA SE VEÍA CERRADO CON UN TURNO ABIERTO
--    El estado del día salía de max(estado) de sus cierres. Entre 'borrador' y
--    'firmado' gana 'firmado' por orden alfabético, así que un día con el turno
--    de noche sin cerrar aparecía cerrado. Un tablero que dice que está listo
--    lo que no lo está es peor que no tener tablero.
--    Ahora el día está cerrado sólo si TODOS sus turnos lo están, y se muestra
--    cuáles faltan.
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

            -- Del TURNO, no del dia. Con dos turnos, mirar el dia completo
            -- haria que el supervisor de noche firmara tambien por las cargas
            -- del turno de dia, que es justo lo que el cierre por turno evita.
            SELECT COALESCE(v.despachos, 0), COALESCE(v.litros, 0)
              INTO v_rd, v_rl
              FROM v_comb_faena_turno_para_verificar v
             WHERE v.faena_id = p_faena_id AND v.fecha = p_fecha
               AND v.turno = COALESCE(NULLIF(trim(COALESCE(p_turno,'')),''), 'Día');
            v_rd := COALESCE(v_rd, 0);
            v_rl := COALESCE(v_rl, 0);
            v_delta := v_rd - COALESCE(v_vd, 0);

            -- En línea, el supervisor puede volver a mirar ahora mismo, así que
            -- se le exige. Sin señal no puede: el teléfono revisó lo que tenía,
            -- y lo que otro sincronizó después no lo podía ver. Bloquearlo ahí
            -- sería perder el turno entero por algo que no estaba en su mano.
            IF NOT p_sin_senal THEN
                IF v_delta <> 0 THEN
                    RAISE EXCEPTION 'Usted revisó % carga(s) y el turno tiene %. Puede haber llegado una carga desde terreno mientras revisaba: vuelva a mirar la lista antes de firmar.',
                        COALESCE(v_vd, 0), v_rd USING ERRCODE = '22023';
                END IF;
                IF v_vl IS NOT NULL AND round(v_rl) <> round(v_vl) THEN
                    RAISE EXCEPTION 'Usted revisó % L y el turno suma % L. Vuelva a mirar la lista antes de firmar.',
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

-- ── El día no está cerrado si le falta un turno ────────────────────────────
-- destructivo-ok: se recrea la vista v_comb_faena_control_diario porque se le
-- agregan columnas al medio (turnos, turnos_firmados, turnos_detalle) y
-- CREATE OR REPLACE no permite insertar columnas, solo agregarlas al final. Es
-- una vista: no contiene datos, se reconstruye entera en esta misma migracion.
DROP VIEW IF EXISTS public.v_comb_faena_control_diario;

CREATE VIEW public.v_comb_faena_control_diario AS
WITH grupos AS (
    SELECT g.faena_id, g.fecha,
           sum(g.v_fis) AS v_fis, sum(g.v_mec) AS v_mec, sum(g.var1) AS var1,
           count(*) FILTER (WHERE g.resultado = 'investigar')::integer AS grupos_investigar,
           count(*) FILTER (WHERE g.resultado = 'atencion')::integer   AS grupos_atencion,
           count(*) FILTER (WHERE g.resultado = 'incompleto')::integer AS grupos_sin_contador
      FROM v_comb_faena_cuadre_grupo g
     GROUP BY g.faena_id, g.fecha
), turnos AS (
    SELECT t.faena_id, t.fecha, t.turnos, t.turnos_firmados, t.detalle, t.dia_completo
      FROM v_comb_faena_turnos_del_dia t
), puntos AS (
    SELECT p.faena_id, p.fecha,
           count(*) FILTER (WHERE NOT p.sin_medicion AND p.mf IS NOT NULL)::integer AS puntos_medidos,
           count(*)::integer AS puntos_total,
           string_agg(DISTINCT p.medido_por, ' · ') AS medido_por
      FROM v_comb_faena_cierre_punto p
     GROUP BY p.faena_id, p.fecha
), despachos AS (
    SELECT d.faena_id, d.fecha,
           sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'venta')      AS litros_venta,
           sum(d.litros) FILTER (WHERE d.tipo_movimiento = 'trasvasije') AS litros_trasvasije,
           sum(d.litros) AS litros_total,
           count(*)::integer AS despachos,
           count(*) FILTER (WHERE d.ceco_id IS NULL AND COALESCE(d.ceco_texto,'') = ''
                              AND d.tipo_movimiento = 'venta')::integer AS sin_ceco,
           count(*) FILTER (WHERE d.equipo_id IS NULL AND d.equipo_texto IS NOT NULL)::integer
               AS equipo_sin_mapear
      FROM combustible_faena_despachos d
     WHERE NOT d.anulado
     GROUP BY d.faena_id, d.fecha
), orpak AS (
    SELECT t.faena_id, t.dia_cierre AS fecha,
           count(*)::integer AS transacciones,
           sum(t.litros) FILTER (WHERE t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION')) AS litros_venta,
           sum(t.litros) FILTER (WHERE t.clasificacion = 'TRASVASIJE') AS litros_trasvasije,
           sum(t.litros) AS litros_total,
           count(*) FILTER (WHERE t.ceco_codigo IS NULL
                              AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION'))::integer
               AS sin_codigo,
           count(*) FILTER (WHERE t.ceco_codigo IS NOT NULL AND t.ceco_id IS NULL
                              AND t.clasificacion NOT IN ('TRASVASIJE','RECIRCULACION','CALIBRACION'))::integer
               AS fuera_del_maestro
      FROM combustible_orpak_transaccion t
     GROUP BY t.faena_id, t.dia_cierre
), recep AS (
    SELECT r.faena_id, r.fecha,
           sum(r.litros_recibidos) AS litros_recibidos,
           count(*)::integer AS recepciones,
           count(*) FILTER (WHERE r.estado <> 'confirmada')::integer AS recepciones_sin_confirmar,
           count(*) FILTER (WHERE r.diferencia_vs_guia IS NOT NULL
                              AND abs(r.diferencia_vs_guia) > 0)::integer AS recepciones_con_diferencia
      FROM v_comb_faena_recepcion r
     GROUP BY r.faena_id, r.fecha
)
SELECT COALESCE(gr.faena_id, de.faena_id, re.faena_id, op.faena_id) AS faena_id,
       COALESCE(gr.fecha, de.fecha, re.fecha, op.fecha) AS fecha,
       CASE WHEN tu.dia_completo THEN 'firmado' ELSE 'borrador' END AS estado_cierre,
       tu.turnos, tu.turnos_firmados, tu.detalle AS turnos_detalle,
       pu.medido_por, pu.puntos_medidos, pu.puntos_total,
       gr.grupos_investigar AS puntos_fuera_tolerancia,
       gr.grupos_atencion,
       gr.grupos_sin_contador AS puntos_sin_contador,
       gr.v_fis, gr.v_mec, gr.var1,
       CASE
         WHEN gr.fecha IS NULL THEN 'sin_cierre'
         WHEN NOT COALESCE(tu.dia_completo, false) THEN 'borrador'
         WHEN gr.grupos_investigar > 0 THEN 'revisar'
         WHEN gr.grupos_sin_contador > 0 THEN 'incompleto'
         ELSE 'cuadrado'
       END AS volumen_estado,
       COALESCE(de.despachos, 0) + COALESCE(op.transacciones, 0) AS despachos,
       COALESCE(de.litros_total, 0)      + COALESCE(op.litros_total, 0)      AS litros_total,
       COALESCE(de.litros_venta, 0)      + COALESCE(op.litros_venta, 0)      AS litros_venta,
       COALESCE(de.litros_trasvasije, 0) + COALESCE(op.litros_trasvasije, 0) AS litros_trasvasije,
       COALESCE(de.sin_ceco, 0) + COALESCE(op.sin_codigo, 0) AS sin_ceco,
       COALESCE(op.fuera_del_maestro, 0) AS ceco_fuera_del_maestro,
       de.equipo_sin_mapear,
       COALESCE(op.transacciones, 0) AS transacciones_orpak,
       CASE
         WHEN COALESCE(de.despachos, 0) + COALESCE(op.transacciones, 0) = 0 THEN 'sin_datos'
         WHEN COALESCE(de.sin_ceco, 0) + COALESCE(op.sin_codigo, 0) > 0 THEN 'incompleta'
         WHEN COALESCE(op.fuera_del_maestro, 0) > 0 THEN 'por_registrar'
         ELSE 'completa'
       END AS imputacion_estado,
       re.recepciones, re.litros_recibidos,
       re.recepciones_sin_confirmar, re.recepciones_con_diferencia
  FROM grupos gr
  LEFT JOIN turnos tu ON tu.faena_id = gr.faena_id AND tu.fecha = gr.fecha
  LEFT JOIN puntos pu ON pu.faena_id = gr.faena_id AND pu.fecha = gr.fecha
  FULL JOIN despachos de ON de.faena_id = gr.faena_id AND de.fecha = gr.fecha
  FULL JOIN orpak op ON op.faena_id = COALESCE(gr.faena_id, de.faena_id)
                    AND op.fecha    = COALESCE(gr.fecha, de.fecha)
  FULL JOIN recep re ON re.faena_id = COALESCE(gr.faena_id, de.faena_id, op.faena_id)
                    AND re.fecha    = COALESCE(gr.fecha, de.fecha, op.fecha);

GRANT SELECT ON public.v_comb_faena_control_diario TO authenticated;

COMMIT;
