-- ============================================================================
-- SICOM-ICEO  |  Fase 2  |  Tablas OT e Inventario
-- Sistema Integral de Control Operacional - Indice Compuesto de Excelencia
-- Operacional
-- ----------------------------------------------------------------------------
-- Archivo : 03_tablas_ot_inventario.sql
-- Propósito : Tablas centrales de órdenes de trabajo (OT), checklist,
--             evidencias, historial de estado, movimientos de inventario,
--             kardex, conteos de inventario y lecturas de pistola.
-- Dependencias:
--   01_tipos_y_enums.sql   → tipos enumerados
--   02_tablas_maestras.sql  → contratos, faenas, activos, productos,
--                             bodegas, planes_mantenimiento, usuarios_perfil
-- ============================================================================

-- ============================================================================
-- 1. ÓRDENES DE TRABAJO (eje central del sistema)
-- ============================================================================

CREATE TABLE ordenes_trabajo (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    folio                       VARCHAR(20) UNIQUE NOT NULL,
    tipo                        tipo_ot_enum NOT NULL,

    -- Relaciones de contexto
    contrato_id                 UUID NOT NULL
                                    REFERENCES contratos(id),
    faena_id                    UUID NOT NULL
                                    REFERENCES faenas(id),
    activo_id                   UUID NOT NULL
                                    REFERENCES activos(id),
    plan_mantenimiento_id       UUID
                                    REFERENCES planes_mantenimiento(id),

    -- Prioridad y estado
    prioridad                   prioridad_enum NOT NULL DEFAULT 'normal',
    estado                      estado_ot_enum NOT NULL DEFAULT 'creada',

    -- Asignación
    responsable_id              UUID
                                    REFERENCES usuarios_perfil(id),
    cuadrilla                   VARCHAR(100),

    -- Fechas
    fecha_programada            DATE,
    fecha_inicio                TIMESTAMPTZ,
    fecha_termino               TIMESTAMPTZ,
    fecha_cierre_supervisor     TIMESTAMPTZ,

    -- Cierre supervisor
    supervisor_cierre_id        UUID
                                    REFERENCES usuarios_perfil(id),

    -- No ejecución
    causa_no_ejecucion          causa_no_ejecucion_enum,
    detalle_no_ejecucion        TEXT,

    -- Observaciones
    observaciones               TEXT,
    observaciones_supervisor    TEXT,

    -- Costos
    costo_mano_obra             NUMERIC(12,2) NOT NULL DEFAULT 0,
    costo_materiales            NUMERIC(12,2) NOT NULL DEFAULT 0,
    costo_total                 NUMERIC(12,2) GENERATED ALWAYS AS
                                    (costo_mano_obra + costo_materiales) STORED,

    -- Firmas y QR
    firma_tecnico_url           TEXT,
    firma_supervisor_url        TEXT,
    qr_code                     VARCHAR(100) UNIQUE,

    -- Origen
    generada_automaticamente    BOOLEAN NOT NULL DEFAULT false,

    -- Auditoría
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  UUID REFERENCES auth.users(id),

    -- Regla: si el estado es 'no_ejecutada', la causa es obligatoria
    CONSTRAINT chk_ot_causa_no_ejecucion
        CHECK (
            estado <> 'no_ejecutada'
            OR causa_no_ejecucion IS NOT NULL
        )
);

-- Índices de acceso frecuente
CREATE INDEX idx_ot_folio            ON ordenes_trabajo (folio);
CREATE INDEX idx_ot_contrato         ON ordenes_trabajo (contrato_id);
CREATE INDEX idx_ot_faena            ON ordenes_trabajo (faena_id);
CREATE INDEX idx_ot_activo           ON ordenes_trabajo (activo_id);
CREATE INDEX idx_ot_estado           ON ordenes_trabajo (estado);
CREATE INDEX idx_ot_fecha_programada ON ordenes_trabajo (fecha_programada);
CREATE INDEX idx_ot_responsable      ON ordenes_trabajo (responsable_id);
CREATE INDEX idx_ot_plan_pm          ON ordenes_trabajo (plan_mantenimiento_id)
                                         WHERE plan_mantenimiento_id IS NOT NULL;

COMMENT ON TABLE  ordenes_trabajo IS 'Órdenes de trabajo — eje central del sistema operativo SICOM-ICEO.';
COMMENT ON COLUMN ordenes_trabajo.folio IS 'Folio único con formato OT-YYYYMM-XXXXX, generado automáticamente.';
COMMENT ON COLUMN ordenes_trabajo.costo_total IS 'Columna generada: costo_mano_obra + costo_materiales.';

-- ============================================================================
-- 2. CHECKLIST DE OT
-- ============================================================================

CREATE TABLE checklist_ot (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ot_id               UUID NOT NULL
                            REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    orden               INTEGER NOT NULL,
    descripcion         TEXT NOT NULL,
    obligatorio         BOOLEAN NOT NULL DEFAULT true,
    requiere_foto       BOOLEAN NOT NULL DEFAULT false,
    resultado           VARCHAR(20)
                            CHECK (resultado IN ('ok', 'no_ok', 'na')),
    observacion         TEXT,
    foto_url            TEXT,
    completado_en       TIMESTAMPTZ,
    completado_por      UUID
                            REFERENCES usuarios_perfil(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Un ítem de checklist es único por OT + orden
    CONSTRAINT uq_checklist_ot_orden UNIQUE (ot_id, orden)
);

CREATE INDEX idx_checklist_ot ON checklist_ot (ot_id);

COMMENT ON TABLE checklist_ot IS 'Ítems de checklist asociados a cada orden de trabajo.';

-- ============================================================================
-- 3. EVIDENCIAS DE OT (fotos, documentos, firmas)
-- ============================================================================

CREATE TABLE evidencias_ot (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ot_id               UUID NOT NULL
                            REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    tipo                VARCHAR(30) NOT NULL
                            CHECK (tipo IN (
                                'foto_antes', 'foto_durante', 'foto_despues',
                                'documento', 'firma'
                            )),
    archivo_url         TEXT NOT NULL,
    descripcion         TEXT,
    metadata            JSONB DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          UUID REFERENCES auth.users(id)
);

CREATE INDEX idx_evidencias_ot ON evidencias_ot (ot_id);

COMMENT ON TABLE  evidencias_ot IS 'Evidencia fotográfica y documental adjunta a órdenes de trabajo.';
COMMENT ON COLUMN evidencias_ot.metadata IS 'Datos adicionales: coordenadas GPS, info dispositivo, etc.';

-- ============================================================================
-- 4. HISTORIAL DE ESTADOS DE OT
-- ============================================================================

CREATE TABLE historial_estado_ot (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ot_id               UUID NOT NULL
                            REFERENCES ordenes_trabajo(id) ON DELETE CASCADE,
    estado_anterior     estado_ot_enum,
    estado_nuevo        estado_ot_enum NOT NULL,
    motivo              TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by          UUID REFERENCES auth.users(id)
);

CREATE INDEX idx_historial_estado_ot ON historial_estado_ot (ot_id);
CREATE INDEX idx_historial_estado_ot_fecha ON historial_estado_ot (created_at);

COMMENT ON TABLE historial_estado_ot IS 'Registro inmutable de cada transición de estado de una OT.';

-- ============================================================================
-- 5. MOVIMIENTOS DE INVENTARIO
-- ============================================================================

CREATE TABLE movimientos_inventario (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bodega_id               UUID NOT NULL
                                REFERENCES bodegas(id),
    producto_id             UUID NOT NULL
                                REFERENCES productos(id),
    tipo                    tipo_movimiento_enum NOT NULL,
    cantidad                NUMERIC(12,3) NOT NULL
                                CHECK (cantidad > 0),
    costo_unitario          NUMERIC(15,4) NOT NULL,
    costo_total             NUMERIC(15,2) GENERATED ALWAYS AS
                                (cantidad * costo_unitario) STORED,

    -- Trazabilidad operativa
    ot_id                   UUID
                                REFERENCES ordenes_trabajo(id),
    activo_id               UUID
                                REFERENCES activos(id),
    lote                    VARCHAR(100),
    fecha_vencimiento       DATE,
    documento_referencia    VARCHAR(100),
    motivo                  TEXT,

    -- Transferencias
    bodega_destino_id       UUID
                                REFERENCES bodegas(id),

    -- Responsable
    usuario_id              UUID NOT NULL
                                REFERENCES usuarios_perfil(id),

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Regla: salidas y mermas deben estar vinculadas a una OT
    CONSTRAINT chk_mov_salida_requiere_ot
        CHECK (
            tipo NOT IN ('salida', 'merma')
            OR ot_id IS NOT NULL
        )
);

CREATE INDEX idx_mov_inv_ot          ON movimientos_inventario (ot_id);
CREATE INDEX idx_mov_inv_producto    ON movimientos_inventario (producto_id);
CREATE INDEX idx_mov_inv_bodega      ON movimientos_inventario (bodega_id);
CREATE INDEX idx_mov_inv_created     ON movimientos_inventario (created_at);
CREATE INDEX idx_mov_inv_tipo        ON movimientos_inventario (tipo);

COMMENT ON TABLE  movimientos_inventario IS 'Registro de todos los movimientos de inventario (entradas, salidas, ajustes, transferencias).';
COMMENT ON COLUMN movimientos_inventario.costo_total IS 'Columna generada: cantidad × costo_unitario.';
COMMENT ON COLUMN movimientos_inventario.documento_referencia IS 'Número de factura, guía de despacho u otro documento externo.';

-- ============================================================================
-- 6. KARDEX (libro mayor de inventario por producto/bodega)
-- ============================================================================

CREATE TABLE kardex (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bodega_id                   UUID NOT NULL
                                    REFERENCES bodegas(id),
    producto_id                 UUID NOT NULL
                                    REFERENCES productos(id),
    movimiento_id               UUID NOT NULL
                                    REFERENCES movimientos_inventario(id),
    fecha                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    tipo                        tipo_movimiento_enum NOT NULL,

    -- Cantidades
    cantidad_movimiento         NUMERIC(12,3) NOT NULL,
    cantidad_anterior           NUMERIC(12,3) NOT NULL,
    cantidad_posterior          NUMERIC(12,3) NOT NULL,

    -- Costos y valorización
    costo_unitario              NUMERIC(15,4) NOT NULL,
    costo_promedio_anterior     NUMERIC(15,4),
    costo_promedio_posterior    NUMERIC(15,4),
    valor_movimiento            NUMERIC(15,2),
    valor_stock_posterior       NUMERIC(15,2)
);

CREATE INDEX idx_kardex_bodega_producto ON kardex (bodega_id, producto_id);
CREATE INDEX idx_kardex_movimiento      ON kardex (movimiento_id);
CREATE INDEX idx_kardex_fecha           ON kardex (fecha);

COMMENT ON TABLE kardex IS 'Libro mayor de inventario: saldos corrientes por producto y bodega tras cada movimiento.';

-- ============================================================================
-- 7. CONTEOS DE INVENTARIO
-- ============================================================================

CREATE TABLE conteos_inventario (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bodega_id                   UUID NOT NULL
                                    REFERENCES bodegas(id),
    tipo                        tipo_conteo_enum NOT NULL,
    fecha_inicio                TIMESTAMPTZ,
    fecha_fin                   TIMESTAMPTZ,
    estado                      VARCHAR(20) NOT NULL DEFAULT 'en_proceso'
                                    CHECK (estado IN (
                                        'en_proceso', 'completado', 'aprobado'
                                    )),
    responsable_id              UUID NOT NULL
                                    REFERENCES usuarios_perfil(id),
    supervisor_aprobacion_id    UUID
                                    REFERENCES usuarios_perfil(id),
    observaciones               TEXT,

    -- Auditoría
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                  UUID REFERENCES auth.users(id)
);

CREATE INDEX idx_conteos_bodega ON conteos_inventario (bodega_id);
CREATE INDEX idx_conteos_estado ON conteos_inventario (estado);

COMMENT ON TABLE conteos_inventario IS 'Cabecera de procesos de conteo físico de inventario (cíclico, general o selectivo).';

-- ============================================================================
-- 8. DETALLE DE CONTEOS
-- ============================================================================

CREATE TABLE conteo_detalle (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conteo_id                   UUID NOT NULL
                                    REFERENCES conteos_inventario(id) ON DELETE CASCADE,
    producto_id                 UUID NOT NULL
                                    REFERENCES productos(id),
    stock_sistema               NUMERIC(12,3) NOT NULL,
    stock_fisico                NUMERIC(12,3) NOT NULL,
    diferencia                  NUMERIC(12,3) GENERATED ALWAYS AS
                                    (stock_fisico - stock_sistema) STORED,
    diferencia_valorizada       NUMERIC(15,2),
    motivo                      TEXT,
    ajuste_aplicado             BOOLEAN NOT NULL DEFAULT false,
    movimiento_ajuste_id        UUID
                                    REFERENCES movimientos_inventario(id),
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- Un producto no se cuenta dos veces en el mismo conteo
    CONSTRAINT uq_conteo_producto UNIQUE (conteo_id, producto_id)
);

CREATE INDEX idx_conteo_det_conteo ON conteo_detalle (conteo_id);

COMMENT ON TABLE  conteo_detalle IS 'Líneas de detalle de cada conteo físico: stock sistema vs. stock físico.';
COMMENT ON COLUMN conteo_detalle.diferencia IS 'Columna generada: stock_fisico − stock_sistema.';

-- ============================================================================
-- 9. LECTURAS DE PISTOLA (log de código de barras)
-- ============================================================================

CREATE TABLE lecturas_pistola (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    codigo_leido        VARCHAR(200) NOT NULL,
    tipo_lectura        VARCHAR(30)
                            CHECK (tipo_lectura IN ('producto', 'ot', 'activo')),
    entidad_id          UUID,
    exitoso             BOOLEAN NOT NULL DEFAULT true,
    dispositivo         VARCHAR(100),
    usuario_id          UUID NOT NULL
                            REFERENCES usuarios_perfil(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_lecturas_usuario  ON lecturas_pistola (usuario_id);
CREATE INDEX idx_lecturas_fecha    ON lecturas_pistola (created_at);
CREATE INDEX idx_lecturas_codigo   ON lecturas_pistola (codigo_leido);

COMMENT ON TABLE lecturas_pistola IS 'Log de lecturas del lector de código de barras para trazabilidad y diagnóstico.';

-- ============================================================================
-- 10. FUNCIÓN: Generar folio automático para OT
-- ============================================================================

CREATE OR REPLACE FUNCTION generar_folio_ot()
RETURNS TRIGGER AS $$
DECLARE
    v_periodo TEXT;
    v_seq     INTEGER;
BEGIN
    -- Período actual YYYYMM
    v_periodo := to_char(now(), 'YYYYMM');

    -- Obtener siguiente secuencial del período
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

CREATE TRIGGER trg_ot_folio_auto
    BEFORE INSERT ON ordenes_trabajo
    FOR EACH ROW
    WHEN (NEW.folio IS NULL OR NEW.folio = '')
    EXECUTE FUNCTION generar_folio_ot();

COMMENT ON FUNCTION generar_folio_ot() IS 'Genera automáticamente el folio OT-YYYYMM-XXXXX al insertar una orden de trabajo.';

-- ============================================================================
-- 11. FUNCIÓN: Registrar transiciones de estado de OT
-- ============================================================================

CREATE OR REPLACE FUNCTION registrar_cambio_estado_ot()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.estado IS DISTINCT FROM NEW.estado THEN
        INSERT INTO historial_estado_ot (ot_id, estado_anterior, estado_nuevo, created_by)
        VALUES (NEW.id, OLD.estado, NEW.estado, NEW.created_by);
    END IF;

    -- Actualizar timestamp
    NEW.updated_at := now();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ot_estado_historial
    BEFORE UPDATE ON ordenes_trabajo
    FOR EACH ROW
    EXECUTE FUNCTION registrar_cambio_estado_ot();

COMMENT ON FUNCTION registrar_cambio_estado_ot() IS 'Registra automáticamente cada cambio de estado de una OT en historial_estado_ot.';

-- ============================================================================
-- 12. FUNCIÓN: updated_at automático para ordenes_trabajo
-- ============================================================================

CREATE OR REPLACE FUNCTION actualizar_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- NOTA: El trigger trg_ot_estado_historial ya actualiza updated_at.
--       Este trigger genérico se puede reutilizar en otras tablas.

COMMENT ON FUNCTION actualizar_updated_at() IS 'Función genérica para actualizar updated_at en cualquier tabla.';

-- ============================================================================
-- Fin de 03_tablas_ot_inventario.sql
-- ============================================================================
