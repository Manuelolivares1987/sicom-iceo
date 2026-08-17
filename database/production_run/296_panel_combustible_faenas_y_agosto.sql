-- ============================================================================
-- SICOM-ICEO | 296 — Panel: combustible de faenas + foco en el mes en curso
-- ============================================================================
-- Dos correcciones al Panel de Gerencia (MIG295), las dos por el mismo motivo:
-- el panel estaba contando cosas que no comparan.
--
-- ── A. COMBUSTIBLE DE FAENAS: EL PANEL DECÍA "CERO" Y NO ERA CERO ──────────
--
-- MIG295 leía combustible desde `combustible_movimientos` (Franke) y
-- `combustible_faena_despachos` (Romeral), y ambas están casi vacías. El panel
-- concluía "0 movimientos" y lo pintaba en rojo.
--
-- Pero la operación existe y es grande: se controla en planillas Excel de
-- cierre mensual, fuera del sistema. Solo en agosto 2026:
--     Franke  → 461 transacciones, 106.722 L vendidos, 52.117 L trasvasijados
--     Romeral → 857 transacciones, 253.888 L despachados
--
-- Decir "0" de eso no es un dato faltante: es un dato FALSO, y sobre un dato
-- falso se toman decisiones. Se agrega `combustible_faena_resumen_mensual`,
-- que guarda el cierre mensual de cada faena con su archivo de origen, y el
-- panel pasa a mostrar el volumen real declarando de dónde viene.
--
-- La distinción que el panel hace explícita:
--     CONTROLADO   → hay cierre mensual cargado (Excel). El negocio se mide.
--     TRAZADO      → además hay movimientos registrados en el sistema.
-- Hoy Franke y Romeral están CONTROLADOS pero no TRAZADOS. Esa es la brecha
-- real, y es muy distinta de "no se está despachando combustible".
--
-- ── B. OT Y NC: AGOSTO ES EL PRIMER MES DEL PROCESO DIGITAL ────────────────
--
-- El checklist digital con OT y NC arrancó en agosto 2026. Mezclar el backlog
-- viejo con lo que produce el proceso nuevo esconde las dos cosas:
--
--     OT creadas en junio  55  (24 siguen abiertas)  ← proceso anterior
--     OT creadas en julio  56  (20 siguen abiertas)  ← proceso anterior
--     OT creadas en agosto  7  ( 7 siguen abiertas)  ← proceso digital
--     NC en agosto         57  (origen ejecucion_ot + inspeccion_ot)
--
-- Un backlog de 44 OT heredadas no dice nada sobre cómo está funcionando el
-- checklist digital; y 57 NC en dos semanas no es "explosión de fallas", es un
-- proceso nuevo que por fin las está detectando. `fn_panel_taller` ahora separa
-- período vs. arrastre y entrega el resumen por fecha.
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================


-- ############################################################################
-- 1. CIERRE MENSUAL DE COMBUSTIBLE POR FAENA
-- ############################################################################
-- Una fila por faena y mes. Es el resumen del cierre, NO el detalle
-- transaccional: el detalle son ~5.000 filas mensuales por faena y su lugar es
-- `combustible_movimientos` cuando la operación migre al sistema. Mientras
-- tanto, esto le da a la gerencia el volumen real y la trazabilidad de la
-- fuente (qué archivo, quién lo cargó, cuándo).

CREATE TABLE IF NOT EXISTS combustible_faena_resumen_mensual (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    faena_codigo        VARCHAR(60) NOT NULL,   -- FRANKE | ROMERAL
    faena_nombre        VARCHAR(160) NOT NULL,
    operacion           VARCHAR(40) NOT NULL,   -- Coquimbo | Calama
    anio                INTEGER     NOT NULL,
    mes                 INTEGER     NOT NULL,

    -- Volúmenes del período (litros).
    transacciones       INTEGER     NOT NULL DEFAULT 0,
    litros_venta        NUMERIC(14,2) NOT NULL DEFAULT 0,
    litros_trasvasije   NUMERIC(14,2) NOT NULL DEFAULT 0,
    litros_total        NUMERIC(14,2) NOT NULL DEFAULT 0,
    stock_inicial       NUMERIC(14,2),

    -- Control: la fluctuación es EL indicador del negocio de combustible.
    fluctuacion_lt      NUMERIC(14,2),
    fluctuacion_pct     NUMERIC(8,4),

    -- Cobertura temporal del cierre: si el mes va al día 16 y solo hay 12 días
    -- cargados, el número no es comparable con un mes completo.
    dias_con_registro   INTEGER,
    fecha_min           DATE,
    fecha_max           DATE,

    -- Aperturas del cierre: por camión/estación y por empresa/cliente.
    -- [{ "clave": "ROM Mina", "litros": 116929 }, ...]
    detalle_por_punto   JSONB       NOT NULL DEFAULT '[]',
    detalle_por_empresa JSONB       NOT NULL DEFAULT '[]',

    -- Trazabilidad de la fuente. Sin esto, un número de gerencia sin dueño.
    fuente_archivo      TEXT,
    cargado_por         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    cargado_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    observacion         TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_cfrm_mes  CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT chk_cfrm_anio CHECK (anio BETWEEN 2020 AND 2100),
    CONSTRAINT uq_cfrm_faena_periodo UNIQUE (faena_codigo, anio, mes)
);

COMMENT ON TABLE combustible_faena_resumen_mensual IS
    'Cierre mensual de combustible por faena, cargado desde las planillas Excel de operación. MIG296.';
COMMENT ON COLUMN combustible_faena_resumen_mensual.fluctuacion_pct IS
    'Fluctuación como fracción del total (0.0008 = 0,08%). Indicador central del control de combustible.';

CREATE INDEX IF NOT EXISTS idx_cfrm_periodo
    ON combustible_faena_resumen_mensual (anio DESC, mes DESC, operacion);

DROP TRIGGER IF EXISTS trg_cfrm_updated_at ON combustible_faena_resumen_mensual;
CREATE TRIGGER trg_cfrm_updated_at
    BEFORE UPDATE ON combustible_faena_resumen_mensual
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE combustible_faena_resumen_mensual ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cfrm_select ON combustible_faena_resumen_mensual;
CREATE POLICY cfrm_select ON combustible_faena_resumen_mensual
    FOR SELECT TO authenticated
    USING (fn_panel_gerencia_puede_ver()
           OR fn_tiene_permiso_modulo('abastecimiento', 'view', ARRAY[
                'administrador','gerencia','subgerente_operaciones',
                'jefe_operaciones','operador_combustible','operador_abastecimiento'
              ]));

DROP POLICY IF EXISTS cfrm_write ON combustible_faena_resumen_mensual;
CREATE POLICY cfrm_write ON combustible_faena_resumen_mensual
    FOR ALL TO authenticated
    USING (fn_tiene_permiso_modulo('abastecimiento', 'create', ARRAY[
                'administrador','gerencia','subgerente_operaciones',
                'jefe_operaciones','operador_combustible'
           ]))
    WITH CHECK (fn_tiene_permiso_modulo('abastecimiento', 'create', ARRAY[
                'administrador','gerencia','subgerente_operaciones',
                'jefe_operaciones','operador_combustible'
           ]));

GRANT SELECT, INSERT, UPDATE, DELETE ON combustible_faena_resumen_mensual TO authenticated;


-- ############################################################################
-- 2. COMBUSTIBLE EN EL PANEL: VOLUMEN REAL + BRECHA DE TRAZABILIDAD
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_combustible_coquimbo(DATE, DATE);
CREATE FUNCTION fn_panel_combustible_coquimbo(
    p_desde DATE,
    p_hasta DATE
)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH periodo AS (
        SELECT EXTRACT(YEAR FROM p_desde)::INTEGER AS anio,
               EXTRACT(MONTH FROM p_desde)::INTEGER AS mes
    ),
    cierre AS (
        SELECT r.* FROM combustible_faena_resumen_mensual r, periodo p
         WHERE r.anio = p.anio AND r.mes = p.mes
    )
    SELECT jsonb_build_object(
        'faenas', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'codigo',            c.faena_codigo,
                'nombre',            c.faena_nombre,
                'transacciones',     c.transacciones,
                'litros_venta',      c.litros_venta,
                'litros_trasvasije', c.litros_trasvasije,
                'litros_total',      c.litros_total,
                'fluctuacion_lt',    c.fluctuacion_lt,
                'fluctuacion_pct',   c.fluctuacion_pct,
                'dias_con_registro', c.dias_con_registro,
                'fecha_min',         c.fecha_min,
                'fecha_max',         c.fecha_max,
                'detalle_por_punto',   c.detalle_por_punto,
                'detalle_por_empresa', c.detalle_por_empresa,
                'fuente_archivo',    c.fuente_archivo,
                'cargado_at',        c.cargado_at
            ) ORDER BY c.litros_total DESC)
            FROM cierre c), '[]'::JSONB),

        'litros_total_periodo', COALESCE((SELECT SUM(litros_total) FROM cierre), 0),
        'con_cierre_cargado',   (SELECT count(*) FROM cierre),

        -- Lo que SÍ está registrado transaccionalmente en el sistema. La
        -- diferencia contra el cierre es exactamente la brecha de trazabilidad.
        'trazado_en_sistema', jsonb_build_object(
            'movimientos_franke', (
                SELECT count(*) FROM combustible_movimientos m
                 WHERE m.created_at::DATE BETWEEN p_desde AND p_hasta),
            'despachos_romeral', (
                SELECT count(*) FROM combustible_faena_despachos d
                 WHERE d.created_at::DATE BETWEEN p_desde AND p_hasta),
            'ultimo_movimiento', (SELECT max(created_at)::DATE FROM combustible_movimientos),
            'ultimo_despacho',   (SELECT max(created_at)::DATE FROM combustible_faena_despachos)
        ),

        -- Infraestructura ya configurada (lo que costó montar y está ocioso).
        'infraestructura', jsonb_build_object(
            'camiones_activos', (SELECT count(*) FROM combustible_estanques
                                  WHERE tipo = 'movil' AND activo),
            'estanques_fijos',  (SELECT count(*) FROM combustible_estanques
                                  WHERE tipo = 'fijo' AND activo),
            'romeral_ubicaciones', (
                SELECT count(*) FROM combustible_faena_ubicaciones u
                  JOIN faenas f ON f.id = u.faena_id
                 WHERE f.codigo = 'FAE-CMP-ROMERAL' AND u.activo),
            'romeral_equipos', (
                SELECT count(*) FROM combustible_faena_equipos e
                  JOIN faenas f ON f.id = e.faena_id
                 WHERE f.codigo = 'FAE-CMP-ROMERAL')
        )
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) IS
    'Combustible de faenas: volumen real del cierre mensual vs. lo trazado en el sistema. MIG296.';


-- ############################################################################
-- 3. TALLER: SEPARAR EL PROCESO DIGITAL DEL ARRASTRE + RESUMEN POR FECHA
-- ############################################################################

DROP FUNCTION IF EXISTS fn_panel_taller(DATE, DATE, TEXT);
CREATE FUNCTION fn_panel_taller(
    p_desde     DATE,
    p_hasta     DATE,
    p_operacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH base AS (
        SELECT o.*, (o.created_at::DATE BETWEEN p_desde AND p_hasta) AS del_periodo
          FROM ordenes_trabajo o
          LEFT JOIN activos a ON a.id = o.activo_id
         WHERE p_operacion IS NULL OR a.operacion = p_operacion
    ),
    abiertas AS (
        SELECT * FROM base
         WHERE estado::TEXT IN ('creada','asignada','en_ejecucion','pausada')
    ),
    nc AS (
        SELECT n.*, (n.created_at::DATE BETWEEN p_desde AND p_hasta) AS del_periodo
          FROM no_conformidades n
          LEFT JOIN activos a2 ON a2.id = n.activo_id
         WHERE p_operacion IS NULL OR a2.operacion = p_operacion
    )
    SELECT jsonb_build_object(
        -- ── Lo que produjo el proceso digital EN el período ────────────────
        'periodo', jsonb_build_object(
            'ot_creadas',    (SELECT count(*) FROM base     WHERE del_periodo),
            'ot_abiertas',   (SELECT count(*) FROM abiertas WHERE del_periodo),
            'ot_cerradas',   (SELECT count(*) FROM base
                               WHERE estado::TEXT IN ('ejecutada_ok','ejecutada_con_observaciones')
                                 AND COALESCE(fecha_termino, updated_at)::DATE BETWEEN p_desde AND p_hasta),
            'ot_correctivas',(SELECT count(*) FROM base WHERE del_periodo AND tipo::TEXT = 'correctivo'),
            'ot_preventivas',(SELECT count(*) FROM base WHERE del_periodo AND tipo::TEXT = 'preventivo'),
            'ot_primera',    (SELECT min(created_at)::DATE FROM base WHERE del_periodo),
            'ot_ultima',     (SELECT max(created_at)::DATE FROM base WHERE del_periodo),
            'nc_creadas',    (SELECT count(*) FROM nc WHERE del_periodo),
            'nc_abiertas',   (SELECT count(*) FROM nc WHERE del_periodo AND NOT resuelto),
            'nc_altas',      (SELECT count(*) FROM nc WHERE del_periodo
                                AND severidad::TEXT IN ('critica','alta')),
            'nc_primera',    (SELECT min(created_at)::DATE FROM nc WHERE del_periodo),
            'nc_ultima',     (SELECT max(created_at)::DATE FROM nc WHERE del_periodo),
            -- De dónde nacen las NC: el checklist digital produce
            -- 'ejecucion_ot' e 'inspeccion_ot'; 'manual' es carga a mano.
            'nc_por_origen', COALESCE((
                SELECT jsonb_object_agg(origen, n) FROM (
                    SELECT COALESCE(origen::TEXT, 'sin_origen') AS origen, count(*) AS n
                      FROM nc WHERE del_periodo GROUP BY 1
                ) s), '{}'::JSONB)
        ),

        -- ── Arrastre: abierto pero nacido ANTES del período ────────────────
        -- Es el pasivo heredado del proceso anterior. No mide al proceso nuevo.
        'arrastre', jsonb_build_object(
            'ot_abiertas',       (SELECT count(*) FROM abiertas WHERE NOT del_periodo),
            'ot_mas_antigua',    (SELECT min(created_at)::DATE FROM abiertas WHERE NOT del_periodo),
            'ot_dias_prom',      (SELECT ROUND(AVG(EXTRACT(DAY FROM NOW() - created_at))::NUMERIC, 1)
                                    FROM abiertas WHERE NOT del_periodo),
            'nc_abiertas',       (SELECT count(*) FROM nc WHERE NOT del_periodo AND NOT resuelto),
            'nc_mas_antigua',    (SELECT min(created_at)::DATE FROM nc WHERE NOT del_periodo AND NOT resuelto)
        ),

        -- ── Totales vivos (período + arrastre) ─────────────────────────────
        'ot_abiertas',        (SELECT count(*) FROM abiertas),
        'ot_correctivas',     (SELECT count(*) FROM abiertas WHERE tipo::TEXT = 'correctivo'),
        'ot_preventivas',     (SELECT count(*) FROM abiertas WHERE tipo::TEXT = 'preventivo'),
        'ot_en_ejecucion',    (SELECT count(*) FROM abiertas WHERE estado::TEXT = 'en_ejecucion'),
        'ot_pausadas',        (SELECT count(*) FROM abiertas WHERE estado::TEXT = 'pausada'),
        'ot_sin_responsable', (SELECT count(*) FROM abiertas
                                WHERE responsable_id IS NULL AND tecnico_id IS NULL),
        'backlog_dias_prom',  (SELECT ROUND(AVG(EXTRACT(DAY FROM NOW() - created_at))::NUMERIC, 1)
                                FROM abiertas),
        'backlog_mas_antigua',(SELECT min(created_at)::DATE FROM abiertas),
        'nc_abiertas',        (SELECT count(*) FROM nc WHERE NOT resuelto),
        'nc_criticas_abiertas',(SELECT count(*) FROM nc
                                WHERE NOT resuelto AND severidad::TEXT IN ('critica','alta')),

        -- Compatibilidad con MIG295 (el frontend viejo sigue leyendo estas).
        'ot_creadas_periodo', (SELECT count(*) FROM base WHERE del_periodo),
        'ot_cerradas_periodo',(SELECT count(*) FROM base
                                WHERE estado::TEXT IN ('ejecutada_ok','ejecutada_con_observaciones')
                                  AND COALESCE(fecha_termino, updated_at)::DATE BETWEEN p_desde AND p_hasta),
        'nc_periodo',         (SELECT count(*) FROM nc WHERE del_periodo),

        -- ── RESUMEN POR FECHA ──────────────────────────────────────────────
        -- Día a día del período: cuántas OT y cuántas NC. Permite ver si el
        -- proceso digital se usa todos los días o solo cuando alguien empuja.
        'por_fecha', COALESCE((
            SELECT jsonb_agg(jsonb_build_object('fecha', d, 'ot', ot, 'nc', ncs) ORDER BY d)
              FROM (
                SELECT dd::DATE AS d,
                       (SELECT count(*) FROM base b
                         WHERE b.created_at::DATE = dd::DATE AND b.del_periodo) AS ot,
                       (SELECT count(*) FROM nc n
                         WHERE n.created_at::DATE = dd::DATE AND n.del_periodo) AS ncs
                  FROM generate_series(p_desde, p_hasta, INTERVAL '1 day') dd
              ) s
             WHERE ot > 0 OR ncs > 0), '[]'::JSONB)
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_taller(DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_panel_taller(DATE, DATE, TEXT) IS
    'Taller: separa lo producido por el proceso digital en el período del arrastre anterior, con resumen día a día. MIG296.';
