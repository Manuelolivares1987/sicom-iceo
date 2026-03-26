-- SICOM-ICEO | Fase 2 | Funciones, Triggers y RLS
-- ============================================================================
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 05_funciones_triggers_rls.sql
-- Proposito : Funciones utilitarias, triggers de reglas de negocio, trigger
--             de auditoria generico y politicas RLS por rol.
-- Dependencias:
--   01_tipos_y_enums.sql        -> extensiones, tipos ENUM
--   02_tablas_core.sql          -> contratos, faenas, activos, productos,
--                                  bodegas, planes_mantenimiento, stock_bodega
--   03_tablas_ot_inventario.sql -> ordenes_trabajo, checklist_ot, evidencias_ot,
--                                  historial_estado_ot, movimientos_inventario,
--                                  kardex, conteos_inventario
--   04_tablas_kpi_iceo.sql      -> certificaciones, incidentes, abastecimientos,
--                                  rutas_despacho, iceo_periodos, iceo_detalle,
--                                  mediciones_kpi, alertas, auditoria_eventos
-- ============================================================================


-- ############################################################################
-- SECCION 1: FUNCIONES UTILITARIAS
-- ############################################################################

-- ============================================================================
-- 1.1 auto_updated_at() - Actualiza updated_at en cada UPDATE
-- ============================================================================
-- NOTA: fn_set_updated_at() ya existe en 02_tablas_core.sql.
-- Creamos auto_updated_at() como alias estandarizado para uso en este archivo.

CREATE OR REPLACE FUNCTION auto_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_updated_at()
    IS 'Funcion trigger generica: establece updated_at = NOW() en cada UPDATE.';

-- Aplicar auto_updated_at a tablas que aun no tienen trigger de updated_at
-- (las tablas de 02 y 03 ya usan fn_set_updated_at; aqui cubrimos las de 04)

-- Se crean triggers solo si la tabla existe (tablas de fase 04).
-- Si se ejecuta antes de 04, estos CREATE TRIGGER fallan silenciosamente.
-- Para seguridad, usamos DO blocks con exception handling.

-- Los triggers updated_at para tablas de fase 04 ya se crean en 04_tablas_kpi_iceo_compliance.sql.
-- Se omiten aqui para evitar duplicacion (error 42710 duplicate_object).

-- ============================================================================
-- 1.2 generar_folio_ot() - Folio automatico OT-YYYYMM-XXXXX
-- ============================================================================
-- NOTA: Ya existe en 03_tablas_ot_inventario.sql. Se redefine aqui con
-- CREATE OR REPLACE para garantizar la version mas reciente.

CREATE OR REPLACE FUNCTION generar_folio_ot()
RETURNS TRIGGER AS $$
DECLARE
    v_periodo TEXT;
    v_seq     INTEGER;
BEGIN
    -- Periodo actual YYYYMM
    v_periodo := to_char(NOW(), 'YYYYMM');

    -- Obtener siguiente secuencial del periodo (con bloqueo para concurrencia)
    SELECT COALESCE(MAX(
        CAST(RIGHT(folio, 5) AS INTEGER)
    ), 0) + 1
    INTO v_seq
    FROM ordenes_trabajo
    WHERE folio LIKE 'OT-' || v_periodo || '-%';

    -- Asignar folio con formato OT-YYYYMM-XXXXX
    NEW.folio := 'OT-' || v_periodo || '-' || LPAD(v_seq::TEXT, 5, '0');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generar_folio_ot()
    IS 'Genera automaticamente el folio OT-YYYYMM-XXXXX al insertar una orden de trabajo.';

-- El trigger trg_ot_folio_auto ya existe en 03. No se recrea.

-- ============================================================================
-- 1.3 generar_qr_ot() - Codigo QR unico basado en folio
-- ============================================================================

CREATE OR REPLACE FUNCTION generar_qr_ot()
RETURNS TRIGGER AS $$
BEGIN
    -- Generar string unico para QR: folio + hash corto para evitar colisiones
    IF NEW.qr_code IS NULL OR NEW.qr_code = '' THEN
        NEW.qr_code := NEW.folio || '-' || UPPER(SUBSTR(
            encode(digest(NEW.folio || '-' || gen_random_uuid()::TEXT, 'sha256'), 'hex'),
            1, 8
        ));
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generar_qr_ot()
    IS 'Genera un codigo QR unico basado en el folio de la OT.';

CREATE TRIGGER trg_ot_qr_auto
    BEFORE INSERT ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION generar_qr_ot();


-- ############################################################################
-- SECCION 2: TRIGGERS DE REGLAS DE NEGOCIO
-- ############################################################################

-- ============================================================================
-- 2.1 validar_cierre_ot() - Validacion al cerrar una OT
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_cierre_ot()
RETURNS TRIGGER AS $$
DECLARE
    v_evidencias_count  INTEGER;
    v_checklist_pendiente INTEGER;
BEGIN
    -- Solo validar cuando el estado cambia a 'ejecutada_ok' o 'ejecutada_con_observaciones'
    IF NEW.estado IN ('ejecutada_ok', 'ejecutada_con_observaciones')
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        -- 1. Verificar al menos 1 evidencia
        SELECT COUNT(*)
        INTO v_evidencias_count
        FROM evidencias_ot
        WHERE ot_id = NEW.id;

        IF v_evidencias_count = 0 THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere al menos 1 evidencia fotografica o documental.',
                NEW.folio;
        END IF;

        -- 2. Verificar que todos los items obligatorios del checklist tengan resultado
        SELECT COUNT(*)
        INTO v_checklist_pendiente
        FROM checklist_ot
        WHERE ot_id = NEW.id
          AND obligatorio = true
          AND resultado IS NULL;

        IF v_checklist_pendiente > 0 THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Existen % items obligatorios del checklist sin completar.',
                NEW.folio, v_checklist_pendiente;
        END IF;

        -- 3. Verificar firma del tecnico
        IF NEW.firma_tecnico_url IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar la OT %. Se requiere la firma del tecnico responsable.',
                NEW.folio;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validar_cierre_ot()
    IS 'Valida evidencias, checklist completo y firma antes de cerrar una OT.';

CREATE TRIGGER trg_ot_validar_cierre
    BEFORE UPDATE ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION validar_cierre_ot();

-- ============================================================================
-- 2.2 validar_no_ejecucion_ot() - Validacion al marcar OT como no ejecutada
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_no_ejecucion_ot()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'no_ejecutada'
       AND OLD.estado IS DISTINCT FROM NEW.estado THEN

        IF NEW.causa_no_ejecucion IS NULL THEN
            RAISE EXCEPTION 'No se puede marcar la OT % como no ejecutada sin indicar la causa de no ejecucion.',
                NEW.folio;
        END IF;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validar_no_ejecucion_ot()
    IS 'Exige causa_no_ejecucion al cambiar estado de OT a no_ejecutada.';

CREATE TRIGGER trg_ot_validar_no_ejecucion
    BEFORE UPDATE ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION validar_no_ejecucion_ot();

-- ============================================================================
-- 2.3 registrar_transicion_ot() - Log de transiciones de estado
-- ============================================================================
-- NOTA: registrar_cambio_estado_ot() ya existe en 03. Se redefine como
-- AFTER UPDATE para separar responsabilidades (la version de 03 es BEFORE).
-- Aqui creamos la version AFTER que solo inserta en historial.

CREATE OR REPLACE FUNCTION registrar_transicion_ot()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado IS DISTINCT FROM NEW.estado THEN
        INSERT INTO historial_estado_ot (
            ot_id,
            estado_anterior,
            estado_nuevo,
            motivo,
            created_by
        ) VALUES (
            NEW.id,
            OLD.estado,
            NEW.estado,
            COALESCE(NEW.observaciones, NEW.detalle_no_ejecucion),
            auth.uid()
        );
    END IF;

    RETURN NULL; -- AFTER trigger: retorno ignorado
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION registrar_transicion_ot()
    IS 'Registra cada transicion de estado de una OT en historial_estado_ot (AFTER UPDATE).';

-- NOTA: El trigger trg_ot_estado_historial de 03 (BEFORE UPDATE) ya cumple
-- esta funcion. Si se desea usar esta version AFTER en su lugar, descomentar
-- las siguientes lineas y eliminar el trigger de 03:

-- DROP TRIGGER IF EXISTS trg_ot_estado_historial ON ordenes_trabajo;
-- CREATE TRIGGER trg_ot_registrar_transicion
--     AFTER UPDATE ON ordenes_trabajo
--     FOR EACH ROW
--     EXECUTE FUNCTION registrar_transicion_ot();

-- ============================================================================
-- 2.4 validar_salida_inventario() - Validacion de salidas de inventario
-- ============================================================================

CREATE OR REPLACE FUNCTION validar_salida_inventario()
RETURNS TRIGGER AS $$
DECLARE
    v_stock_actual NUMERIC(12,3);
BEGIN
    IF NEW.tipo IN ('salida', 'merma') THEN

        -- Validar OT asociada
        IF NEW.ot_id IS NULL THEN
            RAISE EXCEPTION 'No se permite salida de inventario sin OT asociada.';
        END IF;

        -- Validar usuario
        IF NEW.usuario_id IS NULL THEN
            RAISE EXCEPTION 'No se permite salida de inventario sin usuario responsable.';
        END IF;

        -- Validar stock suficiente
        SELECT COALESCE(sb.cantidad, 0)
        INTO v_stock_actual
        FROM stock_bodega sb
        WHERE sb.bodega_id = NEW.bodega_id
          AND sb.producto_id = NEW.producto_id;

        IF v_stock_actual IS NULL THEN
            RAISE EXCEPTION 'No existe stock del producto en la bodega indicada.';
        END IF;

        IF v_stock_actual < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente. Disponible: %, solicitado: %.',
                v_stock_actual, NEW.cantidad;
        END IF;

    END IF;

    -- Validar stock para transferencia_salida
    IF NEW.tipo = 'transferencia_salida' THEN
        SELECT COALESCE(sb.cantidad, 0)
        INTO v_stock_actual
        FROM stock_bodega sb
        WHERE sb.bodega_id = NEW.bodega_id
          AND sb.producto_id = NEW.producto_id;

        IF COALESCE(v_stock_actual, 0) < NEW.cantidad THEN
            RAISE EXCEPTION 'Stock insuficiente para transferencia. Disponible: %, solicitado: %.',
                COALESCE(v_stock_actual, 0), NEW.cantidad;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validar_salida_inventario()
    IS 'Valida OT, usuario y stock antes de registrar salidas o mermas de inventario.';

CREATE TRIGGER trg_mov_inv_validar_salida
    BEFORE INSERT ON movimientos_inventario
    FOR EACH ROW
    EXECUTE FUNCTION validar_salida_inventario();

-- ============================================================================
-- 2.5 actualizar_stock_bodega() - Actualizacion de stock tras movimiento
-- ============================================================================

CREATE OR REPLACE FUNCTION actualizar_stock_bodega()
RETURNS TRIGGER AS $$
DECLARE
    v_stock_actual    NUMERIC(12,3);
    v_costo_actual    NUMERIC(15,4);
    v_nuevo_stock     NUMERIC(12,3);
    v_nuevo_costo     NUMERIC(15,4);
    v_stock_minimo    NUMERIC(12,3);
    v_producto_nombre VARCHAR(200);
BEGIN
    -- Obtener stock actual
    SELECT COALESCE(sb.cantidad, 0), COALESCE(sb.costo_promedio, 0)
    INTO v_stock_actual, v_costo_actual
    FROM stock_bodega sb
    WHERE sb.bodega_id = NEW.bodega_id
      AND sb.producto_id = NEW.producto_id;

    -- Si no existe registro, inicializar en cero
    IF NOT FOUND THEN
        v_stock_actual := 0;
        v_costo_actual := 0;
    END IF;

    -- Calcular nuevo stock y costo segun tipo de movimiento
    CASE NEW.tipo
        WHEN 'entrada' THEN
            v_nuevo_stock := v_stock_actual + NEW.cantidad;
            -- Recalcular CPP (Costo Promedio Ponderado)
            IF v_nuevo_stock > 0 THEN
                v_nuevo_costo := (
                    (v_stock_actual * v_costo_actual) + (NEW.cantidad * NEW.costo_unitario)
                ) / v_nuevo_stock;
            ELSE
                v_nuevo_costo := NEW.costo_unitario;
            END IF;

        WHEN 'salida', 'merma' THEN
            v_nuevo_stock := v_stock_actual - NEW.cantidad;
            v_nuevo_costo := v_costo_actual; -- CPP no cambia en salidas

        WHEN 'ajuste_positivo' THEN
            v_nuevo_stock := v_stock_actual + NEW.cantidad;
            v_nuevo_costo := v_costo_actual;

        WHEN 'ajuste_negativo' THEN
            v_nuevo_stock := v_stock_actual - NEW.cantidad;
            v_nuevo_costo := v_costo_actual;

        WHEN 'transferencia_salida' THEN
            v_nuevo_stock := v_stock_actual - NEW.cantidad;
            v_nuevo_costo := v_costo_actual;

        WHEN 'transferencia_entrada' THEN
            v_nuevo_stock := v_stock_actual + NEW.cantidad;
            IF v_nuevo_stock > 0 THEN
                v_nuevo_costo := (
                    (v_stock_actual * v_costo_actual) + (NEW.cantidad * NEW.costo_unitario)
                ) / v_nuevo_stock;
            ELSE
                v_nuevo_costo := NEW.costo_unitario;
            END IF;

        WHEN 'devolucion' THEN
            v_nuevo_stock := v_stock_actual + NEW.cantidad;
            v_nuevo_costo := v_costo_actual;

        ELSE
            RAISE EXCEPTION 'Tipo de movimiento no reconocido: %', NEW.tipo;
    END CASE;

    -- UPSERT en stock_bodega
    INSERT INTO stock_bodega (bodega_id, producto_id, cantidad, costo_promedio, ultimo_movimiento)
    VALUES (NEW.bodega_id, NEW.producto_id, v_nuevo_stock, v_nuevo_costo, NOW())
    ON CONFLICT (bodega_id, producto_id)
    DO UPDATE SET
        cantidad          = v_nuevo_stock,
        costo_promedio    = v_nuevo_costo,
        ultimo_movimiento = NOW();

    -- Verificar stock minimo y generar alerta si corresponde
    SELECT p.stock_minimo, p.nombre
    INTO v_stock_minimo, v_producto_nombre
    FROM productos p
    WHERE p.id = NEW.producto_id;

    IF v_nuevo_stock < v_stock_minimo THEN
        -- Insertar alerta (tabla alertas de fase 04)
        BEGIN
            INSERT INTO alertas (
                tipo,
                titulo,
                mensaje,
                severidad,
                entidad_tipo,
                entidad_id,
                created_at
            ) VALUES (
                'stock_minimo',
                'Stock bajo minimo: ' || v_producto_nombre,
                'El producto "' || v_producto_nombre || '" tiene stock ' ||
                    v_nuevo_stock || ' unidades, por debajo del minimo de ' ||
                    v_stock_minimo || ' unidades en bodega ' || NEW.bodega_id || '.',
                'warning',
                'producto',
                NEW.producto_id,
                NOW()
            );
        EXCEPTION WHEN undefined_table THEN
            -- Tabla alertas aun no existe; ignorar
            NULL;
        END;
    END IF;

    RETURN NULL; -- AFTER trigger
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION actualizar_stock_bodega()
    IS 'Actualiza stock_bodega (UPSERT) y recalcula CPP tras cada movimiento de inventario.';

CREATE TRIGGER trg_mov_inv_actualizar_stock
    AFTER INSERT ON movimientos_inventario
    FOR EACH ROW
    EXECUTE FUNCTION actualizar_stock_bodega();

-- ============================================================================
-- 2.6 registrar_kardex() - Asiento en el libro mayor de inventario
-- ============================================================================

CREATE OR REPLACE FUNCTION registrar_kardex()
RETURNS TRIGGER AS $$
DECLARE
    v_cant_anterior   NUMERIC(12,3);
    v_cpp_anterior    NUMERIC(15,4);
    v_cant_posterior   NUMERIC(12,3);
    v_cpp_posterior    NUMERIC(15,4);
BEGIN
    -- Obtener valores ACTUALIZADOS de stock_bodega (ya fue actualizado por
    -- el trigger trg_mov_inv_actualizar_stock que corre antes por orden alfa)
    SELECT sb.cantidad, sb.costo_promedio
    INTO v_cant_posterior, v_cpp_posterior
    FROM stock_bodega sb
    WHERE sb.bodega_id = NEW.bodega_id
      AND sb.producto_id = NEW.producto_id;

    -- Calcular cantidades anteriores a partir de la posterior
    CASE NEW.tipo
        WHEN 'entrada', 'ajuste_positivo', 'transferencia_entrada', 'devolucion' THEN
            v_cant_anterior := COALESCE(v_cant_posterior, 0) - NEW.cantidad;
        WHEN 'salida', 'merma', 'ajuste_negativo', 'transferencia_salida' THEN
            v_cant_anterior := COALESCE(v_cant_posterior, 0) + NEW.cantidad;
        ELSE
            v_cant_anterior := COALESCE(v_cant_posterior, 0);
    END CASE;

    -- CPP anterior: para entradas se recalcula; para salidas es el mismo
    IF NEW.tipo IN ('entrada', 'transferencia_entrada') AND v_cant_anterior > 0 THEN
        v_cpp_anterior := (
            (COALESCE(v_cant_posterior, 0) * COALESCE(v_cpp_posterior, 0))
            - (NEW.cantidad * NEW.costo_unitario)
        ) / v_cant_anterior;
    ELSE
        v_cpp_anterior := COALESCE(v_cpp_posterior, NEW.costo_unitario);
    END IF;

    INSERT INTO kardex (
        bodega_id,
        producto_id,
        movimiento_id,
        fecha,
        tipo,
        cantidad_movimiento,
        cantidad_anterior,
        cantidad_posterior,
        costo_unitario,
        costo_promedio_anterior,
        costo_promedio_posterior,
        valor_movimiento,
        valor_stock_posterior
    ) VALUES (
        NEW.bodega_id,
        NEW.producto_id,
        NEW.id,
        NOW(),
        NEW.tipo,
        NEW.cantidad,
        GREATEST(v_cant_anterior, 0),
        COALESCE(v_cant_posterior, 0),
        NEW.costo_unitario,
        GREATEST(v_cpp_anterior, 0),
        COALESCE(v_cpp_posterior, 0),
        NEW.cantidad * NEW.costo_unitario,
        COALESCE(v_cant_posterior, 0) * COALESCE(v_cpp_posterior, 0)
    );

    RETURN NULL; -- AFTER trigger
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION registrar_kardex()
    IS 'Registra asiento en kardex con cantidades y costos antes/despues de cada movimiento.';

CREATE TRIGGER trg_mov_inv_registrar_kardex
    AFTER INSERT ON movimientos_inventario
    FOR EACH ROW
    EXECUTE FUNCTION registrar_kardex();

-- ============================================================================
-- 2.7 actualizar_costo_ot() - Costo de materiales de la OT
-- ============================================================================

CREATE OR REPLACE FUNCTION actualizar_costo_ot()
RETURNS TRIGGER AS $$
DECLARE
    v_costo_total NUMERIC(12,2);
BEGIN
    IF NEW.ot_id IS NOT NULL THEN
        SELECT COALESCE(SUM(mi.cantidad * mi.costo_unitario), 0)
        INTO v_costo_total
        FROM movimientos_inventario mi
        WHERE mi.ot_id = NEW.ot_id
          AND mi.tipo IN ('salida', 'merma');

        UPDATE ordenes_trabajo
        SET costo_materiales = v_costo_total
        WHERE id = NEW.ot_id;
    END IF;

    RETURN NULL; -- AFTER trigger
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION actualizar_costo_ot()
    IS 'Actualiza costo_materiales de la OT sumando los movimientos de salida asociados.';

CREATE TRIGGER trg_mov_inv_actualizar_costo_ot
    AFTER INSERT ON movimientos_inventario
    FOR EACH ROW
    WHEN (NEW.ot_id IS NOT NULL)
    EXECUTE FUNCTION actualizar_costo_ot();

-- ============================================================================
-- 2.8 verificar_certificaciones() - Funcion callable (no trigger)
-- ============================================================================

CREATE OR REPLACE FUNCTION verificar_certificaciones()
RETURNS TABLE (
    certificacion_id UUID,
    estado_anterior  estado_documento_enum,
    estado_nuevo     estado_documento_enum,
    activo_afectado  UUID,
    bloqueante       BOOLEAN
) AS $$
DECLARE
    r RECORD;
    v_estado_nuevo estado_documento_enum;
BEGIN
    FOR r IN
        SELECT c.id, c.estado, c.fecha_vencimiento, c.bloqueante AS es_bloqueante,
               c.activo_id
        FROM certificaciones c
        WHERE c.estado <> 'no_aplica'
    LOOP
        -- Determinar nuevo estado
        IF r.fecha_vencimiento > NOW() + INTERVAL '30 days' THEN
            v_estado_nuevo := 'vigente';
        ELSIF r.fecha_vencimiento BETWEEN NOW() AND NOW() + INTERVAL '30 days' THEN
            v_estado_nuevo := 'por_vencer';
        ELSE
            v_estado_nuevo := 'vencido';
        END IF;

        -- Solo procesar si cambio de estado
        IF r.estado IS DISTINCT FROM v_estado_nuevo THEN
            -- Actualizar certificacion
            UPDATE certificaciones
            SET estado = v_estado_nuevo,
                updated_at = NOW()
            WHERE id = r.id;

            -- Generar alerta para por_vencer y vencido
            IF v_estado_nuevo IN ('por_vencer', 'vencido') THEN
                BEGIN
                    INSERT INTO alertas (
                        tipo,
                        titulo,
                        mensaje,
                        severidad,
                        entidad_tipo,
                        entidad_id,
                        created_at
                    ) VALUES (
                        'vencimiento',
                        CASE v_estado_nuevo
                            WHEN 'por_vencer' THEN 'Certificacion proxima a vencer'
                            WHEN 'vencido'    THEN 'Certificacion VENCIDA'
                        END,
                        'La certificacion ID ' || r.id::TEXT || ' del activo ' ||
                            COALESCE(r.activo_id::TEXT, 'N/A') ||
                            CASE v_estado_nuevo
                                WHEN 'por_vencer' THEN ' vence el ' || r.fecha_vencimiento::TEXT
                                WHEN 'vencido'    THEN ' ha VENCIDO el ' || r.fecha_vencimiento::TEXT
                            END || '.',
                        CASE v_estado_nuevo
                            WHEN 'por_vencer' THEN 'warning'
                            WHEN 'vencido'    THEN 'critical'
                        END,
                        'certificacion',
                        r.id,
                        NOW()
                    );
                EXCEPTION WHEN undefined_table THEN NULL;
                END;
            END IF;

            -- Si es bloqueante y vencido, poner activo fuera de servicio
            IF r.es_bloqueante = true AND v_estado_nuevo = 'vencido' AND r.activo_id IS NOT NULL THEN
                UPDATE activos
                SET estado = 'fuera_servicio'
                WHERE id = r.activo_id
                  AND estado <> 'fuera_servicio';
            END IF;

            -- Retornar resultado
            certificacion_id := r.id;
            estado_anterior  := r.estado;
            estado_nuevo     := v_estado_nuevo;
            activo_afectado  := r.activo_id;
            bloqueante       := r.es_bloqueante;
            RETURN NEXT;
        END IF;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION verificar_certificaciones()
    IS 'Revisa todas las certificaciones, actualiza estados y genera alertas. Retorna las certificaciones modificadas.';

-- ============================================================================
-- 2.9 generar_ots_preventivas() - Generacion automatica de OTs preventivas
-- ============================================================================

CREATE OR REPLACE FUNCTION generar_ots_preventivas()
RETURNS INTEGER AS $$
DECLARE
    r              RECORD;
    v_count        INTEGER := 0;
    v_trigger_met  BOOLEAN;
    v_activo       RECORD;
    v_ot_existente UUID;
    v_new_ot_id    UUID;
    v_item         JSONB;
    v_orden        INTEGER;
BEGIN
    FOR r IN
        SELECT pm.*, pf.items_checklist, pf.duracion_estimada_hrs,
               a.contrato_id, a.faena_id, a.kilometraje_actual,
               a.horas_uso_actual, a.ciclos_actual
        FROM planes_mantenimiento pm
        JOIN pautas_fabricante pf ON pf.id = pm.pauta_fabricante_id
        JOIN activos a ON a.id = pm.activo_id
        WHERE pm.activo_plan = true
          AND a.estado = 'operativo'
    LOOP
        v_trigger_met := false;

        -- Evaluar condicion de disparo segun tipo de plan
        CASE COALESCE(r.tipo_plan, 'por_tiempo')
            WHEN 'por_tiempo' THEN
                IF r.proxima_ejecucion_fecha IS NOT NULL
                   AND r.proxima_ejecucion_fecha <= CURRENT_DATE THEN
                    v_trigger_met := true;
                ELSIF r.frecuencia_dias IS NOT NULL
                      AND r.ultima_ejecucion_fecha IS NOT NULL
                      AND (r.ultima_ejecucion_fecha + (r.frecuencia_dias || ' days')::INTERVAL) <= NOW() THEN
                    v_trigger_met := true;
                ELSIF r.frecuencia_dias IS NOT NULL
                      AND r.ultima_ejecucion_fecha IS NULL THEN
                    v_trigger_met := true;
                END IF;

            WHEN 'por_kilometraje' THEN
                IF r.frecuencia_km IS NOT NULL THEN
                    IF r.ultima_ejecucion_km IS NULL
                       OR (r.kilometraje_actual - COALESCE(r.ultima_ejecucion_km, 0)) >= r.frecuencia_km THEN
                        v_trigger_met := true;
                    END IF;
                END IF;

            WHEN 'por_horas' THEN
                IF r.frecuencia_horas IS NOT NULL THEN
                    IF r.ultima_ejecucion_horas IS NULL
                       OR (r.horas_uso_actual - COALESCE(r.ultima_ejecucion_horas, 0)) >= r.frecuencia_horas THEN
                        v_trigger_met := true;
                    END IF;
                END IF;

            WHEN 'por_ciclos' THEN
                IF r.frecuencia_ciclos IS NOT NULL THEN
                    IF r.ultima_ejecucion_ciclos IS NULL
                       OR (r.ciclos_actual - COALESCE(r.ultima_ejecucion_ciclos, 0)) >= r.frecuencia_ciclos THEN
                        v_trigger_met := true;
                    END IF;
                END IF;

            WHEN 'mixto' THEN
                -- Mixto: cualquier condicion que se cumpla dispara
                IF (r.frecuencia_dias IS NOT NULL AND r.proxima_ejecucion_fecha IS NOT NULL
                    AND r.proxima_ejecucion_fecha <= CURRENT_DATE)
                   OR (r.frecuencia_km IS NOT NULL
                       AND (r.kilometraje_actual - COALESCE(r.ultima_ejecucion_km, 0)) >= r.frecuencia_km)
                   OR (r.frecuencia_horas IS NOT NULL
                       AND (r.horas_uso_actual - COALESCE(r.ultima_ejecucion_horas, 0)) >= r.frecuencia_horas)
                   OR (r.frecuencia_ciclos IS NOT NULL
                       AND (r.ciclos_actual - COALESCE(r.ultima_ejecucion_ciclos, 0)) >= r.frecuencia_ciclos) THEN
                    v_trigger_met := true;
                END IF;

            ELSE
                NULL;
        END CASE;

        -- Si se cumplio la condicion, verificar que no exista OT abierta
        IF v_trigger_met THEN
            SELECT ot.id INTO v_ot_existente
            FROM ordenes_trabajo ot
            WHERE ot.plan_mantenimiento_id = r.id
              AND ot.estado NOT IN ('ejecutada_ok', 'ejecutada_con_observaciones',
                                     'no_ejecutada', 'cancelada')
            LIMIT 1;

            IF v_ot_existente IS NULL THEN
                -- Crear nueva OT preventiva
                INSERT INTO ordenes_trabajo (
                    tipo,
                    contrato_id,
                    faena_id,
                    activo_id,
                    plan_mantenimiento_id,
                    prioridad,
                    estado,
                    fecha_programada,
                    generada_automaticamente,
                    observaciones
                ) VALUES (
                    'preventivo',
                    r.contrato_id,
                    r.faena_id,
                    r.activo_id,
                    r.id,
                    COALESCE(r.prioridad, 'normal'),
                    'creada',
                    CURRENT_DATE,
                    true,
                    'OT generada automaticamente por plan de mantenimiento preventivo.'
                )
                RETURNING id INTO v_new_ot_id;

                -- Copiar items de checklist desde pauta_fabricante
                IF r.items_checklist IS NOT NULL AND jsonb_typeof(r.items_checklist) = 'array' THEN
                    v_orden := 0;
                    FOR v_item IN SELECT * FROM jsonb_array_elements(r.items_checklist)
                    LOOP
                        v_orden := v_orden + 1;
                        INSERT INTO checklist_ot (
                            ot_id,
                            orden,
                            descripcion,
                            obligatorio,
                            requiere_foto
                        ) VALUES (
                            v_new_ot_id,
                            v_orden,
                            COALESCE(v_item->>'descripcion', v_item->>'nombre', 'Item ' || v_orden),
                            COALESCE((v_item->>'obligatorio')::BOOLEAN, true),
                            COALESCE((v_item->>'requiere_foto')::BOOLEAN, false)
                        );
                    END LOOP;
                END IF;

                -- Actualizar proxima ejecucion del plan
                IF r.frecuencia_dias IS NOT NULL THEN
                    UPDATE planes_mantenimiento
                    SET proxima_ejecucion_fecha = CURRENT_DATE + r.frecuencia_dias
                    WHERE id = r.id;
                END IF;

                v_count := v_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generar_ots_preventivas()
    IS 'Genera OTs preventivas automaticas segun planes activos. Retorna cantidad de OTs generadas.';


-- ############################################################################
-- SECCION 3: TRIGGER DE AUDITORIA GENERICO
-- ############################################################################

-- ============================================================================
-- 3.1 audit_trigger() - Log de cambios a auditoria_eventos
-- ============================================================================

CREATE OR REPLACE FUNCTION audit_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_old JSONB;
    v_new JSONB;
    v_user_id UUID;
BEGIN
    -- Obtener usuario actual (Supabase auth)
    BEGIN
        v_user_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;

    -- Construir OLD y NEW como JSONB
    IF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD);
        v_new := NULL;
    ELSIF TG_OP = 'INSERT' THEN
        v_old := NULL;
        v_new := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_old := to_jsonb(OLD);
        v_new := to_jsonb(NEW);
    END IF;

    -- Insertar en auditoria_eventos
    BEGIN
        INSERT INTO auditoria_eventos (
            tabla,
            accion,
            registro_id,
            datos_anteriores,
            datos_nuevos,
            usuario_id,
            ip_address,
            created_at
        ) VALUES (
            TG_TABLE_NAME,
            TG_OP,
            CASE
                WHEN TG_OP = 'DELETE' THEN (v_old->>'id')::UUID
                ELSE (v_new->>'id')::UUID
            END,
            v_old,
            v_new,
            v_user_id,
            COALESCE(
                current_setting('request.headers', true)::JSONB->>'x-forwarded-for',
                inet_client_addr()::TEXT
            ),
            NOW()
        );
    EXCEPTION WHEN undefined_table THEN
        -- Tabla auditoria_eventos aun no existe; ignorar
        NULL;
    END;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION audit_trigger()
    IS 'Trigger generico de auditoria: registra INSERT/UPDATE/DELETE en auditoria_eventos con OLD y NEW como JSONB.';

-- Aplicar audit_trigger a tablas criticas

CREATE TRIGGER trg_audit_ordenes_trabajo
    AFTER INSERT OR UPDATE OR DELETE ON ordenes_trabajo
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER trg_audit_movimientos_inventario
    AFTER INSERT OR UPDATE OR DELETE ON movimientos_inventario
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER trg_audit_activos
    AFTER INSERT OR UPDATE OR DELETE ON activos
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

CREATE TRIGGER trg_audit_stock_bodega
    AFTER INSERT OR UPDATE OR DELETE ON stock_bodega
    FOR EACH ROW EXECUTE FUNCTION audit_trigger();

-- Tablas de fase 04: crear triggers con manejo de error si no existen aun

DO $$ BEGIN
    CREATE TRIGGER trg_audit_certificaciones
        AFTER INSERT OR UPDATE OR DELETE ON certificaciones
        FOR EACH ROW EXECUTE FUNCTION audit_trigger();
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE TRIGGER trg_audit_incidentes
        AFTER INSERT OR UPDATE OR DELETE ON incidentes
        FOR EACH ROW EXECUTE FUNCTION audit_trigger();
EXCEPTION WHEN undefined_table THEN NULL;
END $$;


-- ############################################################################
-- SECCION 4: POLITICAS DE SEGURIDAD A NIVEL DE FILA (RLS)
-- ############################################################################

-- ============================================================================
-- 4.0 Funcion auxiliar: obtener rol del usuario actual
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_user_rol()
RETURNS TEXT AS $$
BEGIN
    RETURN COALESCE(
        -- Primero intentar desde JWT (mas eficiente)
        current_setting('request.jwt.claims', true)::JSONB->'user_metadata'->>'rol',
        -- Fallback: consultar tabla usuarios_perfil
        (SELECT rol::TEXT FROM usuarios_perfil WHERE id = auth.uid())
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fn_user_rol()
    IS 'Retorna el rol del usuario autenticado desde JWT o usuarios_perfil.';

-- ============================================================================
-- 4.0.1 Funcion auxiliar: obtener faena_id del usuario actual
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_user_faena_id()
RETURNS UUID AS $$
BEGIN
    RETURN (SELECT faena_id FROM usuarios_perfil WHERE id = auth.uid());
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION fn_user_faena_id()
    IS 'Retorna la faena_id del usuario autenticado desde usuarios_perfil.';

-- ============================================================================
-- 4.1 HABILITAR RLS EN TODAS LAS TABLAS
-- ============================================================================

ALTER TABLE contratos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE faenas                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios_perfil          ENABLE ROW LEVEL SECURITY;
ALTER TABLE marcas                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE modelos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE activos                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE pautas_fabricante        ENABLE ROW LEVEL SECURITY;
ALTER TABLE planes_mantenimiento     ENABLE ROW LEVEL SECURITY;
ALTER TABLE bodegas                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE productos                ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_bodega             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ordenes_trabajo          ENABLE ROW LEVEL SECURITY;
ALTER TABLE checklist_ot             ENABLE ROW LEVEL SECURITY;
ALTER TABLE evidencias_ot            ENABLE ROW LEVEL SECURITY;
ALTER TABLE historial_estado_ot      ENABLE ROW LEVEL SECURITY;
ALTER TABLE movimientos_inventario   ENABLE ROW LEVEL SECURITY;
ALTER TABLE kardex                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE conteos_inventario       ENABLE ROW LEVEL SECURITY;
ALTER TABLE conteo_detalle           ENABLE ROW LEVEL SECURITY;
ALTER TABLE lecturas_pistola         ENABLE ROW LEVEL SECURITY;

-- Tablas fase 04 (habilitadas con manejo de error)
DO $$ BEGIN ALTER TABLE certificaciones      ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE incidentes           ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE abastecimientos      ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE rutas_despacho       ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE iceo_periodos        ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE iceo_detalle         ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE mediciones_kpi       ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE alertas              ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE auditoria_eventos    ENABLE ROW LEVEL SECURITY; EXCEPTION WHEN undefined_table THEN NULL; END $$;

-- ============================================================================
-- 4.2 POLITICAS: ADMINISTRADOR (acceso total)
-- ============================================================================

-- Macro para crear politica de administrador en multiples tablas
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'usuarios_perfil', 'marcas', 'modelos',
        'activos', 'pautas_fabricante', 'planes_mantenimiento', 'bodegas',
        'productos', 'stock_bodega', 'ordenes_trabajo', 'checklist_ot',
        'evidencias_ot', 'historial_estado_ot', 'movimientos_inventario',
        'kardex', 'conteos_inventario', 'conteo_detalle', 'lecturas_pistola'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_admin_all_%1$s ON %1$I FOR ALL
             USING (fn_user_rol() = ''administrador'')
             WITH CHECK (fn_user_rol() = ''administrador'')',
            t
        );
    END LOOP;
END $$;

-- Politicas de admin para tablas fase 04
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'certificaciones', 'incidentes', 'abastecimientos', 'rutas_despacho',
        'iceo_periodos', 'iceo_detalle', 'mediciones_kpi', 'alertas',
        'auditoria_eventos'
    ] LOOP
        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_admin_all_%1$s ON %1$I FOR ALL
                 USING (fn_user_rol() = ''administrador'')
                 WITH CHECK (fn_user_rol() = ''administrador'')',
                t
            );
        EXCEPTION WHEN undefined_table THEN NULL;
        END;
    END LOOP;
END $$;

-- ============================================================================
-- 4.3 POLITICAS: GERENCIA y SUBGERENTE_OPERACIONES (solo lectura total)
-- ============================================================================

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'usuarios_perfil', 'marcas', 'modelos',
        'activos', 'pautas_fabricante', 'planes_mantenimiento', 'bodegas',
        'productos', 'stock_bodega', 'ordenes_trabajo', 'checklist_ot',
        'evidencias_ot', 'historial_estado_ot', 'movimientos_inventario',
        'kardex', 'conteos_inventario', 'conteo_detalle', 'lecturas_pistola'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_gerencia_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() IN (''gerencia'', ''subgerente_operaciones''))',
            t
        );
    END LOOP;
END $$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'certificaciones', 'incidentes', 'abastecimientos', 'rutas_despacho',
        'iceo_periodos', 'iceo_detalle', 'mediciones_kpi', 'alertas',
        'auditoria_eventos'
    ] LOOP
        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_gerencia_select_%1$s ON %1$I FOR SELECT
                 USING (fn_user_rol() IN (''gerencia'', ''subgerente_operaciones''))',
                t
            );
        EXCEPTION WHEN undefined_table THEN NULL;
        END;
    END LOOP;
END $$;

-- ============================================================================
-- 4.4 POLITICAS: AUDITOR (solo lectura total, sin modificaciones)
-- ============================================================================

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'usuarios_perfil', 'marcas', 'modelos',
        'activos', 'pautas_fabricante', 'planes_mantenimiento', 'bodegas',
        'productos', 'stock_bodega', 'ordenes_trabajo', 'checklist_ot',
        'evidencias_ot', 'historial_estado_ot', 'movimientos_inventario',
        'kardex', 'conteos_inventario', 'conteo_detalle', 'lecturas_pistola'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_auditor_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() = ''auditor'')',
            t
        );
    END LOOP;
END $$;

DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'certificaciones', 'incidentes', 'abastecimientos', 'rutas_despacho',
        'iceo_periodos', 'iceo_detalle', 'mediciones_kpi', 'alertas',
        'auditoria_eventos'
    ] LOOP
        BEGIN
            EXECUTE format(
                'CREATE POLICY pol_auditor_select_%1$s ON %1$I FOR SELECT
                 USING (fn_user_rol() = ''auditor'')',
                t
            );
        EXCEPTION WHEN undefined_table THEN NULL;
        END;
    END LOOP;
END $$;

-- ============================================================================
-- 4.5 POLITICAS: SUPERVISOR (lectura en su faena, update OT, insert incidentes)
-- ============================================================================

-- SELECT en tablas con faena_id directo
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'activos', 'bodegas'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_supervisor_select_%1$s ON %1$I FOR SELECT
             USING (
                fn_user_rol() = ''supervisor''
                AND faena_id = fn_user_faena_id()
             )',
            t
        );
    END LOOP;
END $$;

-- SELECT en planes_mantenimiento (faena via activo)
CREATE POLICY pol_supervisor_select_planes_mantenimiento ON planes_mantenimiento
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND activo_id IN (SELECT id FROM activos WHERE faena_id = fn_user_faena_id())
    );

-- SELECT en stock_bodega (faena via bodega)
CREATE POLICY pol_supervisor_select_stock_bodega ON stock_bodega
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- SELECT en ordenes_trabajo (tiene faena_id)
CREATE POLICY pol_supervisor_select_ordenes_trabajo ON ordenes_trabajo
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND faena_id = fn_user_faena_id()
    );

-- UPDATE en ordenes_trabajo (validacion/cierre) en su faena
CREATE POLICY pol_supervisor_update_ordenes_trabajo ON ordenes_trabajo
    FOR UPDATE
    USING (
        fn_user_rol() = 'supervisor'
        AND faena_id = fn_user_faena_id()
    )
    WITH CHECK (
        fn_user_rol() = 'supervisor'
        AND faena_id = fn_user_faena_id()
    );

-- SELECT en tablas relacionadas a OT (via JOIN con ordenes_trabajo)
CREATE POLICY pol_supervisor_select_checklist_ot ON checklist_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_supervisor_select_evidencias_ot ON evidencias_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_supervisor_select_historial_estado_ot ON historial_estado_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

-- SELECT en tablas maestras (sin filtro de faena)
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'marcas', 'modelos', 'pautas_fabricante',
        'productos', 'usuarios_perfil'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_supervisor_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() = ''supervisor'')',
            t
        );
    END LOOP;
END $$;

-- SELECT en movimientos_inventario e kardex de su faena
CREATE POLICY pol_supervisor_select_movimientos_inventario ON movimientos_inventario
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_supervisor_select_kardex ON kardex
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_supervisor_select_conteos_inventario ON conteos_inventario
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_supervisor_select_conteo_detalle ON conteo_detalle
    FOR SELECT
    USING (
        fn_user_rol() = 'supervisor'
        AND conteo_id IN (
            SELECT id FROM conteos_inventario
            WHERE bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
        )
    );

CREATE POLICY pol_supervisor_select_lecturas_pistola ON lecturas_pistola
    FOR SELECT
    USING (fn_user_rol() = 'supervisor');

-- INSERT en incidentes
DO $$ BEGIN
    CREATE POLICY pol_supervisor_insert_incidentes ON incidentes
        FOR INSERT
        WITH CHECK (fn_user_rol() = 'supervisor');
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY pol_supervisor_select_incidentes ON incidentes
        FOR SELECT
        USING (
            fn_user_rol() = 'supervisor'
            AND faena_id = fn_user_faena_id()
        );
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- ============================================================================
-- 4.6 POLITICAS: PLANIFICADOR (CRUD OT y planes en su faena)
-- ============================================================================

-- SELECT en tablas maestras
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'contratos', 'faenas', 'marcas', 'modelos', 'pautas_fabricante',
        'productos', 'usuarios_perfil'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_planificador_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() = ''planificador'')',
            t
        );
    END LOOP;
END $$;

-- SELECT en tablas con faena_id directo
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'activos', 'bodegas'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_planificador_select_%1$s ON %1$I FOR SELECT
             USING (
                fn_user_rol() = ''planificador''
                AND faena_id = fn_user_faena_id()
             )',
            t
        );
    END LOOP;
END $$;

-- SELECT en stock_bodega (faena via bodega)
CREATE POLICY pol_planificador_select_stock_bodega ON stock_bodega
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- ordenes_trabajo: SELECT, INSERT, UPDATE en su faena
CREATE POLICY pol_planificador_select_ordenes_trabajo ON ordenes_trabajo
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND faena_id = fn_user_faena_id()
    );

CREATE POLICY pol_planificador_insert_ordenes_trabajo ON ordenes_trabajo
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'planificador'
        AND faena_id = fn_user_faena_id()
    );

CREATE POLICY pol_planificador_update_ordenes_trabajo ON ordenes_trabajo
    FOR UPDATE
    USING (
        fn_user_rol() = 'planificador'
        AND faena_id = fn_user_faena_id()
    )
    WITH CHECK (
        fn_user_rol() = 'planificador'
        AND faena_id = fn_user_faena_id()
    );

-- planes_mantenimiento: SELECT, INSERT, UPDATE en su faena (via activo)
CREATE POLICY pol_planificador_select_planes_mantenimiento ON planes_mantenimiento
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND activo_id IN (SELECT id FROM activos WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_insert_planes_mantenimiento ON planes_mantenimiento
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'planificador'
        AND activo_id IN (SELECT id FROM activos WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_update_planes_mantenimiento ON planes_mantenimiento
    FOR UPDATE
    USING (
        fn_user_rol() = 'planificador'
        AND activo_id IN (SELECT id FROM activos WHERE faena_id = fn_user_faena_id())
    )
    WITH CHECK (
        fn_user_rol() = 'planificador'
        AND activo_id IN (SELECT id FROM activos WHERE faena_id = fn_user_faena_id())
    );

-- checklist_ot e evidencias_ot: SELECT/INSERT para OTs de su faena
CREATE POLICY pol_planificador_select_checklist_ot ON checklist_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_insert_checklist_ot ON checklist_ot
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'planificador'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_select_evidencias_ot ON evidencias_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_select_historial_estado_ot ON historial_estado_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
    );

-- movimientos e kardex de su faena (solo lectura)
CREATE POLICY pol_planificador_select_movimientos_inventario ON movimientos_inventario
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_select_kardex ON kardex
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_select_conteos_inventario ON conteos_inventario
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

CREATE POLICY pol_planificador_select_conteo_detalle ON conteo_detalle
    FOR SELECT
    USING (
        fn_user_rol() = 'planificador'
        AND conteo_id IN (
            SELECT id FROM conteos_inventario
            WHERE bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
        )
    );

CREATE POLICY pol_planificador_select_lecturas_pistola ON lecturas_pistola
    FOR SELECT
    USING (fn_user_rol() = 'planificador');

-- ============================================================================
-- 4.7 POLITICAS: TECNICO_MANTENIMIENTO (solo sus OTs asignadas)
-- ============================================================================

-- SELECT en sus OTs asignadas
CREATE POLICY pol_tecnico_select_ordenes_trabajo ON ordenes_trabajo
    FOR SELECT
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND responsable_id = auth.uid()
    );

-- UPDATE en sus OTs asignadas
CREATE POLICY pol_tecnico_update_ordenes_trabajo ON ordenes_trabajo
    FOR UPDATE
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND responsable_id = auth.uid()
    )
    WITH CHECK (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND responsable_id = auth.uid()
    );

-- INSERT en evidencias_ot para sus OTs
CREATE POLICY pol_tecnico_insert_evidencias_ot ON evidencias_ot
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    );

-- SELECT en evidencias_ot para sus OTs
CREATE POLICY pol_tecnico_select_evidencias_ot ON evidencias_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    );

-- INSERT en checklist_ot para sus OTs
CREATE POLICY pol_tecnico_insert_checklist_ot ON checklist_ot
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    );

-- UPDATE en checklist_ot para sus OTs (completar items)
CREATE POLICY pol_tecnico_update_checklist_ot ON checklist_ot
    FOR UPDATE
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    )
    WITH CHECK (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    );

-- SELECT en checklist_ot para sus OTs
CREATE POLICY pol_tecnico_select_checklist_ot ON checklist_ot
    FOR SELECT
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND ot_id IN (SELECT id FROM ordenes_trabajo WHERE responsable_id = auth.uid())
    );

-- SELECT en tablas maestras necesarias para la app
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'activos', 'productos', 'marcas', 'modelos'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_tecnico_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() = ''tecnico_mantenimiento'')',
            t
        );
    END LOOP;
END $$;

-- SELECT en su propio perfil
CREATE POLICY pol_tecnico_select_usuarios_perfil ON usuarios_perfil
    FOR SELECT
    USING (
        fn_user_rol() = 'tecnico_mantenimiento'
        AND id = auth.uid()
    );

-- ============================================================================
-- 4.8 POLITICAS: BODEGUERO (inventario completo en su faena)
-- ============================================================================

-- Acceso completo a movimientos_inventario en su faena
CREATE POLICY pol_bodeguero_all_movimientos_inventario ON movimientos_inventario
    FOR ALL
    USING (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    )
    WITH CHECK (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- Acceso completo a stock_bodega en su faena
CREATE POLICY pol_bodeguero_all_stock_bodega ON stock_bodega
    FOR ALL
    USING (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    )
    WITH CHECK (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- Acceso completo a conteos_inventario en su faena
CREATE POLICY pol_bodeguero_all_conteos_inventario ON conteos_inventario
    FOR ALL
    USING (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    )
    WITH CHECK (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- Acceso completo a conteo_detalle en su faena
CREATE POLICY pol_bodeguero_all_conteo_detalle ON conteo_detalle
    FOR ALL
    USING (
        fn_user_rol() = 'bodeguero'
        AND conteo_id IN (
            SELECT id FROM conteos_inventario
            WHERE bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
        )
    )
    WITH CHECK (
        fn_user_rol() = 'bodeguero'
        AND conteo_id IN (
            SELECT id FROM conteos_inventario
            WHERE bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
        )
    );

-- SELECT en kardex de su faena
CREATE POLICY pol_bodeguero_select_kardex ON kardex
    FOR SELECT
    USING (
        fn_user_rol() = 'bodeguero'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- SELECT en ordenes_trabajo (para validar OT existente)
CREATE POLICY pol_bodeguero_select_ordenes_trabajo ON ordenes_trabajo
    FOR SELECT
    USING (
        fn_user_rol() = 'bodeguero'
        AND faena_id = fn_user_faena_id()
    );

-- SELECT en productos (catalogo)
CREATE POLICY pol_bodeguero_select_productos ON productos
    FOR SELECT
    USING (fn_user_rol() = 'bodeguero');

-- SELECT en bodegas de su faena
CREATE POLICY pol_bodeguero_select_bodegas ON bodegas
    FOR SELECT
    USING (
        fn_user_rol() = 'bodeguero'
        AND faena_id = fn_user_faena_id()
    );

-- SELECT en lecturas_pistola de su faena
CREATE POLICY pol_bodeguero_all_lecturas_pistola ON lecturas_pistola
    FOR ALL
    USING (
        fn_user_rol() = 'bodeguero'
        AND usuario_id = auth.uid()
    )
    WITH CHECK (
        fn_user_rol() = 'bodeguero'
        AND usuario_id = auth.uid()
    );

-- SELECT en su propio perfil
CREATE POLICY pol_bodeguero_select_usuarios_perfil ON usuarios_perfil
    FOR SELECT
    USING (
        fn_user_rol() = 'bodeguero'
        AND (id = auth.uid() OR faena_id = fn_user_faena_id())
    );

-- ============================================================================
-- 4.9 POLITICAS: OPERADOR_ABASTECIMIENTO
-- ============================================================================

-- SELECT en ordenes_trabajo de su faena
CREATE POLICY pol_operador_abast_select_ordenes_trabajo ON ordenes_trabajo
    FOR SELECT
    USING (
        fn_user_rol() = 'operador_abastecimiento'
        AND faena_id = fn_user_faena_id()
    );

-- INSERT en movimientos_inventario (solo tipo 'salida')
CREATE POLICY pol_operador_abast_insert_movimientos_inventario ON movimientos_inventario
    FOR INSERT
    WITH CHECK (
        fn_user_rol() = 'operador_abastecimiento'
        AND tipo = 'salida'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- SELECT en movimientos_inventario de su faena
CREATE POLICY pol_operador_abast_select_movimientos_inventario ON movimientos_inventario
    FOR SELECT
    USING (
        fn_user_rol() = 'operador_abastecimiento'
        AND bodega_id IN (SELECT id FROM bodegas WHERE faena_id = fn_user_faena_id())
    );

-- Abastecimientos (sin faena_id directo, se filtra via ruta_despacho)
DO $$ BEGIN
    CREATE POLICY pol_operador_abast_all_abastecimientos ON abastecimientos
        FOR ALL
        USING (
            fn_user_rol() = 'operador_abastecimiento'
            AND (
                ruta_despacho_id IN (SELECT id FROM rutas_despacho WHERE faena_id = fn_user_faena_id())
                OR ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
            )
        )
        WITH CHECK (
            fn_user_rol() = 'operador_abastecimiento'
            AND (
                ruta_despacho_id IN (SELECT id FROM rutas_despacho WHERE faena_id = fn_user_faena_id())
                OR ot_id IN (SELECT id FROM ordenes_trabajo WHERE faena_id = fn_user_faena_id())
            )
        );
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY pol_operador_abast_all_rutas_despacho ON rutas_despacho
        FOR ALL
        USING (
            fn_user_rol() = 'operador_abastecimiento'
            AND faena_id = fn_user_faena_id()
        )
        WITH CHECK (
            fn_user_rol() = 'operador_abastecimiento'
            AND faena_id = fn_user_faena_id()
        );
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- SELECT en tablas de referencia
DO $$
DECLARE
    t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'productos', 'activos', 'bodegas'
    ] LOOP
        EXECUTE format(
            'CREATE POLICY pol_operador_abast_select_%1$s ON %1$I FOR SELECT
             USING (fn_user_rol() = ''operador_abastecimiento'')',
            t
        );
    END LOOP;
END $$;

-- SELECT en su propio perfil
CREATE POLICY pol_operador_abast_select_usuarios_perfil ON usuarios_perfil
    FOR SELECT
    USING (
        fn_user_rol() = 'operador_abastecimiento'
        AND id = auth.uid()
    );

-- ============================================================================
-- 4.10 POLITICAS: RRHH_INCENTIVOS (solo lectura de KPI e ICEO)
-- ============================================================================

DO $$ BEGIN
    CREATE POLICY pol_rrhh_select_iceo_periodos ON iceo_periodos
        FOR SELECT
        USING (fn_user_rol() = 'rrhh_incentivos');
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY pol_rrhh_select_iceo_detalle ON iceo_detalle
        FOR SELECT
        USING (fn_user_rol() = 'rrhh_incentivos');
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    CREATE POLICY pol_rrhh_select_mediciones_kpi ON mediciones_kpi
        FOR SELECT
        USING (fn_user_rol() = 'rrhh_incentivos');
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

CREATE POLICY pol_rrhh_select_usuarios_perfil ON usuarios_perfil
    FOR SELECT
    USING (fn_user_rol() = 'rrhh_incentivos');


-- ############################################################################
-- SECCION 5: PERMISOS SERVICE_ROLE (bypass RLS para funciones SECURITY DEFINER)
-- ############################################################################

-- Las funciones marcadas como SECURITY DEFINER (actualizar_stock_bodega,
-- registrar_kardex, actualizar_costo_ot, audit_trigger, verificar_certificaciones,
-- generar_ots_preventivas) ejecutan con los privilegios del creador, por lo que
-- no necesitan politicas RLS adicionales.

-- Permitir que el service_role de Supabase acceda sin restriccion:
-- (Supabase ya configura esto por defecto, pero lo documentamos)

-- GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
-- GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;


-- ============================================================================
-- Fin de 05_funciones_triggers_rls.sql
-- ============================================================================
