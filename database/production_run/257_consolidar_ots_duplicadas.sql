-- ============================================================================
-- SICOM-ICEO | 257 — Consolidar las OT duplicadas que ya están en producción
-- ----------------------------------------------------------------------------
-- MIG256 dejó de duplicar la OT al planificar la semana, pero no limpió lo que
-- ya estaba hecho. Al momento de escribir esta migración, producción tiene:
--
--     102 OT abiertas · 23 grupos duplicados (mismo equipo + mismo trabajo)
--      57 OT sobrantes · 126 días del plan semanal repartidos entre folios
--
-- Los duplicados están casi vacíos: 659 ítems de checklist clonados de la pauta
-- con CERO respondidos, 0 evidencias, 0 NC, 0 vales de bodega. Lo que sí duele
-- son los 126 días del plan y las 4 ejecuciones (horas del mecánico) colgando
-- de folios distintos del mismo trabajo.
--
-- Criterio, confirmado por Manuel y el mismo de MIG256:
--   · mismo equipo + mismo tipo + misma pauta = un solo trabajo = una sola OT
--   · un correctivo de embrague y uno de frenos sobre el mismo equipo van como
--     tareas dentro de la misma OT correctiva abierta, no como OT separadas
--
-- La OT que sobrevive es la que tiene el trabajo de verdad:
--   1. la que tiene ejecuciones registradas (horas del mecánico)
--   2. la de estado más avanzado (en_ejecucion > pausada > asignada > creada)
--   3. la que tiene más días en el plan semanal
--   4. a igualdad, la más reciente
--
-- Todo lo que cuelga del duplicado se mueve a la que sobrevive (días del plan,
-- ejecuciones y sus eventos, recursos pedidos, evidencias, NC, ítems de
-- checklist ya respondidos) y sus observaciones se copian con el folio de
-- origen. Recién entonces el duplicado pasa a 'cancelada' diciendo dónde sigue
-- el trabajo.
--
-- Lo que NO se toca: si un duplicado ya movió inventario (kardex, salidas de
-- bodega, consumos) o emitió documentos (informe de intervención, certificado),
-- se OMITE y se reporta para revisión manual. Reimputar un kardex hacia atrás es
-- peor que dejar dos OT abiertas. Hoy no hay ninguna en ese caso.
--
-- Además arregla un bug de MIG256: el rank de prioridad comparaba contra
-- ARRAY['baja','normal','alta','urgente'] y prioridad_enum es
-- 'emergencia|urgente|alta|normal|baja' — 'emergencia' no estaba en el array,
-- así que array_position devolvía NULL y una OT en emergencia que se
-- reprogramaba quedaba DEGRADADA a la prioridad nueva.
--
-- Queda log en ot_consolidaciones (con estado, fecha y observaciones originales)
-- para poder revertir o auditar. IDEMPOTENTE: re-ejecutarla no hace nada.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_programar_ot_taller') THEN
        RAISE EXCEPTION 'STOP — falta rpc_programar_ot_taller (MIG256 no aplicada).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_ot_abierta_reutilizable') THEN
        RAISE EXCEPTION 'STOP — falta fn_ot_abierta_reutilizable (MIG256 no aplicada).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_user_rol') THEN
        RAISE EXCEPTION 'STOP — falta fn_user_rol.';
    END IF;
END $$;


-- ── 1. Rank de prioridad, con las 5 de verdad ───────────────────────────────
-- prioridad_enum está declarado de mayor a menor (emergencia primero), así que
-- el orden del enum NO sirve como severidad. Se declara explícito y ascendente.
CREATE OR REPLACE FUNCTION public.fn_prioridad_rank(p_prioridad prioridad_enum)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $function$
    SELECT COALESCE(
        array_position(ARRAY['baja','normal','alta','urgente','emergencia'],
                       p_prioridad::text),
        0);
$function$;

COMMENT ON FUNCTION public.fn_prioridad_rank(prioridad_enum) IS
    'Severidad ascendente de prioridad_enum (baja=1 .. emergencia=5). El orden del enum es descendente y no sirve. MIG257.';

GRANT EXECUTE ON FUNCTION public.fn_prioridad_rank(prioridad_enum) TO authenticated, anon;


-- ── 2. MIG256 sin degradar la emergencia ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_programar_ot_taller(
    p_activo_id  UUID,
    p_tipo       tipo_ot_enum,
    p_prioridad  prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_fecha      DATE DEFAULT NULL,
    p_responsable_id UUID DEFAULT NULL,
    p_plan_mantenimiento_id UUID DEFAULT NULL,
    p_reutilizar BOOLEAN DEFAULT TRUE      -- [MIG256] false = forzar OT nueva
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_contrato_id uuid;
    v_faena_id    uuid;
    v_a_contrato  uuid;
    v_a_faena     uuid;
    v_existente   uuid;
    v_ot          RECORD;
BEGIN
    SELECT contrato_id, faena_id INTO v_a_contrato, v_a_faena FROM activos WHERE id = p_activo_id;

    -- [MIG256] ¿Ya hay una OT abierta de este mismo trabajo? Se sigue usando.
    IF COALESCE(p_reutilizar, TRUE) THEN
        v_existente := fn_ot_abierta_reutilizable(p_activo_id, p_tipo, p_plan_mantenimiento_id);
    END IF;

    IF v_existente IS NOT NULL THEN
        -- La fecha programada se corre a la semana que se está planificando y
        -- la prioridad solo sube, nunca baja.
        -- [MIG257] fn_prioridad_rank incluye 'emergencia'; el array de MIG256 no
        -- la tenía y una OT en emergencia terminaba degradada.
        UPDATE ordenes_trabajo
           SET fecha_programada = COALESCE(p_fecha, fecha_programada),
               prioridad = CASE WHEN fn_prioridad_rank(p_prioridad) > fn_prioridad_rank(prioridad)
                                THEN p_prioridad ELSE prioridad END,
               responsable_id = COALESCE(p_responsable_id, responsable_id),
               updated_at = NOW()
         WHERE id = v_existente
        RETURNING * INTO v_ot;

        RETURN jsonb_build_object(
            'id', v_ot.id,
            'folio', v_ot.folio,
            'estado', v_ot.estado,
            'reutilizada', true,
            'mensaje', 'Se siguió usando la OT abierta ' || v_ot.folio ||
                       ' (no se creó una nueva); su checklist y su avance se mantienen.'
        );
    END IF;

    -- Contrato: el del activo si está activo; si no, el contrato interno.
    SELECT id INTO v_contrato_id FROM contratos WHERE id = v_a_contrato AND estado = 'activo';
    IF v_contrato_id IS NULL THEN v_contrato_id := fn_contrato_interno_id(); END IF;

    -- Faena: la del TALLER (el trabajo se hace ahí y sus vales salen de la
    -- bodega del taller), no la del arriendo del equipo.
    v_faena_id := COALESCE(fn_faena_taller_para_activo(p_activo_id), v_a_faena, fn_faena_interna_id());

    RETURN rpc_crear_ot(p_tipo, v_contrato_id, v_faena_id, p_activo_id, p_prioridad,
                        p_fecha, p_responsable_id, p_plan_mantenimiento_id, auth.uid())
           || jsonb_build_object('reutilizada', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_programar_ot_taller(UUID, tipo_ot_enum, prioridad_enum, DATE, UUID, UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_programar_ot_taller(UUID, tipo_ot_enum, prioridad_enum, DATE, UUID, UUID, BOOLEAN) TO authenticated;


-- ── 3. Log de la consolidación (auditable y reversible) ─────────────────────
CREATE TABLE IF NOT EXISTS public.ot_consolidaciones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ot_origen_id        UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    ot_destino_id       UUID NOT NULL REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    folio_origen        VARCHAR(40),
    folio_destino       VARCHAR(40),
    activo_id           UUID REFERENCES activos(id),
    tipo                tipo_ot_enum,
    plan_mantenimiento_id UUID,
    -- estado original, para poder revertir
    estado_origen       estado_ot_enum,
    prioridad_origen    prioridad_enum,
    fecha_programada_origen DATE,
    observaciones_origen    TEXT,
    -- qué se movió
    movidos             JSONB NOT NULL DEFAULT '{}'::jsonb,
    motivo              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by          UUID
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_ot_consolidaciones_origen
    ON public.ot_consolidaciones (ot_origen_id);
CREATE INDEX IF NOT EXISTS idx_ot_consolidaciones_destino
    ON public.ot_consolidaciones (ot_destino_id);

COMMENT ON TABLE public.ot_consolidaciones IS
    'Duplicados de OT fusionados: qué OT se canceló, en cuál sigue el trabajo y qué se movió. MIG257.';

ALTER TABLE public.ot_consolidaciones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pol_ot_consolidaciones_select ON public.ot_consolidaciones;
CREATE POLICY pol_ot_consolidaciones_select ON public.ot_consolidaciones
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS pol_ot_consolidaciones_write ON public.ot_consolidaciones;
CREATE POLICY pol_ot_consolidaciones_write ON public.ot_consolidaciones
    FOR ALL TO authenticated
    USING      (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'))
    WITH CHECK (fn_user_rol() IN ('administrador','subgerente_operaciones','jefe_mantenimiento'));

GRANT SELECT ON public.ot_consolidaciones TO authenticated;


-- ── 4. Cuáles son los duplicados (misma definición que MIG256) ──────────────
CREATE OR REPLACE VIEW public.v_ot_duplicadas_abiertas AS
WITH abiertas AS (
    SELECT o.id, o.folio, o.activo_id, o.tipo, o.plan_mantenimiento_id,
           o.estado, o.prioridad, o.fecha_programada, o.created_at
      FROM ordenes_trabajo o
     WHERE o.estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones',
                            'no_ejecutada','cancelada','cerrada')
),
grupos AS (
    SELECT activo_id, tipo, plan_mantenimiento_id, count(*) AS ot_abiertas
      FROM abiertas
     GROUP BY activo_id, tipo, plan_mantenimiento_id
    HAVING count(*) > 1
)
SELECT a.patente,
       a.id                AS activo_id,
       ab.tipo,
       ab.plan_mantenimiento_id,
       g.ot_abiertas,
       ab.id               AS ot_id,
       ab.folio,
       ab.estado,
       ab.prioridad,
       ab.fecha_programada,
       (SELECT count(*) FROM taller_ot_ejecuciones e WHERE e.ot_id = ab.id)     AS ejecuciones,
       (SELECT count(*) FROM taller_plan_semanal_ots p WHERE p.ot_id = ab.id)   AS dias_en_plan,
       ab.created_at
  FROM abiertas ab
  JOIN grupos  g ON g.activo_id = ab.activo_id
                AND g.tipo = ab.tipo
                AND g.plan_mantenimiento_id IS NOT DISTINCT FROM ab.plan_mantenimiento_id
  JOIN activos a ON a.id = ab.activo_id;

COMMENT ON VIEW public.v_ot_duplicadas_abiertas IS
    'OT abiertas que comparten equipo + tipo + pauta: el duplicado que MIG256 ya no genera. MIG257.';

GRANT SELECT ON public.v_ot_duplicadas_abiertas TO authenticated;


-- ── 5. La consolidación ─────────────────────────────────────────────────────
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
    v_grupos      INT := 0;
    v_canceladas  INT := 0;
    v_omitidas    INT := 0;
    v_dias        INT := 0;
    v_ejec        INT := 0;
    v_recursos    INT := 0;
    v_items       INT := 0;
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
                -- ── Días del plan semanal ───────────────────────────────────
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

                -- ── Ejecuciones (horas del mecánico) y sus eventos ──────────
                UPDATE taller_ot_ejecuciones SET ot_id = v_dest.id, updated_at = NOW()
                 WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_ejec := v_ejec + v_n;
                v_movidos := v_movidos || jsonb_build_object('ejecuciones', v_n);

                UPDATE taller_ot_ejecucion_eventos SET ot_id = v_dest.id WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos || jsonb_build_object('eventos_ejecucion', v_n);

                UPDATE taller_plan_jornada_eventos SET ot_id = v_dest.id WHERE ot_id = v_orig.id;

                -- ── Recursos pedidos, evidencias, NC, vales, checklist V03 ──
                UPDATE ot_recursos_solicitados SET ot_id = v_dest.id, updated_at = NOW()
                 WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_recursos := v_recursos + v_n;
                v_movidos := v_movidos || jsonb_build_object('recursos', v_n);

                UPDATE evidencias_ot        SET ot_id = v_dest.id WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos || jsonb_build_object('evidencias', v_n);

                UPDATE no_conformidades     SET ot_id = v_dest.id WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos || jsonb_build_object('no_conformidades', v_n);

                UPDATE bodega_tickets       SET ot_id = v_dest.id WHERE ot_id = v_orig.id;
                GET DIAGNOSTICS v_n = ROW_COUNT;
                v_movidos := v_movidos || jsonb_build_object('vales_bodega', v_n);

                UPDATE ot_materiales_planeados SET ot_id = v_dest.id WHERE ot_id = v_orig.id;
                UPDATE checklist_v2_instance   SET ot_id = v_dest.id WHERE ot_id = v_orig.id;

                -- ── Ítems del checklist YA RESPONDIDOS ──────────────────────
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
                          'dias_plan',  v_dias,
                          'ejecuciones', v_ejec,
                          'recursos',   v_recursos,
                          'items_checklist', v_items),
        'detalle',    v_detalle
    );
END;
$function$;

COMMENT ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) IS
    'Fusiona las OT abiertas duplicadas del mismo trabajo en una sola y cancela el resto. p_dry_run=true solo reporta. MIG257.';

REVOKE ALL ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_consolidar_ots_duplicadas(BOOLEAN) TO authenticated;


-- ── 6. EJECUCIÓN + VALIDACIÓN ───────────────────────────────────────────────
DO $$
DECLARE
    v_prev JSONB; v_res JSONB;
    v_abiertas_antes INT; v_abiertas_despues INT;
    v_dup_despues INT; v_huerfanos INT; v_ejec_perdidas INT;
BEGIN
    -- El fix de prioridad, primero: 'emergencia' tiene que ser el techo.
    IF fn_prioridad_rank('emergencia'::prioridad_enum) <= fn_prioridad_rank('urgente'::prioridad_enum) THEN
        RAISE EXCEPTION 'FALLO — fn_prioridad_rank no pone emergencia sobre urgente';
    END IF;
    IF fn_prioridad_rank('baja'::prioridad_enum) >= fn_prioridad_rank('normal'::prioridad_enum) THEN
        RAISE EXCEPTION 'FALLO — fn_prioridad_rank no ordena baja < normal';
    END IF;

    SELECT count(*) INTO v_abiertas_antes FROM ordenes_trabajo
     WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada');

    -- Ensayo primero, para que quede en el log qué se iba a tocar.
    v_prev := fn_consolidar_ots_duplicadas(TRUE);
    RAISE NOTICE 'MIG257 ensayo: % grupos, % a cancelar, % omitidas',
        v_prev->>'grupos', v_prev->>'canceladas', v_prev->>'omitidas';

    v_res := fn_consolidar_ots_duplicadas(FALSE);

    SELECT count(*) INTO v_abiertas_despues FROM ordenes_trabajo
     WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada');

    -- Ya no debe quedar ningún grupo duplicado, salvo los omitidos a propósito.
    SELECT count(*) INTO v_dup_despues
      FROM (SELECT activo_id, tipo, plan_mantenimiento_id FROM ordenes_trabajo
             WHERE estado NOT IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada','cancelada','cerrada')
             GROUP BY 1,2,3 HAVING count(*) > 1) g;
    IF v_dup_despues > 0 AND COALESCE((v_res->>'omitidas')::int, 0) = 0 THEN
        RAISE EXCEPTION 'FALLO — quedaron % grupos duplicados sin motivo de omisión', v_dup_despues;
    END IF;

    -- Nada del plan semanal puede quedar apuntando a una OT que cancelamos.
    SELECT count(*) INTO v_huerfanos
      FROM taller_plan_semanal_ots p
      JOIN ot_consolidaciones c ON c.ot_origen_id = p.ot_id;
    IF v_huerfanos > 0 THEN
        RAISE EXCEPTION 'FALLO — % días del plan siguen colgando de OT canceladas', v_huerfanos;
    END IF;

    -- Ni una hora de mecánico puede quedar en una OT cancelada.
    SELECT count(*) INTO v_ejec_perdidas
      FROM taller_ot_ejecuciones e
      JOIN ot_consolidaciones c ON c.ot_origen_id = e.ot_id;
    IF v_ejec_perdidas > 0 THEN
        RAISE EXCEPTION 'FALLO — % ejecuciones quedaron en OT canceladas', v_ejec_perdidas;
    END IF;

    -- Toda cancelada tiene que decir dónde sigue el trabajo.
    IF EXISTS (SELECT 1 FROM ordenes_trabajo o JOIN ot_consolidaciones c ON c.ot_origen_id = o.id
                WHERE o.estado <> 'cancelada' OR position(c.folio_destino IN COALESCE(o.observaciones,'')) = 0) THEN
        RAISE EXCEPTION 'FALLO — hay OT consolidadas sin cancelar o sin la referencia al folio destino';
    END IF;

    RAISE NOTICE 'MIG257 OK — OT abiertas % -> % | % grupos consolidados, % canceladas, % omitidas | movido: %',
        v_abiertas_antes, v_abiertas_despues,
        v_res->>'grupos', v_res->>'canceladas', v_res->>'omitidas', v_res->>'movido';
END $$;

NOTIFY pgrst, 'reload schema';
