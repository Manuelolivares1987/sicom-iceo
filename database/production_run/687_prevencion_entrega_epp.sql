-- ============================================================================
-- SICOM-ICEO | 687 — Registro de entrega de EPP con firma del trabajador
-- ============================================================================
-- Pedido de Manuel (13-11-2026). El DS 44 (art. 13) obliga a entregar EPP
-- gratis, a instruir su uso y a llevar registro; fue de lo más multado en el
-- primer año de fiscalización. Romeral (CMP) y Franke ya piden «Consumo de
-- EPP — Registros de entrega de EPP» como entregable (MIG546), sin dato detrás.
--
-- Decisiones de Manuel:
--   · Registro de PREVENCIÓN con firma del trabajador en la pantalla. No
--     descuenta stock de bodega (hoy 2 de 357 productos EPP tienen stock).
--   · Registran prevención y supervisores (teléfono y panel).
--
-- El trabajador sale del control documental (prevencion_personal), así la
-- entrega queda atada a su RUT y a su ficha. La firma (PNG) va al bucket
-- privado prevencion-evidencias.
--
-- ADITIVA.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS prevencion_epp_catalogo (
    codigo            VARCHAR(40)  PRIMARY KEY,
    nombre            VARCHAR(120) NOT NULL,
    categoria         VARCHAR(40)  NOT NULL,
    requiere_talla    BOOLEAN      NOT NULL DEFAULT false,
    -- Referencia para sugerir reposición; vacío = según desgaste.
    vida_util_meses   INTEGER CHECK (vida_util_meses IS NULL OR vida_util_meses > 0),
    orden             INTEGER      NOT NULL DEFAULT 100,
    activo            BOOLEAN      NOT NULL DEFAULT true
);

COMMENT ON TABLE prevencion_epp_catalogo IS
    'Catálogo de EPP que se entrega al personal. Agregar uno es un INSERT. MIG687.';

INSERT INTO prevencion_epp_catalogo (codigo, nombre, categoria, requiere_talla, vida_util_meses, orden) VALUES
    ('casco',            'Casco de seguridad',                       'Cabeza',        false, 24, 10),
    ('barbiquejo',       'Barbiquejo',                               'Cabeza',        false, 12, 11),
    ('legionario',       'Legionario / cubrenuca',                   'Cabeza',        false,  6, 12),
    ('lentes_claros',    'Lentes de seguridad claros',               'Ojos y cara',   false,  3, 20),
    ('lentes_oscuros',   'Lentes de seguridad oscuros',              'Ojos y cara',   false,  3, 21),
    ('antiparras',       'Antiparras',                               'Ojos y cara',   false,  6, 22),
    ('careta_facial',    'Careta / protector facial',                'Ojos y cara',   false, 12, 23),
    ('fono_auditivo',    'Protector auditivo tipo fono',             'Auditiva',      false, 12, 30),
    ('tapon_auditivo',   'Tapones auditivos',                        'Auditiva',      false,  1, 31),
    ('respirador',       'Respirador medio rostro',                  'Respiratoria',  true,  12, 40),
    ('filtros',          'Filtros / cartuchos para respirador',      'Respiratoria',  false,  1, 41),
    ('mascarilla',       'Mascarilla desechable',                    'Respiratoria',  false, NULL, 42),
    ('guantes_cabritilla','Guantes de cabritilla',                   'Manos',         true,   1, 50),
    ('guantes_nitrilo',  'Guantes de nitrilo (hidrocarburos)',       'Manos',         true,   1, 51),
    ('guantes_anticorte','Guantes anticorte',                        'Manos',         true,   2, 52),
    ('zapatos',          'Zapatos de seguridad',                     'Pies',          true,  12, 60),
    ('botas_goma',       'Botas de goma de seguridad',               'Pies',          true,  12, 61),
    ('ropa_trabajo',     'Ropa de trabajo (pantalón y camisa / geólogo)', 'Cuerpo',   true,  12, 70),
    ('overol',           'Overol',                                   'Cuerpo',        true,  12, 71),
    ('chaleco_reflectante','Chaleco / ropa reflectante',             'Cuerpo',        true,  12, 72),
    ('traje_quimico',    'Traje de protección química / Tyvek',      'Cuerpo',        true, NULL, 73),
    ('chaqueta_termica', 'Chaqueta térmica',                         'Cuerpo',        true,  24, 74),
    ('arnes',            'Arnés de seguridad con cola de vida',      'Altura',        true,  60, 80),
    ('bloqueador',       'Bloqueador solar',                         'Radiación UV',  false,  1, 90)
ON CONFLICT (codigo) DO NOTHING;


CREATE TABLE IF NOT EXISTS prevencion_epp_entregas (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cliente_uuid        UUID        NOT NULL UNIQUE,   -- reintento sin duplicar
    personal_id         UUID        NOT NULL REFERENCES prevencion_personal(id),
    faena_id            UUID        NOT NULL REFERENCES faenas(id),
    fecha               DATE        NOT NULL DEFAULT CURRENT_DATE,
    motivo              VARCHAR(20) NOT NULL
                        CHECK (motivo IN ('ingreso','reposicion','deterioro','perdida','cambio_talla','otro')),
    -- DS 44 art. 13: además de entregar, instruir uso, cuidado y mantención.
    instruccion_uso     BOOLEAN     NOT NULL DEFAULT false,
    observacion         TEXT,
    firma_path          TEXT        NOT NULL,
    -- Copia del nombre y RUT al momento de firmar: el comprobante no cambia
    -- si después se corrige la ficha.
    trabajador_nombre   VARCHAR(250) NOT NULL,
    trabajador_rut      VARCHAR(20),
    entregado_por       UUID        NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
    entregado_por_nombre VARCHAR(160),
    anulada             BOOLEAN     NOT NULL DEFAULT false,
    anulada_motivo      TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_prev_epp_anulada CHECK (NOT anulada OR length(trim(COALESCE(anulada_motivo, ''))) > 0)
);

CREATE INDEX IF NOT EXISTS idx_prev_epp_persona ON prevencion_epp_entregas (personal_id, fecha DESC);
CREATE INDEX IF NOT EXISTS idx_prev_epp_faena   ON prevencion_epp_entregas (faena_id, fecha DESC);

COMMENT ON TABLE prevencion_epp_entregas IS
    'Entrega de EPP a un trabajador, con su firma. No descuenta stock. MIG687.';

CREATE TABLE IF NOT EXISTS prevencion_epp_entrega_items (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    entrega_id      UUID        NOT NULL REFERENCES prevencion_epp_entregas(id) ON DELETE CASCADE,
    epp_codigo      VARCHAR(40) NOT NULL REFERENCES prevencion_epp_catalogo(codigo),
    cantidad        INTEGER     NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    talla           VARCHAR(20),
    CONSTRAINT uq_prev_epp_item UNIQUE (entrega_id, epp_codigo)
);


-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE prevencion_epp_catalogo      ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_epp_entregas      ENABLE ROW LEVEL SECURITY;
ALTER TABLE prevencion_epp_entrega_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS prev_epp_cat_sel ON prevencion_epp_catalogo;
CREATE POLICY prev_epp_cat_sel ON prevencion_epp_catalogo
    FOR SELECT TO authenticated
    USING (fn_prevencion_reporta_puede_ver() OR fn_prevencion_reporta_puede_crear());
DROP POLICY IF EXISTS prev_epp_cat_admin ON prevencion_epp_catalogo;
CREATE POLICY prev_epp_cat_admin ON prevencion_epp_catalogo
    FOR ALL TO authenticated
    USING (fn_prevencion_reporta_puede_admin()) WITH CHECK (fn_prevencion_reporta_puede_admin());

DROP POLICY IF EXISTS prev_epp_ent_sel ON prevencion_epp_entregas;
CREATE POLICY prev_epp_ent_sel ON prevencion_epp_entregas
    FOR SELECT TO authenticated
    USING ((fn_prevencion_reporta_puede_ver() OR entregado_por = auth.uid())
           AND fn_prevencion_faena_visible(faena_id));

-- Anular (no borrar): solo la administración del módulo.
DROP POLICY IF EXISTS prev_epp_ent_upd ON prevencion_epp_entregas;
CREATE POLICY prev_epp_ent_upd ON prevencion_epp_entregas
    FOR UPDATE TO authenticated
    USING (fn_prevencion_reporta_puede_admin()) WITH CHECK (fn_prevencion_reporta_puede_admin());

DROP POLICY IF EXISTS prev_epp_item_sel ON prevencion_epp_entrega_items;
CREATE POLICY prev_epp_item_sel ON prevencion_epp_entrega_items
    FOR SELECT TO authenticated
    USING (EXISTS (SELECT 1 FROM prevencion_epp_entregas e WHERE e.id = entrega_id));

GRANT SELECT ON prevencion_epp_catalogo, prevencion_epp_entregas, prevencion_epp_entrega_items TO authenticated;
GRANT INSERT, UPDATE, DELETE ON prevencion_epp_catalogo TO authenticated;
GRANT UPDATE (anulada, anulada_motivo) ON prevencion_epp_entregas TO authenticated;


-- ── Registrar (atómico, idempotente) ────────────────────────────────────────
-- { cliente_uuid, personal_id, faena_id, fecha, motivo, instruccion_uso,
--   observacion, firma_path, items: [{epp_codigo, cantidad, talla}] }
CREATE OR REPLACE FUNCTION fn_prevencion_epp_registrar(p JSONB)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_id     UUID;
    v_nombre TEXT;
    v_rut    TEXT;
BEGIN
    IF NOT (fn_prevencion_reporta_puede_crear() OR fn_prevencion_reporta_puede_admin()) THEN
        RAISE EXCEPTION 'Su cuenta no puede registrar entregas de EPP.' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_id FROM prevencion_epp_entregas
     WHERE cliente_uuid = (p->>'cliente_uuid')::uuid;
    IF FOUND THEN RETURN v_id; END IF;   -- reintento: ya quedó guardada

    SELECT trim(nombres || ' ' || COALESCE(apellidos, '')),
           CASE WHEN rut LIKE 'PEND-%' THEN NULL ELSE rut END
      INTO v_nombre, v_rut
      FROM prevencion_personal
     WHERE id = (p->>'personal_id')::uuid AND activo;
    IF v_nombre IS NULL THEN
        RAISE EXCEPTION 'El trabajador no está (o no está vigente) en el control documental.';
    END IF;
    IF NULLIF(p->>'firma_path', '') IS NULL THEN
        RAISE EXCEPTION 'Falta la firma del trabajador.';
    END IF;
    IF jsonb_array_length(COALESCE(p->'items', '[]'::jsonb)) = 0 THEN
        RAISE EXCEPTION 'Indique al menos un elemento entregado.';
    END IF;

    INSERT INTO prevencion_epp_entregas (
        cliente_uuid, personal_id, faena_id, fecha, motivo, instruccion_uso,
        observacion, firma_path, trabajador_nombre, trabajador_rut,
        entregado_por, entregado_por_nombre)
    VALUES (
        (p->>'cliente_uuid')::uuid, (p->>'personal_id')::uuid, (p->>'faena_id')::uuid,
        COALESCE(NULLIF(p->>'fecha', '')::date, CURRENT_DATE),
        COALESCE(NULLIF(p->>'motivo', ''), 'reposicion'),
        COALESCE((p->>'instruccion_uso')::boolean, false),
        NULLIF(trim(p->>'observacion'), ''),
        p->>'firma_path', v_nombre, v_rut,
        auth.uid(), (SELECT nombre_completo FROM usuarios_perfil WHERE id = auth.uid()))
    RETURNING id INTO v_id;

    INSERT INTO prevencion_epp_entrega_items (entrega_id, epp_codigo, cantidad, talla)
    SELECT v_id, i->>'epp_codigo',
           GREATEST(COALESCE(NULLIF(i->>'cantidad', '')::int, 1), 1),
           NULLIF(trim(i->>'talla'), '')
      FROM jsonb_array_elements(p->'items') i;

    RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION fn_prevencion_epp_registrar(JSONB) TO authenticated;


-- ── Lectura: una fila por entrega con el detalle armado ─────────────────────
CREATE OR REPLACE VIEW v_prevencion_epp_entregas
WITH (security_invoker = true) AS
SELECT e.id, e.personal_id, e.faena_id, f.nombre AS faena_nombre, e.fecha,
       e.motivo, e.instruccion_uso, e.observacion, e.firma_path,
       e.trabajador_nombre, e.trabajador_rut, e.entregado_por, e.entregado_por_nombre,
       e.anulada, e.anulada_motivo, e.created_at,
       COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'epp_codigo', i.epp_codigo, 'nombre', c.nombre, 'categoria', c.categoria,
                    'cantidad', i.cantidad, 'talla', i.talla,
                    'proxima_reposicion', CASE WHEN c.vida_util_meses IS NOT NULL
                        THEN (e.fecha + make_interval(months => c.vida_util_meses))::date END)
                  ORDER BY c.orden)
                   FROM prevencion_epp_entrega_items i
                   JOIN prevencion_epp_catalogo c ON c.codigo = i.epp_codigo
                  WHERE i.entrega_id = e.id), '[]'::jsonb) AS items
  FROM prevencion_epp_entregas e
  JOIN faenas f ON f.id = e.faena_id;

GRANT SELECT ON v_prevencion_epp_entregas TO authenticated;

COMMIT;

SELECT (SELECT count(*) FROM prevencion_epp_catalogo) AS catalogo,
       (SELECT count(*) FROM prevencion_epp_entregas) AS entregas;
