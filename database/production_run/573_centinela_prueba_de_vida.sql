-- ============================================================================
-- MIG573 · Centinela de flota — Fase C: prueba de vida en el cierre del día
-- ============================================================================
--
-- LO QUE PASÓ
-- KVWD-27 fue confirmado «A» (arrendado) TODOS los días del 05-06 al 23-09
-- desde «Sugerencias estado (GPS)». Sin GPS, fn_estado_por_geocerca devuelve
-- NULL y la sugerencia cae al estado del día anterior: la «A» se arrastró sola
-- 110 días, y el botón «Cerrar día · toda la flota» la confirmó en bloque.
--
-- LO QUE HACE
--  1. fn_prueba_de_vida(activo): la última evidencia de que el equipo existe y
--     se mueve — contacto GPS, OT iniciada/terminada, checklist QR, recepción,
--     checklist semanal del cliente, o una declaración del planificador.
--     (Hoy combustible por vehículo y checklist semanal del cliente están en
--     cero filas: no sirven todavía como evidencia.)
--  2. fn_prueba_de_vida_estado(activo): exige justificar si la última evidencia
--     tiene 7 días o más, o si hay un crítico abierto en el Centinela sin
--     declaración posterior.
--  3. fn_sugerencias_estado_gps muestra la evidencia por equipo.
--  4. rpc_confirmar_estado_dia y rpc_confirmar_cierre_diario: confirmar A o C
--     de hoy/ayer sobre un equipo sin prueba de vida exige una justificación
--     (≥10 caracteres). La justificación queda en estado_diario_flota con
--     quién y cuándo, y VALE COMO EVIDENCIA por 7 días: se pide a lo más una
--     vez por semana por camión. Corregir días pasados no se bloquea.
-- ============================================================================

BEGIN;

-- ── 1. La última evidencia ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_prueba_de_vida(p_activo_id UUID, OUT fecha TIMESTAMPTZ, OUT fuente TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT x.fecha, x.fuente
      FROM (
        SELECT ts_ultimo_contacto AS fecha, 'GPS' AS fuente
          FROM gps_estado_actual WHERE activo_id = p_activo_id
        UNION ALL
        SELECT max(f), 'OT' FROM (
            SELECT fecha_inicio AS f FROM ordenes_trabajo WHERE activo_id = p_activo_id AND fecha_inicio <= NOW()
            UNION ALL
            SELECT fecha_termino FROM ordenes_trabajo WHERE activo_id = p_activo_id AND fecha_termino <= NOW()) o
        UNION ALL
        SELECT max(created_at), 'Checklist QR' FROM qr_checklist_respuestas WHERE activo_id = p_activo_id
        UNION ALL
        SELECT max(fecha_recepcion)::TIMESTAMPTZ, 'Recepción' FROM informes_recepcion WHERE activo_id = p_activo_id
        UNION ALL
        SELECT max(fecha)::TIMESTAMPTZ, 'Checklist cliente' FROM checklist_cliente_semanal WHERE activo_id = p_activo_id
        UNION ALL
        -- La palabra del planificador también cuenta, con nombre y fecha.
        SELECT e.actualizado_at,
               'Declaración de ' || COALESCE(u.nombre_completo, 'planificador') || ': '
               || substr(e.observacion, length('Prueba de vida: ') + 1)
          FROM estado_diario_flota e
          LEFT JOIN usuarios_perfil u ON u.id = e.actualizado_por
         WHERE e.activo_id = p_activo_id AND e.observacion LIKE 'Prueba de vida: %'
      ) x
     WHERE x.fecha IS NOT NULL AND x.fecha <= NOW() + INTERVAL '5 minutes'
     ORDER BY x.fecha DESC
     LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_prueba_de_vida_estado(
    p_activo_id UUID,
    OUT fecha TIMESTAMPTZ, OUT fuente TEXT, OUT dias INT,
    OUT centinela TEXT, OUT requiere BOOLEAN)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_inc RECORD; v_decl TIMESTAMPTZ;
BEGIN
    SELECT p.fecha, p.fuente INTO fecha, fuente FROM fn_prueba_de_vida(p_activo_id) p;
    dias := CASE WHEN fecha IS NULL THEN NULL
                 ELSE floor(EXTRACT(EPOCH FROM NOW() - fecha) / 86400)::INT END;

    SELECT severidad, abierto_en INTO v_inc
      FROM centinela_incidentes WHERE activo_id = p_activo_id AND estado <> 'cerrado';
    centinela := v_inc.severidad;

    SELECT max(actualizado_at) INTO v_decl
      FROM estado_diario_flota
     WHERE activo_id = p_activo_id AND observacion LIKE 'Prueba de vida: %';

    requiere := fecha IS NULL OR dias >= 7
             OR (v_inc.severidad = 'critico' AND (v_decl IS NULL OR v_decl < v_inc.abierto_en));
END;
$$;

REVOKE ALL ON FUNCTION fn_prueba_de_vida(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION fn_prueba_de_vida_estado(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_prueba_de_vida(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION fn_prueba_de_vida_estado(UUID) TO authenticated;

-- ── 2. Sugerencias con la evidencia a la vista ──────────────────────────────
DROP FUNCTION IF EXISTS fn_sugerencias_estado_gps(DATE);
CREATE FUNCTION fn_sugerencias_estado_gps(p_fecha DATE DEFAULT CURRENT_DATE)
RETURNS TABLE(activo_id UUID, patente TEXT, equipamiento TEXT, estado_actual CHARACTER,
              estado_sugerido CHARACTER, estado_guardado CHARACTER, zona TEXT,
              gps_ts TIMESTAMPTZ, coincide BOOLEAN,
              -- [MIG573] prueba de vida
              evidencia_fecha TIMESTAMPTZ, evidencia_fuente TEXT, evidencia_dias INT,
              centinela TEXT, requiere_justificacion BOOLEAN)
LANGUAGE sql
STABLE
AS $function$
  SELECT
    a.id,
    a.patente::text,
    a.nombre::text,
    prev.estado_codigo AS estado_actual,
    COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')::character(1) AS estado_sugerido,
    (SELECT e.estado_codigo FROM estado_diario_flota e
       WHERE e.activo_id = a.id AND e.fecha = p_fecha LIMIT 1) AS estado_guardado,
    (SELECT g.nombre FROM gps_geocercas g
       WHERE g.activo AND ga.latitud IS NOT NULL
         AND fn_punto_en_geocerca(ga.latitud, ga.longitud, g.id)
       ORDER BY (g.tipo = 'faena_cliente') DESC, g.radio_m ASC LIMIT 1) AS zona,
    ga.ts_gps,
    (prev.estado_codigo = COALESCE(fn_estado_por_geocerca(a.id), prev.estado_codigo, 'D')) AS coincide,
    pv.fecha, pv.fuente, pv.dias, pv.centinela, pv.requiere
  FROM activos a
  LEFT JOIN gps_estado_actual ga ON ga.activo_id = a.id
  LEFT JOIN LATERAL (
    SELECT e.estado_codigo
      FROM estado_diario_flota e
     WHERE e.activo_id = a.id AND e.fecha < p_fecha
     ORDER BY e.fecha DESC LIMIT 1
  ) prev ON true
  LEFT JOIN LATERAL fn_prueba_de_vida_estado(a.id) pv ON true
  WHERE a.estado <> 'dado_baja'
    AND a.tipo IN ('camion_cisterna','camion','camioneta','lubrimovil','equipo_menor')
    AND NOT COALESCE(a.es_prueba, false)   -- MIG564: el equipo de prueba no se planifica
  ORDER BY a.patente;
$function$;

REVOKE ALL ON FUNCTION fn_sugerencias_estado_gps(DATE) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_sugerencias_estado_gps(DATE) TO authenticated, service_role;

-- ── 3. Confirmar el día: A/C sin prueba de vida exige justificación ─────────
DROP FUNCTION IF EXISTS rpc_confirmar_estado_dia(UUID, DATE, CHARACTER);
CREATE FUNCTION rpc_confirmar_estado_dia(
    p_activo_id UUID, p_fecha DATE, p_estado CHARACTER, p_justificacion TEXT DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ultima_fecha DATE;
    v_a            RECORD;
    v_error        TEXT := NULL;
    v_pv           RECORD;
    v_obs          TEXT := NULL;
    v_patente      TEXT;
BEGIN
    -- [MIG189] Autorización fail-closed (flota/approve). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'approve' USING ERRCODE = '42501';
    END IF;

    -- [MIG573] Prueba de vida: decir «arrendado» de un camión del que nadie
    -- sabe nada hace una semana es lo que dejó a KVWD-27 110 días a ciegas.
    IF upper(p_estado) IN ('A', 'C') AND p_fecha >= CURRENT_DATE - 1 THEN
        SELECT * INTO v_pv FROM fn_prueba_de_vida_estado(p_activo_id);
        IF v_pv.requiere THEN
            IF length(trim(COALESCE(p_justificacion, ''))) < 10 THEN
                SELECT patente INTO v_patente FROM activos WHERE id = p_activo_id;
                RAISE EXCEPTION 'PRUEBA_DE_VIDA: % no tiene evidencia de estar operando (%). Para confirmarlo como % escribe cómo sabes que está donde el cliente (mínimo 10 caracteres).',
                    v_patente,
                    CASE WHEN v_pv.fecha IS NULL THEN 'nunca hubo'
                         ELSE 'la última es de hace ' || v_pv.dias || ' días, ' || v_pv.fuente END
                    || CASE WHEN v_pv.centinela = 'critico' THEN '; tiene un crítico abierto en el Centinela' ELSE '' END,
                    upper(p_estado)
                    USING ERRCODE = 'P0001';
            END IF;
            v_obs := 'Prueba de vida: ' || trim(p_justificacion);
        END IF;
    END IF;

    INSERT INTO estado_diario_flota
      (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override,
       actualizado_por, actualizado_at, observacion)
    VALUES
      (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)',
       auth.uid(), now(), v_obs)
    ON CONFLICT (activo_id, fecha) DO UPDATE
      SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
          motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
          actualizado_at = now(), updated_at = now(),
          -- Una re-confirmación sin justificación no borra la que ya había.
          observacion = COALESCE(EXCLUDED.observacion, estado_diario_flota.observacion);

    -- La ficha sigue al planificador SOLO si esta es la última fecha registrada
    -- del equipo. Corregir un día pasado no puede reescribir el estado de hoy.
    SELECT MAX(fecha) INTO v_ultima_fecha
      FROM estado_diario_flota WHERE activo_id = p_activo_id;

    IF v_ultima_fecha IS NULL OR p_fecha < v_ultima_fecha THEN
        RETURN;
    END IF;

    SELECT id, estado, estado_comercial, categoria_uso INTO v_a
      FROM activos WHERE id = p_activo_id;

    IF NOT FOUND OR v_a.estado = 'dado_baja' THEN
        RETURN;   -- una baja no vuelve sola desde un cierre de día
    END IF;

    -- Un gate puede negarse con razón (DS 298 por antigüedad, calidad por
    -- pendientes críticos). Cuando eso pasa, el cierre del día IGUAL vale:
    -- estado_diario_flota es la fuente de verdad y el planificador está
    -- registrando la realidad, no pidiendo permiso. Lo que se hace es dejar
    -- anotado el motivo para que alguien lo resuelva.
    BEGIN
        UPDATE activos a
           SET estado           = fn_estado_ficha_desde_codigo(p_estado),
               estado_comercial = fn_estado_comercial_desde_codigo(p_estado, a.estado_comercial),
               categoria_uso    = COALESCE(fn_categoria_uso_desde_codigo(p_estado), a.categoria_uso),
               updated_at       = now()
         WHERE a.id = p_activo_id
           AND (a.estado           IS DISTINCT FROM fn_estado_ficha_desde_codigo(p_estado)
             OR a.estado_comercial IS DISTINCT FROM fn_estado_comercial_desde_codigo(p_estado, a.estado_comercial)
             OR a.categoria_uso    IS DISTINCT FROM COALESCE(fn_categoria_uso_desde_codigo(p_estado), a.categoria_uso));
    EXCEPTION WHEN OTHERS THEN
        v_error := SQLERRM;
    END;

    UPDATE estado_diario_flota
       SET ficha_sync_error = v_error
     WHERE activo_id = p_activo_id AND fecha = p_fecha
       AND ficha_sync_error IS DISTINCT FROM v_error;
END $function$;

REVOKE ALL ON FUNCTION rpc_confirmar_estado_dia(UUID, DATE, CHARACTER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_confirmar_estado_dia(UUID, DATE, CHARACTER, TEXT) TO authenticated, service_role;

-- ── 4. Tablero de cierre diario: omite (no rechaza) los que no tienen prueba ─
CREATE OR REPLACE FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_item      JSONB;
    v_activo    UUID;
    v_estado    CHAR(1);
    v_contrato  UUID;
    v_cliente   VARCHAR;
    v_estado_com estado_comercial_enum;
    v_n         INTEGER := 0;
    v_pv        RECORD;
    v_obs       TEXT;
    v_omitidos  TEXT[] := '{}';
BEGIN
    -- Autorización (MIG185): sesión + permiso approve sobre módulo flota.
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;
    -- Fail-closed (rev. gate): SIN fallback amplio. Cierre diario = admin-only por
    -- defecto (reescribe toda la flota). Supervisores u otros roles se habilitan
    -- SOLO con override explícito en Admin (rol_permisos_modulo, MIG126) tras
    -- ratificación individual. Alinea con rpc_confirmar_estado_dia (flota/approve).
    IF NOT public.fn_tiene_permiso_modulo(
        'flota', 'approve',
        ARRAY['administrador']
    ) THEN
        RAISE EXCEPTION 'No autorizado para confirmar el cierre diario de flota.';
    END IF;

    IF p_fecha IS NULL THEN
        RAISE EXCEPTION 'p_fecha es obligatoria';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'p_items debe ser un arreglo JSON';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_activo   := (v_item->>'activo_id')::uuid;
        v_estado   := upper(v_item->>'estado_codigo')::char(1);
        v_contrato := NULLIF(v_item->>'contrato_id', '')::uuid;
        v_obs      := 'Cierre diario confirmado';

        IF v_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L','S') THEN
            RAISE EXCEPTION 'Estado invalido % para activo %', v_estado, v_activo;
        END IF;

        -- Activo debe existir y no estar dado de baja: rechaza el lote completo
        -- (la transacción revierte todo → sin cambios parciales).
        PERFORM 1 FROM public.activos WHERE id = v_activo AND estado <> 'dado_baja';
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Activo % inexistente o dado de baja; cierre rechazado completo.', v_activo;
        END IF;
        -- Contrato, si viene, debe existir.
        IF v_contrato IS NOT NULL THEN
            PERFORM 1 FROM public.contratos WHERE id = v_contrato;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Contrato % inexistente; cierre rechazado completo.', v_contrato;
            END IF;
        END IF;

        -- [MIG573] Sin prueba de vida, A/C no se confirma en bloque: se omite
        -- y se devuelve, para justificarlo en Sugerencias estado (GPS).
        IF v_estado IN ('A', 'C') AND p_fecha >= CURRENT_DATE - 1 THEN
            SELECT * INTO v_pv FROM fn_prueba_de_vida_estado(v_activo);
            IF v_pv.requiere THEN
                IF length(trim(COALESCE(v_item->>'justificacion', ''))) < 10 THEN
                    v_omitidos := v_omitidos || (SELECT patente::TEXT FROM activos WHERE id = v_activo);
                    CONTINUE;
                END IF;
                v_obs := 'Prueba de vida: ' || trim(v_item->>'justificacion');
            END IF;
        END IF;

        -- Cliente: del contrato si viene; si no, el actual del activo
        v_cliente := NULL;
        IF v_contrato IS NOT NULL THEN
            SELECT cliente INTO v_cliente FROM public.contratos WHERE id = v_contrato;
        END IF;
        IF v_cliente IS NULL THEN
            SELECT cliente_actual INTO v_cliente FROM public.activos WHERE id = v_activo;
        END IF;

        -- Upsert del estado del dia (congelado como cierre)
        INSERT INTO public.estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo, cliente,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at, registrado_por, observacion
        ) VALUES (
            v_activo, p_fecha, v_contrato, v_estado, v_cliente,
            true, 'Cierre diario de flota', false,
            v_user, now(), v_user, v_obs
        )
        ON CONFLICT (activo_id, fecha) DO UPDATE SET
            estado_codigo   = EXCLUDED.estado_codigo,
            contrato_id     = EXCLUDED.contrato_id,
            cliente         = EXCLUDED.cliente,
            override_manual = true,
            motivo_override = 'Cierre diario de flota',
            calculado_auto  = false,
            actualizado_por = EXCLUDED.actualizado_por,
            actualizado_at  = now(),
            updated_at      = now(),
            observacion     = CASE WHEN EXCLUDED.observacion LIKE 'Prueba de vida: %'
                                   THEN EXCLUDED.observacion ELSE estado_diario_flota.observacion END;

        -- Reverse-map a estado_comercial (solo codigos comerciales;
        -- M/T/F/H no cambian el comercial: un equipo arrendado en taller
        -- sigue comercialmente arrendado).
        v_estado_com := (CASE v_estado
            WHEN 'A' THEN 'arrendado'
            WHEN 'C' THEN 'arrendado'
            WHEN 'D' THEN 'disponible'
            WHEN 'U' THEN 'uso_interno'
            WHEN 'L' THEN 'leasing'
            WHEN 'R' THEN 'en_recepcion'
            WHEN 'V' THEN 'en_venta'
            ELSE NULL
        END)::estado_comercial_enum;

        -- Propagar a activos: contrato siempre; comercial + cliente solo si mapea
        UPDATE public.activos SET
            contrato_id      = v_contrato,
            estado_comercial = COALESCE(v_estado_com, estado_comercial),
            cliente_actual   = CASE WHEN v_estado_com IS NOT NULL THEN v_cliente
                                    ELSE cliente_actual END,
            updated_at       = now()
        WHERE id = v_activo;

        v_n := v_n + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'fecha', p_fecha, 'confirmados', v_n,
                              'omitidos_prueba_vida', to_jsonb(v_omitidos));
END $function$;

COMMIT;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_kvwd RECORD; v_n INT; v_lista TEXT;
BEGIN
    SELECT * INTO v_kvwd FROM fn_prueba_de_vida_estado(
        (SELECT id FROM activos WHERE patente = 'KVWD-27'));
    IF NOT v_kvwd.requiere THEN RAISE EXCEPTION 'FALLO: KVWD-27 debería exigir justificación'; END IF;

    SELECT count(*), string_agg(s.patente || ' (' || COALESCE(s.evidencia_dias::TEXT, 'nunca') || ' d, '
                                || COALESCE(s.evidencia_fuente, '—') || ')', ', ' ORDER BY s.patente)
      INTO v_n, v_lista
      FROM fn_sugerencias_estado_gps(CURRENT_DATE) s
     WHERE s.requiere_justificacion
       AND COALESCE(s.estado_guardado, s.estado_sugerido) IN ('A', 'C');
    RAISE NOTICE 'Prueba de vida OK · KVWD-27: % días (%) · hoy piden justificación % equipos en A/C: %',
        v_kvwd.dias, v_kvwd.fuente, v_n, v_lista;
END
$mig$;
