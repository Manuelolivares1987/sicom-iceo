-- ============================================================================
-- SICOM-ICEO | 271 — La auditoría de calidad se retoma, no se vuelve a empezar
-- ============================================================================
-- Reporte de Felipe López (auditor_calidad, 2026-08-04):
--   iniciaba la auditoría de un equipo, salía, volvía… y tenía que empezar de
--   nuevo. Debe poder pausar, volver al otro día y seguir donde quedó.
--
-- Causa: fn_iniciar_auditoria_calidad hacía un INSERT pelado, sin mirar si el
--   equipo YA tenía una auditoría abierta. Cada clic en «Iniciar» fabricaba una
--   auditoría nueva con sus 188 ítems en blanco, y la anterior quedaba viva pero
--   perdida en la lista. En RSCY-85 quedaron 14 auditorías pendientes del mismo
--   equipo — dos creadas en el MISMO segundo (18:08:46.327 y .334), o sea un
--   doble clic. El trabajo real de Felipe quedó repartido:
--     a37ea70d 56 ítems (11 observaciones) · f866d3c4 14 · 46c567a4 3 · ce2f5969 1
--   y las otras 10 completamente vacías (sus 3 «marcados» son documentación
--   auto-marcada al crear, no trabajo humano).
--
-- El autoguardado (MIG260) siempre funcionó: nada se había perdido, estaba
-- disperso. Esta migración:
--   1. fn_iniciar_auditoria_calidad RETOMA la auditoría abierta del equipo.
--   2. Consolida los duplicados existentes: el avance de las repetidas se trae
--      a la que tiene más trabajo y las demás se anulan (no se borran).
--   3. Índice único parcial: una sola auditoría abierta por equipo, garantizado
--      por la base — cubre el doble clic, que un chequeo en la función no ataja.
--   4. La vista de pendientes expone la última actividad, para que al volver al
--      otro día se vea cuándo se dejó el trabajo.
--
-- ADITIVA salvo la anulación de duplicados (reversible: anulada=false).
-- ============================================================================


-- ── 1. Retomar en vez de duplicar ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_iniciar_auditoria_calidad(
    p_activo_id uuid,
    p_ot_id     uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_aud  UUID;
    v_tot  INT;
    v_tipo tipo_equipamiento_enum;
    v_tpl  UUID;
    v_tpl_nombre TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM activos WHERE id = p_activo_id) THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id; END IF;

    SELECT COALESCE(tipo_equipamiento,'generico') INTO v_tipo FROM activos WHERE id = p_activo_id;
    SELECT id, nombre INTO v_tpl, v_tpl_nombre
      FROM checklist_template_v2
     WHERE momento_uso='recepcion_devolucion' AND activo=true
     ORDER BY version DESC LIMIT 1;

    -- [MIG271] Retomar en vez de duplicar. Antes cada clic en «Iniciar» insertaba
    -- una auditoria nueva con sus 188 items en blanco: el auditor salia, volvia,
    -- apretaba Iniciar y perdia de vista lo avanzado (14 auditorias abiertas del
    -- mismo equipo en RSCY-85, dos creadas en el mismo segundo por doble clic).
    SELECT id INTO v_aud FROM auditorias_calidad
     WHERE activo_id = p_activo_id AND resultado = 'pendiente' AND anulada = false
     ORDER BY created_at DESC LIMIT 1;
    IF v_aud IS NOT NULL THEN
        IF p_ot_id IS NOT NULL THEN
            UPDATE auditorias_calidad SET ot_id = COALESCE(ot_id, p_ot_id) WHERE id = v_aud;
        END IF;
        RETURN jsonb_build_object(
            'auditoria_id', v_aud,
            'retomada', true,
            'items_total', (SELECT count(*) FROM auditoria_calidad_items WHERE auditoria_id = v_aud),
            'items_marcados', (SELECT count(*) FROM auditoria_calidad_items
                                WHERE auditoria_id = v_aud AND resultado <> 'pendiente'),
            'fuente', 'auditoria en curso',
            'no_aplican_al_tipo', (SELECT count(*) FROM auditoria_calidad_items
                                    WHERE auditoria_id = v_aud AND aplica_tipo = false));
    END IF;

    INSERT INTO auditorias_calidad (activo_id, ot_id, iniciada_por, created_by)
    VALUES (p_activo_id, p_ot_id, v_user, v_user)
    RETURNING id INTO v_aud;

    IF v_tpl IS NOT NULL THEN
        -- [MIG260] TODOS los ítems del template. Antes se filtraba por
        -- tipo_equipamiento y un equipo sin tipo perdía 28 ítems, entre ellos
        -- las pruebas de ruta.
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado, bloque, bloque_orden, requiere_foto, aplica_tipo)
        SELECT
            v_aud,
            ti.categoria_calidad,
            ti.bloque_orden * 1000 + ti.orden,
            ti.descripcion, ti.obligatorio, ti.critico,
            c.cert_id,
            CASE
                WHEN ti.categoria_calidad = 'documentacion' AND ti.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END,
            ti.bloque, ti.bloque_orden, COALESCE(ti.requiere_foto, false),
            (v_tipo = ANY(ti.tipos_equipamiento))
        FROM checklist_template_v2_item ti
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND ti.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = ti.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE ti.template_id = v_tpl
          AND ti.categoria_calidad IS NOT NULL
        ORDER BY ti.bloque_orden, ti.orden;

        GET DIAGNOSTICS v_tot = ROW_COUNT;
    ELSE
        v_tot := 0;
    END IF;

    -- Fallback: plantilla legacy si el template no aportó ítems
    IF v_tot = 0 THEN
        INSERT INTO auditoria_calidad_items
            (auditoria_id, categoria, orden, descripcion, obligatorio, critico,
             referencia_cert_id, resultado, bloque, bloque_orden)
        SELECT
            v_aud, p.categoria, p.orden, p.descripcion, p.obligatorio, p.critico,
            c.cert_id,
            CASE
                WHEN p.categoria = 'documentacion' AND p.cert_tipo IS NOT NULL THEN
                    CASE WHEN c.estado = 'vigente' THEN 'ok'
                         WHEN c.estado IS NULL THEN 'pendiente'
                         ELSE 'no_ok' END
                ELSE 'pendiente'
            END,
            'Plantilla base', 1
        FROM auditoria_calidad_plantilla_items p
        LEFT JOIN LATERAL (
            SELECT cc.id AS cert_id, cc.estado AS estado
            FROM certificaciones cc
            WHERE cc.activo_id = p_activo_id
              AND p.cert_tipo IS NOT NULL
              AND cc.tipo::TEXT = p.cert_tipo
            ORDER BY cc.fecha_vencimiento DESC NULLS LAST
            LIMIT 1
        ) c ON true
        WHERE p.activo = true
        ORDER BY p.categoria, p.orden;
        GET DIAGNOSTICS v_tot = ROW_COUNT;
        v_tpl_nombre := 'plantilla legacy';
    END IF;

    UPDATE auditorias_calidad SET items_total = v_tot WHERE id = v_aud;
    RETURN jsonb_build_object(
        'auditoria_id', v_aud,
        'retomada', false,
        'items_total', v_tot,
        'fuente', COALESCE(v_tpl_nombre, 'plantilla legacy'),
        'no_aplican_al_tipo', (SELECT count(*) FROM auditoria_calidad_items
                                WHERE auditoria_id = v_aud AND aplica_tipo = false));
END $function$;

COMMENT ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) IS
    'Abre la auditoría de calidad con el checklist V03 completo, o RETOMA la que el equipo ya tenga abierta. MIG125 + MIG260 + MIG271.';

REVOKE ALL ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_iniciar_auditoria_calidad(UUID, UUID) TO authenticated;


-- ── 2. Consolidar los duplicados que ya existen ─────────────────────────────
-- Gana la auditoría con más trabajo HUMANO (completado_at NOT NULL; los ítems
-- de documentación auto-marcados al crear no cuentan). A ella se le trae lo que
-- las repetidas tengan y a ella le falte. Las repetidas se anulan, no se borran.
DO $$
DECLARE
    r_act       RECORD;
    v_win       UUID;
    v_n_merge   INT;
    v_n_anul    INT;
    v_tot_merge INT := 0;
    v_tot_anul  INT := 0;
    v_equipos   INT := 0;
BEGIN
    FOR r_act IN
        SELECT activo_id FROM auditorias_calidad
         WHERE resultado = 'pendiente' AND anulada = false
         GROUP BY activo_id HAVING count(*) > 1
    LOOP
        SELECT a.id INTO v_win
          FROM auditorias_calidad a
         WHERE a.activo_id = r_act.activo_id AND a.resultado = 'pendiente' AND a.anulada = false
         ORDER BY (SELECT count(*) FROM auditoria_calidad_items i
                    WHERE i.auditoria_id = a.id AND i.completado_at IS NOT NULL) DESC,
                  a.created_at DESC
         LIMIT 1;

        WITH dup AS (
            SELECT id FROM auditorias_calidad
             WHERE activo_id = r_act.activo_id AND resultado = 'pendiente'
               AND anulada = false AND id <> v_win
        ), mejor AS (
            -- por ítem, la marca humana más reciente entre las duplicadas
            SELECT DISTINCT ON (i.orden, i.descripcion)
                   i.orden, i.descripcion, i.resultado, i.observacion, i.foto_url,
                   i.completado_at, i.completado_por
              FROM auditoria_calidad_items i
              JOIN dup ON dup.id = i.auditoria_id
             WHERE i.completado_at IS NOT NULL
             ORDER BY i.orden, i.descripcion, i.completado_at DESC
        )
        UPDATE auditoria_calidad_items w SET
            resultado      = m.resultado,
            observacion    = COALESCE(w.observacion, m.observacion),
            foto_url       = COALESCE(w.foto_url, m.foto_url),
            completado_at  = m.completado_at,
            completado_por = m.completado_por
          FROM mejor m
         WHERE w.auditoria_id = v_win
           AND w.orden       = m.orden
           AND w.descripcion = m.descripcion
           AND w.completado_at IS NULL;   -- nunca pisa lo que la ganadora ya tiene
        GET DIAGNOSTICS v_n_merge = ROW_COUNT;

        UPDATE auditorias_calidad
           SET anulada = true, anulada_at = NOW(),
               anulada_motivo = 'MIG271 — duplicada del mismo equipo; su avance se consolidó en ' || v_win
         WHERE activo_id = r_act.activo_id AND resultado = 'pendiente'
           AND anulada = false AND id <> v_win;
        GET DIAGNOSTICS v_n_anul = ROW_COUNT;

        v_equipos := v_equipos + 1;
        v_tot_merge := v_tot_merge + v_n_merge;
        v_tot_anul  := v_tot_anul  + v_n_anul;
        RAISE NOTICE 'activo %: gana %, % items traidos, % duplicadas anuladas',
                     r_act.activo_id, v_win, v_n_merge, v_n_anul;
    END LOOP;
    RAISE NOTICE 'MIG271: % equipos consolidados, % items traidos, % auditorias anuladas',
                 v_equipos, v_tot_merge, v_tot_anul;
END $$;


-- ── 3. Una sola auditoría abierta por equipo, garantizado por la base ───────
-- El chequeo dentro de la función no ataja el doble clic (dos transacciones a la
-- vez leen «no hay ninguna» y ambas insertan). El índice sí.
CREATE UNIQUE INDEX IF NOT EXISTS ux_auditoria_calidad_abierta_por_activo
    ON auditorias_calidad (activo_id)
 WHERE resultado = 'pendiente' AND anulada = false;

COMMENT ON INDEX ux_auditoria_calidad_abierta_por_activo IS
    'Un equipo no puede tener dos auditorías de calidad abiertas a la vez. MIG271.';


-- ── 4. La vista muestra cuándo se dejó el trabajo ───────────────────────────
-- Para el caso «vuelvo al otro día»: la tarjeta puede decir desde cuándo está
-- pausada. Columna al final: CREATE OR REPLACE VIEW no admite reordenar.
CREATE OR REPLACE VIEW public.v_auditorias_calidad_pendientes AS
SELECT ac.id,
       ac.activo_id,
       a.patente,
       a.codigo,
       ac.ot_id,
       ot.folio,
       ac.iniciada_por,
       ui.nombre_completo AS iniciada_nombre,
       ac.items_total,
       ac.created_at,
       (SELECT count(*) FROM auditoria_calidad_items i
         WHERE i.auditoria_id = ac.id AND i.resultado <> 'pendiente')::int AS items_marcados,
       (SELECT max(i.completado_at) FROM auditoria_calidad_items i
         WHERE i.auditoria_id = ac.id) AS ultima_actividad
  FROM auditorias_calidad ac
  JOIN activos a ON a.id = ac.activo_id
  LEFT JOIN ordenes_trabajo ot ON ot.id = ac.ot_id
  LEFT JOIN usuarios_perfil ui ON ui.id = ac.iniciada_por
 WHERE ac.resultado = 'pendiente'::resultado_verificacion_enum
   AND ac.anulada = false
 ORDER BY ac.created_at;

GRANT SELECT ON public.v_auditorias_calidad_pendientes TO authenticated;


-- ── 5. VALIDACION ───────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'equipos_con_mas_de_una_abierta', (SELECT count(*) FROM (
        SELECT activo_id FROM auditorias_calidad
         WHERE resultado='pendiente' AND anulada=false
         GROUP BY activo_id HAVING count(*) > 1) x),
    'auditorias_abiertas', (SELECT count(*) FROM auditorias_calidad
        WHERE resultado='pendiente' AND anulada=false),
    'anuladas_por_mig271', (SELECT count(*) FROM auditorias_calidad
        WHERE anulada_motivo LIKE 'MIG271%'),
    'indice_unico', (SELECT EXISTS(SELECT 1 FROM pg_indexes
        WHERE indexname='ux_auditoria_calidad_abierta_por_activo')),
    'fn_retoma', (SELECT prosrc LIKE '%retomada%' FROM pg_proc p
        JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='fn_iniciar_auditoria_calidad'),
    'rscy85_abierta', (SELECT jsonb_agg(jsonb_build_object(
            'id', left(ac.id::text,8),
            'humano', (SELECT count(*) FROM auditoria_calidad_items i
                        WHERE i.auditoria_id=ac.id AND i.completado_at IS NOT NULL),
            'con_obs', (SELECT count(*) FROM auditoria_calidad_items i
                        WHERE i.auditoria_id=ac.id AND i.observacion IS NOT NULL
                          AND btrim(i.observacion)<>'')))
        FROM auditorias_calidad ac JOIN activos a ON a.id=ac.activo_id
       WHERE a.patente='RSCY-85' AND ac.resultado='pendiente' AND ac.anulada=false)
) AS resultado;

NOTIFY pgrst, 'reload schema';
