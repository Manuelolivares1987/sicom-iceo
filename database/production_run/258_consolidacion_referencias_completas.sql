-- ============================================================================
-- SICOM-ICEO | 258 — La consolidación tiene que mover TODAS las referencias
-- ----------------------------------------------------------------------------
-- BUG de MIG257. Para saber qué colgaba de una OT busqué las columnas llamadas
-- exactamente `ot_id`, en vez de las claves foráneas de verdad. Se me pasaron
-- todas las que se llaman distinto, y una duele:
--
--   · no_conformidades.plan_ot_id          → 36 filas. La OT que va a ARREGLAR
--     la NC. Quedaron 36 NC en estado 'planificada' apuntando a una OT
--     cancelada: no aparecen como pendientes en la bandeja (ya están
--     "planificadas") y tampoco en «Correctivos de recepción por agendar»
--     (esa vista exige OT en 'creada'/'asignada'). Invisibles.
--   · estado_diario_flota.ot_relacionada_id  → 3 filas
--   · verificaciones_disponibilidad.ot_id    → 2 filas
--
-- (no_conformidades.ot_id — dónde se ENCONTRÓ la NC — sí se movió en MIG257.)
--
-- Esta migración:
--   1. repunta lo que quedó huérfano, usando el log ot_consolidaciones
--   2. reescribe fn_consolidar_ots_duplicadas para que barra TODAS las FK que
--      apuntan a ordenes_trabajo (leídas de pg_constraint, no de una lista a
--      mano), así una tabla nueva con FK a la OT queda cubierta sola
--
-- Excluidas del barrido a propósito:
--   · historial_estado_ot   → es la bitácora de ESA OT, no se reescribe
--   · ot_consolidaciones    → es el log de esta operación
--   · movimientos_inventario, salidas_bodega, inventario_consumos_capas,
--     informes_intervencion, activo_certificados → costo imputado o documento
--     emitido: son motivo de OMISIÓN, no se reimputan hacia atrás
--
-- ADITIVA. IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname='ot_consolidaciones') THEN
        RAISE EXCEPTION 'STOP — falta ot_consolidaciones (MIG257 no aplicada).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_consolidar_ots_duplicadas') THEN
        RAISE EXCEPTION 'STOP — falta fn_consolidar_ots_duplicadas (MIG257 no aplicada).';
    END IF;
END $$;


-- ── 1. Qué tablas hay que barrer (una sola fuente de verdad) ────────────────
CREATE OR REPLACE VIEW public.v_ot_referencias_fk AS
SELECT t.relname::text  AS tabla,
       a.attname::text  AS columna,
       -- las que se tratan aparte o no se tocan nunca
       (t.relname::text IN ('historial_estado_ot','ot_consolidaciones',
                            'movimientos_inventario','salidas_bodega',
                            'inventario_consumos_capas','informes_intervencion',
                            'activo_certificados')
        OR (t.relname::text = 'taller_plan_semanal_ots' AND a.attname::text = 'ot_id')
        OR (t.relname::text = 'checklist_ot'            AND a.attname::text = 'ot_id')
       ) AS excluida
  FROM pg_constraint c
  JOIN pg_class t     ON t.oid = c.conrelid
  JOIN pg_class r     ON r.oid = c.confrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  JOIN unnest(c.conkey) k ON true
  JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k
 WHERE c.contype = 'f'
   AND r.relname = 'ordenes_trabajo'
   AND n.nspname = 'public'
   AND array_length(c.conkey, 1) = 1;

COMMENT ON VIEW public.v_ot_referencias_fk IS
    'Toda columna FK que apunta a ordenes_trabajo, y si la consolidación la barre o la trata aparte. MIG258.';

GRANT SELECT ON public.v_ot_referencias_fk TO authenticated;


-- ── 2. Reparar lo que dejó huérfano MIG257 ──────────────────────────────────
DO $$
DECLARE
    r        RECORD;
    v_sql    TEXT;
    v_n      INT;
    v_total  INT := 0;
BEGIN
    FOR r IN SELECT tabla, columna FROM v_ot_referencias_fk WHERE NOT excluida
    LOOP
        v_sql := format(
            'UPDATE %I x SET %I = c.ot_destino_id
               FROM ot_consolidaciones c
              WHERE x.%I = c.ot_origen_id', r.tabla, r.columna, r.columna);
        BEGIN
            EXECUTE v_sql;
            GET DIAGNOSTICS v_n = ROW_COUNT;
            IF v_n > 0 THEN
                v_total := v_total + v_n;
                RAISE NOTICE 'MIG258 repuntadas % filas de %.%', v_n, r.tabla, r.columna;
            END IF;
        EXCEPTION WHEN unique_violation THEN
            -- La fila del destino ya existe: la del duplicado se deja como está
            -- y se reporta para revisión manual (no se borra nada).
            RAISE WARNING 'MIG258 conflicto de unicidad en %.% — revisar a mano', r.tabla, r.columna;
        END;
    END LOOP;
    RAISE NOTICE 'MIG258 total repuntado: % filas', v_total;
END $$;


-- ── 3. La consolidación, ahora completa ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_consolidar_ots_duplicadas(
    p_dry_run BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_rol         TEXT;
    v_grupo       RECORD;
    v_dest        RECORD;
    v_orig        RECORD;
    v_ref         RECORD;
    v_grupos      INT := 0;
    v_canceladas  INT := 0;
    v_omitidas    INT := 0;
    v_dias        INT := 0;
    v_items       INT := 0;
    v_refs        INT := 0;
    v_n           INT;
    v_movidos     JSONB;
    v_detalle     JSONB := '[]'::jsonb;
    v_cancel_grupo JSONB;
    v_omit_grupo   JSONB;
    v_bloqueo     TEXT;
    v_max_orden   INT;
    v_abiertos CONSTANT TEXT[] := ARRAY['ejecutada_ok','ejecutada_con_observaciones',
                                        'no_ejecutada','cancelada','cerrada'];
BEGIN
    v_rol := fn_user_rol();
    -- Desde el script de migración no hay JWT (rol NULL) y eso es válido.
    IF v_rol IS NOT NULL
       AND v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Solo administración o la jefatura de mantenimiento puede consolidar OT duplicadas.';
    END IF;

    FOR v_grupo IN
        SELECT o.activo_id, o.tipo, o.plan_mantenimiento_id, count(*) AS n
          FROM ordenes_trabajo o
         WHERE o.estado::text <> ALL (v_abiertos)
         GROUP BY o.activo_id, o.tipo, o.plan_mantenimiento_id
        HAVING count(*) > 1
         ORDER BY count(*) DESC
    LOOP
        -- La que sobrevive: donde está el trabajo de verdad.
        SELECT o.* INTO v_dest
          FROM ordenes_trabajo o
         WHERE o.activo_id = v_grupo.activo_id
           AND o.tipo = v_grupo.tipo
           AND o.plan_mantenimiento_id IS NOT DISTINCT FROM v_grupo.plan_mantenimiento_id
           AND o.estado::text <> ALL (v_abiertos)
         ORDER BY (SELECT count(*) FROM taller_ot_ejecuciones e WHERE e.ot_id = o.id) DESC,
                  array_position(ARRAY['creada','asignada','pausada','en_ejecucion'],
                                 o.estado::text) DESC NULLS LAST,
                  (SELECT count(*) FROM taller_plan_semanal_ots p WHERE p.ot_id = o.id) DESC,
                  o.created_at DESC
         LIMIT 1;

        v_grupos := v_grupos + 1;
        v_cancel_grupo := '[]'::jsonb;
        v_omit_grupo   := '[]'::jsonb;

        FOR v_orig IN
            SELECT o.* FROM ordenes_trabajo o
             WHERE o.activo_id = v_grupo.activo_id
               AND o.tipo = v_grupo.tipo
               AND o.plan_mantenimiento_id IS NOT DISTINCT FROM v_grupo.plan_mantenimiento_id
               AND o.estado::text <> ALL (v_abiertos)
               AND o.id <> v_dest.id
             ORDER BY o.created_at
        LOOP
            -- Costo ya imputado o documento ya emitido: no se reimputa hacia
            -- atrás. Se deja abierta y se reporta.
            v_bloqueo := NULL;
            IF EXISTS (SELECT 1 FROM movimientos_inventario  WHERE ot_id = v_orig.id) THEN
                v_bloqueo := 'tiene movimientos de inventario imputados';
            ELSIF EXISTS (SELECT 1 FROM salidas_bodega       WHERE ot_id = v_orig.id) THEN
                v_bloqueo := 'tiene salidas de bodega imputadas';
            ELSIF EXISTS (SELECT 1 FROM inventario_consumos_capas WHERE ot_id = v_orig.id) THEN
                v_bloqueo := 'tiene consumos de inventario valorizados';
            ELSIF EXISTS (SELECT 1 FROM informes_intervencion WHERE ot_id = v_orig.id) THEN
                v_bloqueo := 'ya emitió informe de intervención';
            ELSIF EXISTS (SELECT 1 FROM activo_certificados   WHERE ot_id = v_orig.id) THEN
                v_bloqueo := 'ya emitió certificado del equipo';
            END IF;

            IF v_bloqueo IS NOT NULL THEN
                v_omitidas := v_omitidas + 1;
                v_omit_grupo := v_omit_grupo || jsonb_build_object(
                    'folio', v_orig.folio, 'motivo', v_bloqueo);
                CONTINUE;
            END IF;

            v_movidos := '{}'::jsonb;

            IF NOT p_dry_run THEN
                -- ── Días del plan semanal (unique: plan + ot + día) ─────────
                -- Si la que sobrevive ya está ese mismo día de ese mismo plan,
                -- el día del duplicado se borra (es el mismo día repetido).
                -- Antes se repunta la ejecución que apuntaba a esa fila.
                UPDATE taller_ot_ejecuciones e
                   SET plan_semanal_ot_id = q.id, updated_at = NOW()
                  FROM taller_plan_semanal_ots p
                  JOIN taller_plan_semanal_ots q
                    ON q.ot_id = v_dest.id
                   AND q.plan_semanal_id = p.plan_semanal_id
                   AND q.plan_dia_id = p.plan_dia_id
                 WHERE e.plan_semanal_ot_id = p.id
                   AND p.ot_id = v_orig.id
                   AND p.plan_dia_id IS NOT NULL;

                DELETE FROM taller_plan_semanal_ots p
                 WHERE p.ot_id = v_orig.id
                   AND p.plan_dia_id IS NOT NULL
                   AND EXISTS (SELECT 1 FROM taller_plan_semanal_ots q
                                WHERE q.ot_id = v_dest.id
                                  AND q.plan_semanal_id = p.plan_semanal_id
                                  AND q.plan_dia_id = p.plan_dia_id);
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos || jsonb_build_object('dias_plan_repetidos_borrados', v_n);

                UPDATE taller_plan_semanal_ots
                   SET ot_id = v_dest.id, updated_at = NOW()
                 WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_dias := v_dias + v_n;
                v_movidos := v_movidos || jsonb_build_object('dias_plan', v_n);

                -- ── Ítems del checklist YA RESPONDIDOS (unique: ot + orden) ──
                -- El checklist en blanco es un clon de la pauta y se va con el
                -- duplicado; lo respondido se anexa al final del que sobrevive.
                SELECT COALESCE(max(orden), 0) INTO v_max_orden
                  FROM checklist_ot WHERE ot_id = v_dest.id;

                WITH movibles AS (
                    SELECT id, row_number() OVER (ORDER BY orden) AS rn
                      FROM checklist_ot
                     WHERE ot_id = v_orig.id AND resultado IS NOT NULL
                )
                UPDATE checklist_ot c
                   SET ot_id = v_dest.id,
                       orden = v_max_orden + m.rn,
                       descripcion = c.descripcion || ' [de ' || v_orig.folio || ']'
                  FROM movibles m
                 WHERE c.id = m.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_items := v_items + v_n;
                v_movidos := v_movidos || jsonb_build_object('items_checklist_respondidos', v_n);

                -- ── [MIG258] Y TODO el resto de las FK, sin lista a mano ─────
                -- Incluye no_conformidades.plan_ot_id (la OT que arregla la NC),
                -- que es justo la que se me pasó en MIG257.
                FOR v_ref IN SELECT tabla, columna FROM v_ot_referencias_fk WHERE NOT excluida
                LOOP
                    BEGIN
                        EXECUTE format('UPDATE %I SET %I = $1 WHERE %I = $2',
                                       v_ref.tabla, v_ref.columna, v_ref.columna)
                          USING v_dest.id, v_orig.id;
                        GET DIAGNOSTICS v_n = ROW_COUNT;
                        IF v_n > 0 THEN
                            v_refs := v_refs + v_n;
                            v_movidos := v_movidos || jsonb_build_object(
                                v_ref.tabla || '.' || v_ref.columna, v_n);
                        END IF;
                    EXCEPTION WHEN unique_violation THEN
                        v_movidos := v_movidos || jsonb_build_object(
                            v_ref.tabla || '.' || v_ref.columna, 'conflicto_unicidad');
                    END;
                END LOOP;

                -- ── Lo que se sabía del duplicado no se pierde ──────────────
                IF COALESCE(trim(v_orig.observaciones), '') <> ''
                   AND position(v_orig.folio IN COALESCE(v_dest.observaciones, '')) = 0 THEN
                    UPDATE ordenes_trabajo
                       SET observaciones = trim(COALESCE(observaciones, '') || E'\n[de ' ||
                                                v_orig.folio || '] ' || trim(v_orig.observaciones)),
                           updated_at = NOW()
                     WHERE id = v_dest.id;
                END IF;

                -- La que sobrevive queda con la última fecha planificada, la
                -- prioridad más alta del grupo y responsable/técnico si le falta.
                UPDATE ordenes_trabajo d
                   SET fecha_programada = GREATEST(COALESCE(d.fecha_programada, v_orig.fecha_programada),
                                                   COALESCE(v_orig.fecha_programada, d.fecha_programada)),
                       prioridad = CASE WHEN fn_prioridad_rank(v_orig.prioridad) > fn_prioridad_rank(d.prioridad)
                                        THEN v_orig.prioridad ELSE d.prioridad END,
                       responsable_id = COALESCE(d.responsable_id, v_orig.responsable_id),
                       tecnico_id     = COALESCE(d.tecnico_id, v_orig.tecnico_id),
                       cuadrilla      = COALESCE(d.cuadrilla, v_orig.cuadrilla),
                       updated_at = NOW()
                 WHERE d.id = v_dest.id;

                -- ── Y ahora sí, se cancela el duplicado ─────────────────────
                UPDATE ordenes_trabajo
                   SET estado = 'cancelada',
                       observaciones = trim(COALESCE(observaciones, '') || E'\n[MIG257] ' ||
                           'OT duplicada del mismo trabajo: se canceló y el trabajo continúa en ' ||
                           v_dest.folio || '.'),
                       updated_at = NOW()
                 WHERE id = v_orig.id;

                INSERT INTO ot_consolidaciones (
                    ot_origen_id, ot_destino_id, folio_origen, folio_destino,
                    activo_id, tipo, plan_mantenimiento_id,
                    estado_origen, prioridad_origen, fecha_programada_origen,
                    observaciones_origen, movidos, motivo, created_by
                ) VALUES (
                    v_orig.id, v_dest.id, v_orig.folio, v_dest.folio,
                    v_orig.activo_id, v_orig.tipo, v_orig.plan_mantenimiento_id,
                    v_orig.estado, v_orig.prioridad, v_orig.fecha_programada,
                    v_orig.observaciones, v_movidos,
                    'Duplicada del mismo trabajo (mismo equipo, tipo y pauta). MIG257.',
                    auth.uid()
                )
                ON CONFLICT (ot_origen_id) DO NOTHING;
            END IF;

            v_canceladas := v_canceladas + 1;
            v_cancel_grupo := v_cancel_grupo || jsonb_build_object(
                'folio', v_orig.folio, 'estado', v_orig.estado, 'movidos', v_movidos);
        END LOOP;

        v_detalle := v_detalle || jsonb_build_object(
            'patente',   (SELECT patente FROM activos WHERE id = v_grupo.activo_id),
            'tipo',      v_grupo.tipo,
            'pauta',     v_grupo.plan_mantenimiento_id,
            'sobrevive', v_dest.folio,
            'canceladas', v_cancel_grupo,
            'omitidas',   v_omit_grupo
        );
    END LOOP;

    RETURN jsonb_build_object(
        'dry_run',    p_dry_run,
        'grupos',     v_grupos,
        'canceladas', v_canceladas,
        'omitidas',   v_omitidas,
        'movido',     jsonb_build_object(
                          'dias_plan', v_dias,
                          'items_checklist', v_items,
                          'otras_referencias', v_refs),
        'detalle',    v_detalle
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) IS
    'Fusiona las OT abiertas duplicadas del mismo trabajo en una sola y cancela el resto, moviendo TODA referencia FK (v_ot_referencias_fk). p_dry_run=true solo reporta. MIG257 + MIG258.';

REVOKE ALL ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    r RECORD; v_sql TEXT; v_n INT; v_huerfanos INT := 0; v_lista TEXT := '';
BEGIN
    -- Ninguna referencia viva puede seguir apuntando a una OT que consolidamos.
    FOR r IN SELECT tabla, columna FROM v_ot_referencias_fk WHERE NOT excluida
    LOOP
        v_sql := format('SELECT count(*) FROM %I x JOIN ot_consolidaciones c ON c.ot_origen_id = x.%I',
                        r.tabla, r.columna);
        EXECUTE v_sql INTO v_n;
        IF v_n > 0 THEN
            v_huerfanos := v_huerfanos + v_n;
            v_lista := v_lista || format('%s.%s=%s ', r.tabla, r.columna, v_n);
        END IF;
    END LOOP;
    IF v_huerfanos > 0 THEN
        RAISE EXCEPTION 'FALLO — quedan % referencias a OT consolidadas: %', v_huerfanos, v_lista;
    END IF;

    -- Y ninguna NC puede quedar 'planificada' contra una OT cancelada.
    SELECT count(*) INTO v_n
      FROM no_conformidades nc
      JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
     WHERE nc.estado_planificacion = 'planificada'
       AND o.estado IN ('cancelada','no_ejecutada')
       AND COALESCE(nc.resuelto, false) = false;
    IF v_n > 0 THEN
        RAISE EXCEPTION 'FALLO — % NC planificadas contra una OT cancelada', v_n;
    END IF;

    RAISE NOTICE 'MIG258 OK — 0 referencias huérfanas, 0 NC planificadas contra OT cancelada';
END $$;

NOTIFY pgrst, 'reload schema';
