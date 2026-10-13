-- ############################################################################
-- MIG589 · Un equipo vendido sale de TODO el sistema (y la venta se deshace)
-- ----------------------------------------------------------------------------
-- MIG585 hizo que 'B' (vendido) dejara la ficha en 'dado_baja'. Eso sacaba al
-- equipo de Sugerencias, del cierre diario y de fiabilidad, pero no del resto:
-- buena parte del sistema filtra por `fecha_baja IS NULL`, y vender no la
-- llenaba. Un camión vendido seguía:
--   · en el Centinela GPS (incidentes nuevos, correo, zonas) — el tracker
--     seguía mapeado y actualizando posición;
--   · en el correo de papeles de flota y en el de revisión técnica;
--   · en el cumplimiento del checklist cliente;
--   · en las preventivas del taller (sus planes seguían activos);
--   · en el Panel de Gerencia con sus OT y NC abiertas;
--   · en los selectores de vale de bodega y de no conformidad.
--
-- LO QUE HACE VENDER AHORA (fn_vender_equipo), todo de una vez:
--   1. Ficha: estado 'dado_baja', fecha_baja = día de la venta,
--      estado_comercial 'en_venta', categoría 'venta'.
--   2. Planes de mantenimiento: activo_plan = false (no más preventivas).
--   3. GPS: el tracker se desmapea (gps_activo_mapeo.activo = false).
--   4. Centinela: los incidentes abiertos se cierran («Equipo vendido»).
--   5. Historial: NC, OT, vales, repuestos y checklists del equipo pasan al
--      historial en UN lote (el mismo mecanismo de MIG406, «archivar el
--      equipo completo»). No se borra nada.
--   Todo lo que se cambió queda anotado en `activo_ventas`.
--
-- DESHACER (fn_revertir_venta): si ese mismo día en Sugerencias se cambia 'B'
-- por otro código, se devuelve exactamente lo que se cambió: ficha, planes,
-- tracker y el lote del historial. Los incidentes del Centinela cerrados no se
-- reabren (el Centinela abre uno nuevo solo si el problema sigue).
--
-- Y los paneles que leían OT, NC y días sin mirar si el equipo existe todavía
-- (fn_panel_taller, fn_panel_excepciones, fn_panel_disponibilidad,
-- fn_panel_equipos_detenidos) dejan fuera a los dados de baja.
-- ############################################################################

BEGIN;

-- ── 1. Registro de la venta ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.activo_ventas (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id           UUID NOT NULL REFERENCES public.activos(id),
    fecha_venta         DATE NOT NULL,
    motivo              TEXT NOT NULL,
    vigente             BOOLEAN NOT NULL DEFAULT TRUE,
    -- lo que había antes, para poder devolverlo
    prev_estado         TEXT,
    prev_estado_comercial TEXT,
    prev_categoria_uso  TEXT,
    prev_fecha_baja     DATE,
    planes_desactivados UUID[] NOT NULL DEFAULT '{}',
    gps_desmapeados     UUID[] NOT NULL DEFAULT '{}',
    incidentes_cerrados UUID[] NOT NULL DEFAULT '{}',
    archivo_lote_id     UUID,
    registrado_por      UUID,
    registrado_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    revertido_por       UUID,
    revertido_at        TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_activo_ventas_vigente
    ON public.activo_ventas (activo_id) WHERE vigente;

ALTER TABLE public.activo_ventas ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_activo_ventas_sel ON public.activo_ventas;
CREATE POLICY pol_activo_ventas_sel ON public.activo_ventas
    FOR SELECT TO authenticated USING (fn_user_rol() IS NOT NULL);
GRANT SELECT ON public.activo_ventas TO authenticated;

COMMENT ON TABLE public.activo_ventas IS
    'MIG589: cada venta de equipo y todo lo que se cambió al venderlo, para poder deshacerlo.';

-- ── 2. Vender ───────────────────────────────────────────────────────────
-- Interna: la llama rpc_confirmar_estado_dia (que ya validó permiso y motivo).
CREATE OR REPLACE FUNCTION public.fn_vender_equipo(p_activo_id UUID, p_fecha DATE, p_motivo TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_a        RECORD;
    v_venta    UUID;
    v_planes   UUID[];
    v_gps      UUID[];
    v_inc      UUID[];
    v_lote     UUID;
    v_n        INT := 0;
    v_k        INT;
    v_user     UUID := auth.uid();
    v_motivo   TEXT := 'Equipo vendido el ' || to_char(p_fecha, 'DD-MM-YYYY') || ': ' || p_motivo;
BEGIN
    SELECT id, patente, codigo, estado, estado_comercial, categoria_uso, fecha_baja
      INTO v_a FROM activos WHERE id = p_activo_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo no encontrado'; END IF;

    -- Ya vendido: solo se ajusta la fecha si cambió.
    SELECT id INTO v_venta FROM activo_ventas WHERE activo_id = p_activo_id AND vigente;
    IF v_venta IS NOT NULL THEN
        UPDATE activo_ventas SET fecha_venta = p_fecha, motivo = p_motivo WHERE id = v_venta;
        UPDATE activos SET fecha_baja = p_fecha, updated_at = now() WHERE id = p_activo_id;
        RETURN v_venta;
    END IF;

    -- Planes de mantenimiento
    WITH u AS (
        UPDATE planes_mantenimiento SET activo_plan = false, updated_at = now()
         WHERE activo_id = p_activo_id AND activo_plan
        RETURNING id)
    SELECT COALESCE(array_agg(id), '{}') INTO v_planes FROM u;

    -- Tracker GPS
    WITH u AS (
        UPDATE gps_activo_mapeo SET activo = false
         WHERE activo_id = p_activo_id AND activo
        RETURNING id)
    SELECT COALESCE(array_agg(id), '{}') INTO v_gps FROM u;

    -- Centinela
    WITH u AS (
        UPDATE centinela_incidentes
           SET estado = 'cerrado', cerrado_en = now(), cerrado_por = v_user,
               motivo_cierre = 'otro', detalle_cierre = v_motivo
         WHERE activo_id = p_activo_id AND estado <> 'cerrado'
        RETURNING id)
    SELECT COALESCE(array_agg(id), '{}') INTO v_inc FROM u;

    -- Historial: un lote de tipo «equipo» (MIG406), devolvible entero.
    INSERT INTO archivo_lotes (entidad, motivo, archivado_por)
    VALUES ('equipo', v_motivo || ' · ' || COALESCE(v_a.patente, v_a.codigo), v_user)
    RETURNING id INTO v_lote;

    UPDATE no_conformidades SET archivado_at = now(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = p_activo_id AND archivado_at IS NULL;
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;

    UPDATE ot_recursos_solicitados r SET archivado_at = now(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
      FROM ordenes_trabajo o
     WHERE o.id = r.ot_id AND o.activo_id = p_activo_id AND r.archivado_at IS NULL;
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;

    -- Las OT 'cerrada' son inmutables (trg_bloquear_update_ot_cerrada) y ya son
    -- historia: no aparecen como trabajo vivo. Se archiva el resto.
    UPDATE ordenes_trabajo SET archivado_at = now(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = p_activo_id AND archivado_at IS NULL AND estado <> 'cerrada';
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;

    UPDATE bodega_tickets SET archivado_at = now(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = p_activo_id AND archivado_at IS NULL;
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;

    UPDATE checklist_v2_instance SET archivado_at = now(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = p_activo_id AND archivado_at IS NULL;
    GET DIAGNOSTICS v_k = ROW_COUNT; v_n := v_n + v_k;

    IF v_n = 0 THEN
        DELETE FROM archivo_lotes WHERE id = v_lote;
        v_lote := NULL;
    ELSE
        UPDATE archivo_lotes SET n_registros = v_n WHERE id = v_lote;
    END IF;

    -- Ficha
    UPDATE activos
       SET estado           = 'dado_baja',
           fecha_baja       = p_fecha,
           estado_comercial = 'en_venta',
           categoria_uso    = 'venta',
           notas            = COALESCE(NULLIF(btrim(notas), '') || E'\n', '')
                              || '[' || to_char(p_fecha, 'YYYY-MM-DD') || '] Vendido: ' || p_motivo,
           updated_at       = now()
     WHERE id = p_activo_id;

    INSERT INTO activo_ventas (activo_id, fecha_venta, motivo, prev_estado, prev_estado_comercial,
        prev_categoria_uso, prev_fecha_baja, planes_desactivados, gps_desmapeados,
        incidentes_cerrados, archivo_lote_id, registrado_por)
    VALUES (p_activo_id, p_fecha, p_motivo, v_a.estado::TEXT, v_a.estado_comercial::TEXT,
        v_a.categoria_uso::TEXT, v_a.fecha_baja, v_planes, v_gps, v_inc, v_lote, v_user)
    RETURNING id INTO v_venta;

    RETURN v_venta;
END $function$;
REVOKE ALL ON FUNCTION public.fn_vender_equipo(UUID, DATE, TEXT) FROM PUBLIC, anon, authenticated;

-- ── 3. Deshacer la venta ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_revertir_venta(p_activo_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v RECORD;
BEGIN
    SELECT * INTO v FROM activo_ventas WHERE activo_id = p_activo_id AND vigente FOR UPDATE;
    IF NOT FOUND THEN RETURN FALSE; END IF;

    UPDATE planes_mantenimiento SET activo_plan = true, updated_at = now()
     WHERE id = ANY(v.planes_desactivados);
    UPDATE gps_activo_mapeo SET activo = true WHERE id = ANY(v.gps_desmapeados);

    IF v.archivo_lote_id IS NOT NULL THEN
        UPDATE no_conformidades SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL WHERE archivado_lote = v.archivo_lote_id;
        UPDATE ot_recursos_solicitados SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL WHERE archivado_lote = v.archivo_lote_id;
        UPDATE ordenes_trabajo SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL WHERE archivado_lote = v.archivo_lote_id;
        UPDATE bodega_tickets SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL WHERE archivado_lote = v.archivo_lote_id;
        UPDATE checklist_v2_instance SET archivado_at = NULL, archivado_por = NULL,
               archivado_motivo = NULL, archivado_lote = NULL WHERE archivado_lote = v.archivo_lote_id;
        DELETE FROM archivo_lotes WHERE id = v.archivo_lote_id;
    END IF;

    -- La ficha la vuelve a sincronizar quien llama (con el código nuevo del día);
    -- aquí se devuelve lo que la venta pisó y no se deriva del código.
    -- estado NO se toca aquí: lo pone el código nuevo del día en
    -- rpc_confirmar_estado_dia, dentro de su bloque protegido (un gate de la
    -- ficha no debe tumbar el deshacer).
    UPDATE activos
       SET fecha_baja       = v.prev_fecha_baja,
           estado_comercial = v.prev_estado_comercial::estado_comercial_enum,
           categoria_uso    = v.prev_categoria_uso::categoria_uso_enum,
           notas            = COALESCE(NULLIF(btrim(notas), '') || E'\n', '')
                              || '[' || to_char(CURRENT_DATE, 'YYYY-MM-DD') || '] Venta deshecha.',
           updated_at       = now()
     WHERE id = p_activo_id;

    UPDATE activo_ventas SET vigente = false, revertido_por = auth.uid(), revertido_at = now()
     WHERE id = v.id;
    RETURN TRUE;
END $function$;
REVOKE ALL ON FUNCTION public.fn_revertir_venta(UUID) FROM PUBLIC, anon, authenticated;

-- ── 4. rpc_confirmar_estado_dia usa vender / deshacer ────────────────────
DO $patch$
DECLARE
    v_def TEXT;
    v_viejo_b TEXT := $$        IF v_a.estado <> 'dado_baja' THEN
            UPDATE activos
               SET estado        = 'dado_baja',
                   categoria_uso = 'venta',
                   notas         = COALESCE(NULLIF(btrim(notas), '') || E'\n', '')
                                   || '[' || to_char(p_fecha, 'YYYY-MM-DD') || '] ' || v_obs,
                   updated_at    = now()
             WHERE id = p_activo_id;
        END IF;
        RETURN;$$;
    v_nuevo_b TEXT := $$        -- [MIG589] Vender saca al equipo de todo el sistema.
        PERFORM fn_vender_equipo(p_activo_id, p_fecha, trim(p_justificacion));
        RETURN;$$;
    v_viejo_u TEXT := $$    IF v_a.estado = 'dado_baja' AND v_prev_dia IS DISTINCT FROM 'B' THEN
        RETURN;
    END IF;$$;
    v_nuevo_u TEXT := $$    IF v_a.estado = 'dado_baja' AND v_prev_dia IS DISTINCT FROM 'B' THEN
        RETURN;
    END IF;
    -- [MIG589] Deshacer la venta devuelve planes, tracker e historial.
    IF v_a.estado = 'dado_baja' AND v_prev_dia = 'B' THEN
        PERFORM fn_revertir_venta(p_activo_id);
    END IF;$$;
BEGIN
    SELECT pg_get_functiondef(p.oid) INTO v_def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_confirmar_estado_dia' AND p.prokind = 'f';
    -- El archivo puede llegar con CRLF (git en Windows); la definición viva no.
    v_viejo_b := replace(v_viejo_b, chr(13), ''); v_nuevo_b := replace(v_nuevo_b, chr(13), '');
    v_viejo_u := replace(v_viejo_u, chr(13), ''); v_nuevo_u := replace(v_nuevo_u, chr(13), '');
    IF position(v_viejo_b IN v_def) = 0 THEN RAISE EXCEPTION 'MIG589: bloque B no encontrado'; END IF;
    IF position(v_viejo_u IN v_def) = 0 THEN RAISE EXCEPTION 'MIG589: bloque deshacer no encontrado'; END IF;
    v_def := replace(replace(v_def, v_viejo_b, v_nuevo_b), v_viejo_u, v_nuevo_u);
    EXECUTE v_def;
    RAISE NOTICE 'MIG589: rpc_confirmar_estado_dia parchada';
END $patch$;

-- ── 5. Paneles: los dados de baja fuera ──────────────────────────────────
DO $patch$
DECLARE
    r RECORD; v_def TEXT;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('fn_panel_disponibilidad',
           $$       AND e.estado_codigo NOT IN ('S','B')$$,
           $$       AND e.estado_codigo NOT IN ('S','B')
       AND a.estado <> 'dado_baja'   -- MIG589$$),
        ('fn_panel_equipos_detenidos',
           $$           AND e.estado_codigo NOT IN ('S','B')$$,
           $$           AND e.estado_codigo NOT IN ('S','B')
           AND a.estado <> 'dado_baja'   -- MIG589$$),
        ('fn_panel_taller',
           $$         WHERE p_operacion IS NULL OR a.operacion = p_operacion$$,
           $$         WHERE (p_operacion IS NULL OR a.operacion = p_operacion)
           AND a.estado IS DISTINCT FROM 'dado_baja'   -- MIG589$$),
        ('fn_panel_taller',
           $$         WHERE p_operacion IS NULL OR a2.operacion = p_operacion$$,
           $$         WHERE (p_operacion IS NULL OR a2.operacion = p_operacion)
           AND a2.estado IS DISTINCT FROM 'dado_baja'   -- MIG589$$),
        ('fn_panel_excepciones',
           $$     WHERE NOT nc.resuelto$$,
           $$     WHERE NOT nc.resuelto
       AND a.estado IS DISTINCT FROM 'dado_baja'   -- MIG589$$)
      ) AS t(fn, viejo, nuevo)
    LOOP
        SELECT pg_get_functiondef(p.oid) INTO v_def
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = r.fn AND p.prokind = 'f';
        IF position(replace(r.viejo, chr(13), '') IN v_def) = 0 THEN
            RAISE EXCEPTION 'MIG589: en % no aparece %', r.fn, r.viejo;
        END IF;
        EXECUTE replace(v_def, replace(r.viejo, chr(13), ''), replace(r.nuevo, chr(13), ''));
        RAISE NOTICE 'MIG589: % parchada', r.fn;
    END LOOP;
END $patch$;

COMMIT;
