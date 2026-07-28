-- ============================================================================
-- SICOM-ICEO | 253 — El contrato no traba la OT + informe de recobro sin valores
-- ----------------------------------------------------------------------------
-- Dos correcciones pedidas por Manuel (2026-07-28):
--
-- 1. «Los equipos deben tener el mismo contrato que el que se ha colocado en
--    sugerencias GPS. Y no debe ser traba para ello.»
--    El contrato que se fija en Sugerencias GPS → modal Cambiar Estado vive en
--    activos.contrato_id, que es justo lo que leen las funciones de planificar.
--    El problema es que cuando está NULL, la función ABORTA: hoy 22 equipos
--    activos no tienen contrato y no pueden generar OT desde una NC
--    («El equipo no tiene contrato/faena para crear OT»).
--    FIX: fn_contrato_para_ot() / fn_faena_para_ot() resuelven en cascada y
--    NUNCA devuelven NULL:
--        activos.contrato_id  (lo que fijó Sugerencias GPS — manda siempre)
--          → contrato del último arriendo del equipo (v_activo_ultimo_arriendo)
--          → contrato interno (mismo fallback que ya usa el informe de recepción)
--    Se aplican en fn_planificar_nc_equipo y fn_planificar_nc: la falta de
--    contrato deja de ser una traba.
--
-- 2. «El informe de recobro debe ser editable y sin valores, dado que esos los
--    coloca el planificador aparte.»
--    rpc_nc_informe_recobro pre-valorizaba con el costo de bodega y la tarifa
--    HH. Ya no: los ítems llegan con TODO lo necesario para cobrar (qué
--    material, cuánta cantidad, cuántas HH) pero con precio_unitario = 0, para
--    que el planificador ponga los valores en el informe. El informe sigue
--    editable hasta que se emite (ahí se congela, como siempre).
-- ADITIVA, IDEMPOTENTE. No borra datos.
-- ============================================================================

-- ── 0. PRECHECKS ─────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='rpc_nc_informe_recobro') THEN
        RAISE EXCEPTION 'STOP — falta MIG251.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='fn_contrato_interno_id') THEN
        RAISE EXCEPTION 'STOP — falta fn_contrato_interno_id.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='v_activo_ultimo_arriendo') THEN
        RAISE EXCEPTION 'STOP — falta v_activo_ultimo_arriendo (MIG147).';
    END IF;
END $$;


-- ── 1. Contrato y faena de la OT: cascada que nunca falla ───────────────────
CREATE OR REPLACE FUNCTION public.fn_contrato_para_ot(p_activo_id UUID)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
    -- 1) El que se fijó en Sugerencias GPS / Cambiar Estado: manda siempre
    SELECT contrato_id INTO v_id FROM activos WHERE id = p_activo_id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 2) El del último arriendo del equipo (aunque ya haya terminado)
    SELECT contrato_id INTO v_id
      FROM v_activo_ultimo_arriendo
     WHERE activo_id = p_activo_id AND contrato_id IS NOT NULL;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 3) Contrato interno: el trabajo es nuestro. Nunca se devuelve NULL.
    RETURN fn_contrato_interno_id();
END;
$function$;

COMMENT ON FUNCTION public.fn_contrato_para_ot(UUID) IS
    'Contrato con que se abre una OT del equipo: activos.contrato_id (Sugerencias GPS) > último arriendo > contrato interno. Nunca NULL. MIG253.';

CREATE OR REPLACE FUNCTION public.fn_faena_para_ot(p_activo_id UUID)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
    SELECT faena_id INTO v_id FROM activos WHERE id = p_activo_id;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    SELECT faena_id INTO v_id
      FROM v_activo_ultimo_arriendo
     WHERE activo_id = p_activo_id AND faena_id IS NOT NULL;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    RETURN fn_faena_interna_id();
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_contrato_para_ot(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_faena_para_ot(UUID)    TO authenticated;


-- ── 2. Planificar el equipo: sin traba de contrato ──────────────────────────
CREATE OR REPLACE FUNCTION public.fn_planificar_nc_equipo(p_activo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user    UUID := auth.uid();
    v_act     RECORD;
    v_contrato UUID;
    v_faena    UUID;
    v_ot      UUID;
    v_reusa   BOOLEAN := false;
    v_n       INT;
    v_sev_max VARCHAR;
    v_grupos  TEXT;
    v_horas   NUMERIC;
    v_lista   TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;

    SELECT count(*),
           (array_agg(severidad ORDER BY CASE severidad
                WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END))[1],
           string_agg(DISTINCT grupo_trabajo, ', '),
           sum(horas_estimadas),
           string_agg('• ' || descripcion, E'\n' ORDER BY created_at)
      INTO v_n, v_sev_max, v_grupos, v_horas, v_lista
      FROM no_conformidades
     WHERE activo_id = p_activo_id
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    IF v_n = 0 THEN
        RETURN jsonb_build_object('n_ncs', 0, 'mensaje', 'El equipo no tiene NC pendientes de planificar.');
    END IF;

    SELECT id, patente, codigo INTO v_act FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    SELECT nc.plan_ot_id INTO v_ot
      FROM no_conformidades nc
      JOIN ordenes_trabajo o ON o.id = nc.plan_ot_id
     WHERE nc.activo_id = p_activo_id
       AND o.estado IN ('creada','asignada')
     ORDER BY o.created_at DESC
     LIMIT 1;

    IF v_ot IS NOT NULL THEN
        v_reusa := true;
        UPDATE ordenes_trabajo
           SET observaciones = COALESCE(observaciones || E'\n', '') || v_lista,
               updated_at = NOW()
         WHERE id = v_ot;
    ELSE
        -- [MIG253] El contrato ya no traba: cascada Sugerencias GPS > último
        -- arriendo > contrato interno.
        v_contrato := fn_contrato_para_ot(p_activo_id);
        v_faena    := fn_faena_para_ot(p_activo_id);
        IF v_contrato IS NULL OR v_faena IS NULL THEN
            RAISE EXCEPTION 'No hay contrato/faena interna configurada para abrir la OT de %',
                COALESCE(v_act.patente, v_act.codigo);
        END IF;

        INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by)
        VALUES ('correctivo'::tipo_ot_enum, v_contrato, v_faena, p_activo_id,
            (CASE v_sev_max WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END)::prioridad_enum,
            'creada'::estado_ot_enum,
            'Correctivo por ' || v_n || ' NC del equipo ' || COALESCE(v_act.patente, v_act.codigo) || E':\n' || v_lista ||
            COALESCE(E'\nGrupo: ' || v_grupos, '') ||
            COALESCE(' · ' || v_horas || ' h', ''),
            true, v_user)
        RETURNING id INTO v_ot;
    END IF;

    UPDATE no_conformidades
       SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
     WHERE activo_id = p_activo_id
       AND origen IN ('recepcion_checklist','recepcion_adhoc','inspeccion_ot','ejecucion_ot','manual')
       AND plan_ot_id IS NULL
       AND estado_planificacion IN ('registrada','con_recursos')
       AND COALESCE(resuelto, false) = false;

    RETURN jsonb_build_object('ot_id', v_ot, 'n_ncs', v_n, 'ot_reutilizada', v_reusa);
END $function$;


-- ── 3. Planificar UNA NC: mismo criterio ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_planificar_nc(p_nc_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user UUID := auth.uid();
    v_nc   RECORD;
    v_act  RECORD;
    v_contrato UUID;
    v_faena    UUID;
    v_ot   UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado.'; END IF;
    SELECT * INTO v_nc FROM no_conformidades WHERE id = p_nc_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'NC % no existe', p_nc_id; END IF;
    IF v_nc.plan_ot_id IS NOT NULL THEN
        RETURN jsonb_build_object('ot_id', v_nc.plan_ot_id, 'mensaje', 'Ya tenía OT'); END IF;

    SELECT id, patente, codigo INTO v_act FROM activos WHERE id = v_nc.activo_id;

    -- [MIG253] Cascada de contrato: la falta de contrato ya no aborta.
    v_contrato := fn_contrato_para_ot(v_nc.activo_id);
    v_faena    := fn_faena_para_ot(v_nc.activo_id);
    IF v_contrato IS NULL OR v_faena IS NULL THEN
        RAISE EXCEPTION 'No hay contrato/faena interna configurada para abrir la OT de %',
            COALESCE(v_act.patente, v_act.codigo);
    END IF;

    INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
        observaciones, generada_automaticamente, created_by)
    VALUES ('correctivo', v_contrato, v_faena, v_nc.activo_id,
        CASE v_nc.severidad WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END,
        'creada',
        'NC de recepción: ' || v_nc.descripcion ||
        COALESCE(E'\nGrupo: ' || v_nc.grupo_trabajo, '') ||
        COALESCE(' · ' || v_nc.horas_estimadas || ' h', ''),
        true, v_user)
    RETURNING id INTO v_ot;

    UPDATE no_conformidades SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
    WHERE id = p_nc_id;

    RETURN jsonb_build_object('ot_id', v_ot, 'nc_id', p_nc_id);
END $function$;

GRANT EXECUTE ON FUNCTION public.fn_planificar_nc(UUID) TO authenticated;


-- ── 4. Informe de recobro SIN valores: los pone el planificador ─────────────
CREATE OR REPLACE FUNCTION public.rpc_nc_informe_recobro(
    p_activo_id     UUID,
    p_nc_ids        UUID[] DEFAULT NULL,
    p_tarifa_hh_id  UUID   DEFAULT NULL   -- solo nombra la línea de MO; el precio lo pone el planificador
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user      UUID := auth.uid();
    v_rol       TEXT := public.fn_user_rol();
    v_activo    RECORD;
    v_informe   RECORD;
    v_folio     VARCHAR;
    v_periodo   VARCHAR(6);
    v_sec       INTEGER;
    v_tarifa    RECORD;
    v_nuevo     BOOLEAN := false;
    v_hallazgo  UUID;
    v_creados   INT := 0;
    v_ya        INT := 0;
    v_costos    INT := 0;
    nc          RECORD;
    mat         RECORD;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol IS NULL OR v_rol NOT IN (
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones',
        'jefe_mantenimiento','planificador','supervisor') THEN
        RAISE EXCEPTION 'No autorizado para armar el informe de recobro (rol: %)', COALESCE(v_rol,'?')
            USING ERRCODE='42501';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo % no existe', p_activo_id; END IF;

    -- [MIG253] La especialidad solo se anota si el jefe la eligió. NO se toma
    -- una por defecto: sería insinuar un valor, y los valores los pone el
    -- planificador.
    IF p_tarifa_hh_id IS NOT NULL THEN
        SELECT * INTO v_tarifa FROM tarifas_hh WHERE id = p_tarifa_hh_id AND activo;
    END IF;

    SELECT * INTO v_informe FROM informes_recepcion
     WHERE activo_id = p_activo_id AND estado IN ('en_inspeccion','borrador')
     ORDER BY created_at DESC LIMIT 1;

    IF NOT FOUND THEN
        PERFORM pg_advisory_xact_lock(hashtext('ir_folio_lock'));
        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
          INTO v_sec FROM informes_recepcion WHERE folio LIKE 'IR-' || v_periodo || '-%';
        v_folio := 'IR-' || v_periodo || '-' || LPAD(v_sec::TEXT, 5, '0');

        INSERT INTO informes_recepcion (
            activo_id, contrato_id, cliente_nombre, fecha_recepcion,
            inspector_id, estado, folio, observaciones_finales
        ) VALUES (
            -- [MIG253] mismo criterio de contrato que la OT (Sugerencias GPS primero)
            p_activo_id, fn_contrato_para_ot(p_activo_id), v_activo.cliente_actual, CURRENT_DATE,
            v_user, 'borrador', v_folio,
            'Recobro armado desde las No Conformidades del taller. Valores pendientes: los carga el planificador.'
        )
        RETURNING * INTO v_informe;
        v_nuevo := true;
    END IF;

    FOR nc IN
        SELECT n.id, n.descripcion, n.severidad, n.foto_url, n.checklist_item_ref,
               n.horas_estimadas, n.grupo_trabajo, n.recobro_hallazgo_id, n.recobro_nota,
               v.recobro, v.observacion_item, n.plan_ot_id
          FROM no_conformidades n
          JOIN v_nc_recepcion v ON v.id = n.id
         WHERE n.activo_id = p_activo_id
           AND (p_nc_ids IS NULL OR n.id = ANY(p_nc_ids))
           AND v.recobro IN ('cliente','compartido')
           AND n.estado_planificacion <> 'descartada'
         ORDER BY n.created_at
    LOOP
        IF nc.recobro_hallazgo_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM informe_recepcion_hallazgos
             WHERE id = nc.recobro_hallazgo_id AND informe_id = v_informe.id) THEN
            v_ya := v_ya + 1;
            CONTINUE;
        END IF;

        INSERT INTO informe_recepcion_hallazgos (
            informe_id, seccion, descripcion, gravedad, atribuible_cliente,
            fotos, observacion, checklist_v2_item_id
        ) VALUES (
            v_informe.id,
            'No Conformidad del taller',
            nc.descripcion,
            (CASE nc.severidad WHEN 'critica' THEN 'critica'
                               WHEN 'alta'    THEN 'mayor'
                               ELSE 'menor' END)::gravedad_hallazgo_enum,
            (nc.recobro = 'cliente'),
            CASE WHEN nc.foto_url IS NOT NULL THEN jsonb_build_array(nc.foto_url) ELSE '[]'::JSONB END,
            NULLIF(concat_ws(' · ', nc.observacion_item, nc.recobro_nota), ''),
            nc.checklist_item_ref
        )
        RETURNING id INTO v_hallazgo;
        v_creados := v_creados + 1;

        UPDATE no_conformidades
           SET recobro_informe_id = v_informe.id, recobro_hallazgo_id = v_hallazgo, updated_at = NOW()
         WHERE id = nc.id;

        -- [MIG253] SIN VALORES: se lleva QUÉ y CUÁNTO, el precio lo pone el
        -- planificador en el informe (precio_unitario = 0).
        FOR mat IN
            SELECT m.cantidad, m.descripcion, m.producto_id,
                   p.nombre AS producto_nombre, p.unidad_medida
              FROM nc_materiales m
              LEFT JOIN productos p ON p.id = m.producto_id
             WHERE m.no_conformidad_id = nc.id
        LOOP
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, producto_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'repuesto'::tipo_costo_recepcion_enum, mat.producto_id,
                COALESCE(mat.producto_nombre, mat.descripcion, 'Material'),
                COALESCE(mat.cantidad, 1), mat.unidad_medida,
                0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END LOOP;

        IF COALESCE(nc.horas_estimadas, 0) > 0 THEN
            INSERT INTO informe_recepcion_costos (
                informe_id, tipo, tarifa_hh_id, descripcion, cantidad, unidad,
                precio_unitario, cobrable_cliente, hallazgo_id
            ) VALUES (
                v_informe.id, 'mano_obra'::tipo_costo_recepcion_enum, v_tarifa.id,
                'Mano de obra' || COALESCE(' — ' || v_tarifa.nombre, '') ||
                    COALESCE(' (' || nc.grupo_trabajo || ')', ''),
                nc.horas_estimadas, 'HH', 0, true, v_hallazgo
            );
            v_costos := v_costos + 1;
        END IF;
    END LOOP;

    SELECT * INTO v_informe FROM informes_recepcion WHERE id = v_informe.id;

    RETURN jsonb_build_object(
        'ok', true,
        'informe_id', v_informe.id,
        'folio', v_informe.folio,
        'informe_nuevo', v_nuevo,
        'hallazgos_creados', v_creados,
        'ya_estaban', v_ya,
        'costos_creados', v_costos,
        'total_cobrable', v_informe.total_cobrable_cliente,
        'total', v_informe.total
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_nc_informe_recobro(UUID, UUID[], UUID) TO authenticated;


-- ── VALIDACIÓN ──────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_user UUID; v_activo UUID; v_pat TEXT; v_res JSONB;
    v_sin INT; v_ceros INT; v_total NUMERIC;
BEGIN
    -- 1. La cascada de contrato no devuelve NULL para NINGÚN activo vigente
    SELECT count(*) INTO v_sin
      FROM activos a
     WHERE a.fecha_baja IS NULL
       AND (fn_contrato_para_ot(a.id) IS NULL OR fn_faena_para_ot(a.id) IS NULL);
    IF v_sin > 0 THEN
        RAISE EXCEPTION 'FALLO — % activos siguen sin contrato/faena resoluble', v_sin;
    END IF;
    RAISE NOTICE 'MIG253 OK: todos los activos vigentes resuelven contrato y faena';

    SELECT count(*) INTO v_sin FROM activos WHERE fecha_baja IS NULL AND contrato_id IS NULL;
    RAISE NOTICE 'MIG253: % activos sin contrato propio -> ahora caen al último arriendo o al interno', v_sin;

    -- 2. Planificar un equipo que ANTES no podía (sin contrato_id)
    SELECT nc.activo_id, a.patente INTO v_activo, v_pat
      FROM no_conformidades nc
      JOIN activos a ON a.id = nc.activo_id
     WHERE a.contrato_id IS NULL AND nc.plan_ot_id IS NULL
       AND nc.estado_planificacion IN ('registrada','con_recursos')
     LIMIT 1;
    SELECT id INTO v_user FROM usuarios_perfil WHERE rol='jefe_mantenimiento' LIMIT 1;

    IF v_activo IS NOT NULL AND v_user IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_user, 'role','authenticated')::text, true);
        v_res := public.fn_planificar_nc_equipo(v_activo);
        IF (v_res->>'ot_id') IS NULL THEN
            RAISE EXCEPTION 'FALLO — % sigue sin poder generar OT', v_pat;
        END IF;
        RAISE NOTICE 'MIG253 OK: % (sin contrato propio) generó OT con % NC', v_pat, v_res->>'n_ncs';
    END IF;

    -- 3. El informe de recobro llega SIN valores
    SELECT activo_id INTO v_activo FROM v_nc_recepcion
     WHERE recobro IN ('cliente','compartido') GROUP BY activo_id
     ORDER BY count(*) DESC LIMIT 1;
    IF v_activo IS NOT NULL AND v_user IS NOT NULL THEN
        PERFORM set_config('request.jwt.claims',
            json_build_object('sub', v_user, 'role','authenticated')::text, true);
        v_res := public.rpc_nc_informe_recobro(v_activo, NULL, NULL);
        SELECT count(*) FILTER (WHERE precio_unitario <> 0), COALESCE(sum(total),0)
          INTO v_ceros, v_total
          FROM informe_recepcion_costos WHERE informe_id = (v_res->>'informe_id')::uuid;
        IF v_ceros > 0 OR v_total <> 0 THEN
            RAISE EXCEPTION 'FALLO — el informe llegó valorizado (% ítems con precio, total %)', v_ceros, v_total;
        END IF;
        RAISE NOTICE 'MIG253 OK: informe % con % hallazgos y % ítems SIN valores (total %)',
            v_res->>'folio', v_res->>'hallazgos_creados', v_res->>'costos_creados', v_total;
    END IF;

    RAISE EXCEPTION 'rollback-smoke';
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'rollback-smoke' THEN RAISE NOTICE 'Smoke revertido (ok)';
    ELSE RAISE; END IF;
END $$;

NOTIFY pgrst, 'reload schema';
