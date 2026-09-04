-- ============================================================================
-- MIG509 · La OS se EJECUTA (foto+comentario+repuestos) y la OT aparte
-- ============================================================================
--
-- LO QUE PIDIÓ MANUEL (04-09-2026)
--  1. «Al hacer clic para ejecutar, debe aparecer como checklist las
--     actividades que me encomendaron, donde pueda colocar foto y comentario;
--     además volver a pedir repuestos (pasa por el ciclo anterior) y hacer
--     comentarios que el jefe vuelve a evaluar.»
--  2. «Cuando vuelvo a planificar la misma patente el mismo día, no
--     necesariamente es para la misma OT: un preventivo y una correctiva son
--     dos actividades distintas, dos OT. El sistema debería preguntar.»
--
-- QUÉ SE HACE
--  a. rpc_taller_os_detalle v2: cada actividad trae el ítem del checklist del
--     que nació (item_id + instance_id + sus fotos) — con eso la página puede
--     escribir foto y comentario POR EL MISMO CANAL de siempre
--     (checklist_v2_instance_item), y el pedido de repuesto se amarra al
--     hallazgo (ciclo MIG197/497: lo evalúa el jefe).
--  b. rpc_ot_recurso_solicitar: aceptar pedidos sobre una OT que aún no está
--     liberada PERO tiene una OS abierta — la OS ES la liberación de ese
--     trabajo. Sin esto, pedir repuesto desde la OS de una correctiva recién
--     planificada rebotaba con «no está liberada a ejecución».
--  c. rpc_nc_planificar_os: p_ot_separada. TRUE = este paquete NO va en la OT
--     correctiva abierta del equipo: se abre OTRA OT (solo con las NC
--     seleccionadas, que deben venir sin OT previa). El caso: preventivo +
--     correctivo el mismo día sobre la misma patente.
-- ============================================================================

BEGIN;

-- ── a · Detalle de la OS, ahora ejecutable ──────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_taller_os_detalle(p_os_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_os JSONB; v_acts JSONB;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;

    SELECT jsonb_build_object(
             'os_id', o.id, 'folio', o.folio, 'titulo', o.titulo,
             'descripcion', o.descripcion, 'estado', o.estado,
             'fecha_programada', o.fecha_programada,
             'horas_estimadas', o.horas_estimadas,
             'es_externo', COALESCE(o.es_externo, FALSE),
             'ot_id', ot.id, 'ot_folio', ot.folio,
             'patente', a.patente, 'equipo', a.nombre,
             'responsable', tt.nombre,
             'mi_asignada', EXISTS (
                 SELECT 1 FROM taller_os_asignacion x
                  WHERE x.os_id = o.id AND x.hasta IS NULL
                    AND x.tecnico_id = fn_taller_mi_tecnico_id()),
             'asignados', (
                 SELECT COALESCE(jsonb_agg(t2.nombre ORDER BY t2.nombre), '[]'::jsonb)
                   FROM taller_os_asignacion x JOIN taller_tecnicos t2 ON t2.id = x.tecnico_id
                  WHERE x.os_id = o.id AND x.hasta IS NULL))
      INTO v_os
      FROM taller_os o
      JOIN ordenes_trabajo ot ON ot.id = o.ot_id
      JOIN activos a ON a.id = ot.activo_id
      LEFT JOIN taller_tecnicos tt ON tt.id = o.responsable_id
     WHERE o.id = p_os_id;

    IF v_os IS NULL THEN RAISE EXCEPTION 'Esa OS no existe.'; END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'nc_id', nc.id,
             'descripcion', nc.descripcion,
             'severidad', nc.severidad,
             'foto_url', COALESCE(nc.foto_url, ii.foto_url),
             'observacion', ii.observacion,
             'resuelto', COALESCE(nc.resuelto, FALSE),
             -- [MIG509] El canal de ejecución: el ítem del checklist del que
             -- nació la NC. Foto y comentario se escriben AHÍ, como siempre.
             'item_id', ii.id,
             'instance_id', ii.instance_id,
             'fotos', COALESCE(to_jsonb(ii.foto_urls), '[]'::jsonb))
             ORDER BY COALESCE(nc.resuelto, FALSE), nc.created_at), '[]'::jsonb)
      INTO v_acts
      FROM taller_os_nc x
      JOIN no_conformidades nc ON nc.id = x.no_conformidad_id
      LEFT JOIN checklist_v2_instance_item ii ON ii.id = nc.checklist_item_ref
     WHERE x.os_id = p_os_id;

    RETURN v_os || jsonb_build_object('actividades', v_acts);
END;
$$;

REVOKE ALL ON FUNCTION rpc_taller_os_detalle(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_taller_os_detalle(UUID) TO authenticated;

-- ── b · Pedir repuesto sobre una OT con OS abierta ──────────────────────────
CREATE OR REPLACE FUNCTION rpc_ot_recurso_solicitar(
    p_ot_id UUID, p_cantidad NUMERIC,
    p_producto_id UUID DEFAULT NULL, p_descripcion VARCHAR DEFAULT NULL,
    p_unidad VARCHAR DEFAULT NULL, p_comentario TEXT DEFAULT NULL,
    p_solicitado_nombre VARCHAR DEFAULT NULL, p_client_uuid UUID DEFAULT NULL,
    p_fotos TEXT[] DEFAULT NULL, p_instance_item_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user UUID := auth.uid(); v_rol TEXT := fn_user_rol();
    v_ot RECORD; v_id UUID; v_unidad VARCHAR; v_nombre_prod TEXT; v_u RECORD;
    v_nc UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('operador_taller','tecnico_mantenimiento','jefe_mantenimiento',
                     'supervisor','planificador','administrador','subgerente_operaciones') THEN
        RAISE EXCEPTION 'Sin permiso para solicitar recursos (rol: %)', v_rol; END IF;
    IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor que cero'; END IF;
    IF p_producto_id IS NULL AND NULLIF(TRIM(COALESCE(p_descripcion,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Indica el producto del catálogo o una descripción'; END IF;

    IF p_client_uuid IS NOT NULL THEN
        SELECT id INTO v_id FROM ot_recursos_solicitados WHERE client_uuid = p_client_uuid;
        IF v_id IS NOT NULL THEN
            RETURN jsonb_build_object('success', true, 'recurso_id', v_id, 'duplicado', true);
        END IF;
    END IF;

    SELECT id, folio, estado, preparacion_ok_at, activo_id INTO v_ot
      FROM ordenes_trabajo WHERE id = p_ot_id;
    IF v_ot.id IS NULL THEN RAISE EXCEPTION 'OT no existe'; END IF;
    -- [MIG509] Una OT con OS abierta ES trabajo liberado: el pedido de
    -- repuesto de esa OS no puede rebotar por un checklist sin liberar.
    IF (v_ot.preparacion_ok_at IS NULL OR v_ot.estado NOT IN ('asignada','en_ejecucion','pausada'))
       AND NOT EXISTS (SELECT 1 FROM taller_os s
                        WHERE s.ot_id = p_ot_id AND s.estado NOT IN ('finalizada','anulada')) THEN
        RAISE EXCEPTION 'La OT % no está liberada a ejecución', v_ot.folio; END IF;

    IF p_producto_id IS NOT NULL THEN
        SELECT unidad_medida, nombre INTO v_unidad, v_nombre_prod FROM productos WHERE id = p_producto_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Producto no existe en el catálogo'; END IF;
    END IF;

    -- [MIG497] El pedido nace amarrado a la NC de su hallazgo.
    IF p_instance_item_id IS NOT NULL THEN
        SELECT id INTO v_nc FROM no_conformidades
         WHERE checklist_item_ref = p_instance_item_id
         ORDER BY created_at DESC LIMIT 1;
    END IF;

    INSERT INTO ot_recursos_solicitados (
        client_uuid, ot_id, producto_id, descripcion, unidad, cantidad,
        comentario, solicitado_por, solicitado_nombre, fotos, instance_item_id,
        no_conformidad_id)
    VALUES (
        p_client_uuid, p_ot_id, p_producto_id, NULLIF(TRIM(COALESCE(p_descripcion,'')),''),
        COALESCE(NULLIF(TRIM(COALESCE(p_unidad,'')),''), v_unidad), p_cantidad,
        p_comentario, v_user, NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''),
        CASE WHEN p_fotos IS NOT NULL AND array_length(p_fotos,1) > 0 THEN p_fotos ELSE NULL END,
        p_instance_item_id, v_nc)
    RETURNING id INTO v_id;

    BEGIN
        FOR v_u IN
            SELECT id FROM usuarios_perfil
             WHERE activo = true AND rol IN ('administrador','jefe_mantenimiento','supervisor')
        LOOP
            INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id,
                                 destinatario_id, leida, created_at)
            VALUES ('recurso_solicitado',
                    'Recursos solicitados: ' || v_ot.folio,
                    COALESCE(NULLIF(TRIM(COALESCE(p_solicitado_nombre,'')),''), 'Operador de taller')
                      || ' pide ' || p_cantidad || ' ' || COALESCE(v_unidad, p_unidad, 'un')
                      || ' de ' || COALESCE(v_nombre_prod, p_descripcion, 'material')
                      || CASE WHEN p_instance_item_id IS NOT NULL
                              THEN ' por hallazgo NO OK' ELSE ' para reparar' END,
                    'info', 'recurso_ot', p_ot_id, v_u.id, false, NOW());
        END LOOP;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN jsonb_build_object('success', true, 'recurso_id', v_id);
END $$;
GRANT EXECUTE ON FUNCTION rpc_ot_recurso_solicitar(UUID,NUMERIC,UUID,VARCHAR,VARCHAR,TEXT,VARCHAR,UUID,TEXT[],UUID) TO authenticated;

-- ── c · La OT aparte (firma nueva → DROP, regla MIG471) ─────────────────────
DROP FUNCTION IF EXISTS rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT);

CREATE FUNCTION rpc_nc_planificar_os(
    p_nc_ids           UUID[],
    p_tecnico_ids      UUID[],
    p_horas            NUMERIC,
    p_fecha_programada DATE,
    p_titulo           TEXT DEFAULT NULL,
    p_descripcion      TEXT DEFAULT NULL,
    p_justificacion    TEXT DEFAULT NULL,
    p_externo          BOOLEAN DEFAULT FALSE,
    p_proveedor        TEXT DEFAULT NULL,
    p_motivo_externo   TEXT DEFAULT NULL,
    p_ot_separada      BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user     UUID := auth.uid();
    v_activo   UUID; v_n_act INT; v_patente TEXT;
    v_sin_plan INT;  v_n_ot INT; v_ot UUID;
    v_titulo   TEXT;
    v_res      JSONB; v_os UUID;
    v_t        UUID; v_i INT := 0; v_r JSONB;
    v_avisos   TEXT[] := ARRAY[]::TEXT[];
    v_contrato UUID; v_faena UUID; v_sev TEXT; v_lista TEXT;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF NOT fn_taller_es_jefatura() THEN
        RAISE EXCEPTION 'Planificar una Orden de Servicio es de la jefatura de taller o planificación.';
    END IF;
    IF p_nc_ids IS NULL OR array_length(p_nc_ids, 1) IS NULL THEN
        RAISE EXCEPTION 'Elige al menos una no conformidad.'; END IF;
    IF NOT p_externo AND (p_tecnico_ids IS NULL OR array_length(p_tecnico_ids, 1) IS NULL) THEN
        RAISE EXCEPTION 'Elige quién la va a ejecutar (uno, o de a pares), o márcala como de un externo.'; END IF;
    IF p_externo AND NULLIF(TRIM(COALESCE(p_proveedor,'')),'') IS NULL THEN
        RAISE EXCEPTION 'Di qué proveedor hace el trabajo externo.'; END IF;
    IF p_horas IS NULL OR p_horas <= 0 THEN
        RAISE EXCEPTION 'Ponle el tiempo (horas): es el compromiso contra el que se mide.'; END IF;
    IF p_fecha_programada IS NULL THEN
        RAISE EXCEPTION 'Ponle el día: planificar la OS es programar cuándo se hace.'; END IF;
    IF p_fecha_programada < CURRENT_DATE THEN
        RAISE EXCEPTION 'El día programado (%) ya pasó.', p_fecha_programada; END IF;

    SELECT count(DISTINCT nc.activo_id) INTO v_n_act
      FROM no_conformidades nc WHERE nc.id = ANY(p_nc_ids);
    IF v_n_act <> 1 THEN
        RAISE EXCEPTION 'Las NC elegidas son de % equipos distintos: una OS resuelve trabajo de UN equipo.', v_n_act;
    END IF;
    SELECT nc.activo_id INTO v_activo FROM no_conformidades nc WHERE nc.id = ANY(p_nc_ids) LIMIT 1;
    SELECT COALESCE(a.patente, a.codigo) INTO v_patente FROM activos a WHERE a.id = v_activo;

    IF EXISTS (SELECT 1 FROM no_conformidades
                WHERE id = ANY(p_nc_ids) AND estado_planificacion IN ('resuelta','descartada')) THEN
        RAISE EXCEPTION 'Hay NC ya resueltas o descartadas entre las elegidas.'; END IF;

    IF EXISTS (SELECT 1 FROM taller_os_nc x
                 JOIN taller_os o ON o.id = x.os_id AND o.estado <> 'anulada'
                WHERE x.no_conformidad_id = ANY(p_nc_ids)) THEN
        RAISE EXCEPTION 'Alguna de las NC elegidas ya está en otra Orden de Servicio.'; END IF;

    IF p_ot_separada THEN
        -- [MIG509] Trabajo APARTE: preventivo + correctivo el mismo día son dos
        -- OT. Sólo con NC que aún no viven en ninguna OT (una NC no se muda).
        IF EXISTS (SELECT 1 FROM no_conformidades
                    WHERE id = ANY(p_nc_ids) AND plan_ot_id IS NOT NULL) THEN
            RAISE EXCEPTION 'Para abrir una OT aparte, las NC elegidas no pueden estar ya en otra OT. '
                            'Deja fuera las que ya tienen OT, o planifícalas en la suya.';
        END IF;

        v_contrato := fn_contrato_para_ot(v_activo);
        v_faena    := fn_faena_para_ot(v_activo);
        IF v_contrato IS NULL OR v_faena IS NULL THEN
            RAISE EXCEPTION 'No hay contrato/faena interna configurada para abrir la OT de %', v_patente;
        END IF;

        SELECT (array_agg(nc.severidad ORDER BY CASE nc.severidad
                    WHEN 'critica' THEN 1 WHEN 'alta' THEN 2 WHEN 'media' THEN 3 ELSE 4 END))[1],
               string_agg('• ' || nc.descripcion, E'\n' ORDER BY nc.created_at)
          INTO v_sev, v_lista
          FROM no_conformidades nc WHERE nc.id = ANY(p_nc_ids);

        INSERT INTO ordenes_trabajo (tipo, contrato_id, faena_id, activo_id, prioridad, estado,
            observaciones, generada_automaticamente, created_by)
        VALUES ('correctivo'::tipo_ot_enum, v_contrato, v_faena, v_activo,
            (CASE v_sev WHEN 'critica' THEN 'urgente' WHEN 'alta' THEN 'alta' ELSE 'normal' END)::prioridad_enum,
            'creada'::estado_ot_enum,
            'Trabajo aparte (OT separada a pedido del planificador) · ' || array_length(p_nc_ids,1)
              || ' NC de ' || COALESCE(v_patente,'equipo') || E':\n' || v_lista,
            true, v_user)
        RETURNING id INTO v_ot;

        UPDATE no_conformidades
           SET plan_ot_id = v_ot, estado_planificacion = 'planificada', updated_at = NOW()
         WHERE id = ANY(p_nc_ids);
    ELSE
        SELECT count(*) INTO v_sin_plan
          FROM no_conformidades WHERE id = ANY(p_nc_ids) AND plan_ot_id IS NULL;
        IF v_sin_plan > 0 THEN
            PERFORM fn_planificar_nc_equipo(v_activo);
        END IF;

        SELECT count(DISTINCT plan_ot_id) INTO v_n_ot
          FROM no_conformidades WHERE id = ANY(p_nc_ids);
        IF v_n_ot <> 1 OR EXISTS (SELECT 1 FROM no_conformidades
                                   WHERE id = ANY(p_nc_ids) AND plan_ot_id IS NULL) THEN
            RAISE EXCEPTION 'Las NC elegidas quedaron en OT correctivas distintas: planifícalas por separado.';
        END IF;
        SELECT plan_ot_id INTO v_ot FROM no_conformidades WHERE id = ANY(p_nc_ids) LIMIT 1;
    END IF;

    v_titulo := COALESCE(NULLIF(TRIM(COALESCE(p_titulo,'')),''),
                         CASE WHEN p_externo THEN 'Trabajo externo · ' ELSE 'Corrección NC · ' END
                         || COALESCE(v_patente, 'equipo'));

    v_res := rpc_taller_os_crear(v_ot, v_titulo, p_nc_ids,
                                 CASE WHEN p_externo THEN NULL ELSE p_tecnico_ids[1] END,
                                 p_horas, p_descripcion, NULL, p_justificacion,
                                 p_fecha_programada);
    IF NOT COALESCE((v_res->>'success')::BOOLEAN, FALSE) THEN
        RETURN v_res;
    END IF;
    v_os := (v_res->>'os_id')::UUID;

    IF p_externo THEN
        PERFORM rpc_taller_os_declarar_externo(v_os, TRUE, p_proveedor, p_motivo_externo);
    ELSE
        FOREACH v_t IN ARRAY p_tecnico_ids LOOP
            v_i := v_i + 1;
            IF v_i = 1 THEN CONTINUE; END IF;
            v_r := rpc_taller_os_asignar(v_os, v_t, 'Asignado al planificar la OS', FALSE);
            IF NULLIF(v_r->>'aviso','') IS NOT NULL THEN
                v_avisos := array_append(v_avisos, v_r->>'aviso');
            END IF;
        END LOOP;
    END IF;

    RETURN v_res || jsonb_build_object(
        'ot_id', v_ot,
        'ot_separada', p_ot_separada,
        'externo', p_externo,
        'tecnicos', CASE WHEN p_externo THEN 0 ELSE array_length(p_tecnico_ids, 1) END,
        'avisos', to_jsonb(v_avisos));
END;
$$;

REVOKE ALL ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_nc_planificar_os(UUID[], UUID[], NUMERIC, DATE, TEXT, TEXT, TEXT, BOOLEAN, TEXT, TEXT, BOOLEAN) TO authenticated;

-- ── Verificación ────────────────────────────────────────────────────────────
DO $mig$
DECLARE v_n INT;
BEGIN
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname='public' AND p.proname IN
       ('rpc_taller_os_detalle','rpc_ot_recurso_solicitar','rpc_nc_planificar_os');
    IF v_n <> 3 THEN RAISE EXCEPTION 'FALLO: quedaron % funciones (esperadas 3, una firma cada una)', v_n; END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='rpc_taller_os_detalle'
                      AND p.prosrc LIKE '%item_id%') THEN
        RAISE EXCEPTION 'FALLO: el detalle no expone el ítem del checklist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                    WHERE n.nspname='public' AND p.proname='rpc_ot_recurso_solicitar'
                      AND p.prosrc LIKE '%taller_os s%') THEN
        RAISE EXCEPTION 'FALLO: el pedido de repuesto no considera la OS abierta';
    END IF;
    RAISE NOTICE 'MIG509 OK · OS ejecutable + repuestos vía OS + OT aparte';
END
$mig$;

COMMIT;
