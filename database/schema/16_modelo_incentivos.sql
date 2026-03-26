-- SICOM-ICEO | Modelo de Incentivos Variables
-- ============================================================================
-- Ejecutar DESPUÉS de 15_fix_kpi_funciones.sql
--
-- 1. Tabla de cargos con sueldo base y % incentivo máximo
-- 2. Tabla de incentivos por período
-- 3. RPC para calcular incentivos del período
-- 4. Vista de reporte de incentivos
-- ============================================================================


-- ############################################################################
-- 1. TABLA: CARGOS E INCENTIVOS BASE
-- ############################################################################

CREATE TABLE IF NOT EXISTS cargos_incentivo (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cargo           VARCHAR(100) UNIQUE NOT NULL,
    area_principal  area_kpi_enum,  -- área que más afecta su incentivo
    sueldo_base_clp NUMERIC(12,0) NOT NULL,
    pct_incentivo_max NUMERIC(5,2) NOT NULL DEFAULT 15.00, -- % máximo del sueldo
    bono_excelencia_anual_clp NUMERIC(12,0) DEFAULT 0,
    activo          BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Datos base de ejemplo
INSERT INTO cargos_incentivo (cargo, area_principal, sueldo_base_clp, pct_incentivo_max, bono_excelencia_anual_clp)
VALUES
    ('Jefe de Operaciones', NULL, 2800000, 20.00, 1500000),
    ('Supervisor de Terreno', NULL, 2200000, 18.00, 1000000),
    ('Planificador de Mantenimiento', 'mantenimiento_fijos', 1800000, 15.00, 800000),
    ('Técnico de Mantenimiento Senior', 'mantenimiento_fijos', 1500000, 15.00, 600000),
    ('Técnico de Mantenimiento', 'mantenimiento_fijos', 1200000, 12.00, 400000),
    ('Operador de Abastecimiento', 'administracion_combustibles', 1100000, 12.00, 400000),
    ('Bodeguero', 'administracion_combustibles', 1000000, 10.00, 300000),
    ('Conductor Cisterna', 'mantenimiento_moviles', 1300000, 12.00, 400000),
    ('Lubricador', 'administracion_combustibles', 1000000, 10.00, 300000),
    ('Ayudante Terreno', NULL, 850000, 8.00, 200000)
ON CONFLICT (cargo) DO NOTHING;


-- ############################################################################
-- 2. TABLA: TRAMOS DE INCENTIVO POR ICEO
-- ############################################################################
-- Define qué % del incentivo máximo se paga según el ICEO del período.

CREATE TABLE IF NOT EXISTS tramos_incentivo (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contrato_id UUID REFERENCES contratos(id),
    iceo_min    NUMERIC(5,2) NOT NULL,
    iceo_max    NUMERIC(5,2) NOT NULL,
    pct_pago    NUMERIC(5,2) NOT NULL, -- % del incentivo máximo que se paga
    descripcion VARCHAR(100),
    CONSTRAINT chk_tramo_rango CHECK (iceo_max > iceo_min),
    CONSTRAINT chk_tramo_pago CHECK (pct_pago >= 0 AND pct_pago <= 100)
);

-- Tramos estándar
INSERT INTO tramos_incentivo (contrato_id, iceo_min, iceo_max, pct_pago, descripcion)
SELECT
    c.id,
    v.iceo_min,
    v.iceo_max,
    v.pct_pago,
    v.descripcion
FROM contratos c
CROSS JOIN (VALUES
    (95.00, 100.00, 100.00, 'Excelencia: 100% del incentivo'),
    (90.00,  94.99,  90.00, 'Muy bueno: 90% del incentivo'),
    (85.00,  89.99,  75.00, 'Bueno: 75% del incentivo'),
    (80.00,  84.99,  50.00, 'Aceptable: 50% del incentivo'),
    (70.00,  79.99,  25.00, 'Regular: 25% del incentivo'),
    ( 0.00,  69.99,   0.00, 'Deficiente: sin incentivo')
) AS v(iceo_min, iceo_max, pct_pago, descripcion)
WHERE c.estado = 'activo'
ON CONFLICT DO NOTHING;


-- ############################################################################
-- 3. TABLA: INCENTIVOS CALCULADOS POR PERÍODO
-- ############################################################################

CREATE TABLE IF NOT EXISTS incentivos_periodo (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    iceo_periodo_id     UUID NOT NULL REFERENCES iceo_periodos(id),
    contrato_id         UUID NOT NULL REFERENCES contratos(id),
    usuario_id          UUID NOT NULL REFERENCES usuarios_perfil(id),
    periodo_inicio      DATE NOT NULL,
    periodo_fin         DATE NOT NULL,
    -- Datos del cálculo
    cargo               VARCHAR(100),
    sueldo_base         NUMERIC(12,0),
    pct_incentivo_max   NUMERIC(5,2),
    iceo_valor          NUMERIC(7,4),
    iceo_clasificacion  clasificacion_iceo_enum,
    incentivo_habilitado BOOLEAN NOT NULL DEFAULT false,
    -- Tramo aplicado
    tramo_pct_pago      NUMERIC(5,2) DEFAULT 0,
    -- Montos
    monto_incentivo_max NUMERIC(12,0),       -- sueldo × pct_max
    monto_incentivo_real NUMERIC(12,0),       -- max × tramo_pct
    monto_incentivo_final NUMERIC(12,0),      -- 0 si bloqueante activo
    -- Auditoría
    bloqueantes_activos JSONB DEFAULT '[]',
    observaciones       TEXT,
    aprobado            BOOLEAN DEFAULT false,
    aprobado_por        UUID REFERENCES usuarios_perfil(id),
    aprobado_en         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_incentivo_periodo UNIQUE (usuario_id, periodo_inicio)
);

CREATE INDEX IF NOT EXISTS idx_incentivos_periodo ON incentivos_periodo (contrato_id, periodo_inicio);
CREATE INDEX IF NOT EXISTS idx_incentivos_usuario ON incentivos_periodo (usuario_id, periodo_inicio);


-- ############################################################################
-- 4. RPC: CALCULAR INCENTIVOS DEL PERÍODO
-- ############################################################################

CREATE OR REPLACE FUNCTION rpc_calcular_incentivos_periodo(
    p_contrato_id    UUID,
    p_periodo_inicio DATE DEFAULT NULL,
    p_periodo_fin    DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inicio        DATE;
    v_fin           DATE;
    v_iceo          RECORD;
    v_usuario       RECORD;
    v_cargo_info    RECORD;
    v_tramo_pct     NUMERIC(5,2);
    v_monto_max     NUMERIC(12,0);
    v_monto_real    NUMERIC(12,0);
    v_monto_final   NUMERIC(12,0);
    v_count         INTEGER := 0;
    v_total_pagado  NUMERIC(15,0) := 0;
BEGIN
    v_inicio := COALESCE(p_periodo_inicio, DATE_TRUNC('month', CURRENT_DATE)::DATE);
    v_fin := COALESCE(p_periodo_fin, (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE);

    -- Obtener ICEO del período
    SELECT * INTO v_iceo
    FROM iceo_periodos
    WHERE contrato_id = p_contrato_id
      AND periodo_inicio = v_inicio
    ORDER BY calculado_en DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se encontró ICEO calculado para el período % - %. Calcule primero el ICEO.', v_inicio, v_fin;
    END IF;

    -- Para cada usuario activo del contrato
    FOR v_usuario IN
        SELECT up.id, up.nombre_completo, up.cargo, up.faena_id
        FROM usuarios_perfil up
        WHERE up.activo = true
          AND (up.faena_id IN (SELECT id FROM faenas WHERE contrato_id = p_contrato_id)
               OR up.faena_id IS NULL)
    LOOP
        -- Buscar configuración de cargo
        SELECT * INTO v_cargo_info
        FROM cargos_incentivo
        WHERE cargo = v_usuario.cargo AND activo = true;

        IF NOT FOUND THEN
            CONTINUE; -- Skip usuarios sin cargo configurado
        END IF;

        -- Buscar tramo de pago según ICEO
        SELECT COALESCE(ti.pct_pago, 0) INTO v_tramo_pct
        FROM tramos_incentivo ti
        WHERE ti.contrato_id = p_contrato_id
          AND v_iceo.iceo_final >= ti.iceo_min
          AND v_iceo.iceo_final < ti.iceo_max
        LIMIT 1;

        IF v_tramo_pct IS NULL THEN
            v_tramo_pct := 0;
        END IF;

        -- Calcular montos
        v_monto_max := ROUND(v_cargo_info.sueldo_base_clp * v_cargo_info.pct_incentivo_max / 100);
        v_monto_real := ROUND(v_monto_max * v_tramo_pct / 100);
        v_monto_final := CASE
            WHEN v_iceo.incentivo_habilitado = false THEN 0
            ELSE v_monto_real
        END;

        -- Insertar o actualizar incentivo
        INSERT INTO incentivos_periodo (
            iceo_periodo_id, contrato_id, usuario_id, periodo_inicio, periodo_fin,
            cargo, sueldo_base, pct_incentivo_max,
            iceo_valor, iceo_clasificacion, incentivo_habilitado,
            tramo_pct_pago, monto_incentivo_max, monto_incentivo_real, monto_incentivo_final,
            bloqueantes_activos
        ) VALUES (
            v_iceo.id, p_contrato_id, v_usuario.id, v_inicio, v_fin,
            v_usuario.cargo, v_cargo_info.sueldo_base_clp, v_cargo_info.pct_incentivo_max,
            v_iceo.iceo_final, v_iceo.clasificacion, v_iceo.incentivo_habilitado,
            v_tramo_pct, v_monto_max, v_monto_real, v_monto_final,
            COALESCE(v_iceo.bloqueantes_activados, '[]'::JSONB)
        )
        ON CONFLICT (usuario_id, periodo_inicio)
        DO UPDATE SET
            iceo_valor = EXCLUDED.iceo_valor,
            iceo_clasificacion = EXCLUDED.iceo_clasificacion,
            incentivo_habilitado = EXCLUDED.incentivo_habilitado,
            tramo_pct_pago = EXCLUDED.tramo_pct_pago,
            monto_incentivo_max = EXCLUDED.monto_incentivo_max,
            monto_incentivo_real = EXCLUDED.monto_incentivo_real,
            monto_incentivo_final = EXCLUDED.monto_incentivo_final,
            bloqueantes_activos = EXCLUDED.bloqueantes_activos,
            aprobado = false; -- Reset aprobación si se recalcula

        v_count := v_count + 1;
        v_total_pagado := v_total_pagado + v_monto_final;
    END LOOP;

    RETURN jsonb_build_object(
        'periodo', v_inicio || ' a ' || v_fin,
        'iceo_valor', v_iceo.iceo_final,
        'iceo_clasificacion', v_iceo.clasificacion,
        'incentivo_habilitado', v_iceo.incentivo_habilitado,
        'usuarios_procesados', v_count,
        'total_incentivos_clp', v_total_pagado,
        'bloqueantes', v_iceo.bloqueantes_activados
    );
END;
$$;


-- ############################################################################
-- 5. VISTA: REPORTE DE INCENTIVOS
-- ############################################################################

CREATE OR REPLACE VIEW v_reporte_incentivos AS
SELECT
    ip.id,
    ip.periodo_inicio,
    ip.periodo_fin,
    up.nombre_completo,
    up.rut,
    ip.cargo,
    f.nombre AS faena_nombre,
    ip.sueldo_base,
    ip.pct_incentivo_max,
    ip.iceo_valor,
    ip.iceo_clasificacion,
    ip.incentivo_habilitado,
    ip.tramo_pct_pago,
    ip.monto_incentivo_max,
    ip.monto_incentivo_real,
    ip.monto_incentivo_final,
    ip.bloqueantes_activos,
    ip.aprobado,
    ap.nombre_completo AS aprobado_por_nombre,
    ip.aprobado_en,
    ip.observaciones
FROM incentivos_periodo ip
JOIN usuarios_perfil up ON up.id = ip.usuario_id
LEFT JOIN faenas f ON f.id = up.faena_id
LEFT JOIN usuarios_perfil ap ON ap.id = ip.aprobado_por
ORDER BY ip.periodo_inicio DESC, up.nombre_completo;

COMMENT ON VIEW v_reporte_incentivos IS
'Reporte de incentivos por período con detalle por trabajador, ICEO, tramos y montos.';


-- ############################################################################
-- 6. REGLAS DE NEGOCIO IMPLEMENTADAS
-- ############################################################################
--
-- 1. Si ICEO < 70 → incentivo = 0% → monto = $0
-- 2. Si bloqueante activo → incentivo_habilitado = false → monto = $0
-- 3. Si bloqueante 'anular' → ICEO = 0 → automáticamente tramo 0% → $0
-- 4. Si cargo no configurado → usuario no recibe incentivo (skip)
-- 5. Si usuario no pertenece a faena del contrato → skip
-- 6. Recálculo del ICEO invalida aprobación de incentivos (aprobado=false)
-- 7. Incentivo NO es acumulativo — se calcula por período
-- 8. Bono anual de excelencia sostenida:
--    Si los 12 períodos tienen ICEO ≥ 95 → se paga bono_excelencia_anual_clp
--    (debe evaluarse manualmente o via RPC adicional al cierre del año)
--
-- ============================================================================
