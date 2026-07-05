-- ============================================================================
-- SICOM-ICEO | 189 — Fase 0.1: AUTORIZACIÓN REAL de funciones P0 anónimas
-- ----------------------------------------------------------------------------
-- Rediseño (rev. gate 2026-07-04). El REVOKE anon + GRANT authenticated de la
-- versión previa NO alcanza para funciones críticas: 'authenticated' es
-- cualquier sesión válida, no autorización de negocio. Aquí cada P0 queda
-- realmente autorizada:
--
--   GRUPO A (llamadas por el frontend): guard interno fail-closed
--     public.fn_tiene_permiso_modulo(modulo, accion, roles_default) — deniega
--     anon, portal cliente (sin fila en usuarios_perfil → fn_user_rol()=NULL),
--     usuarios inactivos, y autenticados sin el permiso. REVOKE anon+PUBLIC,
--     GRANT authenticated (el grant solo abre la puerta; el guard decide).
--
--   GRUPO B (solo cron/trigger, corren como 'postgres'): REVOKE EXECUTE de
--     anon, authenticated y PUBLIC. Dejan de ser invocables por PostgREST; los
--     jobs/triggers siguen operando (definer/postgres). NO se les pone guard de
--     auth.uid() porque eso rompería el cron.
--
--   P1/P2 (no P0): REVOKE anon + GRANT authenticated (cierre de superficie
--     anónima; su endurecimiento por-función queda en Fase 1). Allowlist QR
--     (rpc_guardar_checklist_publico, rpc_checklist_cliente_guardar) intacta.
--
-- Roles default de cada guard = los MISMOS que el frontend usa hoy para mostrar
-- el botón (fuente: use-permissions.ts); MIG126 puede sobreescribirlos por rol.
-- search_path = public, pg_temp (pg_temp AL FINAL; verificado que anon/
-- authenticated/PUBLIC no tienen CREATE en public ⇒ sin shadowing).
--
-- IDEMPOTENTE. Rollback: database/rollback/rollback_189_fase01.sql.
-- ============================================================================
SET client_min_messages = warning;


-- ═══ GRUPO A · P0 de usuario: guard fail-closed + grant authenticated ═══

-- rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid)  →  ordenes_trabajo/create  [default: administrador, jefe_mantenimiento, jefe_operaciones, planificador, supervisor]
CREATE OR REPLACE FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum DEFAULT 'normal'::prioridad_enum, p_fecha_programada date DEFAULT NULL::date, p_responsable_id uuid DEFAULT NULL::uuid, p_plan_mantenimiento_id uuid DEFAULT NULL::uuid, p_usuario_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_folio       VARCHAR(20);
    v_periodo     TEXT;
    v_secuencia   INTEGER;
    v_ot_id       UUID;
    v_qr_code     VARCHAR(100);
    v_estado      estado_ot_enum;
    v_pauta_items JSONB;
    v_activo      RECORD;
    v_contrato    RECORD;
BEGIN

    -- [MIG189] Autorización fail-closed (ordenes_trabajo/create). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'create', ARRAY['administrador','jefe_mantenimiento','jefe_operaciones','planificador','supervisor']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'create' USING ERRCODE = '42501';
    END IF;

    SELECT id, estado INTO v_contrato FROM contratos WHERE id = p_contrato_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Contrato no encontrado'; END IF;
    IF v_contrato.estado != 'activo' THEN RAISE EXCEPTION 'Contrato no activo'; END IF;

    SELECT id, estado, codigo INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Activo no encontrado'; END IF;
    IF v_activo.estado NOT IN ('operativo', 'en_mantenimiento', 'fuera_servicio') THEN
        RAISE EXCEPTION 'Activo en estado "%" no permite OT', v_activo.estado;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

    v_periodo := TO_CHAR(NOW(), 'YYYYMM');
    SELECT COALESCE(MAX(CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)), 0) + 1
      INTO v_secuencia FROM ordenes_trabajo WHERE folio LIKE 'OT-' || v_periodo || '-%';

    v_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');
    v_ot_id := gen_random_uuid();
    v_qr_code := 'SICOM-' || v_folio || '-' || SUBSTRING(v_ot_id::TEXT, 1, 8);
    v_estado := CASE WHEN p_responsable_id IS NOT NULL THEN 'asignada' ELSE 'creada' END;

    -- El trigger trg_copiar_checklist_para_ot copia el checklist del template aquí.
    INSERT INTO ordenes_trabajo (
        id, folio, tipo, contrato_id, faena_id, activo_id,
        plan_mantenimiento_id, prioridad, estado,
        responsable_id, fecha_programada, qr_code,
        generada_automaticamente, created_by
    ) VALUES (
        v_ot_id, v_folio, p_tipo, p_contrato_id, p_faena_id, p_activo_id,
        p_plan_mantenimiento_id, p_prioridad, v_estado,
        p_responsable_id, p_fecha_programada, v_qr_code,
        (p_plan_mantenimiento_id IS NOT NULL), p_usuario_id
    );

    -- Si la OT viene de un PLAN, reemplazar el checklist genérico (del trigger)
    -- por el específico de la pauta del fabricante.
    IF p_plan_mantenimiento_id IS NOT NULL THEN
        SELECT pf.items_checklist INTO v_pauta_items
          FROM planes_mantenimiento pm
          JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
         WHERE pm.id = p_plan_mantenimiento_id;
        IF v_pauta_items IS NOT NULL AND jsonb_array_length(v_pauta_items) > 0 THEN
            DELETE FROM checklist_ot WHERE ot_id = v_ot_id;
            INSERT INTO checklist_ot (id, ot_id, orden, descripcion, obligatorio, requiere_foto)
            SELECT gen_random_uuid(), v_ot_id, t.ord::INTEGER,
                   -- soporta items como string (texto) o como objeto {descripcion/...}
                   CASE WHEN jsonb_typeof(t.item) = 'string' THEN t.item #>> '{}'
                        ELSE COALESCE(NULLIF(TRIM(t.item->>'descripcion'),''),
                                      NULLIF(TRIM(t.item->>'item'),''),
                                      NULLIF(TRIM(t.item->>'nombre'),''),
                                      NULLIF(TRIM(t.item->>'tarea'),''))
                   END,
                   COALESCE((t.item->>'obligatorio')::BOOLEAN, true),
                   COALESCE((t.item->>'requiere_foto')::BOOLEAN, false)
              FROM jsonb_array_elements(v_pauta_items) WITH ORDINALITY AS t(item, ord)
             WHERE (CASE WHEN jsonb_typeof(t.item) = 'string' THEN t.item #>> '{}'
                         ELSE COALESCE(NULLIF(TRIM(t.item->>'descripcion'),''),
                                       NULLIF(TRIM(t.item->>'item'),''),
                                       NULLIF(TRIM(t.item->>'nombre'),''),
                                       NULLIF(TRIM(t.item->>'tarea'),''))
                    END) IS NOT NULL;
        END IF;
    END IF;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), v_ot_id, NULL, v_estado, 'OT creada', p_usuario_id);

    RETURN jsonb_build_object('id', v_ot_id, 'folio', v_folio, 'estado', v_estado,
        'qr_code', v_qr_code, 'activo_codigo', v_activo.codigo);
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_crear_ot(p_tipo tipo_ot_enum, p_contrato_id uuid, p_faena_id uuid, p_activo_id uuid, p_prioridad prioridad_enum, p_fecha_programada date, p_responsable_id uuid, p_plan_mantenimiento_id uuid, p_usuario_id uuid) TO authenticated;

-- rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid)  →  ordenes_trabajo/edit  [default: administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones, planificador, supervisor, tecnico_mantenimiento]
CREATE OR REPLACE FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum DEFAULT NULL::causa_no_ejecucion_enum, p_detalle_no_ejecucion text DEFAULT NULL::text, p_observaciones text DEFAULT NULL::text, p_responsable_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_ot                     RECORD;
    v_count_evidence         INTEGER;
    v_count_checklist_total  INTEGER;
    v_count_checklist_pending INTEGER;
    v_transiciones_validas   estado_ot_enum[];
BEGIN

    -- [MIG189] Autorización fail-closed (ordenes_trabajo/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones','planificador','supervisor','tecnico_mantenimiento']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'edit' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'OT no encontrada: %', p_ot_id; END IF;

    v_transiciones_validas := CASE v_ot.estado
        WHEN 'creada'                      THEN ARRAY['asignada','cancelada']::estado_ot_enum[]
        WHEN 'asignada'                    THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'en_ejecucion'                THEN ARRAY['pausada','ejecutada_ok','ejecutada_con_observaciones','no_ejecutada']::estado_ot_enum[]
        WHEN 'pausada'                     THEN ARRAY['en_ejecucion','no_ejecutada','cancelada']::estado_ot_enum[]
        WHEN 'ejecutada_ok'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'ejecutada_con_observaciones' THEN ARRAY[]::estado_ot_enum[]
        WHEN 'no_ejecutada'                THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cancelada'                   THEN ARRAY[]::estado_ot_enum[]
        WHEN 'cerrada'                     THEN ARRAY[]::estado_ot_enum[]
        ELSE ARRAY[]::estado_ot_enum[]
    END;

    IF NOT (p_nuevo_estado = ANY(v_transiciones_validas)) THEN
        IF p_nuevo_estado = 'cerrada' THEN
            RAISE EXCEPTION 'La transición a "cerrada" solo puede realizarse mediante cierre de supervisor (rpc_cerrar_ot_supervisor).';
        END IF;
        RAISE EXCEPTION 'Transición inválida: "%" → "%". Permitidas: %', v_ot.estado, p_nuevo_estado, v_transiciones_validas;
    END IF;

    -- 3a. → asignada: requiere responsable
    IF p_nuevo_estado = 'asignada' THEN
        IF COALESCE(p_responsable_id, v_ot.responsable_id) IS NULL THEN
            RAISE EXCEPTION 'No se puede asignar OT sin responsable.';
        END IF;
    END IF;

    -- 3b. → en_ejecucion: responsable obligatorio
    IF p_nuevo_estado = 'en_ejecucion' THEN
        IF v_ot.responsable_id IS NULL THEN
            RAISE EXCEPTION 'No se puede iniciar ejecución sin responsable asignado. Asigne un responsable primero.';
        END IF;
    END IF;

    -- 3c. → no_ejecutada: causa obligatoria
    IF p_nuevo_estado = 'no_ejecutada' THEN
        IF p_causa_no_ejecucion IS NULL THEN RAISE EXCEPTION 'Causa de no ejecución es obligatoria.'; END IF;
    END IF;

    -- 3d/3e. → ejecutada_*: evidencia + checklist (cuenta el checklist V03)
    IF p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones') THEN
        -- Evidencia: fotos de evidencias_ot O fotos del checklist V03 O checklist_ot
        SELECT (SELECT COUNT(*) FROM evidencias_ot WHERE ot_id = p_ot_id)
             + (SELECT COUNT(*) FROM checklist_v2_instance ci
                  JOIN checklist_v2_instance_item ii ON ii.instance_id = ci.id
                 WHERE ci.ot_id = p_ot_id AND ii.foto_url IS NOT NULL AND length(trim(ii.foto_url)) > 0)
             + (SELECT COUNT(*) FROM checklist_ot WHERE ot_id = p_ot_id AND foto_url IS NOT NULL AND length(trim(foto_url)) > 0)
          INTO v_count_evidence;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'REGLA: Tarea sin evidencia = tarea no ejecutada. Cargue al menos 1 foto.';
        END IF;

        -- Obligatorios pendientes: primero el V03 (no excluido); si no hay V03, checklist_ot
        SELECT COUNT(*) FILTER (WHERE obligatorio),
               COUNT(*) FILTER (WHERE obligatorio AND (resultado IS NULL OR resultado = 'pendiente'))
          INTO v_count_checklist_total, v_count_checklist_pending
          FROM v_taller_ot_checklist_v3 WHERE ot_id = p_ot_id AND excluido = false;

        IF COALESCE(v_count_checklist_total,0) = 0 THEN
            SELECT COUNT(*) FILTER (WHERE obligatorio = true),
                   COUNT(*) FILTER (WHERE obligatorio = true AND resultado IS NULL)
              INTO v_count_checklist_total, v_count_checklist_pending
              FROM checklist_ot WHERE ot_id = p_ot_id;
        END IF;

        IF COALESCE(v_count_checklist_total,0) > 0 AND COALESCE(v_count_checklist_pending,0) > 0 THEN
            RAISE EXCEPTION 'Hay % de % ítems obligatorios sin completar.', v_count_checklist_pending, v_count_checklist_total;
        END IF;

        IF p_nuevo_estado = 'ejecutada_con_observaciones'
           AND COALESCE(p_observaciones, v_ot.observaciones, '') = '' THEN
            RAISE EXCEPTION 'Observaciones obligatorias al finalizar con observaciones.';
        END IF;
    END IF;

    UPDATE ordenes_trabajo
       SET estado = p_nuevo_estado,
           responsable_id = CASE WHEN p_nuevo_estado='asignada' AND p_responsable_id IS NOT NULL THEN p_responsable_id ELSE responsable_id END,
           fecha_inicio = CASE WHEN p_nuevo_estado='en_ejecucion' AND fecha_inicio IS NULL THEN NOW() ELSE fecha_inicio END,
           fecha_termino = CASE WHEN p_nuevo_estado IN ('ejecutada_ok','ejecutada_con_observaciones','no_ejecutada') THEN NOW() ELSE fecha_termino END,
           causa_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_causa_no_ejecucion ELSE causa_no_ejecucion END,
           detalle_no_ejecucion = CASE WHEN p_nuevo_estado='no_ejecutada' THEN p_detalle_no_ejecucion ELSE detalle_no_ejecucion END,
           observaciones = CASE WHEN p_observaciones IS NOT NULL THEN p_observaciones ELSE observaciones END,
           updated_at = NOW()
     WHERE id = p_ot_id;

    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, p_nuevo_estado,
            COALESCE(p_observaciones, p_detalle_no_ejecucion, v_ot.estado || ' → ' || p_nuevo_estado), p_usuario_id);

    RETURN jsonb_build_object('ot_id', p_ot_id, 'folio', v_ot.folio,
        'estado_anterior', v_ot.estado, 'estado_nuevo', p_nuevo_estado);
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_transicion_ot(p_ot_id uuid, p_nuevo_estado estado_ot_enum, p_usuario_id uuid, p_causa_no_ejecucion causa_no_ejecucion_enum, p_detalle_no_ejecucion text, p_observaciones text, p_responsable_id uuid) TO authenticated;

-- rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text)  →  ordenes_trabajo/approve  [default: administrador, jefe_mantenimiento, jefe_operaciones, subgerente_operaciones, supervisor]
CREATE OR REPLACE FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_ot                     RECORD;
    v_costo_materiales       NUMERIC(12,2);
    v_costo_mo               NUMERIC(12,2);
    v_count_evidence         INTEGER;
    v_count_checklist_pending INTEGER;
    v_count_movimientos      INTEGER;
    v_advertencias           TEXT[] := ARRAY[]::TEXT[];
BEGIN

    -- [MIG189] Autorización fail-closed (ordenes_trabajo/approve). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('ordenes_trabajo', 'approve', ARRAY['administrador','jefe_mantenimiento','jefe_operaciones','subgerente_operaciones','supervisor']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'ordenes_trabajo', 'ordenes_trabajo', 'approve' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_ot FROM ordenes_trabajo WHERE id = p_ot_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada.';
    END IF;

    IF v_ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada') THEN
        RAISE EXCEPTION 'Solo se puede cerrar OT ejecutada o no ejecutada. Estado: "%".', v_ot.estado;
    END IF;

    -- Validar completitud (solo para ejecutadas)
    IF v_ot.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones') THEN
        SELECT COUNT(*) INTO v_count_evidence FROM evidencias_ot WHERE ot_id = p_ot_id;
        IF v_count_evidence = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar OT sin evidencia.';
        END IF;

        SELECT COUNT(*) INTO v_count_checklist_pending
        FROM checklist_ot WHERE ot_id = p_ot_id AND obligatorio = true AND resultado IS NULL;
        IF v_count_checklist_pending > 0 THEN
            RAISE EXCEPTION 'Hay % ítems obligatorios sin completar.', v_count_checklist_pending;
        END IF;
    END IF;

    -- Calcular costos materiales
    SELECT COALESCE(SUM(cantidad * costo_unitario), 0), COUNT(*)
    INTO v_costo_materiales, v_count_movimientos
    FROM movimientos_inventario
    WHERE ot_id = p_ot_id AND tipo IN ('salida', 'merma');

    -- CORRECCIÓN 6: Calcular costo mano de obra
    -- Si horas_hombre y tarifa están seteados, calcular. Si no, usar lo que ya tenga.
    IF COALESCE(v_ot.horas_hombre, 0) > 0 AND COALESCE(v_ot.tarifa_hora, 0) > 0 THEN
        v_costo_mo := ROUND(v_ot.horas_hombre * v_ot.tarifa_hora);
    ELSE
        v_costo_mo := COALESCE(v_ot.costo_mano_obra, 0);
    END IF;

    -- Advertencias
    IF v_count_movimientos = 0 AND v_ot.tipo NOT IN ('inspeccion', 'regularizacion') THEN
        v_advertencias := array_append(v_advertencias, 'OT sin materiales registrados');
    END IF;
    IF v_costo_materiales = 0 AND v_costo_mo = 0 THEN
        v_advertencias := array_append(v_advertencias, 'OT con costo total $0');
    END IF;
    IF COALESCE(v_ot.horas_hombre, 0) = 0 THEN
        v_advertencias := array_append(v_advertencias, 'Sin horas hombre registradas');
    END IF;

    -- CERRAR
    UPDATE ordenes_trabajo
    SET
        estado = 'cerrada',
        fecha_cierre_supervisor = NOW(),
        supervisor_cierre_id = p_supervisor_id,
        observaciones_supervisor = p_observaciones,
        costo_materiales = v_costo_materiales,
        costo_mano_obra = v_costo_mo,
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- Plan PM
    IF v_ot.plan_mantenimiento_id IS NOT NULL AND v_ot.estado != 'no_ejecutada' THEN
        UPDATE planes_mantenimiento
        SET
            ultima_ejecucion_fecha = NOW(),
            ultima_ejecucion_km = (SELECT kilometraje_actual FROM activos WHERE id = v_ot.activo_id),
            ultima_ejecucion_horas = (SELECT horas_uso_actual FROM activos WHERE id = v_ot.activo_id),
            proxima_ejecucion_fecha = CASE
                WHEN frecuencia_dias IS NOT NULL THEN CURRENT_DATE + frecuencia_dias
                ELSE proxima_ejecucion_fecha
            END,
            updated_at = NOW()
        WHERE id = v_ot.plan_mantenimiento_id;
    END IF;

    -- Historial
    INSERT INTO historial_estado_ot (id, ot_id, estado_anterior, estado_nuevo, motivo, created_by)
    VALUES (gen_random_uuid(), p_ot_id, v_ot.estado, 'cerrada',
            COALESCE(p_observaciones, 'Cierre supervisor'), p_supervisor_id);

    RETURN jsonb_build_object(
        'ot_id', p_ot_id,
        'folio', v_ot.folio,
        'estado_anterior', v_ot.estado,
        'estado_nuevo', 'cerrada',
        'costo_materiales', v_costo_materiales,
        'costo_mano_obra', v_costo_mo,
        'costo_total', v_costo_materiales + v_costo_mo,
        'movimientos_count', v_count_movimientos,
        'advertencias', to_jsonb(v_advertencias),
        'supervisor_id', p_supervisor_id
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_ot_supervisor(p_ot_id uuid, p_supervisor_id uuid, p_observaciones text) TO authenticated;

-- rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text)  →  inventario/create  [default: administrador, bodeguero, operador_abastecimiento]
CREATE OR REPLACE FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid DEFAULT NULL::uuid, p_lote character varying DEFAULT NULL::character varying, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_stock          RECORD;
    v_ot             RECORD;
    v_movimiento_id  UUID;
    v_costo_unitario NUMERIC(15,4);
    v_nuevo_stock    NUMERIC(12,3);
    v_producto       RECORD;
    v_bodega_faena   UUID;
BEGIN

    -- [MIG189] Autorización fail-closed (inventario/create). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('inventario', 'create', ARRAY['administrador','bodeguero','operador_abastecimiento']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'inventario', 'inventario', 'create' USING ERRCODE = '42501';
    END IF;

    -- VALIDACIONES
    IF p_ot_id IS NULL THEN
        RAISE EXCEPTION 'REGLA: No se permite salida de inventario sin OT asociada.';
    END IF;

    SELECT id, estado, folio, faena_id INTO v_ot
    FROM ordenes_trabajo WHERE id = p_ot_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'OT no encontrada: %', p_ot_id;
    END IF;

    IF v_ot.estado NOT IN ('asignada', 'en_ejecucion', 'pausada') THEN
        RAISE EXCEPTION 'No se puede retirar material de OT en estado "%".', v_ot.estado;
    END IF;

    IF p_cantidad <= 0 THEN
        RAISE EXCEPTION 'La cantidad debe ser mayor a 0.';
    END IF;

    SELECT id, nombre, stock_minimo INTO v_producto
    FROM productos WHERE id = p_producto_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto no encontrado.';
    END IF;

    -- CORRECCIÓN 4: Validar que bodega pertenece a la faena de la OT
    SELECT faena_id INTO v_bodega_faena
    FROM bodegas WHERE id = p_bodega_id;

    IF v_bodega_faena IS NOT NULL AND v_ot.faena_id IS NOT NULL
       AND v_bodega_faena != v_ot.faena_id THEN
        RAISE EXCEPTION 'La bodega seleccionada no pertenece a la faena de la OT. Bodega faena: %, OT faena: %.',
            v_bodega_faena, v_ot.faena_id;
    END IF;

    -- LOCK + OPERACIÓN ATÓMICA
    SELECT cantidad, costo_promedio INTO v_stock
    FROM stock_bodega
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe stock de "%" en la bodega indicada.', v_producto.nombre;
    END IF;

    IF v_stock.cantidad < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente de "%". Disponible: %, solicitado: %.',
            v_producto.nombre, v_stock.cantidad, p_cantidad;
    END IF;

    v_costo_unitario := v_stock.costo_promedio;
    v_nuevo_stock := v_stock.cantidad - p_cantidad;
    v_movimiento_id := gen_random_uuid();

    -- Movimiento
    INSERT INTO movimientos_inventario (
        id, bodega_id, producto_id, tipo, cantidad, costo_unitario,
        ot_id, activo_id, lote, motivo, usuario_id, created_at
    ) VALUES (
        v_movimiento_id, p_bodega_id, p_producto_id, 'salida', p_cantidad,
        v_costo_unitario, p_ot_id,
        COALESCE(p_activo_id, (SELECT activo_id FROM ordenes_trabajo WHERE id = p_ot_id)),
        p_lote, p_motivo, p_usuario_id, NOW()
    );

    -- Stock
    UPDATE stock_bodega
    SET cantidad = v_nuevo_stock, ultimo_movimiento = NOW(), updated_at = NOW()
    WHERE bodega_id = p_bodega_id AND producto_id = p_producto_id;

    -- Kardex
    INSERT INTO kardex (
        id, bodega_id, producto_id, movimiento_id, fecha, tipo,
        cantidad_movimiento, cantidad_anterior, cantidad_posterior,
        costo_unitario, costo_promedio_anterior, costo_promedio_posterior,
        valor_movimiento, valor_stock_posterior
    ) VALUES (
        gen_random_uuid(), p_bodega_id, p_producto_id, v_movimiento_id, NOW(), 'salida',
        p_cantidad, v_stock.cantidad, v_nuevo_stock,
        v_costo_unitario, v_stock.costo_promedio, v_stock.costo_promedio,
        p_cantidad * v_costo_unitario, v_nuevo_stock * v_stock.costo_promedio
    );

    -- Costo OT
    UPDATE ordenes_trabajo
    SET costo_materiales = COALESCE(costo_materiales, 0) + (p_cantidad * v_costo_unitario),
        updated_at = NOW()
    WHERE id = p_ot_id;

    -- Alerta stock mínimo
    IF v_nuevo_stock < v_producto.stock_minimo THEN
        INSERT INTO alertas (tipo, titulo, mensaje, severidad, entidad_tipo, entidad_id)
        VALUES ('stock_minimo', 'Stock bajo: ' || v_producto.nombre,
                'Stock: ' || v_nuevo_stock || '. Mínimo: ' || v_producto.stock_minimo,
                'warning', 'producto', p_producto_id);
    END IF;

    RETURN jsonb_build_object(
        'movimiento_id', v_movimiento_id,
        'producto', v_producto.nombre,
        'cantidad', p_cantidad,
        'costo_unitario', v_costo_unitario,
        'costo_total', p_cantidad * v_costo_unitario,
        'stock_anterior', v_stock.cantidad,
        'stock_posterior', v_nuevo_stock,
        'ot_folio', v_ot.folio
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_salida_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_ot_id uuid, p_usuario_id uuid, p_activo_id uuid, p_lote character varying, p_motivo text) TO authenticated;

-- rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text)  →  contratos/edit  [default: administrador]
CREATE OR REPLACE FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_activo  RECORD;
    v_id_hist BIGINT;
    v_oper    VARCHAR;
BEGIN

    -- [MIG189] Autorización fail-closed (contratos/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('contratos', 'edit', ARRAY['administrador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'contratos', 'contratos', 'edit' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF v_activo.id IS NULL THEN
        RAISE EXCEPTION 'Activo % no encontrado', p_activo_id;
    END IF;

    IF p_nuevo_contrato_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM contratos WHERE id = p_nuevo_contrato_id) THEN
            RAISE EXCEPTION 'Contrato % no existe', p_nuevo_contrato_id;
        END IF;
    END IF;

    IF v_activo.contrato_id IS NOT DISTINCT FROM p_nuevo_contrato_id THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    -- Aplicar el cambio + sincronizar cliente_actual con el nuevo contrato
    UPDATE activos
       SET contrato_id   = p_nuevo_contrato_id,
           cliente_actual = CASE WHEN p_nuevo_contrato_id IS NOT NULL
                                 THEN (SELECT cliente FROM contratos WHERE id = p_nuevo_contrato_id)
                                 ELSE 'Sin contrato' END
     WHERE id = p_activo_id;

    -- Completar operación (Calama/Coquimbo) desde el contrato si el equipo no la
    -- tiene: operación dominante de los demás equipos del mismo contrato.
    IF p_nuevo_contrato_id IS NOT NULL
       AND (v_activo.operacion IS NULL OR v_activo.operacion = '') THEN
        SELECT operacion INTO v_oper
          FROM activos
         WHERE contrato_id = p_nuevo_contrato_id
           AND operacion IS NOT NULL AND operacion <> ''
           AND id <> p_activo_id
         GROUP BY operacion
         ORDER BY COUNT(*) DESC
         LIMIT 1;
        IF v_oper IS NOT NULL THEN
            UPDATE activos SET operacion = v_oper WHERE id = p_activo_id;
        END IF;
    END IF;

    SELECT id INTO v_id_hist
      FROM historico_contrato_activo
     WHERE activo_id = p_activo_id
     ORDER BY cambio_at DESC, id DESC
     LIMIT 1;

    IF v_id_hist IS NOT NULL AND p_razon IS NOT NULL THEN
        UPDATE historico_contrato_activo SET razon = p_razon WHERE id = v_id_hist;
    END IF;

    RETURN jsonb_build_object(
        'ok', true, 'activo_id', p_activo_id,
        'contrato_anterior', v_activo.contrato_id,
        'contrato_nuevo', p_nuevo_contrato_id,
        'operacion_completada', v_oper,
        'historico_id', v_id_hist
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cambiar_contrato_activo(p_activo_id uuid, p_nuevo_contrato_id uuid, p_razon text) TO authenticated;

-- rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character)  →  flota/approve  [default: (solo override)]
CREATE OR REPLACE FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
BEGIN

    -- [MIG189] Autorización fail-closed (flota/approve). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('flota', 'approve', ARRAY[]::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'approve' USING ERRCODE = '42501';
    END IF;

  INSERT INTO estado_diario_flota
    (activo_id, fecha, estado_codigo, override_manual, calculado_auto, motivo_override, actualizado_por, actualizado_at)
  VALUES
    (p_activo_id, p_fecha, p_estado, true, false, 'Confirmado por planificador (sugerencia GPS)', auth.uid(), now())
  ON CONFLICT (activo_id, fecha) DO UPDATE
    SET estado_codigo = EXCLUDED.estado_codigo, override_manual = true, calculado_auto = false,
        motivo_override = EXCLUDED.motivo_override, actualizado_por = auth.uid(),
        actualizado_at = now(), updated_at = now();

  -- Sincronizar SOLO la categoría comercial (para el informe de Fiabilidad).
  -- NO se toca estado_comercial: hacerlo dispararía los gates de checklist /
  -- ready-to-rent y la auto-recepción, que son para la acción deliberada del
  -- modal, no para registrar la realidad diaria desde Sugerencias GPS.
  IF p_estado IN ('A','C','L','U','V') THEN
    UPDATE activos a
       SET categoria_uso = CASE p_estado
              WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
              WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
              WHEN 'V' THEN 'venta'::categoria_uso_enum
              ELSE a.categoria_uso END,
           updated_at = now()
     WHERE a.id = p_activo_id
       AND a.categoria_uso IS DISTINCT FROM (CASE p_estado
              WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum
              WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
              WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
              WHEN 'V' THEN 'venta'::categoria_uso_enum END);
  END IF;
END $function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_confirmar_estado_dia(p_activo_id uuid, p_fecha date, p_estado character) TO authenticated;

-- rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid)  →  activos/edit  [default: administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones]
CREATE OR REPLACE FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric DEFAULT NULL::numeric, p_horas_uso numeric DEFAULT NULL::numeric, p_ciclos integer DEFAULT NULL::integer, p_usuario_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_activo          RECORD;
    v_plan            RECORD;
    v_ot_result       JSONB;
    v_ots_generadas   INTEGER := 0;
BEGIN

    -- [MIG189] Autorización fail-closed (activos/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('activos', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'activos', 'activos', 'edit' USING ERRCODE = '42501';
    END IF;

    -- Lock activo
    SELECT * INTO v_activo
    FROM activos
    WHERE id = p_activo_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado.';
    END IF;

    -- Actualizar métricas (solo las que se proporcionan)
    UPDATE activos
    SET
        kilometraje_actual = COALESCE(p_kilometraje, kilometraje_actual),
        horas_uso_actual = COALESCE(p_horas_uso, horas_uso_actual),
        ciclos_actual = COALESCE(p_ciclos, ciclos_actual),
        updated_at = NOW()
    WHERE id = p_activo_id;

    -- Evaluar planes PM que puedan dispararse por las nuevas métricas
    FOR v_plan IN
        SELECT pm.*
        FROM planes_mantenimiento pm
        WHERE pm.activo_id = p_activo_id
          AND pm.activo_plan = true
          AND NOT EXISTS (
              SELECT 1 FROM ordenes_trabajo ot
              WHERE ot.plan_mantenimiento_id = pm.id
                AND ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones', 'no_ejecutada', 'cancelada')
          )
    LOOP
        -- Evaluar condición de disparo
        IF (
            (v_plan.tipo_plan IN ('por_kilometraje', 'mixto')
             AND v_plan.frecuencia_km IS NOT NULL
             AND p_kilometraje IS NOT NULL
             AND (p_kilometraje - COALESCE(v_plan.ultima_ejecucion_km, 0)) >= v_plan.frecuencia_km)
            OR
            (v_plan.tipo_plan IN ('por_horas', 'mixto')
             AND v_plan.frecuencia_horas IS NOT NULL
             AND p_horas_uso IS NOT NULL
             AND (p_horas_uso - COALESCE(v_plan.ultima_ejecucion_horas, 0)) >= v_plan.frecuencia_horas)
            OR
            (v_plan.tipo_plan = 'por_ciclos'
             AND v_plan.frecuencia_ciclos IS NOT NULL
             AND p_ciclos IS NOT NULL
             AND (p_ciclos - COALESCE(v_plan.ultima_ejecucion_ciclos, 0)) >= v_plan.frecuencia_ciclos)
        ) THEN
            -- Crear OT preventiva
            SELECT rpc_crear_ot(
                p_tipo := 'preventivo',
                p_contrato_id := v_activo.contrato_id,
                p_faena_id := v_activo.faena_id,
                p_activo_id := p_activo_id,
                p_prioridad := COALESCE(v_plan.prioridad, 'normal'),
                p_fecha_programada := CURRENT_DATE + COALESCE(v_plan.anticipacion_dias, 7),
                p_plan_mantenimiento_id := v_plan.id,
                p_usuario_id := p_usuario_id
            ) INTO v_ot_result;

            v_ots_generadas := v_ots_generadas + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'activo_id', p_activo_id,
        'kilometraje', COALESCE(p_kilometraje, v_activo.kilometraje_actual),
        'horas_uso', COALESCE(p_horas_uso, v_activo.horas_uso_actual),
        'ciclos', COALESCE(p_ciclos, v_activo.ciclos_actual),
        'ots_preventivas_generadas', v_ots_generadas
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_actualizar_metricas_activo(p_activo_id uuid, p_kilometraje numeric, p_horas_uso numeric, p_ciclos integer, p_usuario_id uuid) TO authenticated;

-- rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid)  →  mantenimiento/edit  [default: administrador, auditor_calidad, jefe_mantenimiento, planificador]
CREATE OR REPLACE FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE v_pf RECORD; v_id uuid;
BEGIN

    -- [MIG189] Autorización fail-closed (mantenimiento/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('mantenimiento', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','planificador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'mantenimiento', 'mantenimiento', 'edit' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_pf FROM pautas_fabricante WHERE id = p_pauta_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Pauta no existe'; END IF;

    IF EXISTS (SELECT 1 FROM planes_mantenimiento WHERE activo_id = p_activo_id AND pauta_fabricante_id = p_pauta_id) THEN
        RETURN jsonb_build_object('ok', true, 'sin_cambio', true);
    END IF;

    v_id := gen_random_uuid();
    INSERT INTO planes_mantenimiento (id, activo_id, pauta_fabricante_id, nombre, tipo_plan,
                                      frecuencia_dias, frecuencia_km, frecuencia_horas, activo_plan, created_by)
    VALUES (v_id, p_activo_id, p_pauta_id, v_pf.nombre, v_pf.tipo_plan,
            v_pf.frecuencia_dias, v_pf.frecuencia_km, v_pf.frecuencia_horas, true, auth.uid());

    RETURN jsonb_build_object('id', v_id);
END $function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_asignar_pauta(p_activo_id uuid, p_pauta_id uuid) TO authenticated;

-- rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum)  →  activos/create  [default: administrador]
CREATE OR REPLACE FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_p      RECORD;
    v_modelo uuid;
    v_codigo text;
    v_n      integer;
    v_id     uuid;
BEGIN

    -- [MIG189] Autorización fail-closed (activos/create). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('activos', 'create', ARRAY['administrador']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'activos', 'activos', 'create' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_p FROM activos WHERE id = p_padre_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo padre no existe'; END IF;

    SELECT id INTO v_modelo FROM modelos WHERE nombre = 'Equipo Auxiliar' LIMIT 1;
    SELECT count(*) INTO v_n FROM activos WHERE activo_padre_id = p_padre_id;
    v_codigo := COALESCE(v_p.codigo, 'EQ') || '-AUX-' || LPAD((v_n + 1)::text, 2, '0');
    v_id := gen_random_uuid();

    INSERT INTO activos (id, codigo, nombre, tipo, modelo_id, activo_padre_id, estado,
                         contrato_id, faena_id, cliente_actual, operacion)
    VALUES (v_id, v_codigo, p_nombre, p_tipo, v_modelo, p_padre_id, 'operativo',
            v_p.contrato_id, v_p.faena_id, v_p.cliente_actual, v_p.operacion);

    RETURN jsonb_build_object('id', v_id, 'codigo', v_codigo);
END $function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_crear_auxiliar(p_padre_id uuid, p_nombre text, p_tipo tipo_activo_enum) TO authenticated;

-- rpc_generar_qr_activo(p_activo_id uuid, p_base_url text)  →  activos/edit  [default: administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones]
CREATE OR REPLACE FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text DEFAULT 'https://pilladoiceo.netlify.app'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_activo RECORD;
    v_qr_code VARCHAR(100);
    v_qr_url TEXT;
BEGIN

    -- [MIG189] Autorización fail-closed (activos/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('activos', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'activos', 'activos', 'edit' USING ERRCODE = '42501';
    END IF;

    SELECT id, codigo INTO v_activo
    FROM activos WHERE id = p_activo_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo no encontrado.';
    END IF;

    -- Generar código QR único basado en código del activo
    v_qr_code := 'SICOM-ACT-' || v_activo.codigo || '-' || SUBSTRING(p_activo_id::TEXT, 1, 8);
    v_qr_url := p_base_url || '/equipo/' || p_activo_id;

    -- Actualizar activo
    UPDATE activos
    SET qr_code = v_qr_code,
        qr_url = v_qr_url,
        updated_at = NOW()
    WHERE id = p_activo_id;

    RETURN jsonb_build_object(
        'activo_id', p_activo_id,
        'codigo', v_activo.codigo,
        'qr_code', v_qr_code,
        'qr_url', v_qr_url
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_generar_qr_activo(p_activo_id uuid, p_base_url text) TO authenticated;

-- rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text)  →  flota/edit  [default: administrador, auditor_calidad, jefe_mantenimiento, jefe_operaciones, planificador, subgerente_operaciones, supervisor]
CREATE OR REPLACE FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE
    v_sug    RECORD;
    v_nueva  accion_sugerencia_enum;
BEGIN

    -- [MIG189] Autorización fail-closed (flota/edit). Deniega anon,
    -- portal cliente (sin fila en usuarios_perfil), inactivos y sin permiso.
    IF NOT public.fn_tiene_permiso_modulo('flota', 'edit', ARRAY['administrador','auditor_calidad','jefe_mantenimiento','jefe_operaciones','planificador','subgerente_operaciones','supervisor']::text[]) THEN
        RAISE EXCEPTION 'No autorizado para % (%.%).', 'flota', 'flota', 'edit' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_sug
      FROM cambios_estado_sugeridos
     WHERE id = p_sugerencia_id;

    IF v_sug.id IS NULL THEN
        RAISE EXCEPTION 'Sugerencia % no encontrada', p_sugerencia_id;
    END IF;
    IF v_sug.accion <> 'pendiente' THEN
        RAISE EXCEPTION 'Sugerencia ya fue resuelta como % en %', v_sug.accion, v_sug.validado_at;
    END IF;

    IF p_accion NOT IN ('aprobar','rechazar') THEN
        RAISE EXCEPTION 'Accion debe ser aprobar o rechazar (recibido: %)', p_accion;
    END IF;

    v_nueva := CASE p_accion WHEN 'aprobar' THEN 'aprobada'::accion_sugerencia_enum
                              ELSE 'rechazada'::accion_sugerencia_enum END;

    UPDATE cambios_estado_sugeridos
       SET accion = v_nueva,
           validado_at = NOW(),
           validado_por = auth.uid(),
           comentario = p_comentario
     WHERE id = p_sugerencia_id;

    IF p_accion = 'aprobar' THEN
        -- Ejecutar el cambio en activos. El trigger registra historico.
        UPDATE activos
           SET estado_comercial = v_sug.estado_sugerido
         WHERE id = v_sug.activo_id;
    END IF;

    RETURN jsonb_build_object(
        'ok', true,
        'sugerencia_id', p_sugerencia_id,
        'accion', v_nueva::text,
        'activo_id', v_sug.activo_id
    );
END;
$function$
;
REVOKE EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_validar_sugerencia(p_sugerencia_id uuid, p_accion character varying, p_comentario text) TO authenticated;


-- ═══ GRUPO B · P0 internas (cron/trigger): sin acceso PostgREST ═══
REVOKE EXECUTE ON FUNCTION public.generar_ots_preventivas() FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verificar_certificaciones() FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_auto_crear_planes_activo(p_activo_id uuid) FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_generar_nc_desde_checklist_ot(p_ot_id uuid) FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_generar_nc_desde_v3_ot(p_ot_id uuid) FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_reconciliar_estado_ficha_desde_matriz() FROM anon, authenticated, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_reconciliar_comercial_ficha_desde_matriz() FROM anon, authenticated, PUBLIC;


-- ═══ P1/P2 · cierre de superficie anónima (endurecimiento por-fn en Fase 1) ═══
REVOKE EXECUTE ON FUNCTION public.calcular_iceo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.calcular_iceo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.calcular_todos_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.calcular_todos_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_calama_aplicar_avance_interno(p_ot_id uuid, p_avance_nuevo numeric, p_fuente text, p_motivo text, p_comentario text, p_uid uuid, p_ejecucion_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_calama_aplicar_avance_interno(p_ot_id uuid, p_avance_nuevo numeric, p_fuente text, p_motivo text, p_comentario text, p_uid uuid, p_ejecucion_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_calama_audit_jornada(p_payload jsonb) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_calama_audit_jornada(p_payload jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_consumir_inventario_fifo(p_producto_id uuid, p_bodega_id uuid, p_cantidad numeric, p_salida_bodega_id uuid, p_salida_bodega_item_id uuid, p_movimiento_id uuid, p_ot_id uuid, p_ceco_id uuid, p_consumido_por uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_consumir_inventario_fifo(p_producto_id uuid, p_bodega_id uuid, p_cantidad numeric, p_salida_bodega_id uuid, p_salida_bodega_item_id uuid, p_movimiento_id uuid, p_ot_id uuid, p_ceco_id uuid, p_consumido_por uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_evaluar_activos_fuera_geocerca() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_evaluar_activos_fuera_geocerca() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_gps_generar_alertas_sin_senal() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_gps_generar_alertas_sin_senal() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_guardar_reporte_diario(p_fecha date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_guardar_reporte_diario(p_fecha date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_inicializar_checklist_v2(p_template_id uuid, p_activo_id uuid, p_contrato_id uuid, p_operador_id uuid, p_horometro numeric, p_kilometraje numeric, p_informe_id uuid, p_entrega_ref uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_inicializar_checklist_v2(p_template_id uuid, p_activo_id uuid, p_contrato_id uuid, p_operador_id uuid, p_horometro numeric, p_kilometraje numeric, p_informe_id uuid, p_entrega_ref uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_mantenimiento_diario(p_umbral_mb numeric) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_mantenimiento_diario(p_umbral_mb numeric) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_qr_evaluar_alertas_calidad(p_respuesta_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_qr_evaluar_alertas_calidad(p_respuesta_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_recalcular_plazos_diferidos(p_activo_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_recalcular_plazos_diferidos(p_activo_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_taller_log_jornada_evento(p_plan_ot_id uuid, p_tipo character varying, p_motivo text, p_dia_anterior date, p_dia_nuevo date, p_responsable_anterior uuid, p_responsable_nuevo uuid, p_cuadrilla_anterior character varying, p_cuadrilla_nueva character varying, p_campo character varying, p_valor_anterior text, p_valor_nuevo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_taller_log_jornada_evento(p_plan_ot_id uuid, p_tipo character varying, p_motivo text, p_dia_anterior date, p_dia_nuevo date, p_responsable_anterior uuid, p_responsable_nuevo uuid, p_cuadrilla_anterior character varying, p_cuadrilla_nueva character varying, p_campo character varying, p_valor_anterior text, p_valor_nuevo text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_aplicar_diff_a_informe(p_recepcion_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_aplicar_diff_a_informe(p_recepcion_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_aprobar_conteo_inventario(p_conteo_id uuid, p_supervisor_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_calcular_iceo_periodo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_calcular_iceo_periodo(p_contrato_id uuid, p_faena_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_calcular_incentivos_periodo(p_contrato_id uuid, p_periodo_inicio date, p_periodo_fin date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_calcular_incentivos_periodo(p_contrato_id uuid, p_periodo_inicio date, p_periodo_fin date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_checklist_v2(p_instance_id uuid, p_firma_operador_url text, p_firma_cliente_url text, p_operador_rut character varying, p_operador_nombre character varying, p_cliente_rut character varying, p_cliente_nombre character varying) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_checklist_v2(p_instance_id uuid, p_firma_operador_url text, p_firma_cliente_url text, p_operador_rut character varying, p_operador_nombre character varying, p_cliente_rut character varying, p_cliente_nombre character varying) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_cerrar_periodo_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo date, p_usuario_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_cerrar_periodo_kpi(p_contrato_id uuid, p_faena_id uuid, p_periodo date, p_usuario_id uuid) TO authenticated;
-- (allowlist QR) rpc_checklist_cliente_guardar
REVOKE EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_confirmar_cierre_diario(p_fecha date, p_items jsonb) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_generar_alerta_temprana(p_checklist_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_generar_alerta_temprana(p_checklist_id uuid) TO authenticated;
-- (allowlist QR) rpc_guardar_checklist_publico
REVOKE EXECUTE ON FUNCTION public.rpc_ingestar_gps_batch(p_proveedor_nombre text, p_eventos jsonb) FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_ingestar_gps_batch(p_proveedor_nombre text, p_eventos jsonb) TO service_role;  -- solo edge function GPS (documentado)
REVOKE EXECUTE ON FUNCTION public.rpc_portal_marcar_acceso() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_portal_marcar_acceso() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_procesar_recalculos_iceo() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_procesar_recalculos_iceo() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_programar_ot_recepcion(p_activo_id uuid, p_prioridad prioridad_enum, p_fecha date, p_responsable_id uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_programar_ot_recepcion(p_activo_id uuid, p_prioridad prioridad_enum, p_fecha date, p_responsable_id uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid, p_autorizado_por uuid) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_ajuste_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_motivo text, p_usuario_id uuid, p_ot_id uuid, p_autorizado_por uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_registrar_entrada_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_costo_unitario numeric, p_documento_referencia character varying, p_usuario_id uuid, p_lote character varying, p_fecha_vencimiento date) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_registrar_entrada_inventario(p_bodega_id uuid, p_producto_id uuid, p_cantidad numeric, p_costo_unitario numeric, p_documento_referencia character varying, p_usuario_id uuid, p_lote character varying, p_fecha_vencimiento date) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.rpc_transferir_inventario(p_bodega_origen_id uuid, p_bodega_destino_id uuid, p_producto_id uuid, p_cantidad numeric, p_usuario_id uuid, p_motivo text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.rpc_transferir_inventario(p_bodega_origen_id uuid, p_bodega_destino_id uuid, p_producto_id uuid, p_cantidad numeric, p_usuario_id uuid, p_motivo text) TO authenticated;

-- ── Verificación (aborta si algo quedó abierto o mal grant) ─────────────────
DO $$
DECLARE v_anon INT; v_b_auth INT;
BEGIN
    -- Ninguna P0/P1/P2 (salvo allowlist) ejecutable por anon.
    SELECT count(*) INTO v_anon
      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'
     WHERE p.prosecdef AND p.prokind='f' AND p.prorettype <> 'trigger'::regtype
       AND has_function_privilege('anon', p.oid, 'EXECUTE')
       AND pg_get_functiondef(p.oid) ~* 'insert into|update .* set|delete from'
       AND pg_get_functiondef(p.oid) !~* 'auth\.uid\(\) is null|no autenticado|fn_user_rol|fn_tiene_permiso'
       AND p.proname NOT IN ('rpc_guardar_checklist_publico','rpc_checklist_cliente_guardar');
    IF v_anon > 0 THEN RAISE EXCEPTION 'MIG189: % funciones de escritura siguen anónimas', v_anon; END IF;

    -- Grupo B no debe ser ejecutable por authenticated.
    SELECT count(*) INTO v_b_auth
      FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace AND nsp.nspname='public'
     WHERE p.proname IN ('generar_ots_preventivas','verificar_certificaciones','fn_auto_crear_planes_activo','fn_generar_nc_desde_checklist_ot','fn_generar_nc_desde_v3_ot','fn_reconciliar_estado_ficha_desde_matriz','fn_reconciliar_comercial_ficha_desde_matriz')
       AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
    IF v_b_auth > 0 THEN RAISE EXCEPTION 'MIG189: % funciones internas siguen ejecutables por authenticated', v_b_auth; END IF;

    RAISE NOTICE 'MIG189 OK: P0 con guard/interno, superficie anónima cerrada.';
END $$;

SELECT 'MIG189 v2 aplicada' AS resultado;
