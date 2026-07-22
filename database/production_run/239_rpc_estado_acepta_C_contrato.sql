-- ============================================================================
-- SICOM-ICEO | 239 — El cambio de estado manual acepta el código 'C' (Contrato)
-- ----------------------------------------------------------------------------
-- Bug (Manuel 2026-07-22): al abrir el modal "Cambiar Estado del Equipo" desde
-- Sugerencias para un equipo cuyo estado guardado es 'C' (Contrato = arriendo
-- de largo plazo), el modal precarga estadoInicial='C' y lo envía al RPC
-- rpc_actualizar_estado_diario_manual, que SOLO aceptaba
-- ('A','D','H','R','M','T','F','V','U','L') → lanzaba "Estado código inválido: C".
-- El frontend lo mostraba como el genérico "Error al actualizar estado",
-- bloqueando además el cambio de contrato del mismo flujo.
--
-- 'C' es un estado comercial legítimo (696 filas en estado_diario_flota; el
-- reporte de fiabilidad ya cuenta días 'A','C' como arriendo, y
-- rpc_confirmar_estado_dia ya mapea 'C' → arriendo_comercial). Se alinea el RPC
-- manual: 'C' se comporta como 'A' (operativo · arrendado · arriendo_comercial).
--
-- Además: RESINCRONIZA activos.cliente_actual desde el contrato vigente para
-- toda la flota (limpia valores basura tipo "contrato CM cenizas" que ensucian
-- el reporte de fiabilidad).
--
-- CREATE OR REPLACE idéntica a MIG 168 + el código 'C'. IDEMPOTENTE.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_actualizar_estado_diario_manual(
    p_activo_id        uuid,
    p_fecha            date,
    p_nuevo_estado     character,
    p_motivo           text,
    p_crear_ot         boolean DEFAULT false,
    p_ot_tipo          tipo_ot_enum DEFAULT NULL::tipo_ot_enum,
    p_ot_prioridad     prioridad_enum DEFAULT 'normal'::prioridad_enum,
    p_ot_responsable_id uuid DEFAULT NULL::uuid,
    p_ot_descripcion   text DEFAULT NULL::text,
    p_ubicacion        varchar DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_user_id            UUID;
    v_activo             RECORD;
    v_ot_id              UUID;
    v_ot_folio           VARCHAR(20);
    v_ot_estado_inicial  estado_ot_enum;
    v_ot_contrato_id     UUID;
    v_ot_faena_id        UUID;
    v_ot_error           TEXT;
    v_periodo            VARCHAR(6);
    v_secuencia          INTEGER;
    v_existente          UUID;
    v_nuevo_estado_act   estado_activo_enum;
    v_nuevo_estado_com   estado_comercial_enum;
    v_nueva_categoria    categoria_uso_enum;
BEGIN
    -- 1. AUTH
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'No autenticado.';
    END IF;

    -- 2. VALIDAR CÓDIGO  (NUEVO: 'C' = Contrato / arriendo de largo plazo)
    IF p_nuevo_estado NOT IN ('A','C','D','H','R','M','T','F','V','U','L') THEN
        RAISE EXCEPTION 'Estado código inválido: %', p_nuevo_estado;
    END IF;

    SELECT * INTO v_activo FROM activos WHERE id = p_activo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Activo % no existe', p_activo_id;
    END IF;

    -- 2b. LUGAR FÍSICO (texto libre) ANTES del cambio de estado.
    IF p_ubicacion IS NOT NULL AND length(trim(p_ubicacion)) > 0 THEN
        UPDATE activos SET ubicacion_actual = trim(p_ubicacion), updated_at = NOW()
         WHERE id = p_activo_id;
        v_activo.ubicacion_actual := trim(p_ubicacion);
    END IF;

    -- 3. CREAR OT AUTOMÁTICA (M, T, F)
    IF p_crear_ot AND p_nuevo_estado IN ('M','T','F') THEN
        IF p_ot_tipo IS NULL THEN
            p_ot_tipo := CASE
                WHEN p_nuevo_estado = 'T' THEN 'correctivo'
                WHEN p_nuevo_estado = 'F' THEN 'correctivo'
                ELSE 'preventivo'
            END;
        END IF;

        v_ot_contrato_id := COALESCE(v_activo.contrato_id, fn_contrato_interno_id());
        v_ot_faena_id    := COALESCE(v_activo.faena_id,    fn_faena_interna_id());

        v_ot_estado_inicial := CASE
            WHEN p_ot_responsable_id IS NOT NULL THEN 'asignada'::estado_ot_enum
            ELSE 'creada'::estado_ot_enum
        END;

        PERFORM pg_advisory_xact_lock(hashtext('ot_folio_lock'));

        v_periodo := TO_CHAR(NOW(), 'YYYYMM');
        SELECT COALESCE(MAX(
            CAST(SUBSTRING(folio FROM 11 FOR 5) AS INTEGER)
        ), 0) + 1
        INTO v_secuencia
        FROM ordenes_trabajo
        WHERE folio LIKE 'OT-' || v_periodo || '-%';

        v_ot_folio := 'OT-' || v_periodo || '-' || LPAD(v_secuencia::TEXT, 5, '0');

        BEGIN
            INSERT INTO ordenes_trabajo (
                folio, tipo, contrato_id, faena_id, activo_id,
                prioridad, estado, responsable_id,
                fecha_programada, observaciones,
                generada_automaticamente, created_by
            ) VALUES (
                v_ot_folio, p_ot_tipo,
                v_ot_contrato_id, v_ot_faena_id, p_activo_id,
                p_ot_prioridad, v_ot_estado_inicial, p_ot_responsable_id,
                p_fecha, COALESCE(p_ot_descripcion, p_motivo),
                true, v_user_id
            )
            RETURNING id INTO v_ot_id;
        EXCEPTION WHEN OTHERS THEN
            v_ot_error := SQLERRM;
            v_ot_id := NULL;
            v_ot_folio := NULL;
        END;
    END IF;

    -- 4. UPSERT estado_diario_flota
    SELECT id INTO v_existente
    FROM estado_diario_flota
    WHERE activo_id = p_activo_id AND fecha = p_fecha;

    IF v_existente IS NULL THEN
        INSERT INTO estado_diario_flota (
            activo_id, fecha, contrato_id, estado_codigo,
            cliente, ubicacion, operacion,
            override_manual, motivo_override, calculado_auto,
            actualizado_por, actualizado_at,
            ot_relacionada_id, observacion, registrado_por
        ) VALUES (
            p_activo_id, p_fecha, v_activo.contrato_id, p_nuevo_estado,
            v_activo.cliente_actual, v_activo.ubicacion_actual, v_activo.operacion,
            true, p_motivo, false,
            v_user_id, NOW(),
            v_ot_id, p_motivo, v_user_id
        );
    ELSE
        UPDATE estado_diario_flota
        SET estado_codigo     = p_nuevo_estado,
            ubicacion         = COALESCE(v_activo.ubicacion_actual, ubicacion),
            override_manual   = true,
            motivo_override   = p_motivo,
            actualizado_por   = v_user_id,
            actualizado_at    = NOW(),
            ot_relacionada_id = COALESCE(v_ot_id, ot_relacionada_id),
            observacion       = p_motivo,
            updated_at        = NOW()
        WHERE id = v_existente;
    END IF;

    -- 5. SINCRONIZAR activos.estado + estado_comercial + categoria_uso
    v_nuevo_estado_act := CASE p_nuevo_estado
        WHEN 'M' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'T' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'H' THEN 'en_mantenimiento'::estado_activo_enum
        WHEN 'F' THEN 'fuera_servicio'::estado_activo_enum
        ELSE        'operativo'::estado_activo_enum
    END;

    v_nuevo_estado_com := CASE p_nuevo_estado
        WHEN 'A' THEN 'arrendado'::estado_comercial_enum
        WHEN 'C' THEN 'arrendado'::estado_comercial_enum   -- NUEVO: Contrato = arrendado
        WHEN 'D' THEN 'disponible'::estado_comercial_enum
        WHEN 'U' THEN 'uso_interno'::estado_comercial_enum
        WHEN 'L' THEN 'leasing'::estado_comercial_enum
        WHEN 'R' THEN 'en_recepcion'::estado_comercial_enum
        WHEN 'V' THEN 'en_venta'::estado_comercial_enum
        WHEN 'H' THEN NULL
        ELSE v_activo.estado_comercial
    END;

    -- Categoría comercial. Solo estados comerciales la definen; los transitorios
    -- (D,H,R,M,T,F) la dejan como está.
    v_nueva_categoria := CASE p_nuevo_estado
        WHEN 'A' THEN 'arriendo_comercial'::categoria_uso_enum
        WHEN 'C' THEN 'arriendo_comercial'::categoria_uso_enum   -- NUEVO
        WHEN 'L' THEN 'leasing_operativo'::categoria_uso_enum
        WHEN 'U' THEN 'uso_interno'::categoria_uso_enum
        WHEN 'V' THEN 'venta'::categoria_uso_enum
        ELSE NULL
    END;

    UPDATE activos
    SET estado           = v_nuevo_estado_act,
        estado_comercial = v_nuevo_estado_com,
        categoria_uso    = COALESCE(v_nueva_categoria, categoria_uso),
        updated_at       = NOW()
    WHERE id = p_activo_id;

    -- 6. NO CONFORMIDAD F+arrendado (protegida)
    IF p_nuevo_estado = 'F' AND v_activo.estado_comercial = 'arrendado' THEN
        BEGIN
            INSERT INTO no_conformidades (
                activo_id, fecha_evento, tipo, severidad, descripcion, created_by
            ) VALUES (
                p_activo_id, p_fecha, 'falla_en_terreno', 'alta',
                'Equipo arrendado pasa a fuera de servicio: ' || COALESCE(p_motivo,'sin motivo'),
                v_user_id
            )
            ON CONFLICT DO NOTHING;
        EXCEPTION WHEN OTHERS THEN NULL;
        END;
    END IF;

    -- 7. RESULTADO
    RETURN jsonb_build_object(
        'success',           true,
        'estado_aplicado',   p_nuevo_estado,
        'activo_estado',     v_nuevo_estado_act,
        'activo_comercial',  v_nuevo_estado_com,
        'activo_categoria',  COALESCE(v_nueva_categoria, v_activo.categoria_uso),
        'ot_creada',         v_ot_id IS NOT NULL,
        'ot_id',             v_ot_id,
        'ot_folio',          v_ot_folio,
        'ot_estado_inicial', v_ot_estado_inicial,
        'ot_error',          v_ot_error
    );
END;
$function$;


-- ── Limpieza de datos: cliente_actual desde el contrato vigente ──────────────
-- Corrige valores basura/desactualizados (ej. "contrato CM cenizas") para que
-- el reporte de fiabilidad muestre el cliente real de cada equipo.
WITH corregidos AS (
    UPDATE activos a
       SET cliente_actual = c.cliente, updated_at = NOW()
      FROM contratos c
     WHERE a.contrato_id = c.id
       AND a.cliente_actual IS DISTINCT FROM c.cliente
       AND a.estado <> 'dado_baja'
    RETURNING a.id
)
SELECT count(*) AS clientes_resincronizados FROM corregidos;


-- ── VALIDACIÓN: el RPC ahora acepta 'C' (repro en rollback) ─────────────────
DO $$
DECLARE v_activo UUID; v_user UUID; v_res JSONB;
BEGIN
    SELECT id INTO v_activo FROM activos
     WHERE estado_comercial = 'arrendado' AND estado <> 'dado_baja' LIMIT 1;
    SELECT id INTO v_user FROM usuarios_perfil ORDER BY created_at LIMIT 1;
    IF v_activo IS NULL OR v_user IS NULL THEN
        RAISE NOTICE 'Sin datos para smoke test (ok en entorno vacío)'; RETURN;
    END IF;
    PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_user, 'role','authenticated')::text, true);
    BEGIN
        v_res := public.rpc_actualizar_estado_diario_manual(
            v_activo, CURRENT_DATE, 'C', 'MIG239 smoke test');
        IF (v_res->>'success')::boolean THEN
            RAISE NOTICE 'MIG239 OK: RPC acepta C · estado_com=% · categoria=%',
                v_res->>'activo_comercial', v_res->>'activo_categoria';
        ELSE
            RAISE EXCEPTION 'FALLO: el RPC no devolvió success con C';
        END IF;
        -- No commitear el smoke test
        RAISE EXCEPTION 'rollback-smoke-test';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM = 'rollback-smoke-test' THEN
                RAISE NOTICE 'Smoke test C revertido (esperado)';
            ELSE
                RAISE EXCEPTION 'MIG239 FALLO smoke C: %', SQLERRM;
            END IF;
    END;
END $$;

NOTIFY pgrst, 'reload schema';
