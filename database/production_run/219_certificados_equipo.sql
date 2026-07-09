-- ============================================================================
-- SICOM-ICEO | 219 — Certificados del equipo (carpeta) firmados por operador
--                    y jefe de taller, habilitados al resolver TODAS las NC
-- ============================================================================
-- Pedido Manuel (2026-07-09): tras los trabajos, el sistema debe emitir los
-- certificados que Pillado entrega al cliente (formato papel actual, ej.
-- "13 - GGHB-32 - Certif. Ausencia códigos de falla del ECM 05-11-2025.pdf").
-- Reglas:
--   * Se HABILITAN solo cuando el equipo no tiene NC abiertas (sacó todas).
--   * Cada certificado lo firma el OPERADOR que hizo el trabajo y el JEFE
--     de taller (el papel actual solo firma el jefe).
--   * Todos quedan en la "carpeta del equipo": pestaña Documentos de la
--     ficha del activo (/dashboard/activos/[id]).
--
--   1. certificado_tipos: catálogo con el texto y los campos de cada tipo
--      (sembrado con los 6 del formato actual; editable a futuro).
--   2. activo_certificados: emitidos (correlativo por equipo, datos snapshot,
--      2 firmas). Solo se insertan vía RPC.
--   3. rpc_emitir_certificado_activo: gate de NC abiertas + roles + firmas.
--   4. v_activo_certificados: carpeta lista para la UI y la impresión.
-- ADITIVA, IDEMPOTENTE.
-- ============================================================================

-- ── 1. Catálogo de tipos ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS certificado_tipos (
    codigo  TEXT PRIMARY KEY,
    titulo  TEXT NOT NULL,
    cuerpo  TEXT NOT NULL,             -- párrafo "Por medio del presente…"
    seccion TEXT DEFAULT 'Última Mantención',
    campos  JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [{key,label,tipo:text|number|date,destacado?}]
    orden   INT  NOT NULL DEFAULT 0,
    activo  BOOLEAN NOT NULL DEFAULT true
);
ALTER TABLE certificado_tipos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_cert_tipos_select ON certificado_tipos;
CREATE POLICY pol_cert_tipos_select ON certificado_tipos FOR SELECT TO authenticated USING (true);

INSERT INTO certificado_tipos (codigo, titulo, cuerpo, seccion, campos, orden) VALUES
('ultima_mantencion', 'CERTIFICADO DE MANTENIMIENTO',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con su mantención al día para operar en faena.',
 'Última Mantención',
 '[{"key":"periodo_mantencion","label":"Periodo Mantención","tipo":"text"},
   {"key":"fecha_mantencion","label":"Fecha de mantención","tipo":"date"},
   {"key":"horometro","label":"Horómetro Mantención","tipo":"number"},
   {"key":"kilometraje","label":"Kilometraje Mantención","tipo":"text"},
   {"key":"proxima_mantencion","label":"Próxima Mantención","tipo":"text","destacado":true}]'::jsonb, 1),
('sistema_hidraulico', 'CERTIFICADO ÚLTIMA MANTENCIÓN SISTEMA HIDRÁULICO',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con la mantención de su sistema hidráulico al día para operar en faena.',
 'Última Mantención',
 '[{"key":"fecha_mantencion","label":"Fecha de mantención","tipo":"date"},
   {"key":"detalle","label":"Detalle","tipo":"text"}]'::jsonb, 2),
('aire_acondicionado', 'CERTIFICADO DE MANTENCIÓN AIRE ACONDICIONADO',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con la mantención de su sistema de aire acondicionado al día para operar en faena.',
 'Última Mantención',
 '[{"key":"fecha_mantencion","label":"Fecha de mantención","tipo":"date"},
   {"key":"detalle","label":"Detalle","tipo":"text"}]'::jsonb, 3),
('carga_descarga_agua', 'CERTIFICADO SISTEMA DE CARGA Y DESCARGA DE AGUA',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con su sistema de carga y descarga de agua operativo y con su prueba de funcionamiento al día.',
 'Última Prueba',
 '[{"key":"fecha_prueba","label":"Fecha de prueba","tipo":"date"},
   {"key":"detalle","label":"Detalle","tipo":"text"}]'::jsonb, 4),
('tacografo', 'CERTIFICADO DE TACÓGRAFO',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con su tacógrafo operativo y con su verificación al día.',
 'Última Verificación',
 '[{"key":"fecha_verificacion","label":"Fecha de verificación","tipo":"date"},
   {"key":"detalle","label":"Detalle","tipo":"text"}]'::jsonb, 5),
('ecm', 'CERTIFICADO DE AUSENCIA DE CÓDIGOS DE FALLA DEL ECM DEL CAMIÓN',
 'Por medio del presente documento se certifica que el equipo que a continuación se describe, se encuentra con su prueba de funcionamiento al día para operar en faena y no presenta códigos de falla activos o memorizados en la ECU.',
 'Última Mantención',
 '[{"key":"fecha_prueba","label":"Fecha de prueba","tipo":"date"},
   {"key":"equipo_utilizado","label":"Equipo utilizado","tipo":"text"}]'::jsonb, 6)
ON CONFLICT (codigo) DO NOTHING;


-- ── 2. Certificados emitidos ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activo_certificados (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activo_id           UUID NOT NULL REFERENCES activos(id),
    tipo_codigo         TEXT NOT NULL REFERENCES certificado_tipos(codigo),
    numero              INT  NOT NULL,               -- correlativo por equipo
    fecha_emision       DATE NOT NULL DEFAULT CURRENT_DATE,
    ciudad              TEXT NOT NULL DEFAULT 'Coquimbo',
    datos               JSONB NOT NULL DEFAULT '{}'::jsonb,  -- snapshot equipo + campos
    operador_tecnico_id UUID REFERENCES taller_tecnicos(id),
    operador_nombre     TEXT NOT NULL,
    firma_operador_url  TEXT NOT NULL,
    jefe_nombre         TEXT NOT NULL,
    firma_jefe_url      TEXT NOT NULL,
    ot_id               UUID REFERENCES ordenes_trabajo(id),
    created_by          UUID REFERENCES usuarios_perfil(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (activo_id, numero)
);
CREATE INDEX IF NOT EXISTS idx_activo_cert_activo ON activo_certificados(activo_id);
ALTER TABLE activo_certificados ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pol_activo_cert_select ON activo_certificados;
CREATE POLICY pol_activo_cert_select ON activo_certificados FOR SELECT TO authenticated USING (true);
-- Sin policy de INSERT/UPDATE: solo la RPC (SECURITY DEFINER) escribe.


-- ── 3. RPC de emisión (gate: sin NC abiertas) ────────────────────────────────
CREATE OR REPLACE FUNCTION rpc_emitir_certificado_activo(
    p_activo_id           UUID,
    p_tipo_codigo         TEXT,
    p_datos               JSONB,
    p_operador_nombre     TEXT,
    p_firma_operador_url  TEXT,
    p_firma_jefe_url      TEXT,
    p_operador_tecnico_id UUID  DEFAULT NULL,
    p_fecha_emision       DATE  DEFAULT CURRENT_DATE,
    p_ciudad              TEXT  DEFAULT 'Coquimbo',
    p_ot_id               UUID  DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_user   UUID := auth.uid();
    v_rol    TEXT := fn_user_rol();
    v_jefe   TEXT;
    v_nc     INT;
    v_numero INT;
    v_id     UUID;
BEGIN
    IF v_user IS NULL THEN RAISE EXCEPTION 'No autenticado'; END IF;
    IF v_rol NOT IN ('administrador','subgerente_operaciones','jefe_mantenimiento','supervisor') THEN
        RAISE EXCEPTION 'Rol % no autorizado para emitir certificados', v_rol;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificado_tipos WHERE codigo = p_tipo_codigo AND activo) THEN
        RAISE EXCEPTION 'Tipo de certificado "%" no existe', p_tipo_codigo;
    END IF;
    IF COALESCE(TRIM(p_operador_nombre),'') = '' THEN
        RAISE EXCEPTION 'Indica el operador que realizó el trabajo';
    END IF;
    IF COALESCE(TRIM(p_firma_operador_url),'') = '' OR COALESCE(TRIM(p_firma_jefe_url),'') = '' THEN
        RAISE EXCEPTION 'El certificado requiere la firma del operador Y la del jefe de taller';
    END IF;

    -- GATE: el equipo debe haber "sacado" todas sus No Conformidades
    SELECT COUNT(*) INTO v_nc FROM no_conformidades
     WHERE activo_id = p_activo_id AND COALESCE(resuelto, false) = false;
    IF v_nc > 0 THEN
        RAISE EXCEPTION 'El equipo tiene % No Conformidad(es) abiertas — deben resolverse todas antes de emitir certificados.', v_nc;
    END IF;

    -- Serializar el correlativo por equipo
    PERFORM 1 FROM activos WHERE id = p_activo_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Equipo no existe'; END IF;
    SELECT COALESCE(MAX(numero), 0) + 1 INTO v_numero
      FROM activo_certificados WHERE activo_id = p_activo_id;

    SELECT nombre_completo INTO v_jefe FROM usuarios_perfil WHERE id = v_user;

    INSERT INTO activo_certificados (
        activo_id, tipo_codigo, numero, fecha_emision, ciudad, datos,
        operador_tecnico_id, operador_nombre, firma_operador_url,
        jefe_nombre, firma_jefe_url, ot_id, created_by
    ) VALUES (
        p_activo_id, p_tipo_codigo, v_numero, p_fecha_emision, p_ciudad,
        COALESCE(p_datos, '{}'::jsonb),
        p_operador_tecnico_id, TRIM(p_operador_nombre), p_firma_operador_url,
        COALESCE(v_jefe, 'Jefe de Taller'), p_firma_jefe_url, p_ot_id, v_user
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('success', true, 'certificado_id', v_id, 'numero', v_numero);
END $$;

REVOKE EXECUTE ON FUNCTION rpc_emitir_certificado_activo(UUID,TEXT,JSONB,TEXT,TEXT,TEXT,UUID,DATE,TEXT,UUID) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION rpc_emitir_certificado_activo(UUID,TEXT,JSONB,TEXT,TEXT,TEXT,UUID,DATE,TEXT,UUID) TO authenticated;


-- ── 4. Vista: la carpeta del equipo ──────────────────────────────────────────
DROP VIEW IF EXISTS v_activo_certificados;
CREATE VIEW v_activo_certificados AS
SELECT c.*,
       t.titulo, t.cuerpo, t.seccion, t.campos,
       a.codigo   AS activo_codigo,
       a.nombre   AS activo_nombre,
       a.patente  AS activo_patente,
       mo.nombre  AS modelo_nombre,
       ma.nombre  AS marca_nombre,
       ot.folio   AS ot_folio
FROM activo_certificados c
JOIN certificado_tipos t ON t.codigo = c.tipo_codigo
JOIN activos a           ON a.id = c.activo_id
LEFT JOIN modelos mo     ON mo.id = a.modelo_id
LEFT JOIN marcas  ma     ON ma.id = mo.marca_id
LEFT JOIN ordenes_trabajo ot ON ot.id = c.ot_id;
GRANT SELECT ON v_activo_certificados TO authenticated;


-- ── VALIDACION ────────────────────────────────────────────────────────────────
SELECT jsonb_build_object(
    'tipos_sembrados', (SELECT COUNT(*) FROM certificado_tipos),
    'tabla_ok', (SELECT EXISTS (SELECT 1 FROM information_schema.tables
        WHERE table_name='activo_certificados')),
    'rpc_gate_nc', (SELECT prosrc LIKE '%No Conformidad(es) abiertas%'
        FROM pg_proc WHERE proname='rpc_emitir_certificado_activo'),
    'vista_ok', (SELECT EXISTS (SELECT 1 FROM pg_views WHERE viewname='v_activo_certificados'))
) AS resultado;

NOTIFY pgrst, 'reload schema';
