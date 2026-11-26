-- ============================================================================
-- SICOM-ICEO | 730 — Cuentas por cobrar: la cartera de clientes desde Softland
-- ============================================================================
-- Fase 1 del módulo de finanzas (26-11-2026). Manuel vio la demo de diio y
-- pidió un módulo propio, mejor, conectado a Softland. Decisiones:
--   · Cartera cobrable = documentos EMITIDOS desde el 01-01-2026. Lo anterior
--     es historia (Softland arrastra saldos sin cruzar desde 2013).
--   · SICOM solo LEE Softland. Lo que vuelva a Softland irá por archivo de carga.
--
-- Fuentes (Softland, solo lectura, vía database/scripts/softland-sync.ps1):
--   · cwmovim de la cuenta 1-1-04 (clientes): facturas V1/V2 (débito), pagos
--     DP/TE y notas de crédito NC (crédito). Cada pago apunta a la factura que
--     paga con MovTipDocRef/MovNumDocRef: el saldo de una factura es la suma de
--     sus movimientos agrupados por (cliente, tipo ref, folio ref).
--   · iw_gsaen/iw_gmovi tipo F: el detalle de cada factura. El centro de costo
--     NO viene por línea, pero cada línea trae la PATENTE en el texto («CAMION
--     DE AGUA INDUSTRIAL 22M3 - TGGF-56»): con eso cada factura se liga a sus
--     equipos de SICOM.
--   · cwtauxi: nombre, RUT, correo y plazo de los clientes.
--
-- Carga: el sincronizador manda TODA la ventana (desde 2026) en cada corrida y
-- la RPC la reemplaza de forma atómica por tipo: lo que ya no viene se anuló o
-- eliminó en Softland.
--
-- ADITIVA. No modifica datos existentes.
-- ============================================================================

BEGIN;

-- ############################################################################
-- 1. TABLAS (copia de Softland; nadie las edita en SICOM)
-- ############################################################################

CREATE TABLE IF NOT EXISTS softland_cxc_mov (
    cpb_ano     SMALLINT     NOT NULL,
    area_cod    VARCHAR(10)  NOT NULL,
    cpb_num     VARCHAR(12)  NOT NULL,
    mov_num     INTEGER      NOT NULL,
    pct_cod     VARCHAR(20)  NOT NULL,
    cod_aux     VARCHAR(20)  NOT NULL,
    ttd_cod     VARCHAR(4)   NOT NULL,     -- V1/V2 factura, DP depósito, TE transferencia, NC nota de crédito…
    num_doc     BIGINT,
    tip_ref     VARCHAR(4)   NOT NULL,     -- documento al que pertenece (la factura)
    num_ref     BIGINT       NOT NULL,
    fecha       DATE,                      -- MovFe
    vence       DATE,                      -- MovFv
    cpb_fec     DATE,
    debe        NUMERIC(16,2) NOT NULL DEFAULT 0,
    haber       NUMERIC(16,2) NOT NULL DEFAULT 0,
    glosa       TEXT,
    sincronizado_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (cpb_ano, area_cod, cpb_num, mov_num)
);
CREATE INDEX IF NOT EXISTS idx_softland_cxc_mov_doc ON softland_cxc_mov (cod_aux, tip_ref, num_ref);
COMMENT ON TABLE softland_cxc_mov IS
    'Movimientos de la cuenta de clientes (1-1-04) de Softland desde 2026. Copia, no se edita. MIG730.';

CREATE TABLE IF NOT EXISTS softland_cxc_linea (
    tipo        VARCHAR(2)   NOT NULL,     -- F factura, N nota de crédito (iw_gsaen.Tipo)
    nro_int     INTEGER      NOT NULL,
    n           INTEGER      NOT NULL,
    folio       BIGINT       NOT NULL,
    fecha       DATE,
    cod_aux     VARCHAR(20),
    cod_prod    VARCHAR(40),
    detalle     TEXT,
    cantidad    NUMERIC(16,4),
    total       NUMERIC(16,2),
    patente     VARCHAR(10),               -- leída del detalle (AAAA-00 / AA-0000)
    sincronizado_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tipo, nro_int, n)
);
CREATE INDEX IF NOT EXISTS idx_softland_cxc_linea_folio ON softland_cxc_linea (tipo, folio);
CREATE INDEX IF NOT EXISTS idx_softland_cxc_linea_patente ON softland_cxc_linea (patente);
COMMENT ON TABLE softland_cxc_linea IS
    'Detalle de facturas y notas de crédito emitidas (iw_gmovi) desde 2026, con la patente leída del texto. MIG730.';

CREATE TABLE IF NOT EXISTS softland_auxiliar (
    cod_aux     VARCHAR(20)  PRIMARY KEY,
    rut         VARCHAR(15),
    nombre      TEXT,
    email       TEXT,
    email_dte   TEXT,
    telefono    TEXT,
    dia_plazo   INTEGER,
    es_cliente  BOOLEAN,
    sincronizado_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE softland_auxiliar IS 'Clientes y proveedores de Softland (cwtauxi). Copia. MIG730.';

ALTER TABLE softland_cxc_mov   ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_cxc_linea ENABLE ROW LEVEL SECURITY;
ALTER TABLE softland_auxiliar  ENABLE ROW LEVEL SECURITY;
-- Sin políticas: solo se leen por las funciones de abajo (SECURITY DEFINER).


-- ############################################################################
-- 2. CARGA DEL SINCRONIZADOR (secreto 'softland_sync', patrón MIG594)
-- ############################################################################

-- Patente chilena dentro de un texto: AAAA-00 / AAAA00 (actual) o AA-0000 (antigua).
CREATE OR REPLACE FUNCTION fn_patente_en_texto(p TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN m IS NULL THEN NULL
        ELSE regexp_replace(m, '^([A-Z]{2,4})[ -]?([0-9]{2,4})$', '\1-\2')
    END
      FROM (SELECT (regexp_match(upper(coalesce(p, '')),
                    -- La antigua (AA-0000) sin espacio: «DE 2026» no es una patente.
                    '(?:^|[^A-Z0-9])([B-DF-HJ-LN-PR-TV-Z]{4}[ -]?[0-9]{2}|[A-Z]{2}-?[0-9]{4})(?:[^A-Z0-9]|$)'))[1] AS m) x;
$$;

-- p_tipo: 'mov' | 'linea' | 'aux'. Reemplaza la ventana completa de ese tipo.
CREATE OR REPLACE FUNCTION rpc_softland_cargar_cxc(p_secreto TEXT, p_tipo TEXT, p_filas JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_n INTEGER := 0; v_borr INTEGER := 0;
BEGIN
    IF NOT fn_sistema_secreto_valido('softland_sync', p_secreto) THEN
        RAISE EXCEPTION 'Secreto inválido.' USING ERRCODE = '42501';
    END IF;
    IF jsonb_typeof(p_filas) <> 'array' THEN RAISE EXCEPTION 'Lote inválido.'; END IF;

    IF p_tipo = 'mov' THEN
        CREATE TEMP TABLE _in ON COMMIT DROP AS
        SELECT (f->>'cpb_ano')::SMALLINT cpb_ano, btrim(f->>'area_cod') area_cod, btrim(f->>'cpb_num') cpb_num,
               (f->>'mov_num')::INTEGER mov_num, btrim(f->>'pct_cod') pct_cod, btrim(f->>'cod_aux') cod_aux,
               upper(btrim(f->>'ttd_cod')) ttd_cod, (f->>'num_doc')::BIGINT num_doc,
               upper(btrim(f->>'tip_ref')) tip_ref, (f->>'num_ref')::BIGINT num_ref,
               (f->>'fecha')::DATE fecha, (f->>'vence')::DATE vence, (f->>'cpb_fec')::DATE cpb_fec,
               coalesce((f->>'debe')::NUMERIC, 0) debe, coalesce((f->>'haber')::NUMERIC, 0) haber,
               nullif(btrim(f->>'glosa'), '') glosa
          FROM jsonb_array_elements(p_filas) f;
        DELETE FROM softland_cxc_mov s
         WHERE NOT EXISTS (SELECT 1 FROM _in i WHERE (i.cpb_ano, i.area_cod, i.cpb_num, i.mov_num)
                                                   = (s.cpb_ano, s.area_cod, s.cpb_num, s.mov_num));
        GET DIAGNOSTICS v_borr = ROW_COUNT;
        INSERT INTO softland_cxc_mov (cpb_ano, area_cod, cpb_num, mov_num, pct_cod, cod_aux, ttd_cod, num_doc,
                                      tip_ref, num_ref, fecha, vence, cpb_fec, debe, haber, glosa, sincronizado_at)
        SELECT cpb_ano, area_cod, cpb_num, mov_num, pct_cod, cod_aux, ttd_cod, num_doc,
               tip_ref, num_ref, fecha, vence, cpb_fec, debe, haber, glosa, NOW() FROM _in
        ON CONFLICT (cpb_ano, area_cod, cpb_num, mov_num) DO UPDATE SET
            pct_cod = EXCLUDED.pct_cod, cod_aux = EXCLUDED.cod_aux, ttd_cod = EXCLUDED.ttd_cod,
            num_doc = EXCLUDED.num_doc, tip_ref = EXCLUDED.tip_ref, num_ref = EXCLUDED.num_ref,
            fecha = EXCLUDED.fecha, vence = EXCLUDED.vence, cpb_fec = EXCLUDED.cpb_fec,
            debe = EXCLUDED.debe, haber = EXCLUDED.haber, glosa = EXCLUDED.glosa, sincronizado_at = NOW();
        SELECT count(*) INTO v_n FROM _in;

    ELSIF p_tipo = 'linea' THEN
        CREATE TEMP TABLE _in ON COMMIT DROP AS
        SELECT upper(btrim(f->>'tipo')) tipo, (f->>'nro_int')::INTEGER nro_int, (f->>'n')::INTEGER n,
               (f->>'folio')::BIGINT folio, (f->>'fecha')::DATE fecha, btrim(f->>'cod_aux') cod_aux,
               btrim(f->>'cod_prod') cod_prod, btrim(f->>'detalle') detalle,
               (f->>'cantidad')::NUMERIC cantidad, (f->>'total')::NUMERIC total
          FROM jsonb_array_elements(p_filas) f;
        DELETE FROM softland_cxc_linea s
         WHERE NOT EXISTS (SELECT 1 FROM _in i WHERE (i.tipo, i.nro_int, i.n) = (s.tipo, s.nro_int, s.n));
        GET DIAGNOSTICS v_borr = ROW_COUNT;
        INSERT INTO softland_cxc_linea (tipo, nro_int, n, folio, fecha, cod_aux, cod_prod, detalle, cantidad, total, patente, sincronizado_at)
        SELECT tipo, nro_int, n, folio, fecha, cod_aux, cod_prod, detalle, cantidad, total,
               fn_patente_en_texto(detalle), NOW() FROM _in
        ON CONFLICT (tipo, nro_int, n) DO UPDATE SET
            folio = EXCLUDED.folio, fecha = EXCLUDED.fecha, cod_aux = EXCLUDED.cod_aux,
            cod_prod = EXCLUDED.cod_prod, detalle = EXCLUDED.detalle, cantidad = EXCLUDED.cantidad,
            total = EXCLUDED.total, patente = EXCLUDED.patente, sincronizado_at = NOW();
        SELECT count(*) INTO v_n FROM _in;

    ELSIF p_tipo = 'aux' THEN
        INSERT INTO softland_auxiliar (cod_aux, rut, nombre, email, email_dte, telefono, dia_plazo, es_cliente, sincronizado_at)
        SELECT btrim(f->>'cod_aux'), nullif(btrim(f->>'rut'), ''), nullif(btrim(f->>'nombre'), ''),
               nullif(lower(btrim(f->>'email')), ''), nullif(lower(btrim(f->>'email_dte')), ''),
               nullif(btrim(f->>'telefono'), ''), (f->>'dia_plazo')::INTEGER, (f->>'es_cliente')::BOOLEAN, NOW()
          FROM jsonb_array_elements(p_filas) f
        ON CONFLICT (cod_aux) DO UPDATE SET
            rut = EXCLUDED.rut, nombre = EXCLUDED.nombre, email = EXCLUDED.email, email_dte = EXCLUDED.email_dte,
            telefono = EXCLUDED.telefono, dia_plazo = EXCLUDED.dia_plazo, es_cliente = EXCLUDED.es_cliente,
            sincronizado_at = NOW();
        GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSE
        RAISE EXCEPTION 'Tipo de carga desconocido: %', p_tipo;
    END IF;
    RETURN jsonb_build_object('tipo', p_tipo, 'filas', v_n, 'borradas', v_borr);
END $$;
REVOKE ALL ON FUNCTION rpc_softland_cargar_cxc(TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rpc_softland_cargar_cxc(TEXT, TEXT, JSONB) TO anon, authenticated;


-- ############################################################################
-- 3. CARTERA
-- ############################################################################

-- Un documento por (cliente, tipo, folio) de la factura. Solo facturas
-- (V1 afecta, V2 exenta) emitidas desde el 01-01-2026: lo anterior es historia.
CREATE OR REPLACE VIEW v_cxc_documento AS
WITH mov AS (
    SELECT cod_aux, tip_ref, num_ref,
           sum(debe) FILTER (WHERE ttd_cod = tip_ref)                  AS monto,
           sum(haber) FILTER (WHERE ttd_cod IN ('NC'))                  AS notas_credito,
           sum(haber) FILTER (WHERE ttd_cod NOT IN ('NC') AND ttd_cod <> tip_ref) AS pagado,
           sum(debe - haber)                                            AS saldo,
           min(fecha) FILTER (WHERE ttd_cod = tip_ref)                  AS emision,
           max(vence) FILTER (WHERE ttd_cod = tip_ref)                  AS vence,
           max(coalesce(cpb_fec, fecha)) FILTER (WHERE haber > 0 AND ttd_cod NOT IN ('NC')) AS ultimo_pago,
           count(*) FILTER (WHERE haber > 0 AND ttd_cod NOT IN ('NC'))  AS n_pagos
      FROM softland_cxc_mov
     WHERE tip_ref IN ('V1', 'V2')
     GROUP BY cod_aux, tip_ref, num_ref
)
SELECT m.cod_aux, a.rut, coalesce(a.nombre, m.cod_aux) AS cliente,
       m.tip_ref AS tipo, m.num_ref AS folio, m.emision, m.vence,
       coalesce(m.monto, 0) AS monto, coalesce(m.notas_credito, 0) AS notas_credito,
       coalesce(m.pagado, 0) AS pagado, round(m.saldo, 0) AS saldo,
       m.ultimo_pago, m.n_pagos,
       CASE WHEN round(m.saldo, 0) <= 0 THEN 'pagada'
            WHEN m.vence IS NULL OR m.vence >= current_date THEN 'por_vencer'
            ELSE 'vencida' END AS estado,
       CASE WHEN round(m.saldo, 0) > 0 AND m.vence < current_date THEN current_date - m.vence ELSE 0 END AS dias_vencida,
       -- Días que tardó en pagarse (si está pagada) y atraso contra el vencimiento.
       CASE WHEN round(m.saldo, 0) <= 0 AND m.ultimo_pago IS NOT NULL THEN m.ultimo_pago - m.emision END AS dias_pago,
       CASE WHEN round(m.saldo, 0) <= 0 AND m.ultimo_pago IS NOT NULL AND m.vence IS NOT NULL THEN m.ultimo_pago - m.vence END AS dias_atraso
  FROM mov m
  LEFT JOIN softland_auxiliar a ON a.cod_aux = m.cod_aux
 WHERE m.emision >= DATE '2026-01-01';

COMMENT ON VIEW v_cxc_documento IS
    'Cartera de clientes: facturas emitidas desde 2026 con su saldo calculado desde Softland. MIG730.';

-- Patentes de cada factura (leídas del detalle) ligadas al equipo de SICOM.
CREATE OR REPLACE VIEW v_cxc_factura_equipo AS
SELECT l.folio, l.cod_aux, l.patente, a.id AS activo_id, sum(l.total) AS total, count(*) AS lineas
  FROM softland_cxc_linea l
  LEFT JOIN activos a ON upper(replace(a.patente, ' ', '')) = l.patente
 WHERE l.tipo = 'F' AND l.patente IS NOT NULL
 GROUP BY l.folio, l.cod_aux, l.patente, a.id;


-- ############################################################################
-- 4. LECTURA (pantalla de cobranza)
-- ############################################################################

CREATE OR REPLACE FUNCTION fn_finanzas_puede_ver()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT fn_tiene_permiso_modulo('finanzas', 'view', ARRAY['administrador','gerencia','subgerente_operaciones']);
$$;
GRANT EXECUTE ON FUNCTION fn_finanzas_puede_ver() TO authenticated;

-- Resumen + clientes + documentos abiertos, en una llamada.
CREATE OR REPLACE FUNCTION rpc_cxc_cartera()
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE r JSONB;
BEGIN
    IF NOT fn_finanzas_puede_ver() THEN
        RAISE EXCEPTION 'Sin permiso para ver finanzas.' USING ERRCODE = '42501';
    END IF;
    WITH d AS (SELECT * FROM v_cxc_documento),
    cli AS (
        SELECT cod_aux, max(rut) rut, max(cliente) cliente,
               sum(saldo) FILTER (WHERE saldo > 0)                     AS deuda,
               sum(saldo) FILTER (WHERE estado = 'vencida')            AS vencido,
               count(*) FILTER (WHERE saldo > 0)                        AS abiertas,
               count(*)                                                 AS facturas,
               sum(monto)                                               AS facturado,
               round(avg(dias_pago)::NUMERIC, 1)                        AS dias_pago_prom,
               round(avg(dias_atraso)::NUMERIC, 1)                      AS dias_atraso_prom,
               count(dias_pago)                                         AS pagadas_con_dato,
               max(dias_vencida)                                        AS max_dias_vencida
          FROM d GROUP BY cod_aux
    )
    SELECT jsonb_build_object(
        'sincronizado_at', (SELECT max(sincronizado_at) FROM softland_cxc_mov),
        'resumen', (SELECT jsonb_build_object(
            'facturado', coalesce(sum(monto), 0),
            'pagado', coalesce(sum(monto) FILTER (WHERE estado = 'pagada'), 0),
            'por_vencer', coalesce(sum(saldo) FILTER (WHERE estado = 'por_vencer'), 0),
            'vencido', coalesce(sum(saldo) FILTER (WHERE estado = 'vencida'), 0),
            'n_por_vencer', count(*) FILTER (WHERE estado = 'por_vencer'),
            'n_vencido', count(*) FILTER (WHERE estado = 'vencida'),
            'n_pagada', count(*) FILTER (WHERE estado = 'pagada'),
            'tramos', jsonb_build_object(
                '1_30',   coalesce(sum(saldo) FILTER (WHERE estado = 'vencida' AND dias_vencida <= 30), 0),
                '31_60',  coalesce(sum(saldo) FILTER (WHERE estado = 'vencida' AND dias_vencida BETWEEN 31 AND 60), 0),
                '61_90',  coalesce(sum(saldo) FILTER (WHERE estado = 'vencida' AND dias_vencida BETWEEN 61 AND 90), 0),
                'mas_90', coalesce(sum(saldo) FILTER (WHERE estado = 'vencida' AND dias_vencida > 90), 0)),
            'credito_a_favor', coalesce(sum(saldo) FILTER (WHERE saldo < 0), 0)
        ) FROM d),
        'mensual', (SELECT coalesce(jsonb_agg(x ORDER BY x.mes), '[]') FROM (
            SELECT to_char(emision, 'YYYY-MM') mes, sum(monto) facturado,
                   sum(monto - greatest(saldo, 0)) cobrado, sum(greatest(saldo, 0)) pendiente
              FROM d GROUP BY 1) x),
        'clientes', (SELECT coalesce(jsonb_agg(c ORDER BY c.deuda DESC NULLS LAST), '[]') FROM cli c),
        'documentos', (SELECT coalesce(jsonb_agg(x ORDER BY x.dias_vencida DESC, x.vence), '[]') FROM (
            SELECT d.*, (SELECT coalesce(jsonb_agg(DISTINCT e.patente), '[]')
                           FROM v_cxc_factura_equipo e WHERE e.folio = d.folio AND e.cod_aux = d.cod_aux) AS patentes
              FROM d WHERE d.saldo <> 0) x)
    ) INTO r;
    RETURN r;
END $$;
REVOKE ALL ON FUNCTION rpc_cxc_cartera() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION rpc_cxc_cartera() TO authenticated;

COMMIT;
