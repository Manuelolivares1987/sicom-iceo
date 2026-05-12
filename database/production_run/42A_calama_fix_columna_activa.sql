-- ============================================================================
-- 42A_calama_fix_columna_activa.sql
-- ----------------------------------------------------------------------------
-- HOTFIX MIG42 (consolidado). La RPC rpc_calama_crear_jornada_prueba_terreno
-- tenia 2 referencias a columnas que no existen en el schema real:
--
--   1) calama_faenas.activa  -> la columna real es calama_faenas.activo
--      (ver 17_operacion_calama_base.sql linea 167).
--      Error: ERROR 42703: column "activa" does not exist
--
--   2) calama_zonas_proyecto: el INSERT pasaba descripcion + cliente_uuid,
--      pero esa tabla solo tiene (id, planificacion_id, codigo_zona, nombre,
--      orden, created_at, updated_at) — sin descripcion, sin cliente_uuid
--      (ver 18_operacion_calama_import_excel.sql linea 124).
--      Error: ERROR 42703: column "descripcion" of relation
--             "calama_zonas_proyecto" does not exist
--
-- Esta migracion REEMPLAZA la funcion completa con ambos fixes.
-- ADITIVA, IDEMPOTENTE (CREATE OR REPLACE FUNCTION).
-- NO toca tablas ni datos. Reentrante: re-correrla no genera efectos.
-- ============================================================================

-- ── Precheck: MIG42 debe estar aplicada ──────────────────────────────────
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
         WHERE proname = 'rpc_calama_crear_jornada_prueba_terreno'
    ) THEN
        RAISE EXCEPTION 'STOP - MIG42 no aplicada (falta rpc_calama_crear_jornada_prueba_terreno). Aplicar 42_calama_modo_prueba_sandbox.sql primero.';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_name = 'calama_faenas' AND column_name = 'activo'
    ) THEN
        RAISE EXCEPTION 'STOP - calama_faenas.activo no existe. Revisar 17_operacion_calama_base.sql.';
    END IF;
END $$;


-- ── Reemplazar funcion con el fix ────────────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_calama_crear_jornada_prueba_terreno(
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user_id        UUID := auth.uid();
    v_rol            TEXT;
    v_planificacion_id UUID;
    v_faena_id       UUID;
    v_responsable_id UUID;
    v_fecha_jornada  DATE;
    v_zona_id        UUID;
    v_ot_id          UUID;
    v_folio          VARCHAR;
    v_plan_semanal_id UUID;
    v_plan_dia_id    UUID;
    v_plan_ot_id     UUID;
    v_fecha_inicio_sem DATE;
    v_fecha_fin_sem  DATE;
    v_oocc_email     TEXT;
    v_nombre_dia     VARCHAR;
    v_orden_dia      INT;
BEGIN
    -- Auth + rol
    IF v_user_id IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    v_rol := fn_user_rol();
    IF v_rol NOT IN ('administrador','supervisor','subgerente_operaciones','jefe_mantenimiento') THEN
        RAISE EXCEPTION 'Rol % no autorizado para crear jornada de prueba', v_rol;
    END IF;

    -- Inputs (con defaults razonables)
    v_planificacion_id := NULLIF(p_payload->>'planificacion_id', '')::UUID;
    v_faena_id         := NULLIF(p_payload->>'faena_id', '')::UUID;
    v_responsable_id   := NULLIF(p_payload->>'responsable_id', '')::UUID;
    v_fecha_jornada    := COALESCE(NULLIF(p_payload->>'fecha_jornada','')::DATE, CURRENT_DATE);

    -- Si no se paso planificacion, usar la primera activa
    IF v_planificacion_id IS NULL THEN
        SELECT id INTO v_planificacion_id FROM calama_planificaciones
         WHERE estado <> 'cancelada' ORDER BY created_at DESC LIMIT 1;
        IF v_planificacion_id IS NULL THEN
            RAISE EXCEPTION 'No hay planificacion Calama disponible. Pasar planificacion_id en p_payload.';
        END IF;
    END IF;

    -- Si no se paso faena, usar la primera disponible
    -- FIX MIG42A: la columna es "activo" (no "activa") en calama_faenas
    IF v_faena_id IS NULL THEN
        SELECT id INTO v_faena_id FROM calama_faenas
         WHERE COALESCE(activo, true) = true ORDER BY created_at LIMIT 1;
        IF v_faena_id IS NULL THEN
            RAISE EXCEPTION 'No hay faena Calama disponible. Pasar faena_id en p_payload.';
        END IF;
    END IF;

    -- Si no se paso responsable, intentar oocc@pillado.cl
    IF v_responsable_id IS NULL THEN
        SELECT up.id INTO v_responsable_id
          FROM usuarios_perfil up
         WHERE up.email = 'oocc@pillado.cl' AND up.activo = true
         LIMIT 1;
        IF v_responsable_id IS NULL THEN
            RAISE EXCEPTION 'No hay responsable: pasar responsable_id en p_payload (o crear oocc@pillado.cl)';
        END IF;
    END IF;

    -- ─ ZONA TEST: crear si no existe en esa planificacion ─
    -- FIX MIG42A: calama_zonas_proyecto no tiene descripcion ni cliente_uuid,
    -- solo (id, planificacion_id, codigo_zona, nombre, orden, timestamps).
    -- Idempotencia esta garantizada por UNIQUE(planificacion_id, codigo_zona).
    SELECT id INTO v_zona_id FROM calama_zonas_proyecto
     WHERE planificacion_id = v_planificacion_id AND codigo_zona = 'TEST'
     LIMIT 1;
    IF v_zona_id IS NULL THEN
        INSERT INTO calama_zonas_proyecto (
            planificacion_id, codigo_zona, nombre
        ) VALUES (
            v_planificacion_id, 'TEST', 'Zona de Pruebas Terreno'
        )
        RETURNING id INTO v_zona_id;
    END IF;

    -- ─ OT TEST: folio unico por corrida ─
    v_folio := 'TEST-TERRENO-' || TO_CHAR(NOW(), 'YYYYMMDDHH24MISS');
    v_ot_id := gen_random_uuid();
    INSERT INTO calama_ordenes_trabajo (
        id, folio, planificacion_id, faena_calama_id,
        titulo, descripcion, fecha_programada,
        avance_pct, estado, prioridad, responsable_id,
        observaciones_apertura,
        es_prueba, excluida_estadisticas, motivo_prueba,
        created_by, cliente_uuid
    ) VALUES (
        v_ot_id, v_folio, v_planificacion_id, v_faena_id,
        'Prueba app terreno (' || v_folio || ')',
        'OT generada por sandbox MIG42 para validar fotos, offline, GPS, pausa, firma y cierre. NO afecta estadisticas reales.',
        v_fecha_jornada,
        0, 'liberada', 'baja', v_responsable_id,
        'Sandbox de pruebas terreno. Reset/anular cuando quieras.',
        true, true,
        'Sandbox app terreno (MIG42)',
        v_user_id, gen_random_uuid()
    );

    -- ─ Marcar precheck como liberado para que la jornada sea ejecutable ─
    INSERT INTO calama_ot_precheck (
        ot_id, epp_completo, herramientas_ok, vehiculo_confirmado,
        charla_ods_realizada, permisos_trabajo_ok,
        observaciones, revisado_por, revisado_at
    ) VALUES (
        v_ot_id, true, true, true, true, true,
        'Precheck OK por sandbox de pruebas', v_user_id, NOW()
    ) ON CONFLICT (ot_id) DO NOTHING;

    -- ─ PLAN SEMANAL: reusar el de la semana de la fecha_jornada ─
    v_fecha_inicio_sem := v_fecha_jornada - ((EXTRACT(ISODOW FROM v_fecha_jornada)::int - 1));
    v_fecha_fin_sem    := v_fecha_inicio_sem + 6;

    SELECT id INTO v_plan_semanal_id FROM calama_planes_semanales
     WHERE planificacion_id = v_planificacion_id
       AND fecha_inicio_semana = v_fecha_inicio_sem
     LIMIT 1;
    IF v_plan_semanal_id IS NULL THEN
        INSERT INTO calama_planes_semanales (
            planificacion_id, faena_calama_id,
            fecha_inicio_semana, fecha_fin_semana,
            estado, creado_por, observaciones
        ) VALUES (
            v_planificacion_id, v_faena_id,
            v_fecha_inicio_sem, v_fecha_fin_sem,
            'confirmado', v_user_id,
            'Plan semanal sandbox MIG42'
        )
        RETURNING id INTO v_plan_semanal_id;
    END IF;

    -- ─ PLAN DIA: reusar el de la fecha ─
    SELECT id INTO v_plan_dia_id FROM calama_plan_semanal_dias
     WHERE plan_semanal_id = v_plan_semanal_id AND fecha = v_fecha_jornada
     LIMIT 1;
    IF v_plan_dia_id IS NULL THEN
        v_orden_dia := EXTRACT(ISODOW FROM v_fecha_jornada)::int;
        v_nombre_dia := CASE v_orden_dia
            WHEN 1 THEN 'Lunes'   WHEN 2 THEN 'Martes'    WHEN 3 THEN 'Miercoles'
            WHEN 4 THEN 'Jueves'  WHEN 5 THEN 'Viernes'   WHEN 6 THEN 'Sabado'
            WHEN 7 THEN 'Domingo' ELSE 'Dia' END;
        INSERT INTO calama_plan_semanal_dias (
            plan_semanal_id, fecha, nombre_dia, orden, estado, observaciones
        ) VALUES (
            v_plan_semanal_id, v_fecha_jornada, v_nombre_dia, v_orden_dia,
            'confirmado', 'Dia sandbox MIG42'
        )
        RETURNING id INTO v_plan_dia_id;
    END IF;

    -- ─ PLAN_SEMANAL_OTS: la jornada de prueba ─
    INSERT INTO calama_plan_semanal_ots (
        plan_semanal_id, plan_dia_id, ot_id, zona_proyecto_id,
        responsable_id, prioridad, estado_plan,
        observaciones, created_by,
        es_prueba, excluida_estadisticas, motivo_prueba
    ) VALUES (
        v_plan_semanal_id, v_plan_dia_id, v_ot_id, v_zona_id,
        v_responsable_id, 0, 'liberada',
        'Jornada sandbox MIG42 - fotos, pausa, firma, offline.',
        v_user_id,
        true, true,
        'Sandbox app terreno (MIG42)'
    )
    RETURNING id INTO v_plan_ot_id;

    RETURN jsonb_build_object(
        'success', true,
        'ot_id', v_ot_id,
        'folio', v_folio,
        'plan_semanal_ot_id', v_plan_ot_id,
        'plan_semanal_id', v_plan_semanal_id,
        'plan_dia_id', v_plan_dia_id,
        'fecha_jornada', v_fecha_jornada,
        'responsable_id', v_responsable_id,
        'zona_id', v_zona_id,
        'planificacion_id', v_planificacion_id,
        'url_mobile', '/m/calama/ot/' || v_ot_id::text,
        'mensaje', 'Jornada de prueba creada. Esta OT es_prueba=true y NO afecta estadisticas reales.'
    );
END;
$$;

COMMENT ON FUNCTION rpc_calama_crear_jornada_prueba_terreno IS
'Crea OT/jornada de prueba en zona TEST de una planificacion. Todo marcado es_prueba=true, excluida_estadisticas=true. NO contamina reportes. MIG42 + fixes MIG42A (calama_faenas.activo y calama_zonas_proyecto sin descripcion/cliente_uuid).';

GRANT EXECUTE ON FUNCTION rpc_calama_crear_jornada_prueba_terreno TO authenticated;

NOTIFY pgrst, 'reload schema';
