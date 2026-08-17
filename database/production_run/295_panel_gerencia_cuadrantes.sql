-- ============================================================================
-- SICOM-ICEO | 295 — Panel de Gerencia: cuadrantes Coquimbo y Calama
-- ============================================================================
-- Tablero semanal para el Gerente General. Dos cuadrantes:
--
--   COQUIMBO → taller · disponibilidad del mes · equipos con mayor tiempo
--              detenido (con plan de acción) · combustible Franke y Romeral.
--   CALAMA   → las 5 faenas del contrato ENEX: plan de combustibles Centinela,
--              mejoras Centinela (NCEN_DES), combustible Spence, combustible
--              Lomas Bayas (LB_COMB) y lubricantes Lomas Bayas (LB_LUB).
--
-- Más un cuaderno de comentarios: por equipo (con plan de acción, responsable y
-- fecha compromiso) y de la semana completa.
--
-- ── DECISIONES DE DISEÑO ────────────────────────────────────────────────────
--
--  1. LA OPERACIÓN SE LEE DE `activos`, NO DE `estado_diario_flota`.
--     El estado diario NO lo genera un proceso automático: lo carga el
--     PLANIFICADOR a mano desde /dashboard/flota/sugerencias (el cron
--     `flota_estados_diarios` está inactivo, y en agosto los 55 equipos de
--     cada día vienen con override_manual = true y calculado_auto = 0).
--     Esa carga manual no rellena la columna `operacion`: viene NULL en todas
--     las filas desde el 2026-04-11. Solo la carga histórica de Excel la traía,
--     y esa llega hasta el 2026-07-22.
--     Filtrar por esa columna dejaría el cuadrante Coquimbo vacío justo en el
--     mes que se quiere mirar. Se usa COALESCE(e.operacion, a.operacion) para
--     aprovechar el histórico donde existe y caer al maestro donde no.
--
--  1b. COROLARIO: EL PANEL VALE LO QUE VALE LA CARGA DEL PLANIFICADOR.
--     Si el planificador no carga un día, ese día simplemente no existe y la
--     disponibilidad del mes queda calculada sobre menos días —sin avisar—.
--     Por eso el panel expone un bloque de CALIDAD DEL DATO (§2.5): días
--     cargados vs. días transcurridos, último día cargado y cobertura de
--     equipos. Un tablero de gerencia que no declara la frescura de su fuente
--     induce a decidir sobre datos viejos.
--
--  2. "DETENIDO" = estado M (mantención), T (taller) o F (fuera de servicio).
--     Es la misma definición que usa `generar-reporte-outlook.mjs` para
--     disponibilidad, para que el panel y el reporte de flota nunca discrepen.
--
--  3. OT ABIERTA POR LISTA BLANCA, no por descarte. Los estados abiertos son
--     creada · asignada · en_ejecucion · pausada. Si mañana se agrega un estado
--     al enum, el panel lo ignora en vez de contarlo como abierto por error.
--
--  4. LOS CUADRANTES QUE AÚN NO TIENEN PLAN NO SE OCULTAN: se muestran con su
--     brecha explícita. Hoy SPENCE y LB_COMB tienen 0 instalaciones cargadas,
--     así que su avance es "sin plan". Esconderlos daría la falsa impresión de
--     que el contrato está cubierto. El panel queda listo para que, al terminar
--     de cargar el plan, el avance aparezca solo, sin tocar código.
--
-- ADITIVA. No modifica ni borra datos de otros módulos.
-- ============================================================================


-- ############################################################################
-- 0. AUTORIZACIÓN
-- ############################################################################
-- Se engancha a la matriz configurable de MIG126 (Admin → perfiles y roles),
-- módulo 'gerencia'. Los roles de abajo son solo el DEFAULT: agregar o quitar
-- gente después NO requiere otra migración.

CREATE OR REPLACE FUNCTION fn_panel_gerencia_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('gerencia', 'view', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','jefe_mantenimiento','supervisor','planificador'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_panel_gerencia_puede_ver() TO authenticated;

COMMENT ON FUNCTION fn_panel_gerencia_puede_ver() IS
    'Quién ve el Panel de Gerencia. Permiso view del módulo gerencia (MIG126). MIG295.';


CREATE OR REPLACE FUNCTION fn_panel_gerencia_puede_comentar()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('gerencia', 'create', ARRAY[
        'administrador','gerencia','subgerente_operaciones',
        'jefe_operaciones','jefe_mantenimiento','supervisor'
    ]);
$$;
GRANT EXECUTE ON FUNCTION fn_panel_gerencia_puede_comentar() TO authenticated;

COMMENT ON FUNCTION fn_panel_gerencia_puede_comentar() IS
    'Quién escribe comentarios y planes de acción en el Panel de Gerencia. MIG295.';


-- ############################################################################
-- 1. CUADERNO DE COMENTARIOS (por equipo y de la semana)
-- ############################################################################

CREATE TABLE IF NOT EXISTS panel_comentarios (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Lunes de la semana ISO a la que pertenece el comentario.
    semana            DATE        NOT NULL,

    -- A qué se refiere: la semana completa, un cuadrante, un equipo o una
    -- faena del contrato ENEX.
    ambito            VARCHAR(20) NOT NULL,

    cuadrante         VARCHAR(20),                 -- coquimbo | calama
    activo_id         UUID REFERENCES activos(id)      ON DELETE CASCADE,
    enex_faena_id     UUID REFERENCES enex_faenas(id)  ON DELETE CASCADE,

    texto             TEXT        NOT NULL,

    -- Plan de acción a seguir. Aplica sobre todo al ámbito 'equipo', que es
    -- donde el GG pregunta "¿y qué van a hacer con esta máquina?".
    plan_accion       TEXT,
    responsable       VARCHAR(160),
    fecha_compromiso  DATE,

    autor_id          UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_panel_com_ambito
        CHECK (ambito IN ('semana','cuadrante','equipo','faena_enex')),
    CONSTRAINT chk_panel_com_cuadrante
        CHECK (cuadrante IS NULL OR cuadrante IN ('coquimbo','calama')),
    CONSTRAINT chk_panel_com_texto
        CHECK (length(trim(texto)) > 0),

    -- Cada ámbito exige exactamente su propia llave. Sin esto se cuelan filas
    -- huérfanas (un comentario 'equipo' sin equipo) que después rompen el panel.
    CONSTRAINT chk_panel_com_llave CHECK (
        (ambito = 'semana'     AND activo_id IS NULL AND enex_faena_id IS NULL AND cuadrante IS NULL)
     OR (ambito = 'cuadrante'  AND activo_id IS NULL AND enex_faena_id IS NULL AND cuadrante IS NOT NULL)
     OR (ambito = 'equipo'     AND activo_id IS NOT NULL AND enex_faena_id IS NULL)
     OR (ambito = 'faena_enex' AND enex_faena_id IS NOT NULL AND activo_id IS NULL)
    )
);

COMMENT ON TABLE panel_comentarios IS
    'Comentarios y planes de acción del Panel de Gerencia, por semana. MIG295.';

-- Un comentario por cosa por semana (se edita, no se duplica). Índices únicos
-- parciales porque las llaves nulas no colisionan en un UNIQUE normal.
CREATE UNIQUE INDEX IF NOT EXISTS uq_panel_com_semana
    ON panel_comentarios (semana) WHERE ambito = 'semana';
CREATE UNIQUE INDEX IF NOT EXISTS uq_panel_com_cuadrante
    ON panel_comentarios (semana, cuadrante) WHERE ambito = 'cuadrante';
CREATE UNIQUE INDEX IF NOT EXISTS uq_panel_com_equipo
    ON panel_comentarios (semana, activo_id) WHERE ambito = 'equipo';
CREATE UNIQUE INDEX IF NOT EXISTS uq_panel_com_faena
    ON panel_comentarios (semana, enex_faena_id) WHERE ambito = 'faena_enex';

CREATE INDEX IF NOT EXISTS idx_panel_com_semana ON panel_comentarios (semana DESC, ambito);

DROP TRIGGER IF EXISTS trg_panel_comentarios_updated_at ON panel_comentarios;
CREATE TRIGGER trg_panel_comentarios_updated_at
    BEFORE UPDATE ON panel_comentarios
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE panel_comentarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS panel_com_select ON panel_comentarios;
CREATE POLICY panel_com_select ON panel_comentarios
    FOR SELECT TO authenticated
    USING (fn_panel_gerencia_puede_ver());

DROP POLICY IF EXISTS panel_com_insert ON panel_comentarios;
CREATE POLICY panel_com_insert ON panel_comentarios
    FOR INSERT TO authenticated
    WITH CHECK (fn_panel_gerencia_puede_comentar());

DROP POLICY IF EXISTS panel_com_update ON panel_comentarios;
CREATE POLICY panel_com_update ON panel_comentarios
    FOR UPDATE TO authenticated
    USING (fn_panel_gerencia_puede_comentar())
    WITH CHECK (fn_panel_gerencia_puede_comentar());

DROP POLICY IF EXISTS panel_com_delete ON panel_comentarios;
CREATE POLICY panel_com_delete ON panel_comentarios
    FOR DELETE TO authenticated
    USING (fn_panel_gerencia_puede_comentar());

GRANT SELECT, INSERT, UPDATE, DELETE ON panel_comentarios TO authenticated;


-- ############################################################################
-- 2. CUADRANTE COQUIMBO
-- ############################################################################

-- ── 2.1 Disponibilidad del período, equipo por equipo ───────────────────────
DROP FUNCTION IF EXISTS fn_panel_disponibilidad(DATE, DATE, TEXT);
CREATE FUNCTION fn_panel_disponibilidad(
    p_desde     DATE,
    p_hasta     DATE,
    p_operacion TEXT DEFAULT NULL
)
RETURNS TABLE (
    activo_id          UUID,
    codigo             TEXT,
    patente            TEXT,
    nombre             TEXT,
    operacion          TEXT,
    dias_obs           INTEGER,
    dias_up            INTEGER,
    dias_down          INTEGER,
    disponibilidad_pct NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(e.operacion, a.operacion)::TEXT,
           count(*)::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))::INTEGER,
           count(*) FILTER (WHERE e.estado_codigo IN ('M','T','F'))::INTEGER,
           ROUND(100.0 * count(*) FILTER (WHERE e.estado_codigo NOT IN ('M','T','F'))
                 / NULLIF(count(*), 0), 1)
      FROM estado_diario_flota e
      JOIN activos a ON a.id = e.activo_id
     WHERE e.fecha BETWEEN p_desde AND p_hasta
       AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
     GROUP BY a.id, a.codigo, a.patente, a.nombre, COALESCE(e.operacion, a.operacion)
     ORDER BY 9 ASC NULLS LAST, 8 DESC;
$$;
GRANT EXECUTE ON FUNCTION fn_panel_disponibilidad(DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_panel_disponibilidad(DATE, DATE, TEXT) IS
    'Disponibilidad por equipo en un rango. Detenido = M/T/F. Operación desde activos si estado_diario no la trae. MIG295.';


-- ── 2.2 Equipos con mayor tiempo detenido + su plan de acción ───────────────
-- Ordena por días detenidos en el período y arrastra: cuántos días lleva
-- detenido de corrido hasta hoy, la OT abierta si existe, y el comentario /
-- plan de acción que se haya escrito para ese equipo en la semana.
DROP FUNCTION IF EXISTS fn_panel_equipos_detenidos(DATE, DATE, TEXT, INTEGER, DATE);
CREATE FUNCTION fn_panel_equipos_detenidos(
    p_desde     DATE,
    p_hasta     DATE,
    p_operacion TEXT    DEFAULT NULL,
    p_limit     INTEGER DEFAULT 10,
    p_semana    DATE    DEFAULT NULL
)
RETURNS TABLE (
    activo_id         UUID,
    codigo            TEXT,
    patente           TEXT,
    nombre            TEXT,
    operacion         TEXT,
    dias_detenido     INTEGER,
    dias_obs          INTEGER,
    pct_detenido      NUMERIC,
    estado_actual     TEXT,
    detenido_desde    DATE,
    dias_consecutivos INTEGER,
    ot_folio          TEXT,
    ot_estado         TEXT,
    ot_tipo           TEXT,
    comentario        TEXT,
    plan_accion       TEXT,
    responsable       TEXT,
    fecha_compromiso  DATE
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH dias AS (
        SELECT e.activo_id,
               e.fecha,
               e.estado_codigo,
               (e.estado_codigo IN ('M','T','F')) AS down
          FROM estado_diario_flota e
          JOIN activos a ON a.id = e.activo_id
         WHERE e.fecha BETWEEN p_desde AND p_hasta
           AND (p_operacion IS NULL OR COALESCE(e.operacion, a.operacion) = p_operacion)
    ),
    agg AS (
        SELECT activo_id,
               count(*)::INTEGER                              AS dias_obs,
               count(*) FILTER (WHERE down)::INTEGER           AS dias_detenido,
               -- Último día NO detenido: lo que venga después es la racha viva.
               max(fecha) FILTER (WHERE NOT down)              AS ultimo_ok,
               max(fecha)                                      AS ultima_fecha,
               (array_agg(estado_codigo ORDER BY fecha DESC))[1] AS estado_actual,
               (array_agg(down          ORDER BY fecha DESC))[1] AS down_actual
          FROM dias
         GROUP BY activo_id
        HAVING count(*) FILTER (WHERE down) > 0
    ),
    ot AS (
        -- OT abierta más reciente por equipo. Lista blanca de estados abiertos.
        SELECT DISTINCT ON (o.activo_id)
               o.activo_id, o.folio::TEXT, o.estado::TEXT, o.tipo::TEXT
          FROM ordenes_trabajo o
         WHERE o.estado::TEXT IN ('creada','asignada','en_ejecucion','pausada')
           AND o.activo_id IS NOT NULL
         ORDER BY o.activo_id, o.created_at DESC
    )
    SELECT a.id,
           a.codigo::TEXT,
           a.patente::TEXT,
           a.nombre::TEXT,
           COALESCE(a.operacion, '—')::TEXT,
           g.dias_detenido,
           g.dias_obs,
           ROUND(100.0 * g.dias_detenido / NULLIF(g.dias_obs, 0), 1),
           g.estado_actual::TEXT,
           CASE WHEN g.down_actual THEN COALESCE(g.ultimo_ok + 1, p_desde) END,
           CASE WHEN g.down_actual
                THEN (g.ultima_fecha - COALESCE(g.ultimo_ok, p_desde - 1))::INTEGER
                ELSE 0 END,
           ot.folio, ot.estado, ot.tipo,
           c.texto, c.plan_accion, c.responsable::TEXT, c.fecha_compromiso
      FROM agg g
      JOIN activos a ON a.id = g.activo_id
      LEFT JOIN ot ON ot.activo_id = g.activo_id
      LEFT JOIN panel_comentarios c
             ON c.ambito    = 'equipo'
            AND c.activo_id = g.activo_id
            AND c.semana    = COALESCE(p_semana, date_trunc('week', p_hasta)::DATE)
     ORDER BY g.dias_detenido DESC, g.dias_obs DESC
     LIMIT GREATEST(p_limit, 1);
$$;
GRANT EXECUTE ON FUNCTION fn_panel_equipos_detenidos(DATE, DATE, TEXT, INTEGER, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_equipos_detenidos(DATE, DATE, TEXT, INTEGER, DATE) IS
    'Ranking de equipos por días detenidos, con OT abierta y plan de acción de la semana. MIG295.';


-- ── 2.3 Taller ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS fn_panel_taller(DATE, DATE, TEXT);
CREATE FUNCTION fn_panel_taller(
    p_desde     DATE,
    p_hasta     DATE,
    p_operacion TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH base AS (
        SELECT o.*
          FROM ordenes_trabajo o
          LEFT JOIN activos a ON a.id = o.activo_id
         WHERE p_operacion IS NULL OR a.operacion = p_operacion
    ),
    abiertas AS (
        SELECT * FROM base
         WHERE estado::TEXT IN ('creada','asignada','en_ejecucion','pausada')
    )
    SELECT jsonb_build_object(
        'ot_abiertas',        (SELECT count(*) FROM abiertas),
        'ot_correctivas',     (SELECT count(*) FROM abiertas WHERE tipo::TEXT = 'correctivo'),
        'ot_preventivas',     (SELECT count(*) FROM abiertas WHERE tipo::TEXT = 'preventivo'),
        'ot_en_ejecucion',    (SELECT count(*) FROM abiertas WHERE estado::TEXT = 'en_ejecucion'),
        'ot_pausadas',        (SELECT count(*) FROM abiertas WHERE estado::TEXT = 'pausada'),
        'ot_sin_responsable', (SELECT count(*) FROM abiertas WHERE responsable_id IS NULL AND tecnico_id IS NULL),
        -- Antigüedad del backlog: lo que lleva más tiempo sin cerrarse.
        'backlog_dias_prom',  (SELECT ROUND(AVG(EXTRACT(DAY FROM NOW() - created_at))::NUMERIC, 1) FROM abiertas),
        'backlog_mas_antigua',(SELECT MIN(created_at)::DATE FROM abiertas),
        'ot_creadas_periodo', (SELECT count(*) FROM base
                                WHERE created_at::DATE BETWEEN p_desde AND p_hasta),
        'ot_cerradas_periodo',(SELECT count(*) FROM base
                                WHERE estado::TEXT IN ('ejecutada_ok','ejecutada_con_observaciones')
                                  AND COALESCE(fecha_termino, updated_at)::DATE BETWEEN p_desde AND p_hasta),
        -- no_conformidades no tiene columna de estado: el cierre es el booleano
        -- `resuelto` (con resuelto_en / resuelto_por para la trazabilidad).
        'nc_abiertas',        (SELECT count(*) FROM no_conformidades nc
                                LEFT JOIN activos a2 ON a2.id = nc.activo_id
                               WHERE NOT nc.resuelto
                                 AND (p_operacion IS NULL OR a2.operacion = p_operacion)),
        'nc_criticas_abiertas',(SELECT count(*) FROM no_conformidades nc
                                LEFT JOIN activos a2 ON a2.id = nc.activo_id
                               WHERE NOT nc.resuelto
                                 AND nc.severidad::TEXT IN ('critica','alta')
                                 AND (p_operacion IS NULL OR a2.operacion = p_operacion)),
        'nc_periodo',         (SELECT count(*) FROM no_conformidades nc
                                LEFT JOIN activos a2 ON a2.id = nc.activo_id
                               WHERE nc.created_at::DATE BETWEEN p_desde AND p_hasta
                                 AND (p_operacion IS NULL OR a2.operacion = p_operacion))
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_taller(DATE, DATE, TEXT) TO authenticated;

COMMENT ON FUNCTION fn_panel_taller(DATE, DATE, TEXT) IS
    'Resumen de taller: backlog de OT, flujo del período y NC abiertas. MIG295.';


-- ── 2.4 Combustible Franke y Romeral ───────────────────────────────────────
-- Dos operaciones distintas con dos modelos de datos distintos:
--   · Franke  → camiones petroleros como estanques móviles (MIG130), cuadre
--               diario por camión sobre combustible_movimientos.
--   · Romeral → app de terreno /m/romeral (MIG279), despachos por ubicación y
--               equipo con CECO; NO consume stock por decisión de diseño.
-- El panel los muestra lado a lado y deja explícito si no hay registros, que es
-- el estado real de hoy (Romeral: 101 ubicaciones y 113 equipos configurados,
-- 0 despachos cargados).
DROP FUNCTION IF EXISTS fn_panel_combustible_coquimbo(DATE, DATE);
CREATE FUNCTION fn_panel_combustible_coquimbo(
    p_desde DATE,
    p_hasta DATE
)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT jsonb_build_object(
        'franke', jsonb_build_object(
            'movimientos_periodo', (
                SELECT count(*) FROM combustible_movimientos m
                 WHERE m.created_at::DATE BETWEEN p_desde AND p_hasta),
            'litros_periodo', (
                SELECT COALESCE(ROUND(SUM(ABS(m.litros))::NUMERIC, 0), 0)
                  FROM combustible_movimientos m
                 WHERE m.created_at::DATE BETWEEN p_desde AND p_hasta),
            'ultimo_movimiento', (
                SELECT max(m.created_at)::DATE FROM combustible_movimientos m),
            'camiones_activos', (
                SELECT count(*) FROM combustible_estanques
                 WHERE tipo = 'movil' AND activo),
            'estanques_fijos', (
                SELECT count(*) FROM combustible_estanques
                 WHERE tipo = 'fijo' AND activo),
            'dias_cuadre', (SELECT count(*) FROM v_combustible_cuadre_diario_franke)
        ),
        'romeral', jsonb_build_object(
            'ubicaciones', (
                SELECT count(*) FROM combustible_faena_ubicaciones u
                  JOIN faenas f ON f.id = u.faena_id
                 WHERE f.codigo = 'FAE-CMP-ROMERAL' AND u.activo),
            'equipos', (
                SELECT count(*) FROM combustible_faena_equipos e
                  JOIN faenas f ON f.id = e.faena_id
                 WHERE f.codigo = 'FAE-CMP-ROMERAL'),
            'despachos_periodo', (
                SELECT count(*) FROM combustible_faena_despachos d
                 WHERE d.created_at::DATE BETWEEN p_desde AND p_hasta),
            'litros_periodo', (
                SELECT COALESCE(ROUND(SUM(d.litros)::NUMERIC, 0), 0)
                  FROM combustible_faena_despachos d
                 WHERE d.created_at::DATE BETWEEN p_desde AND p_hasta),
            'despachos_total', (SELECT count(*) FROM combustible_faena_despachos),
            'ultimo_despacho', (SELECT max(created_at)::DATE FROM combustible_faena_despachos)
        )
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_combustible_coquimbo(DATE, DATE) IS
    'Control de combustible Franke (estanques/camiones) y Romeral (despachos en faena). MIG295.';


-- ── 2.5 Calidad del dato (¿puedo confiar en lo que muestra el panel?) ──────
-- El estado diario lo carga el planificador a mano. Si dejó de cargar, la
-- disponibilidad del mes se calcula sobre menos días y NADIE se entera: el
-- número simplemente sale mejor o peor sin explicación.
--
-- Este bloque hace visible esa dependencia:
--   dias_cargados / dias_transcurridos  → cobertura del mes
--   dias_rezago                         → cuántos días lleva sin cargar
--   equipos_por_dia                     → si de pronto carga menos equipos
--   sugerencias_pendientes              → cola de la pantalla de sugerencias
DROP FUNCTION IF EXISTS fn_panel_calidad_dato(DATE, DATE);
CREATE FUNCTION fn_panel_calidad_dato(
    p_desde DATE,
    p_hasta DATE
)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH d AS (
        SELECT fecha, count(*) AS equipos
          FROM estado_diario_flota
         WHERE fecha BETWEEN p_desde AND p_hasta
         GROUP BY fecha
    )
    SELECT jsonb_build_object(
        'dias_cargados',      (SELECT count(*) FROM d),
        'dias_transcurridos', (p_hasta - p_desde + 1),
        'cobertura_pct',      ROUND(100.0 * (SELECT count(*) FROM d)
                                    / NULLIF(p_hasta - p_desde + 1, 0), 1),
        'ultimo_dia',         (SELECT max(fecha) FROM estado_diario_flota),
        'dias_rezago',        GREATEST(
                                  CURRENT_DATE - COALESCE(
                                      (SELECT max(fecha) FROM estado_diario_flota),
                                      CURRENT_DATE), 0),
        'equipos_por_dia',    (SELECT ROUND(AVG(equipos), 0) FROM d),
        'equipos_ultimo_dia', (SELECT equipos FROM d ORDER BY fecha DESC LIMIT 1),
        -- Cómo se cargó: manual (planificador) vs. calculado por el sistema.
        'carga_manual',       (SELECT count(*) FROM estado_diario_flota
                                WHERE fecha BETWEEN p_desde AND p_hasta AND override_manual),
        'carga_auto',         (SELECT count(*) FROM estado_diario_flota
                                WHERE fecha BETWEEN p_desde AND p_hasta AND calculado_auto),
        -- Cola de la pantalla /dashboard/flota/sugerencias.
        'sugerencias_pendientes', (SELECT count(*) FROM cambios_estado_sugeridos
                                    WHERE accion IS NULL),
        'cron_estados_activo',    (SELECT COALESCE(bool_or(active), false)
                                     FROM cron.job WHERE jobname = 'flota_estados_diarios')
    );
$$;
GRANT EXECUTE ON FUNCTION fn_panel_calidad_dato(DATE, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_calidad_dato(DATE, DATE) IS
    'Frescura y cobertura del estado diario de flota, que carga el planificador a mano. MIG295.';


-- ############################################################################
-- 3. CUADRANTE CALAMA — las 5 faenas del contrato ENEX
-- ############################################################################
-- Una fila por faena, en el orden en que el GG las pide. Cada una trae:
-- instalaciones cargadas, servicios programados del mes, ejecutados, firmados
-- por el mandante, cumplimiento, y la facturación mensual comprometida.
--
-- `sin_plan` = true significa que esa faena todavía no tiene instalaciones ni
-- programación cargadas. Es una brecha visible a propósito, no un error.

DROP FUNCTION IF EXISTS fn_panel_calama_enex(INTEGER, INTEGER, DATE);
CREATE FUNCTION fn_panel_calama_enex(
    p_anio   INTEGER,
    p_mes    INTEGER,
    p_semana DATE DEFAULT NULL
)
RETURNS TABLE (
    faena_id             UUID,
    codigo               TEXT,
    nombre               TEXT,
    cliente_minero       TEXT,
    operador             TEXT,
    lineas               TEXT,
    vigencia_hasta       DATE,
    facturacion_mensual  NUMERIC,
    pct_facturacion      NUMERIC,
    instalaciones        INTEGER,
    programados          INTEGER,
    ejecutados           INTEGER,
    firmados             INTEGER,
    cumplimiento_pct     NUMERIC,
    sin_plan             BOOLEAN,
    ultima_ejecucion     DATE,
    requerimientos_mes   INTEGER,
    requerimientos_sin_firmar INTEGER,
    comentario           TEXT,
    plan_accion          TEXT,
    responsable          TEXT,
    fecha_compromiso     DATE
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    WITH inst AS (
        SELECT faena_id, count(*)::INTEGER AS n
          FROM enex_instalaciones WHERE activo GROUP BY faena_id
    ),
    prog AS (
        SELECT p.faena_id,
               count(*)::INTEGER                                        AS programados,
               count(*) FILTER (WHERE p.cumplida)::INTEGER              AS ejecutados,
               count(*) FILTER (WHERE p.firmante_mandante_at IS NOT NULL)::INTEGER AS firmados,
               max(p.fecha_ejecucion)::DATE                             AS ultima
          FROM v_enex_panel_mensual p
         WHERE p.periodo_anio = p_anio AND p.periodo_mes = p_mes
         GROUP BY p.faena_id
    ),
    req AS (
        -- Los requerimientos ENEX no tienen estado de cierre: lo que existe es
        -- si el informe donde viajan ya fue firmado por el mandante. Un
        -- requerimiento en un informe sin firmar todavía no se le entregó a
        -- nadie, y ese es el que hay que empujar.
        SELECT r.faena_id,
               count(*)::INTEGER                                          AS n,
               count(*) FILTER (WHERE NOT r.informe_firmado)::INTEGER     AS sin_firmar
          FROM v_enex_requerimientos r
         WHERE r.fecha_ejecucion IS NULL
            OR date_trunc('month', r.fecha_ejecucion)
               = make_date(p_anio, p_mes, 1)
         GROUP BY r.faena_id
    )
    SELECT f.id,
           f.codigo::TEXT,
           f.nombre::TEXT,
           f.cliente_minero::TEXT,
           f.operador::TEXT,
           array_to_string(f.lineas, ' + ')::TEXT,
           f.vigencia_hasta::DATE,
           f.facturacion_mensual_clp,
           f.pct_facturacion,
           COALESCE(inst.n, 0),
           COALESCE(prog.programados, 0),
           COALESCE(prog.ejecutados, 0),
           COALESCE(prog.firmados, 0),
           ROUND(100.0 * COALESCE(prog.ejecutados, 0) / NULLIF(prog.programados, 0), 1),
           (COALESCE(inst.n, 0) = 0 OR COALESCE(prog.programados, 0) = 0),
           prog.ultima,
           COALESCE(req.n, 0),
           COALESCE(req.sin_firmar, 0),
           c.texto, c.plan_accion, c.responsable::TEXT, c.fecha_compromiso
      FROM enex_faenas f
      LEFT JOIN inst ON inst.faena_id = f.id
      LEFT JOIN prog ON prog.faena_id = f.id
      LEFT JOIN req  ON req.faena_id  = f.id
      LEFT JOIN panel_comentarios c
             ON c.ambito        = 'faena_enex'
            AND c.enex_faena_id = f.id
            AND c.semana        = COALESCE(p_semana, date_trunc('week', CURRENT_DATE)::DATE)
     WHERE f.activo
     ORDER BY f.orden, f.codigo;
$$;
GRANT EXECUTE ON FUNCTION fn_panel_calama_enex(INTEGER, INTEGER, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_calama_enex(INTEGER, INTEGER, DATE) IS
    'Avance mensual de las 5 faenas ENEX de Calama, con facturación y brecha de plan. MIG295.';


-- ############################################################################
-- 4. EL PANEL COMPLETO EN UNA SOLA LLAMADA
-- ############################################################################
-- El frontend pide esto y nada más: una ida a la base en vez de ocho. El mismo
-- payload lo reusa después el correo semanal al Gerente General.
--
-- p_semana: cualquier día de la semana a mirar (se normaliza al lunes).
-- El mes de disponibilidad es el mes al que pertenece esa semana.

DROP FUNCTION IF EXISTS fn_panel_gerencia(DATE);
CREATE FUNCTION fn_panel_gerencia(p_semana DATE DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_semana     DATE;
    v_sem_fin    DATE;
    v_mes_ini    DATE;
    v_mes_fin    DATE;
    v_hoy        DATE := CURRENT_DATE;
    v_resultado  JSONB;
BEGIN
    IF NOT fn_panel_gerencia_puede_ver() THEN
        RAISE EXCEPTION 'No autorizado para ver el Panel de Gerencia.'
            USING ERRCODE = '42501';
    END IF;

    v_semana  := date_trunc('week', COALESCE(p_semana, v_hoy))::DATE;
    v_sem_fin := v_semana + 6;
    v_mes_ini := date_trunc('month', v_semana)::DATE;
    -- El mes se corta en el día de hoy: no tiene sentido contar como "detenidos"
    -- días que todavía no ocurren.
    v_mes_fin := LEAST((v_mes_ini + INTERVAL '1 month - 1 day')::DATE, v_hoy);

    SELECT jsonb_build_object(
        'semana',        jsonb_build_object(
            'inicio', v_semana, 'fin', v_sem_fin,
            'mes_inicio', v_mes_ini, 'mes_fin', v_mes_fin,
            'generado_at', NOW()
        ),

        -- Encabezado de confianza: se lee ANTES que cualquier número, porque
        -- define si los demás números sirven para decidir.
        'calidad_dato',  fn_panel_calidad_dato(v_mes_ini, v_mes_fin),

        -- ── CUADRANTE COQUIMBO ──────────────────────────────────────────────
        'coquimbo', jsonb_build_object(
            'taller',       fn_panel_taller(v_mes_ini, v_mes_fin, 'Coquimbo'),
            'combustible',  fn_panel_combustible_coquimbo(v_mes_ini, v_mes_fin),
            'disponibilidad', jsonb_build_object(
                'equipos',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'promedio',  (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')),
                'bajo_90',   (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo')
                               WHERE disponibilidad_pct < 90),
                'detalle',   (SELECT COALESCE(jsonb_agg(to_jsonb(d)), '[]'::JSONB)
                                FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Coquimbo') d)
            ),
            'detenidos',    (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                               FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Coquimbo', 10, v_semana) x),
            'comentario',   (SELECT to_jsonb(c) FROM panel_comentarios c
                              WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'coquimbo'
                                AND c.semana = v_semana)
        ),

        -- ── CUADRANTE CALAMA ────────────────────────────────────────────────
        'calama', jsonb_build_object(
            'faenas',      (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) x),
            'facturacion_total', (SELECT SUM(facturacion_mensual_clp) FROM enex_faenas WHERE activo),
            'faenas_sin_plan',   (SELECT count(*) FROM fn_panel_calama_enex(
                                     EXTRACT(YEAR  FROM v_semana)::INTEGER,
                                     EXTRACT(MONTH FROM v_semana)::INTEGER,
                                     v_semana) WHERE sin_plan),
            'taller',      fn_panel_taller(v_mes_ini, v_mes_fin, 'Calama'),
            'disponibilidad', jsonb_build_object(
                'equipos',  (SELECT count(*) FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama')),
                'promedio', (SELECT ROUND(100.0 * SUM(dias_up) / NULLIF(SUM(dias_obs), 0), 1)
                               FROM fn_panel_disponibilidad(v_mes_ini, v_mes_fin, 'Calama'))
            ),
            'detenidos',   (SELECT COALESCE(jsonb_agg(to_jsonb(x)), '[]'::JSONB)
                              FROM fn_panel_equipos_detenidos(v_mes_ini, v_mes_fin, 'Calama', 5, v_semana) x),
            'comentario',  (SELECT to_jsonb(c) FROM panel_comentarios c
                             WHERE c.ambito = 'cuadrante' AND c.cuadrante = 'calama'
                               AND c.semana = v_semana)
        ),

        -- ── COMENTARIO DE LA SEMANA ─────────────────────────────────────────
        'comentario_semana', (SELECT to_jsonb(c) FROM panel_comentarios c
                               WHERE c.ambito = 'semana' AND c.semana = v_semana)
    ) INTO v_resultado;

    RETURN v_resultado;
END $$;
GRANT EXECUTE ON FUNCTION fn_panel_gerencia(DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_gerencia(DATE) IS
    'Panel de Gerencia completo (cuadrantes Coquimbo y Calama) en una sola llamada. MIG295.';


-- ############################################################################
-- 5. GUARDAR UN COMENTARIO / PLAN DE ACCIÓN
-- ############################################################################
-- Upsert por ámbito. El frontend no arma llaves ni decide si es INSERT o
-- UPDATE: manda el ámbito y su llave, y la base resuelve.

DROP FUNCTION IF EXISTS fn_panel_comentario_guardar(DATE, TEXT, TEXT, UUID, UUID, TEXT, TEXT, TEXT, DATE);
CREATE FUNCTION fn_panel_comentario_guardar(
    p_semana           DATE,
    p_ambito           TEXT,
    p_cuadrante        TEXT DEFAULT NULL,
    p_activo_id        UUID DEFAULT NULL,
    p_enex_faena_id    UUID DEFAULT NULL,
    p_texto            TEXT DEFAULT NULL,
    p_plan_accion      TEXT DEFAULT NULL,
    p_responsable      TEXT DEFAULT NULL,
    p_fecha_compromiso DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_semana DATE := date_trunc('week', p_semana)::DATE;
    v_id     UUID;
BEGIN
    IF NOT fn_panel_gerencia_puede_comentar() THEN
        RAISE EXCEPTION 'No autorizado para comentar en el Panel de Gerencia.'
            USING ERRCODE = '42501';
    END IF;

    IF p_texto IS NULL OR length(trim(p_texto)) = 0 THEN
        -- Texto vacío = borrar el comentario de ese ámbito (el usuario lo limpió).
        DELETE FROM panel_comentarios
         WHERE semana = v_semana AND ambito = p_ambito
           AND cuadrante     IS NOT DISTINCT FROM p_cuadrante
           AND activo_id     IS NOT DISTINCT FROM p_activo_id
           AND enex_faena_id IS NOT DISTINCT FROM p_enex_faena_id;
        RETURN NULL;
    END IF;

    INSERT INTO panel_comentarios AS pc (
        semana, ambito, cuadrante, activo_id, enex_faena_id,
        texto, plan_accion, responsable, fecha_compromiso, autor_id
    ) VALUES (
        v_semana, p_ambito, p_cuadrante, p_activo_id, p_enex_faena_id,
        trim(p_texto), NULLIF(trim(COALESCE(p_plan_accion, '')), ''),
        NULLIF(trim(COALESCE(p_responsable, '')), ''), p_fecha_compromiso, auth.uid()
    )
    ON CONFLICT DO NOTHING
    RETURNING pc.id INTO v_id;

    -- ON CONFLICT DO NOTHING + índices únicos parciales: si ya existía, el
    -- INSERT no devuelve id y hay que actualizar la fila existente.
    IF v_id IS NULL THEN
        UPDATE panel_comentarios
           SET texto            = trim(p_texto),
               plan_accion      = NULLIF(trim(COALESCE(p_plan_accion, '')), ''),
               responsable      = NULLIF(trim(COALESCE(p_responsable, '')), ''),
               fecha_compromiso = p_fecha_compromiso,
               autor_id         = auth.uid()
         WHERE semana = v_semana AND ambito = p_ambito
           AND cuadrante     IS NOT DISTINCT FROM p_cuadrante
           AND activo_id     IS NOT DISTINCT FROM p_activo_id
           AND enex_faena_id IS NOT DISTINCT FROM p_enex_faena_id
        RETURNING id INTO v_id;
    END IF;

    RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION fn_panel_comentario_guardar(DATE, TEXT, TEXT, UUID, UUID, TEXT, TEXT, TEXT, DATE) TO authenticated;

COMMENT ON FUNCTION fn_panel_comentario_guardar(DATE, TEXT, TEXT, UUID, UUID, TEXT, TEXT, TEXT, DATE) IS
    'Upsert de comentario/plan de acción del panel. Texto vacío borra. MIG295.';
