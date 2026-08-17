-- ============================================================================
-- SICOM-ICEO | 297 — Fluctuaciones de combustible + corrección manual
-- ============================================================================
-- La fluctuación (teórico vs. físico) es EL indicador del negocio de
-- combustible: es la merma, y es lo que se defiende frente al mandante.
--
-- ── POR QUÉ LA CORRECCIÓN MANUAL ES OBLIGATORIA, NO UN LUJO ────────────────
--
-- Las planillas de cierre no se dejan parsear de forma confiable. Casos reales
-- encontrados al leer el cierre de Romeral de agosto 2026:
--
--   · La celda "MES:" está desactualizada: BIMODAL dice 2026-05-01 y
--     CASA FUERZA dice 2026-01-01, en un archivo de agosto.
--   · El teórico está precalculado para los 31 días, así que los días futuros
--     traen físico = 0 y una variación de -teórico. Sumar el mes completo daba
--     -289% en BIMODAL.
--   · El último día del cierre está a medias: el 13 de agosto MINA registra
--     30.000 L de recepción sin lectura física (-11.700 L de "variación").
--   · Cada estanque tiene distinta cantidad de columnas, así que ni siquiera
--     los índices son estables entre hojas de un mismo archivo.
--
-- Con el corte correcto (último día con despachos o ventas reales) los números
-- cuadran con los totales que la propia planilla calcula: BIMODAL -291 L y
-- MINA +1.097 L. Pero esa regla es una heurística, no una garantía: el mes que
-- viene la planilla cambia y vuelve a fallar.
--
-- Por eso el valor cargado automáticamente es SIEMPRE una PROPUESTA, y quien
-- manda es la corrección de gerencia. Se conserva `valores_originales` con lo
-- que trajo el archivo, para que en la reunión se pueda mostrar qué decía el
-- Excel y qué corrigió una persona, con nombre y motivo.
--
-- ADITIVA. No modifica ni borra datos existentes.
-- ============================================================================


-- ############################################################################
-- 0. QUIÉN PUEDE CORREGIR
-- ############################################################################
-- Corregir un número que va al Gerente General no es lo mismo que registrar un
-- despacho. Lista más corta que la de carga operativa.
-- Va primero porque las políticas RLS de más abajo la invocan.

CREATE OR REPLACE FUNCTION fn_combustible_puede_corregir()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('abastecimiento', 'edit', ARRAY[
        'administrador','gerencia','subgerente_operaciones','jefe_operaciones'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_combustible_puede_corregir() TO authenticated;

COMMENT ON FUNCTION fn_combustible_puede_corregir() IS
    'Quién puede corregir a mano las cifras de combustible que ve gerencia. MIG297.';


-- ############################################################################
-- 1. CORRECCIÓN MANUAL SOBRE EL RESUMEN MENSUAL
-- ############################################################################

ALTER TABLE combustible_faena_resumen_mensual
    ADD COLUMN IF NOT EXISTS corregido_manual   BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS motivo_correccion  TEXT,
    ADD COLUMN IF NOT EXISTS corregido_por      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS corregido_at       TIMESTAMPTZ,
    -- Snapshot de lo que trajo el archivo antes de la primera corrección.
    ADD COLUMN IF NOT EXISTS valores_originales JSONB;

COMMENT ON COLUMN combustible_faena_resumen_mensual.corregido_manual IS
    'true = una persona corrigió estos números. El cargador ya no los pisa. MIG297.';
COMMENT ON COLUMN combustible_faena_resumen_mensual.valores_originales IS
    'Lo que decía la planilla antes de la primera corrección manual. Evidencia para la reunión. MIG297.';


-- ############################################################################
-- 2. FLUCTUACIÓN POR PUNTO (ESTANQUE / ISLA / CAMIÓN)
-- ############################################################################
-- El resumen mensual da el total de la faena; la gestión ocurre por estanque.
-- Una faena con fluctuación neta 0% puede tener un estanque en -3% y otro
-- en +3%: el neto miente y el detalle no.

CREATE TABLE IF NOT EXISTS combustible_fluctuacion_punto (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    faena_codigo      VARCHAR(60) NOT NULL,     -- FRANKE | ROMERAL
    anio              INTEGER     NOT NULL,
    mes               INTEGER     NOT NULL,
    punto             VARCHAR(120) NOT NULL,    -- BIMODAL | MINA | CASA FUERZA | ...
    tipo_punto        VARCHAR(30) NOT NULL DEFAULT 'estanque',

    -- Movimiento del período.
    litros_despachados NUMERIC(14,2),
    litros_recepcion   NUMERIC(14,2),

    -- El indicador. Positivo = sobra combustible; negativo = falta (merma).
    fluctuacion_lt    NUMERIC(14,2),
    fluctuacion_pct   NUMERIC(8,4),             -- fracción: -0.0192 = -1,92%

    dias_cuadrados    INTEGER,
    ultimo_dia_cuadre DATE,

    -- 'orpak'  → sistema automático de medición
    -- 'excel'  → planilla de cierre (propuesta del cargador)
    -- 'manual' → cargado o corregido por una persona
    origen            VARCHAR(20) NOT NULL DEFAULT 'excel',

    corregido_manual  BOOLEAN     NOT NULL DEFAULT false,
    motivo_correccion TEXT,
    corregido_por     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    corregido_at      TIMESTAMPTZ,
    valores_originales JSONB,

    observacion       TEXT,
    fuente_archivo    TEXT,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_cfp_mes   CHECK (mes BETWEEN 1 AND 12),
    CONSTRAINT chk_cfp_origen CHECK (origen IN ('orpak','excel','manual')),
    CONSTRAINT uq_cfp_punto_periodo UNIQUE (faena_codigo, anio, mes, punto)
);

COMMENT ON TABLE combustible_fluctuacion_punto IS
    'Fluctuación (teórico vs físico) por estanque y mes, corregible por gerencia. MIG297.';

CREATE INDEX IF NOT EXISTS idx_cfp_periodo
    ON combustible_fluctuacion_punto (anio DESC, mes DESC, faena_codigo);

DROP TRIGGER IF EXISTS trg_cfp_updated_at ON combustible_fluctuacion_punto;
CREATE TRIGGER trg_cfp_updated_at
    BEFORE UPDATE ON combustible_fluctuacion_punto
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE combustible_fluctuacion_punto ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cfp_select ON combustible_fluctuacion_punto;
CREATE POLICY cfp_select ON combustible_fluctuacion_punto
    FOR SELECT TO authenticated
    USING (fn_panel_gerencia_puede_ver()
           OR fn_tiene_permiso_modulo('abastecimiento', 'view', ARRAY[
                'administrador','gerencia','subgerente_operaciones',
                'jefe_operaciones','operador_combustible','operador_abastecimiento'
              ]));

DROP POLICY IF EXISTS cfp_write ON combustible_fluctuacion_punto;
CREATE POLICY cfp_write ON combustible_fluctuacion_punto
    FOR ALL TO authenticated
    USING (fn_combustible_puede_corregir())
    WITH CHECK (fn_combustible_puede_corregir());

GRANT SELECT, INSERT, UPDATE, DELETE ON combustible_fluctuacion_punto TO authenticated;


-- ############################################################################
-- 3. RPC: CORREGIR EL RESUMEN MENSUAL DE UNA FAENA
-- ############################################################################
-- Solo pisa los campos que vengan NO NULOS: así el usuario corrige la
-- fluctuación sin tener que reescribir los litros.

DROP FUNCTION IF EXISTS fn_combustible_corregir_resumen(TEXT, INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT);
CREATE FUNCTION fn_combustible_corregir_resumen(
    p_faena_codigo     TEXT,
    p_anio             INTEGER,
    p_mes              INTEGER,
    p_litros_venta     NUMERIC DEFAULT NULL,
    p_litros_trasvasije NUMERIC DEFAULT NULL,
    p_fluctuacion_lt   NUMERIC DEFAULT NULL,
    p_fluctuacion_pct  NUMERIC DEFAULT NULL,
    p_transacciones    INTEGER DEFAULT NULL,
    p_motivo           TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_fila combustible_faena_resumen_mensual%ROWTYPE;
BEGIN
    IF NOT fn_combustible_puede_corregir() THEN
        RAISE EXCEPTION 'No autorizado para corregir cifras de combustible.'
            USING ERRCODE = '42501';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
        RAISE EXCEPTION 'El motivo de la corrección es obligatorio: este número va al Gerente General.'
            USING ERRCODE = '23514';
    END IF;

    SELECT * INTO v_fila FROM combustible_faena_resumen_mensual
     WHERE faena_codigo = p_faena_codigo AND anio = p_anio AND mes = p_mes;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe cierre de % para %-%.', p_faena_codigo, p_anio, p_mes
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE combustible_faena_resumen_mensual SET
        -- Se guarda el original UNA sola vez: en la primera corrección. Después
        -- ya no, o se perdería lo que realmente decía el archivo.
        valores_originales = COALESCE(valores_originales, jsonb_build_object(
            'litros_venta',      v_fila.litros_venta,
            'litros_trasvasije', v_fila.litros_trasvasije,
            'litros_total',      v_fila.litros_total,
            'fluctuacion_lt',    v_fila.fluctuacion_lt,
            'fluctuacion_pct',   v_fila.fluctuacion_pct,
            'transacciones',     v_fila.transacciones,
            'fuente_archivo',    v_fila.fuente_archivo
        )),
        litros_venta      = COALESCE(p_litros_venta,      litros_venta),
        litros_trasvasije = COALESCE(p_litros_trasvasije, litros_trasvasije),
        litros_total      = COALESCE(p_litros_venta,      litros_venta)
                          + COALESCE(p_litros_trasvasije, litros_trasvasije),
        fluctuacion_lt    = COALESCE(p_fluctuacion_lt,    fluctuacion_lt),
        fluctuacion_pct   = COALESCE(p_fluctuacion_pct,   fluctuacion_pct),
        transacciones     = COALESCE(p_transacciones,     transacciones),
        corregido_manual  = true,
        motivo_correccion = trim(p_motivo),
        corregido_por     = auth.uid(),
        corregido_at      = NOW()
     WHERE faena_codigo = p_faena_codigo AND anio = p_anio AND mes = p_mes
    RETURNING * INTO v_fila;

    RETURN to_jsonb(v_fila);
END $$;
GRANT EXECUTE ON FUNCTION fn_combustible_corregir_resumen(TEXT, INTEGER, INTEGER, NUMERIC, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_combustible_corregir_resumen IS
    'Corrige a mano el cierre mensual de combustible de una faena. Motivo obligatorio. MIG297.';


-- ############################################################################
-- 4. RPC: CORREGIR / CREAR LA FLUCTUACIÓN DE UN PUNTO
-- ############################################################################
-- Hace upsert: sirve tanto para corregir lo que trajo el cargador como para
-- cargar a mano un estanque que la planilla no permitió leer (hoy, CASA FUERZA
-- de Romeral, cuya hoja tiene otra estructura y viene sin datos).

DROP FUNCTION IF EXISTS fn_combustible_corregir_fluctuacion(TEXT, INTEGER, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT);
CREATE FUNCTION fn_combustible_corregir_fluctuacion(
    p_faena_codigo      TEXT,
    p_anio              INTEGER,
    p_mes               INTEGER,
    p_punto             TEXT,
    p_litros_despachados NUMERIC DEFAULT NULL,
    p_fluctuacion_lt    NUMERIC DEFAULT NULL,
    p_fluctuacion_pct   NUMERIC DEFAULT NULL,
    p_dias_cuadrados    INTEGER DEFAULT NULL,
    p_observacion       TEXT    DEFAULT NULL,
    p_motivo            TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_fila combustible_fluctuacion_punto%ROWTYPE;
    v_pct  NUMERIC;
BEGIN
    IF NOT fn_combustible_puede_corregir() THEN
        RAISE EXCEPTION 'No autorizado para corregir cifras de combustible.'
            USING ERRCODE = '42501';
    END IF;
    IF p_motivo IS NULL OR length(trim(p_motivo)) = 0 THEN
        RAISE EXCEPTION 'El motivo de la corrección es obligatorio.'
            USING ERRCODE = '23514';
    END IF;

    -- Si dan litros y fluctuación pero no el %, se calcula. Es el error más
    -- fácil de cometer a mano y el más caro: un % mal tipeado se discute en
    -- directorio como si fuera real.
    v_pct := COALESCE(p_fluctuacion_pct,
        CASE WHEN COALESCE(p_litros_despachados, 0) <> 0 AND p_fluctuacion_lt IS NOT NULL
             THEN p_fluctuacion_lt / p_litros_despachados END);

    SELECT * INTO v_fila FROM combustible_fluctuacion_punto
     WHERE faena_codigo = p_faena_codigo AND anio = p_anio
       AND mes = p_mes AND punto = p_punto;

    IF FOUND THEN
        UPDATE combustible_fluctuacion_punto SET
            valores_originales = COALESCE(valores_originales, jsonb_build_object(
                'litros_despachados', v_fila.litros_despachados,
                'fluctuacion_lt',     v_fila.fluctuacion_lt,
                'fluctuacion_pct',    v_fila.fluctuacion_pct,
                'dias_cuadrados',     v_fila.dias_cuadrados,
                'origen',             v_fila.origen
            )),
            litros_despachados = COALESCE(p_litros_despachados, litros_despachados),
            fluctuacion_lt     = COALESCE(p_fluctuacion_lt,     fluctuacion_lt),
            fluctuacion_pct    = COALESCE(v_pct,                fluctuacion_pct),
            dias_cuadrados     = COALESCE(p_dias_cuadrados,     dias_cuadrados),
            observacion        = COALESCE(p_observacion,        observacion),
            origen             = 'manual',
            corregido_manual   = true,
            motivo_correccion  = trim(p_motivo),
            corregido_por      = auth.uid(),
            corregido_at       = NOW()
         WHERE id = v_fila.id
        RETURNING * INTO v_fila;
    ELSE
        INSERT INTO combustible_fluctuacion_punto (
            faena_codigo, anio, mes, punto, litros_despachados,
            fluctuacion_lt, fluctuacion_pct, dias_cuadrados, observacion,
            origen, corregido_manual, motivo_correccion, corregido_por, corregido_at
        ) VALUES (
            p_faena_codigo, p_anio, p_mes, p_punto, p_litros_despachados,
            p_fluctuacion_lt, v_pct, p_dias_cuadrados, p_observacion,
            'manual', true, trim(p_motivo), auth.uid(), NOW()
        ) RETURNING * INTO v_fila;
    END IF;

    RETURN to_jsonb(v_fila);
END $$;
GRANT EXECUTE ON FUNCTION fn_combustible_corregir_fluctuacion(TEXT, INTEGER, INTEGER, TEXT, NUMERIC, NUMERIC, NUMERIC, INTEGER, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_combustible_corregir_fluctuacion IS
    'Upsert manual de la fluctuación de un estanque. Calcula el % si no lo dan. MIG297.';


-- ############################################################################
-- 5. EL PANEL MUESTRA LAS FLUCTUACIONES Y SI FUERON CORREGIDAS
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
    ),
    fluct AS (
        SELECT f.* FROM combustible_fluctuacion_punto f, periodo p
         WHERE f.anio = p.anio AND f.mes = p.mes
    )
    SELECT jsonb_build_object(
        'periodo', (SELECT jsonb_build_object('anio', anio, 'mes', mes) FROM periodo),

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
                'cargado_at',        c.cargado_at,
                'corregido_manual',  c.corregido_manual,
                'motivo_correccion', c.motivo_correccion,
                'corregido_at',      c.corregido_at,
                'corregido_por_nombre', (
                    SELECT up.nombre_completo FROM usuarios_perfil up
                     WHERE up.id = c.corregido_por),
                'valores_originales', c.valores_originales,
                -- Fluctuación por estanque de esta faena.
                'puntos', COALESCE((
                    SELECT jsonb_agg(jsonb_build_object(
                        'punto',              f.punto,
                        'litros_despachados', f.litros_despachados,
                        'fluctuacion_lt',     f.fluctuacion_lt,
                        'fluctuacion_pct',    f.fluctuacion_pct,
                        'dias_cuadrados',     f.dias_cuadrados,
                        'origen',             f.origen,
                        'corregido_manual',   f.corregido_manual,
                        'motivo_correccion',  f.motivo_correccion,
                        'observacion',        f.observacion
                    ) ORDER BY abs(COALESCE(f.fluctuacion_pct, 0)) DESC)
                    FROM fluct f WHERE f.faena_codigo = c.faena_codigo), '[]'::JSONB)
            ) ORDER BY c.litros_total DESC)
            FROM cierre c), '[]'::JSONB),

        'litros_total_periodo', COALESCE((SELECT SUM(litros_total) FROM cierre), 0),
        'con_cierre_cargado',   (SELECT count(*) FROM cierre),
        'corregidos_a_mano',    (SELECT count(*) FROM cierre WHERE corregido_manual),
        -- Estanques cuya fluctuación se salió del umbral de gestión (0,5%).
        'puntos_fuera_umbral',  (SELECT count(*) FROM fluct
                                  WHERE abs(COALESCE(fluctuacion_pct, 0)) > 0.005),

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

        'infraestructura', jsonb_build_object(
            'camiones_activos', (SELECT count(*) FROM combustible_estanques
                                  WHERE tipo = 'movil' AND activo),
            'estanques_fijos',  (SELECT count(*) FROM combustible_estanques
                                  WHERE tipo = 'fijo' AND activo),
            'romeral_ubicaciones', (
                SELECT count(*) FROM combustible_faena_ubicaciones u
                  JOIN faenas f2 ON f2.id = u.faena_id
                 WHERE f2.codigo = 'FAE-CMP-ROMERAL' AND u.activo),
            'romeral_equipos', (
                SELECT count(*) FROM combustible_faena_equipos e
                  JOIN faenas f3 ON f3.id = e.faena_id
                 WHERE f3.codigo = 'FAE-CMP-ROMERAL')
        )
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) IS
    'Combustible: cierre mensual, fluctuación por estanque y marca de corrección manual. MIG297.';
