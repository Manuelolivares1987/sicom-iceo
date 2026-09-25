-- ============================================================================
-- MIG577 · Centinela: un cierre a mano no se reabre solo a los pocos minutos
-- ============================================================================
--
-- 25-09-2026, Manuel: «se hizo un comentario desde otro PC, por la patente
-- KVWD-27 y yo no lo puedo ver». Lo que pasó:
--   12:08 UTC  se CERRÓ el incidente de KVWD-27 (motivo «otro»): «camión se
--              encuentra cerca de punta colorada detenido por motivo no
--              habilitación de camino…».
--   12:15 UTC  fn_centinela_evaluar vio el tracker igual de mudo y abrió un
--              incidente NUEVO y vacío; a las 12:20 salió otro correo de
--              «crítico nuevo». El comentario quedó en el incidente cerrado.
--
-- Ahora, antes de abrir un incidente nuevo, se respeta el cierre manual del
-- mismo camión y la misma regla:
--   · corte / mudo: mientras el tracker no haya vuelto a reportar desde ese
--     cierre, hasta 7 días (para re-verificar).
--   · fuera de zona / de horario: 24 h.
-- Los cierres automáticos (señal recuperada, normalizado, traslado) no cuentan.
-- Además se cierra el incidente reabierto de KVWD-27 con el comentario original.
-- ============================================================================

BEGIN;

ALTER TABLE centinela_config
    ADD COLUMN IF NOT EXISTS horas_respeta_cierre_silencio NUMERIC NOT NULL DEFAULT 168,
    ADD COLUMN IF NOT EXISTS horas_respeta_cierre_zona     NUMERIC NOT NULL DEFAULT 24;
COMMENT ON COLUMN centinela_config.horas_respeta_cierre_silencio IS
    '[MIG577] Tras un cierre manual de un corte/mudo, no reabrir el mismo corte durante estas horas (si el tracker no volvió a reportar).';

CREATE OR REPLACE FUNCTION public.fn_centinela_evaluar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    c             centinela_config%ROWTYPE;
    v_ultimo_poll TIMESTAMPTZ;
    v_local       TIMESTAMP := NOW() AT TIME ZONE 'America/Santiago';
    r             RECORD;
    h             RECORD;
    i             centinela_incidentes%ROWTYPE;
    v_rank CONSTANT JSONB := '{"vigilar":1,"alto":2,"critico":3}';
    -- silencio
    s_regla TEXT; s_sev TEXT;
    -- zona
    z_fuera BOOLEAN; z_km NUMERIC; z_zona TEXT; z_sev TEXT; z_horas NUMERIC; z_det TEXT;
    -- horario
    hr_sev TEXT; hr_det TEXT;
    -- elegido
    t_regla TEXT; t_sev TEXT; t_det TEXT;
    v_fresco    BOOLEAN;
    v_abiertos  INT := 0;
    v_subidos   INT := 0;
    v_cerrados  INT := 0;
BEGIN
    SELECT * INTO c FROM centinela_config WHERE id = 1;

    -- Si la ingesta está caída, todo el parque parecería mudo: no evaluar.
    SELECT max(ts_actualizado) INTO v_ultimo_poll FROM gps_estado_actual;
    IF v_ultimo_poll IS NULL
       OR v_ultimo_poll < NOW() - make_interval(secs => c.horas_ingesta_caida * 3600) THEN
        RETURN jsonb_build_object('ingesta_caida', true, 'ultimo_poll', v_ultimo_poll);
    END IF;

    FOR r IN
        SELECT a.id AS activo_id,
               a.estado_comercial::TEXT AS estado_comercial,
               a.cliente_actual::TEXT   AS cliente,
               a.contrato_id,
               e.latitud, e.longitud, e.velocidad_kmh, e.ignicion, e.bateria_pct, e.movimiento,
               COALESCE(e.ts_ultimo_contacto, e.ts_gps) AS contacto,
               EXTRACT(EPOCH FROM NOW() - COALESCE(e.ts_ultimo_contacto, e.ts_gps)) / 3600.0 AS horas,
               (   (COALESCE(e.ignicion, FALSE)
                    OR e.movimiento = 'moving'
                    OR COALESCE(e.velocidad_kmh, 0) > 5)
               AND COALESCE(e.bateria_pct, 100) >= c.bateria_min_pct) AS en_marcha,
               p.motivo AS permiso_motivo
          FROM gps_estado_actual e
          JOIN activos a ON a.id = e.activo_id
          LEFT JOIN LATERAL (
                SELECT pp.motivo FROM centinela_permisos pp
                 WHERE pp.activo_id = a.id AND pp.revocado_en IS NULL
                   AND NOW() BETWEEN pp.desde AND pp.hasta
                 ORDER BY pp.hasta DESC LIMIT 1) p ON TRUE
         WHERE a.fecha_baja IS NULL
           AND NOT COALESCE(a.es_prueba, FALSE)
           AND EXISTS (SELECT 1 FROM gps_activo_mapeo m
                        WHERE m.activo_id = a.id AND m.activo)
    LOOP
        s_regla := NULL; s_sev := NULL;
        z_fuera := FALSE; z_km := NULL; z_zona := NULL; z_sev := NULL; z_horas := NULL; z_det := NULL;
        hr_sev := NULL; hr_det := NULL;
        v_fresco := r.contacto IS NOT NULL AND r.horas < 2;

        SELECT * INTO i FROM centinela_incidentes
         WHERE activo_id = r.activo_id AND estado <> 'cerrado';

        -- ¿Dónde está respecto de su zona? (solo arrendado, con zona, fresco)
        IF v_fresco AND r.estado_comercial = 'arrendado' AND r.contrato_id IS NOT NULL
           AND r.latitud IS NOT NULL
           AND EXISTS (SELECT 1 FROM gps_geocercas g
                        WHERE g.activo AND g.tipo = 'faena_cliente' AND g.contrato_id = r.contrato_id) THEN
            SELECT round((fn_distancia_haversine(r.latitud, r.longitud, g.centro_lat, g.centro_lng)
                          - g.radio_m) / 1000.0, 1),
                   g.nombre
              INTO z_km, z_zona
              FROM gps_geocercas g
             WHERE g.activo
               AND (g.tipo IN ('base_pillado', 'taller_externo', 'bodega')
                    OR (g.tipo = 'faena_cliente' AND g.contrato_id = r.contrato_id))
             ORDER BY fn_distancia_haversine(r.latitud, r.longitud, g.centro_lat, g.centro_lng) - g.radio_m
             LIMIT 1;
            z_fuera := z_km > c.margen_zona_km;
        END IF;

        -- Cierres automáticos del incidente abierto
        IF i.id IS NOT NULL THEN
            IF r.permiso_motivo IS NOT NULL THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'permiso_transito',
                       detalle_cierre = 'Traslado autorizado: ' || r.permiso_motivo, evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            ELSIF i.regla IN ('corte_en_marcha', 'sin_senal')
                  AND r.contacto > i.ultimo_contacto + INTERVAL '1 minute' THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'senal_recuperada',
                       detalle_cierre = 'El tracker volvió a reportar el '
                           || to_char(r.contacto AT TIME ZONE 'America/Santiago', 'DD-MM HH24:MI'),
                       horas_sin_contacto = round(EXTRACT(EPOCH FROM r.contacto - i.ultimo_contacto) / 3600.0, 1),
                       evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            ELSIF i.regla = 'fuera_de_zona' AND v_fresco AND NOT z_fuera THEN
                UPDATE centinela_incidentes
                   SET estado = 'cerrado', cerrado_en = NOW(), motivo_cierre = 'normalizado',
                       detalle_cierre = CASE WHEN z_km IS NULL
                           THEN 'Ya no aplica (cambió su contrato o su estado comercial)'
                           ELSE 'Volvió a su zona (' || z_zona || ')' END,
                       evaluado_en = NOW()
                 WHERE id = i.id;
                v_cerrados := v_cerrados + 1; i.id := NULL;
            END IF;
        END IF;

        -- Con traslado autorizado no se abre nada.
        IF r.permiso_motivo IS NOT NULL THEN CONTINUE; END IF;

        -- Silencio (Fase A)
        IF r.contacto IS NOT NULL THEN
            IF r.en_marcha AND r.horas >= c.horas_critico_marcha THEN
                s_regla := 'corte_en_marcha'; s_sev := 'critico';
            ELSIF r.en_marcha AND r.horas >= c.horas_vigilar_marcha THEN
                s_regla := 'corte_en_marcha'; s_sev := 'vigilar';
            ELSIF r.horas >= c.horas_critico_en_cliente
                  AND r.estado_comercial IN ('arrendado', 'leasing', 'uso_interno') THEN
                s_regla := 'sin_senal'; s_sev := 'critico';
            ELSIF r.horas >= c.horas_alto_detenido THEN
                s_regla := 'sin_senal'; s_sev := 'alto';
            END IF;
        END IF;

        -- Fuera de zona: vigilar al tiro, crítico a las N horas si la zona está verificada.
        IF z_fuera THEN
            z_horas := CASE WHEN i.id IS NOT NULL AND i.regla = 'fuera_de_zona'
                            THEN round(EXTRACT(EPOCH FROM NOW() - i.abierto_en) / 3600.0, 1) ELSE 0 END;
            z_sev := CASE WHEN z_horas >= c.horas_fuera_zona_critico
                               AND fn_centinela_zona_verificada(r.contrato_id)
                          THEN 'critico' ELSE 'vigilar' END;
            z_det := format('A %s km de la zona permitida más cercana (%s)', z_km, z_zona)
                  || CASE WHEN NOT fn_centinela_zona_verificada(r.contrato_id)
                          THEN '. La zona del contrato no está verificada' ELSE '' END;
        END IF;

        -- Fuera de horario (solo contratos que lo configuraron)
        IF v_fresco AND r.estado_comercial = 'arrendado' AND r.contrato_id IS NOT NULL
           AND (COALESCE(r.velocidad_kmh, 0) > 5 OR r.movimiento = 'moving') THEN
            SELECT * INTO h FROM centinela_horario_contrato
             WHERE contrato_id = r.contrato_id AND activo;
            IF FOUND AND NOT (
                   EXTRACT(ISODOW FROM v_local)::INT = ANY (h.dias)
               AND CASE WHEN h.hora_desde <= h.hora_hasta
                        THEN v_local::TIME BETWEEN h.hora_desde AND h.hora_hasta
                        ELSE v_local::TIME >= h.hora_desde OR v_local::TIME <= h.hora_hasta END) THEN
                hr_sev := 'alto';
                hr_det := format('Andando a %s km/h el %s a las %s, fuera del horario del contrato (%s–%s)',
                                 round(COALESCE(r.velocidad_kmh, 0)), to_char(v_local, 'DD-MM'),
                                 to_char(v_local, 'HH24:MI'),
                                 to_char(h.hora_desde, 'HH24:MI'), to_char(h.hora_hasta, 'HH24:MI'));
            END IF;
        END IF;

        -- La más grave gana; empate: silencio > zona > horario.
        t_regla := s_regla; t_sev := s_sev; t_det := NULL;
        IF z_sev IS NOT NULL AND (t_sev IS NULL OR (v_rank->>z_sev)::INT > (v_rank->>t_sev)::INT) THEN
            t_regla := 'fuera_de_zona'; t_sev := z_sev; t_det := z_det;
        END IF;
        IF hr_sev IS NOT NULL AND (t_sev IS NULL OR (v_rank->>hr_sev)::INT > (v_rank->>t_sev)::INT) THEN
            t_regla := 'fuera_de_horario'; t_sev := hr_sev; t_det := hr_det;
        END IF;

        IF t_sev IS NULL THEN
            IF i.id IS NOT NULL THEN
                UPDATE centinela_incidentes
                   SET horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW()
                 WHERE id = i.id;
            END IF;
            CONTINUE;
        END IF;

        -- [MIG577] Un cierre A MANO (alguien verificó y dejó su comentario) no se
        -- deshace a los 7 minutos: mientras siga el MISMO corte (el tracker no ha
        -- vuelto a reportar desde ese cierre) no se abre otro incidente, hasta
        -- c.horas_respeta_cierre_silencio (7 días) para re-verificar. En zona u
        -- horario, c.horas_respeta_cierre_zona (24 h).
        IF i.id IS NULL AND EXISTS (
            SELECT 1 FROM centinela_incidentes x
             WHERE x.activo_id = r.activo_id
               AND x.estado = 'cerrado'
               AND x.regla = t_regla
               AND x.motivo_cierre NOT IN ('senal_recuperada', 'normalizado', 'permiso_transito')
               AND CASE WHEN t_regla IN ('corte_en_marcha', 'sin_senal')
                        THEN r.contacto <= x.ultimo_contacto + INTERVAL '1 minute'
                             AND x.cerrado_en > NOW() - make_interval(secs => c.horas_respeta_cierre_silencio * 3600)
                        ELSE x.cerrado_en > NOW() - make_interval(secs => c.horas_respeta_cierre_zona * 3600)
                   END) THEN
            CONTINUE;
        END IF;

        IF i.id IS NULL THEN
            INSERT INTO centinela_incidentes (
                activo_id, regla, severidad, ultimo_contacto,
                latitud, longitud, velocidad_kmh, ignicion, bateria_pct,
                estado_comercial, cliente, horas_sin_contacto, evaluado_en,
                detalle, km_fuera_zona, zona_nombre, horas_fuera)
            VALUES (
                r.activo_id, t_regla, t_sev, r.contacto,
                r.latitud, r.longitud, r.velocidad_kmh, r.ignicion, r.bateria_pct,
                r.estado_comercial, r.cliente, round(r.horas, 1), NOW(),
                t_det,
                CASE WHEN t_regla = 'fuera_de_zona' THEN z_km END,
                CASE WHEN t_regla = 'fuera_de_zona' THEN z_zona END,
                CASE WHEN t_regla = 'fuera_de_zona' THEN 0 END);
            v_abiertos := v_abiertos + 1;
        ELSIF (v_rank->>t_sev)::INT > (v_rank->>i.severidad)::INT THEN
            UPDATE centinela_incidentes
               SET regla = t_regla, severidad = t_sev, detalle = t_det,
                   km_fuera_zona = CASE WHEN t_regla = 'fuera_de_zona' THEN z_km END,
                   zona_nombre   = CASE WHEN t_regla = 'fuera_de_zona' THEN z_zona END,
                   horas_fuera   = CASE WHEN t_regla = 'fuera_de_zona' THEN z_horas END,
                   -- La foto pasa a ser la de ahora (dónde está al subir de nivel).
                   latitud = COALESCE(r.latitud, latitud), longitud = COALESCE(r.longitud, longitud),
                   horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW()
             WHERE id = i.id;
            v_subidos := v_subidos + 1;
        ELSE
            UPDATE centinela_incidentes
               SET horas_sin_contacto = round(r.horas, 1), evaluado_en = NOW(),
                   detalle       = CASE WHEN regla = t_regla AND t_det IS NOT NULL THEN t_det ELSE detalle END,
                   km_fuera_zona = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN z_km ELSE km_fuera_zona END,
                   horas_fuera   = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN z_horas ELSE horas_fuera END,
                   latitud  = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN r.latitud  ELSE latitud  END,
                   longitud = CASE WHEN regla = 'fuera_de_zona' AND z_fuera THEN r.longitud ELSE longitud END
             WHERE id = i.id;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('ingesta_caida', false, 'ultimo_poll', v_ultimo_poll,
        'abiertos', v_abiertos, 'subidos', v_subidos, 'cerrados', v_cerrados);
END;
$function$;

-- El incidente de KVWD-27 que se reabrió solo: se cierra con el comentario
-- original (mismo corte, el tracker sigue sin reportar desde el cierre manual).
UPDATE centinela_incidentes n
   SET estado = 'cerrado', cerrado_en = NOW(), cerrado_por = o.cerrado_por,
       motivo_cierre = o.motivo_cierre,
       detalle_cierre = o.detalle_cierre || ' [el sistema lo reabrió solo a las 09:15; se cierra de nuevo con este comentario]',
       evaluado_en = NOW()
  FROM centinela_incidentes o
 WHERE n.id = '26899161-41fb-42a5-8061-5b0648fb4d0c'
   AND o.id = 'dabf59c2-fa12-4366-be9f-5a2a409a971a'
   AND n.estado <> 'cerrado';

COMMIT;
