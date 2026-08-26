-- ============================================================================
-- MIG406 · Se elige la patente y todo lo suyo pasa a historia
-- ----------------------------------------------------------------------------
-- LA ACLARACIÓN DE MANUEL
-- 26-08-2026: «la idea es que se pueda seleccionar la patente y colocar como
-- historia, así empiezo limpio».
--
-- MIG405 dejó el archivo por entidad: una pantalla para las no conformidades,
-- otra para las OT, otra para los vales. Eso obliga a acordarse de pasar por
-- cinco menús para dejar UN camión limpio, y a la quinta alguien se olvida y el
-- equipo queda a medias: sin NC pero con la OT vieja colgando.
--
-- La unidad de trabajo real es el equipo. Se elige la patente y se va todo lo
-- suyo de una vez: no conformidades, órdenes de trabajo, vales de bodega,
-- repuestos pedidos y checklists.
--
-- ── UN SOLO LOTE PARA LAS CINCO TABLAS ──────────────────────────────────────
-- Si se archivan cinco cosas juntas, se tienen que poder devolver las cinco
-- juntas. El lote es de tipo «equipo» y `rpc_desarchivar_lote` lo entiende:
-- deshacerlo devuelve el camión entero al estado en que estaba, no una tabla.
--
-- ── SE VE ANTES DE HACERLO ──────────────────────────────────────────────────
-- `fn_equipo_archivable_resumen` dice qué se va a llevar cada patente antes de
-- confirmar. Archivar a ciegas «todo lo del RSCY-85» cuando son 12 NC, 3 OT y
-- un vale con repuestos sin entregar es la clase de acción que uno quiere ver
-- escrita antes de apretar.
--
-- ── EL CORTE POR FECHA ──────────────────────────────────────────────────────
-- Opcional. Sin fecha se lleva todo lo del equipo; con fecha, sólo lo anterior.
-- Sirve para cerrar agosto sin arrastrar lo que ya empezó en septiembre.
-- ============================================================================

BEGIN;

-- ── 1. Qué se llevaría cada patente ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_equipo_archivable_resumen(
    p_activo_id uuid,
    p_hasta     date DEFAULT NULL
) RETURNS TABLE (
    n_nc          integer,
    n_ot          integer,
    n_vales       integer,
    n_recursos    integer,
    n_checklists  integer,
    n_total       integer,
    vales_con_pendiente integer
)
LANGUAGE sql STABLE
SET search_path TO 'public'
AS $function$
  WITH lim AS (SELECT COALESCE(p_hasta, CURRENT_DATE) AS h),
  nc AS (SELECT count(*)::int c FROM no_conformidades x, lim
          WHERE x.activo_id = p_activo_id AND x.archivado_at IS NULL AND x.created_at::date <= lim.h),
  ot AS (SELECT count(*)::int c FROM ordenes_trabajo x, lim
          WHERE x.activo_id = p_activo_id AND x.archivado_at IS NULL AND x.created_at::date <= lim.h),
  bt AS (SELECT count(*)::int c FROM bodega_tickets x, lim
          WHERE x.activo_id = p_activo_id AND x.archivado_at IS NULL AND x.created_at::date <= lim.h),
  rs AS (SELECT count(*)::int c FROM ot_recursos_solicitados x
           JOIN ordenes_trabajo o ON o.id = x.ot_id, lim
          WHERE o.activo_id = p_activo_id AND x.archivado_at IS NULL AND x.created_at::date <= lim.h),
  ck AS (SELECT count(*)::int c FROM checklist_v2_instance x, lim
          WHERE x.activo_id = p_activo_id AND x.archivado_at IS NULL AND x.created_at::date <= lim.h),
  -- Un vale con repuestos sin entregar es plata parada: conviene verlo antes.
  vp AS (SELECT count(*)::int c FROM bodega_tickets x, lim
          WHERE x.activo_id = p_activo_id AND x.archivado_at IS NULL
            AND x.estado = 'emitido' AND x.created_at::date <= lim.h)
  SELECT nc.c, ot.c, bt.c, rs.c, ck.c,
         nc.c + ot.c + bt.c + rs.c + ck.c,
         vp.c
    FROM nc, ot, bt, rs, ck, vp;
$function$;

COMMENT ON FUNCTION public.fn_equipo_archivable_resumen(uuid, date) IS
  'MIG406: qué se llevaría al historial una patente, antes de confirmar. vales_con_pendiente avisa de repuestos sin entregar.';

GRANT EXECUTE ON FUNCTION public.fn_equipo_archivable_resumen(uuid, date) TO authenticated;

-- ── 2. Archivar la patente completa ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_archivar_equipos(
    p_activo_ids uuid[],
    p_motivo     text,
    p_hasta      date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_lote UUID; v_motivo TEXT; v_hasta DATE;
    v_nc INT; v_ot INT; v_bt INT; v_rs INT; v_ck INT; v_total INT;
    v_patentes TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    -- Archivar un equipo entero toca cinco tablas: lo hace la jefatura.
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Tu rol (%) no puede pasar un equipo completo al historial', v_rol;
    END IF;
    IF p_activo_ids IS NULL OR array_length(p_activo_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'No seleccionaste ninguna patente';
    END IF;

    v_motivo := NULLIF(btrim(COALESCE(p_motivo, '')), '');
    IF v_motivo IS NULL OR length(v_motivo) < 4 THEN
        RAISE EXCEPTION 'Escribe por qué se guarda en el historial (por ejemplo: «prueba de agosto»)';
    END IF;
    v_hasta := COALESCE(p_hasta, CURRENT_DATE);

    SELECT string_agg(COALESCE(a.patente, a.codigo), ', ' ORDER BY a.patente)
      INTO v_patentes FROM activos a WHERE a.id = ANY(p_activo_ids);
    IF v_patentes IS NULL THEN RAISE EXCEPTION 'Ninguna de esas patentes existe'; END IF;

    INSERT INTO archivo_lotes (entidad, motivo, archivado_por)
    VALUES ('equipo', v_motivo || ' · ' || v_patentes, v_user)
    RETURNING id INTO v_lote;

    UPDATE no_conformidades SET archivado_at = NOW(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = ANY(p_activo_ids) AND archivado_at IS NULL AND created_at::date <= v_hasta;
    GET DIAGNOSTICS v_nc = ROW_COUNT;

    -- Los repuestos primero: se identifican por su OT, y la OT se archiva después.
    UPDATE ot_recursos_solicitados r SET archivado_at = NOW(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
      FROM ordenes_trabajo o
     WHERE o.id = r.ot_id AND o.activo_id = ANY(p_activo_ids)
       AND r.archivado_at IS NULL AND r.created_at::date <= v_hasta;
    GET DIAGNOSTICS v_rs = ROW_COUNT;

    UPDATE ordenes_trabajo SET archivado_at = NOW(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = ANY(p_activo_ids) AND archivado_at IS NULL AND created_at::date <= v_hasta;
    GET DIAGNOSTICS v_ot = ROW_COUNT;

    UPDATE bodega_tickets SET archivado_at = NOW(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = ANY(p_activo_ids) AND archivado_at IS NULL AND created_at::date <= v_hasta;
    GET DIAGNOSTICS v_bt = ROW_COUNT;

    UPDATE checklist_v2_instance SET archivado_at = NOW(), archivado_por = v_user,
           archivado_motivo = v_motivo, archivado_lote = v_lote
     WHERE activo_id = ANY(p_activo_ids) AND archivado_at IS NULL AND created_at::date <= v_hasta;
    GET DIAGNOSTICS v_ck = ROW_COUNT;

    v_total := v_nc + v_ot + v_bt + v_rs + v_ck;
    UPDATE archivo_lotes SET n_registros = v_total WHERE id = v_lote;

    IF v_total = 0 THEN
        DELETE FROM archivo_lotes WHERE id = v_lote;
        RETURN jsonb_build_object('success', false, 'total', 0,
            'mensaje', 'Esas patentes ya no tenían nada que guardar');
    END IF;

    RETURN jsonb_build_object('success', true, 'lote_id', v_lote, 'total', v_total,
        'patentes', v_patentes, 'hasta', v_hasta,
        'no_conformidades', v_nc, 'ordenes_trabajo', v_ot,
        'vales', v_bt, 'repuestos', v_rs, 'checklists', v_ck);
END $function$;

GRANT EXECUTE ON FUNCTION public.rpc_archivar_equipos(uuid[], text, date) TO authenticated;

-- ── 3. Deshacer entiende el lote de equipo ────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_desarchivar_lote(p_lote uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_lote RECORD; v_cfg RECORD; v_n INTEGER; v_t INTEGER := 0; v_tabla TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT * INTO v_lote FROM archivo_lotes WHERE id = p_lote;
    IF v_lote.id IS NULL THEN RAISE EXCEPTION 'Ese lote no existe'; END IF;
    IF v_lote.revertido_at IS NOT NULL THEN
        RAISE EXCEPTION 'Ese lote ya se había devuelto el %', to_char(v_lote.revertido_at, 'DD-MM-YYYY HH24:MI');
    END IF;

    IF v_lote.entidad = 'equipo' THEN
        -- [MIG406] Se archivaron cinco tablas juntas: se devuelven las cinco.
        -- Deshacer a medias dejaría el camión sin NC pero con la OT colgando.
        IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
            RAISE EXCEPTION 'Tu rol (%) no puede devolver un equipo desde el historial', v_rol;
        END IF;
        FOREACH v_tabla IN ARRAY ARRAY['no_conformidades','ot_recursos_solicitados',
                                       'ordenes_trabajo','bodega_tickets','checklist_v2_instance']
        LOOP
            EXECUTE format($f$
                UPDATE public.%I SET archivado_at = NULL, archivado_por = NULL,
                       archivado_motivo = NULL, archivado_lote = NULL
                 WHERE archivado_lote = $1
            $f$, v_tabla) USING p_lote;
            GET DIAGNOSTICS v_n = ROW_COUNT;
            v_t := v_t + v_n;
        END LOOP;
    ELSE
        SELECT * INTO v_cfg FROM fn_archivable_config(v_lote.entidad);
        IF v_cfg.tabla IS NULL THEN
            RAISE EXCEPTION 'El lote apunta a «%», que ya no es archivable', v_lote.entidad; END IF;
        IF NOT (v_rol = ANY (v_cfg.roles)) THEN
            RAISE EXCEPTION 'Tu rol (%) no puede devolver % desde el historial', v_rol, v_lote.entidad; END IF;
        EXECUTE format($f$
            UPDATE public.%I SET archivado_at = NULL, archivado_por = NULL,
                   archivado_motivo = NULL, archivado_lote = NULL
             WHERE archivado_lote = $1
        $f$, v_cfg.tabla) USING p_lote;
        GET DIAGNOSTICS v_t = ROW_COUNT;
    END IF;

    UPDATE archivo_lotes SET revertido_at = NOW(), revertido_por = v_user WHERE id = p_lote;
    RETURN jsonb_build_object('success', true, 'devueltos', v_t, 'entidad', v_lote.entidad);
END $function$;

-- ── 4. La lista de patentes con lo que arrastra cada una ──────────────────
CREATE OR REPLACE VIEW public.v_equipos_para_archivar AS
SELECT a.id AS activo_id,
       a.codigo AS activo_codigo,
       a.patente,
       a.nombre AS activo_nombre,
       a.tipo,
       a.estado::text AS estado,
       r.n_nc, r.n_ot, r.n_vales, r.n_recursos, r.n_checklists, r.n_total,
       r.vales_con_pendiente
  FROM activos a
  CROSS JOIN LATERAL fn_equipo_archivable_resumen(a.id, NULL) r
 WHERE a.estado <> 'dado_baja'::estado_activo_enum;

GRANT SELECT ON public.v_equipos_para_archivar TO authenticated;

COMMENT ON VIEW public.v_equipos_para_archivar IS
  'MIG406: cada patente con cuánto arrastra sin archivar. Alimenta la pantalla de «guardar equipos en el historial».';

-- ── 5. Cómo queda ─────────────────────────────────────────────────────────
DO $r$
DECLARE r RECORD; v_con INT;
BEGIN
    SELECT count(*) INTO v_con FROM v_equipos_para_archivar WHERE n_total > 0;
    RAISE NOTICE 'Equipos con algo que archivar: %', v_con;
    FOR r IN SELECT patente, n_nc, n_ot, n_vales, n_recursos, n_checklists, n_total
               FROM v_equipos_para_archivar WHERE n_total > 0 ORDER BY n_total DESC LIMIT 6
    LOOP
        RAISE NOTICE '  % · % en total (NC %, OT %, vales %, repuestos %, checklists %)',
            r.patente, r.n_total, r.n_nc, r.n_ot, r.n_vales, r.n_recursos, r.n_checklists;
    END LOOP;
END
$r$;

COMMIT;
